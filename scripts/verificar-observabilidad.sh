#!/usr/bin/env bash
# =============================================================================
# Verificacion de observabilidad   [EP3 IE1, IE3, IE6]
#
# Se ejecuta en el pipeline, con el microservicio y kube-prometheus-stack ya
# instalados en el cluster kind. Pasos:
#   1. Abre puertos a la app, Prometheus, Grafana y Pushgateway.
#   2. Genera trafico real (lecturas, altas, 404 y 400).
#   3. Publica metricas del pipeline (cobertura, pruebas, tiempo de deploy).
#   4. Consulta Prometheus y aplica gates: si el servicio no esta disponible,
#      si la tasa de errores 5xx supera el 5% o si faltan las alertas, FALLA.
#   5. Guarda evidencias: valores, reglas, logs y captura del dashboard.
# =============================================================================
set -euo pipefail

EVID=evidencias
mkdir -p "$EVID"
APP=http://localhost:8081
PROM=http://localhost:9090
GRAF=http://localhost:3000
PGW=http://localhost:9091
FALLAS=0

# --- 1. Puertos -------------------------------------------------------------
GRAFANA_SVC=$(kubectl -n monitoreo get svc -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
PGW_SVC=$(kubectl -n monitoreo get svc -l app.kubernetes.io/name=prometheus-pushgateway -o jsonpath='{.items[0].metadata.name}')
kubectl -n catalogo port-forward svc/catalogo-svc 8081:80 > /tmp/pf-app.log 2>&1 &
kubectl -n monitoreo port-forward svc/prometheus-operated 9090:9090 > /tmp/pf-prom.log 2>&1 &
kubectl -n monitoreo port-forward "svc/${GRAFANA_SVC}" 3000:80 > /tmp/pf-graf.log 2>&1 &
kubectl -n monitoreo port-forward "svc/${PGW_SVC}" 9091:9091 > /tmp/pf-pgw.log 2>&1 &

esperar_url() {  # $1=url $2=nombre
  for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null "$1"; then echo "$2 disponible"; return 0; fi
    sleep 2
  done
  echo "::error::$2 no respondio en $1"; return 1
}
esperar_url "$APP/actuator/health" "Microservicio"
esperar_url "$PROM/-/ready" "Prometheus"
esperar_url "$GRAF/api/health" "Grafana"
esperar_url "$PGW/-/ready" "Pushgateway"

# --- 2. Trafico ---------------------------------------------------------------
generar_trafico() {
  for i in $(seq 1 "$1"); do
    curl -fsS -o /dev/null "$APP/api/productos" || true
    if (( i % 5 == 0 )); then
      curl -sS -o /dev/null -X POST "$APP/api/productos" -H "Content-Type: application/json" \
        -d "{\"nombre\":\"Caja ${i}\",\"marca\":\"SubBox\",\"precio\":9990}" || true
      curl -sS -o /dev/null "$APP/api/productos/999999" || true                     # 404
      curl -sS -o /dev/null -X POST "$APP/api/productos" -H "Content-Type: application/json" -d '{}' || true  # 400
    fi
    sleep 0.2
  done
}
generar_trafico 150
generar_trafico 600 > /dev/null 2>&1 &   # trafico de fondo para los graficos

# --- 3. Metricas del pipeline (Pushgateway) ----------------------------------
CSV=$(find reportes -name jacoco.csv 2>/dev/null | head -1 || true)
COBERTURA=0
if [[ -n "$CSV" ]]; then
  COBERTURA=$(awk -F, 'NR>1 {m+=$8; c+=$9} END {if (m+c>0) printf "%.1f", (c*100)/(m+c); else print 0}' "$CSV")
fi
PRUEBAS=$(find reportes -name 'TEST-*.xml' -exec grep -ho 'tests="[0-9]*"' {} + 2>/dev/null \
  | grep -o '[0-9]*' | awk '{s+=$1} END {print s+0}')
INICIO_RUN=$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}" --jq .run_started_at 2>/dev/null || echo "")
DURACION_PIPELINE=0
if [[ -n "$INICIO_RUN" ]]; then
  DURACION_PIPELINE=$(( $(date +%s) - $(date -d "$INICIO_RUN" +%s) ))
fi
RAMA="${GITHUB_REF_NAME:-local}"
if cat <<METRICAS | curl -fsS --data-binary @- "$PGW/metrics/job/cicd_catalogo"
# TYPE ci_cobertura_porcentaje gauge
ci_cobertura_porcentaje{rama="${RAMA}"} ${COBERTURA}
# TYPE ci_pruebas_total gauge
ci_pruebas_total{rama="${RAMA}"} ${PRUEBAS}
# TYPE ci_deploy_duracion_segundos gauge
ci_deploy_duracion_segundos{rama="${RAMA}"} ${DEPLOY_SEG:-0}
# TYPE ci_pipeline_duracion_segundos gauge
ci_pipeline_duracion_segundos{rama="${RAMA}"} ${DURACION_PIPELINE}
# TYPE ci_ultima_ejecucion_timestamp gauge
ci_ultima_ejecucion_timestamp{rama="${RAMA}"} $(date +%s)
METRICAS
then :; else echo "::warning::No se pudieron publicar las metricas del pipeline"; fi
echo "Metricas CI publicadas: cobertura=${COBERTURA}% pruebas=${PRUEBAS} deploy=${DEPLOY_SEG:-0}s pipeline=${DURACION_PIPELINE}s"

# --- 4. Consultas a Prometheus y gates -----------------------------------------
consultar() {  # devuelve el primer valor o "sin_dato" (nunca corta el script)
  local r
  r=$(curl -sS --get --data-urlencode "query=$1" "$PROM/api/v1/query" 2>/dev/null || true)
  echo "$r" | jq -r '.data.result[0].value[1] // "sin_dato"' 2>/dev/null || echo "sin_dato"
}

echo "Esperando que Prometheus raspe el servicio y el Pushgateway..."
for _ in $(seq 1 36); do
  ARRIBA=$(consultar 'sum(up{namespace="catalogo", job="catalogo-svc"})')
  COB_PROM=$(consultar 'max(ci_cobertura_porcentaje)')
  REQ=$(consultar 'sum(http_server_requests_seconds_count{namespace="catalogo"})')
  if [[ "$ARRIBA" != "sin_dato" && "$COB_PROM" != "sin_dato" && "$REQ" != "sin_dato" ]] \
     && awk -v a="$ARRIBA" 'BEGIN {exit !(a >= 2)}'; then
    break
  fi
  sleep 5
done
sleep 20   # al menos dos raspados mas para que rate() tenga datos

declare -A Q=(
  [disponibilidad]='sum(up{namespace="catalogo", job="catalogo-svc"})'
  [peticiones_total]='sum(http_server_requests_seconds_count{namespace="catalogo"})'
  [errores_5xx_pct]='100 * sum(rate(http_server_requests_seconds_count{namespace="catalogo", status=~"5.."}[2m])) / clamp_min(sum(rate(http_server_requests_seconds_count{namespace="catalogo"}[2m])), 1e-9)'
  [errores_4xx_total]='sum(http_server_requests_seconds_count{namespace="catalogo", status=~"4.."})'
  [latencia_p95_seg]='histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{namespace="catalogo"}[2m])))'
  [cpu_promedio]='avg(process_cpu_usage{namespace="catalogo"})'
  [heap_mb_total]='sum(jvm_memory_used_bytes{namespace="catalogo", area="heap"}) / 1024 / 1024'
  [logs_error_total]='sum(logback_events_total{namespace="catalogo", level="error"})'
  [cobertura_pct]='max(ci_cobertura_porcentaje)'
  [deploy_seg]='max(ci_deploy_duracion_segundos)'
  [pipeline_seg]='max(ci_pipeline_duracion_segundos)'
  [alertas_criticas_activas]='count(ALERTS{alertstate="firing", severity="critical", namespace="catalogo"}) or vector(0)'
)
declare -A V
for k in "${!Q[@]}"; do V[$k]=$(consultar "${Q[$k]}"); done

gate() {  # $1=ok(0/1) $2=descripcion
  if [[ "$1" == "1" ]]; then echo "| OK | $2 |" >> "$EVID/gates.md"
  else echo "| FALLA | $2 |" >> "$EVID/gates.md"; FALLAS=$((FALLAS + 1)); echo "::error::$2"; fi
}
: > "$EVID/gates.md"
gate "$(awk -v a="${V[disponibilidad]}" 'BEGIN {print (a >= 2) ? 1 : 0}')" "Disponibilidad: 2 replicas raspadas por Prometheus (valor: ${V[disponibilidad]})"
gate "$(awk -v e="${V[errores_5xx_pct]}" 'BEGIN {print (e == "sin_dato" || e+0 < 5) ? 1 : 0}')" "Errores 5xx bajo el 5% (valor: ${V[errores_5xx_pct]})"
gate "$(awk -v c="${V[alertas_criticas_activas]}" 'BEGIN {print (c+0 == 0) ? 1 : 0}')" "Sin alertas criticas activas (valor: ${V[alertas_criticas_activas]})"
gate "$([[ "${V[cobertura_pct]}" != "sin_dato" ]] && echo 1 || echo 0)" "Metricas del pipeline visibles en Prometheus (cobertura: ${V[cobertura_pct]}%)"

curl -fsS "$PROM/api/v1/rules" > "$EVID/reglas-alerta.json" || echo "{}" > "$EVID/reglas-alerta.json"
REGLAS=$(jq '[.data.groups[] | select(.name | startswith("catalogo")) | .rules[]] | length' "$EVID/reglas-alerta.json" 2>/dev/null || echo 0)
gate "$([[ "$REGLAS" -ge 6 ]] && echo 1 || echo 0)" "Reglas de alerta del catalogo cargadas en Prometheus (${REGLAS})"

# --- 5. Evidencias -------------------------------------------------------------
for k in "${!V[@]}"; do echo "$k=${V[$k]}"; done | sort > "$EVID/metricas.txt"
curl -fsS "$PROM/api/v1/targets?state=active" | jq '[.data.activeTargets[] | {job: .labels.job, pod: .labels.pod, salud: .health}]' > "$EVID/targets.json" || true
kubectl -n catalogo logs -l app=catalogo-svc --tail=200 --prefix > "$EVID/logs-catalogo.txt" 2>&1 || true
kubectl -n catalogo get deploy,pods,svc,hpa,servicemonitor,prometheusrule -o wide > "$EVID/kubernetes.txt" 2>&1 || true

DASH_OK=0
for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null "$GRAF/api/dashboards/uid/catalogo-ep3"; then DASH_OK=1; break; fi
  sleep 3
done
gate "$DASH_OK" "Dashboard de Grafana 'catalogo-ep3' provisionado automaticamente"
sleep 30   # mas puntos en los graficos antes de la captura
CHROME=$(command -v google-chrome || command -v chromium || command -v chromium-browser || true)
if [[ -n "$CHROME" && "$DASH_OK" == "1" ]]; then
  "$CHROME" --headless=new --no-sandbox --disable-gpu --hide-scrollbars --window-size=1600,2000 \
    --virtual-time-budget=25000 --screenshot="$EVID/dashboard-grafana.png" \
    "$GRAF/d/catalogo-ep3/catalogo?orgId=1&kiosk&from=now-10m&to=now" > /dev/null 2>&1 \
    || echo "::warning::No se pudo capturar el dashboard"
fi

{
  echo "## Observabilidad - metricas del despliegue"
  echo ""
  echo "| Metrica | Valor |"
  echo "|---|---|"
  echo "| Disponibilidad (replicas arriba) | ${V[disponibilidad]} |"
  echo "| Peticiones atendidas | ${V[peticiones_total]} |"
  echo "| Tasa de errores 5xx (%) | ${V[errores_5xx_pct]} |"
  echo "| Errores 4xx (total) | ${V[errores_4xx_total]} |"
  echo "| Latencia p95 (s) | ${V[latencia_p95_seg]} |"
  echo "| CPU promedio (0-1) | ${V[cpu_promedio]} |"
  echo "| Memoria heap total (MB) | ${V[heap_mb_total]} |"
  echo "| Lineas ERROR en logs | ${V[logs_error_total]} |"
  echo "| Cobertura de pruebas (%) | ${V[cobertura_pct]} |"
  echo "| Tiempo de despliegue (s) | ${V[deploy_seg]} |"
  echo "| Duracion del pipeline hasta aqui (s) | ${V[pipeline_seg]} |"
  echo ""
  echo "### Gates de observabilidad"
  echo ""
  echo "| Resultado | Control |"
  echo "|---|---|"
  cat "$EVID/gates.md"
  echo ""
  echo "Evidencias (captura del dashboard, reglas, targets, logs): artefacto \`evidencias-observabilidad\`."
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}" > "$EVID/resumen.md"

if [[ "$FALLAS" -gt 0 ]]; then
  echo "Observabilidad FALLIDA: ${FALLAS} gate(s). El despliegue no continua."
  exit 1
fi
echo "Observabilidad OK."
