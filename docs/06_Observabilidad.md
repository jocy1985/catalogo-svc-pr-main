# 06 — Observabilidad y entornos reales (EP3)

> Documento técnico de la EP3. Redactado con apoyo de IA (Claude Opus 5.5, Anthropic) y
> revisado por la autora. Ver la declaración de uso de IA en el README.

## 1. Qué se monitorea y con qué (IE1)

El microservicio ya expone métricas en formato Prometheus en `/actuator/prometheus`
(Spring Boot Actuator + Micrometer). En la EP3 se agregó el stack de monitoreo:

| Herramienta | Rol | Archivo |
|---|---|---|
| **Prometheus** | Recolecta métricas cada 10 s de cada réplica (ServiceMonitor) | `k8s/monitoreo/servicemonitor.yaml` |
| **Alertmanager** | Recibe las alertas cuando una regla se cumple | instalado por `kube-prometheus-stack` |
| **Reglas de alerta** | 7 reglas: caída, réplica caída, 5xx, errores en logs, latencia, memoria, CPU | `k8s/monitoreo/prometheusrule.yaml` |
| **Grafana** | Dashboard del servicio y del pipeline | `k8s/monitoreo/dashboard-catalogo.json` |
| **Pushgateway** | Recibe métricas del pipeline (cobertura, pruebas, tiempos) | instalado por el pipeline |
| **node-exporter / kube-state-metrics** | CPU, memoria y reinicios a nivel de nodo y pod | instalados por `kube-prometheus-stack` |

**Las cuatro señales que pide la evaluación:**

| Señal | Métrica en Prometheus |
|---|---|
| Logs | `logback_events_total{level="error"}` cuenta las líneas ERROR del log; además los logs completos de los pods se guardan como evidencia en cada ejecución |
| Uso (métricas de uso) | `http_server_requests_seconds_count` (peticiones por endpoint), `process_cpu_usage`, `jvm_memory_used_bytes` |
| Errores | respuestas `status=~"5.."` y `status=~"4.."`; tasa de 5xx en porcentaje |
| Disponibilidad | `up{job="catalogo-svc"}`: cuántas réplicas responden a Prometheus |

**¿Por qué Prometheus y no CloudWatch?** Prometheus es open source, funciona igual en kind, en
EKS o en cualquier nube, y es el estándar de Kubernetes. CloudWatch solo funciona dentro de AWS y
cobra por métrica. En EKS se pueden usar los dos: *CloudWatch Container Insights* para la
infraestructura de AWS y Prometheus/Grafana para la aplicación.

## 2. Kubernetes con monitoreo automatizado (IE2)

El job `observabilidad` del pipeline, en cada push y cada PR:

1. Crea un cluster **Kubernetes** (kind) en el runner de GitHub (servidores en la nube de GitHub/Azure).
2. Instala **kube-prometheus-stack** con Helm (versión fijada) y el **Pushgateway**.
3. Despliega el microservicio (2 réplicas, probes, límites de recursos).
4. Registra el `ServiceMonitor`, las `PrometheusRule` y el dashboard de Grafana. No hay ningún paso manual.
5. Genera tráfico real y comprueba con consultas a Prometheus que todo se está midiendo.

**Limitación declarada:** por tiempo no se alcanzó a desplegar en **AWS EKS** (AWS Academy).
El cluster de monitoreo se crea y se destruye dentro del runner en cada ejecución. Los mismos
manifiestos y el mismo `values` de Helm sirven sin cambios en EKS. El plan es este:

```bash
eksctl create cluster --name catalogo --region us-east-1 --nodes 2 --node-type t3.medium
helm upgrade --install kps prometheus-community/kube-prometheus-stack --version 66.3.0 \
  -n monitoreo --create-namespace -f k8s/monitoreo/values-kube-prometheus-stack.yaml
kubectl apply -f k8s/namespace.yaml -f k8s/service.yaml -f k8s/hpa.yaml
kubectl apply -f k8s/monitoreo/servicemonitor.yaml -f k8s/monitoreo/prometheusrule.yaml
# deployment.yaml con la imagen de GHCR por SHA, igual que en el pipeline
```

## 3. Dashboard integrado con CI/CD (IE3)

El dashboard **"Catalogo SubBox - Observabilidad (EP3)"** se carga solo en Grafana (sidecar de
dashboards) y tiene 14 paneles:

| Fila | Paneles | Origen |
|---|---|---|
| Pipeline | Cobertura de pruebas, tiempo de despliegue, duración del pipeline, pruebas ejecutadas | métricas que el pipeline publica en el Pushgateway |
| Salud | Disponibilidad, tasa de errores 5xx, errores 4xx por minuto, líneas ERROR en logs | Prometheus (aplicación) |
| Tráfico | Peticiones por segundo por endpoint, latencia p95 | Prometheus (aplicación) |
| Recursos | CPU por pod, memoria heap por pod | Prometheus (JVM) |
| Estado | Respuestas por código HTTP, reinicios de contenedores | Prometheus + kube-state-metrics |

**Integración con el pipeline:**
- El tiempo de despliegue se mide desde `kubectl apply` hasta que el rollout queda listo.
- La cobertura y la cantidad de pruebas se leen del reporte JaCoCo/Surefire del job `pruebas`.
- La duración del pipeline se calcula con la API de GitHub (`run_started_at`).
- En cada ejecución el resumen (*Actions → Summary*) muestra una tabla con los valores, y el
  artefacto **`evidencias-observabilidad`** guarda la **captura del dashboard** (`dashboard-grafana.png`),
  las reglas de alerta cargadas, los targets, los logs y los gates.

## 4. Cómo las métricas guían las decisiones (IE4)

| Métrica / alerta | Umbral | Decisión que se toma |
|---|---|---|
| Disponibilidad (`up`) | < 2 réplicas por 2 min | Revisar eventos del deployment; si coincide con un deploy, **rollback** al SHA anterior |
| Servicio caído (`CatalogoCaido`) | 0 réplicas por 1 min | Incidente crítico: rollback inmediato y revisión de logs |
| Errores 5xx | > 5 % | **Detener promociones** a `main` y revisar el último cambio. En el pipeline, si supera 5 % el deploy no se ejecuta |
| Errores 4xx | aumento sostenido | Revisar si un cliente usa mal la API o si cambió un contrato; mejorar validaciones o documentación |
| Líneas ERROR en logs | > 10 en 5 min | Abrir los logs del pod para encontrar la causa antes de que se convierta en 5xx |
| Latencia p95 | > 1 s por 5 min | Escalar réplicas (subir `maxReplicas` del HPA) o optimizar consultas |
| CPU promedio | > 80 % por 5 min | Confirmar que el HPA escale; ajustar `requests/limits` |
| Memoria heap | > 85 % por 5 min | Buscar fugas de memoria o subir el límite del pod |
| Reinicios de contenedores | > 0 | Revisar probes y `OOMKilled`; ajustar memoria o la probe |
| Cobertura de pruebas | < 100 % | El job `pruebas` falla y no hay deploy (política del proyecto) |
| Tiempo de despliegue | > 240 s | Investigar imagen pesada o probes lentas; optimizar el Dockerfile |
| Duración del pipeline | > 15 min | Revisar cachés y paralelizar jobs para dar feedback más rápido |

**Ejemplo real de esta entrega:** el pipeline mostró que la nota de seguridad de SonarCloud
era C (Quality Gate fallido). Con eso se decidió fijar todas las GitHub Actions por SHA, instalar
Snyk con versión fija y verificada, y forzar HTTPS en las descargas, en vez de saltarse el gate.
Ver [07_Cumplimiento.md](07_Cumplimiento.md).

## 5. Cómo verlo

1. **GitHub → Actions →** abrir una ejecución de *CI/CD Catálogo* → job **Observabilidad**.
2. En **Summary** aparece la tabla de métricas y los gates.
3. En **Artifacts** se descarga `evidencias-observabilidad` (captura del dashboard incluida).
4. Local, con un cluster propio: `kubectl -n monitoreo port-forward svc/kps-grafana 3000:80`
   y abrir <http://localhost:3000> (usuario `admin`).
