#!/usr/bin/env bash
# =============================================================================
# Auditoria de cumplimiento del repositorio   [EP3 IE5 / IE6]
#
# Revisa politicas de seguridad y calidad. Cada control es CRITICO (detiene el
# pipeline) o ADVERTENCIA (solo se informa). Genera un reporte Markdown.
#
# Uso:  bash scripts/auditoria.sh [archivo-reporte.md]
# Sale con codigo 1 si falla algun control CRITICO.
# =============================================================================
set -uo pipefail

REPORTE="${1:-auditoria-reporte.md}"
CRITICOS=0
ADVERTENCIAS=0
HOY=$(date -u +%F)

{
  echo "## Auditoria de cumplimiento"
  echo ""
  echo "Fecha: ${HOY} - Commit: \`${GITHUB_SHA:-local}\`"
  echo ""
  echo "| Resultado | Nivel | Control |"
  echo "|---|---|---|"
} > "$REPORTE"

registrar() {  # $1=ok|falla  $2=CRITICO|ADVERTENCIA  $3=descripcion
  local icono="OK"
  if [[ "$1" == "falla" ]]; then
    icono="FALLA"
    if [[ "$2" == "CRITICO" ]]; then CRITICOS=$((CRITICOS + 1)); else ADVERTENCIAS=$((ADVERTENCIAS + 1)); fi
  fi
  echo "| ${icono} | $2 | $3 |" >> "$REPORTE"
  echo "[${icono}] ($2) $3"
}

# 1. Acciones de GitHub fijadas por SHA (cadena de suministro)
SIN_SHA=$(grep -hoE 'uses:[[:space:]]*[^[:space:]#]+' .github/workflows/*.yml \
  | sed -E 's/uses:[[:space:]]*//' | grep -v '^\./' | grep -vE '@[0-9a-f]{40}$' || true)
if [[ -z "$SIN_SHA" ]]; then
  registrar ok CRITICO "Todas las GitHub Actions estan fijadas por SHA de commit"
else
  registrar falla CRITICO "Acciones sin SHA fijo: $(echo "$SIN_SHA" | tr '\n' ' ')"
fi

# 2. Ningun gate se salta con continue-on-error
if grep -nE 'continue-on-error:[[:space:]]*true' .github/workflows/*.yml > /dev/null; then
  registrar falla CRITICO "Hay pasos con continue-on-error: true (los gates no deben ignorar fallas)"
else
  registrar ok CRITICO "Ningun paso usa continue-on-error: true"
fi

# 3. Politica de cobertura 100% en el pom.xml
if grep -qE '<minimum>1(\.0+)?</minimum>' pom.xml; then
  registrar ok CRITICO "JaCoCo exige 100% de cobertura de lineas (pom.xml)"
else
  registrar falla CRITICO "La politica de cobertura del 100% no esta en pom.xml"
fi

# 4. La imagen corre sin root
USUARIO=$(grep -E '^USER[[:space:]]' Dockerfile | tail -1 | awk '{print $2}')
if [[ -n "$USUARIO" && "$USUARIO" != "root" && "${USUARIO%%:*}" != "0" ]]; then
  registrar ok CRITICO "El Dockerfile ejecuta la app con usuario no root (${USUARIO})"
else
  registrar falla CRITICO "El Dockerfile no define un usuario no root"
fi

# 5. Deployment de Kubernetes con limites, probes y sin root
DEP=k8s/deployment.yaml
for clave in "limits:" "readinessProbe:" "livenessProbe:" "runAsNonRoot: true" "allowPrivilegeEscalation: false"; do
  if grep -q "$clave" "$DEP"; then
    registrar ok CRITICO "k8s/deployment.yaml define ${clave%:}"
  else
    registrar falla CRITICO "k8s/deployment.yaml no define ${clave%:}"
  fi
done

# 6. Excepciones de seguridad documentadas y vigentes
if [[ -f .trivyignore ]]; then
  while read -r cve resto || [[ -n "${cve:-}" ]]; do
    [[ -z "$cve" || "$cve" == \#* ]] && continue
    VENCE=$(echo "$resto" | grep -oE 'exp:[0-9]{4}-[0-9]{2}-[0-9]{2}' | cut -d: -f2)
    if [[ -z "$VENCE" ]]; then
      registrar falla CRITICO "Excepcion ${cve} sin fecha de vencimiento en .trivyignore"
    elif [[ "$VENCE" < "$HOY" ]]; then
      registrar falla CRITICO "Excepcion ${cve} vencida el ${VENCE}: corregir o renovar con justificacion"
    else
      registrar ok ADVERTENCIA "Excepcion ${cve} vigente hasta ${VENCE} (riesgo aceptado y documentado)"
    fi
  done < .trivyignore
fi

# 7. Sin archivos de secretos en el repositorio
SECRETOS=$(git ls-files | grep -E '(^|/)(\.env|id_rsa|id_ed25519)$|\.(pem|p12|pfx|key)$' || true)
if [[ -z "$SECRETOS" ]]; then
  registrar ok CRITICO "No hay archivos de secretos versionados (.env, llaves, certificados)"
else
  registrar falla CRITICO "Archivos sensibles versionados: $(echo "$SECRETOS" | tr '\n' ' ')"
fi

# 8. Dependabot activo para Maven, Docker y GitHub Actions
for eco in maven docker github-actions; do
  if grep -q "package-ecosystem: \"${eco}\"" .github/dependabot.yml 2>/dev/null; then
    registrar ok ADVERTENCIA "Dependabot vigila ${eco}"
  else
    registrar falla ADVERTENCIA "Dependabot no vigila ${eco}"
  fi
done

# 9. Alertas de monitoreo definidas
if grep -q "alert: CatalogoCaido" k8s/monitoreo/prometheusrule.yaml 2>/dev/null; then
  registrar ok ADVERTENCIA "Reglas de alerta de Prometheus definidas (k8s/monitoreo)"
else
  registrar falla ADVERTENCIA "No hay reglas de alerta de Prometheus"
fi

{
  echo ""
  echo "**Controles criticos fallidos:** ${CRITICOS} - **Advertencias:** ${ADVERTENCIAS}"
} >> "$REPORTE"

if [[ "$CRITICOS" -gt 0 ]]; then
  echo "Auditoria FALLIDA: ${CRITICOS} control(es) critico(s). El pipeline se detiene."
  exit 1
fi
echo "Auditoria OK (${ADVERTENCIAS} advertencia(s))."
