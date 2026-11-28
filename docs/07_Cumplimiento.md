# 07 — Políticas de cumplimiento y detención ante fallas (EP3)

> Documento técnico de la EP3. Redactado con apoyo de IA (Claude Opus 5.5, Anthropic) y
> revisado por la autora.

## 1. Políticas de cumplimiento (IE5)

| Política | Herramienta | Dónde | Qué pasa si no se cumple |
|---|---|---|---|
| Calidad y seguridad del código | **SonarQube Cloud**, Quality Gate (nota A en seguridad, confiabilidad y mantenibilidad; hotspots revisados; duplicación < 3 %) | job `sonarcloud` | el pipeline se detiene |
| Cobertura de pruebas 100 % | JaCoCo (`jacoco:check`) | `pom.xml`, job `pruebas` | el pipeline se detiene |
| Sin secretos en el repositorio | **Gitleaks** | job `cumplimiento` | el pipeline se detiene |
| Configuración segura de Dockerfile y Kubernetes | **Trivy config** (bloquea CRITICAL, informa HIGH/MEDIUM) | job `cumplimiento` | el pipeline se detiene |
| Imagen sin vulnerabilidades conocidas | **Trivy image** (CRITICAL/HIGH con parche) | job `imagen` | la imagen no se publica ni se despliega |
| Excepciones documentadas y con vencimiento | `.trivyignore` con `exp:` + auditoría | job `cumplimiento` | si una excepción vence, la auditoría falla |
| Cadena de suministro | todas las GitHub Actions fijadas por **SHA**; Snyk con versión fija verificada por SHA-256; descargas solo por HTTPS/TLS 1.2 | `ci-cd.yml` + auditoría | la auditoría falla si una acción no está fijada |
| Contenedores sin privilegios | usuario no root, `runAsNonRoot`, `allowPrivilegeEscalation: false`, límites de recursos, probes | `Dockerfile`, `k8s/deployment.yaml` + auditoría | la auditoría falla |
| Dependencias al día | **Dependabot** (Maven, Docker, Actions) | `.github/dependabot.yml` | PRs automáticos semanales |
| Protección de ramas | `main` y `develop`: solo por PR, checks obligatorios, sin force-push ni borrado | `scripts/proteger-ramas.ps1` | GitHub bloquea el merge |
| Auditoría automática | `scripts/auditoria.sh` (controles críticos y advertencias) | job `cumplimiento` | el pipeline se detiene ante un control crítico |

El reporte de la auditoría aparece en el *Summary* de cada ejecución y queda como artefacto
`auditoria-cumplimiento`.

## 2. El pipeline se detiene ante fallas críticas (IE6)

El job `deploy` depende (`needs`) de **todos** los gates: `pruebas`, `sonarcloud`, `snyk`,
`imagen`, `orquestacion-k8s`, `cumplimiento` y `observabilidad`. Ningún paso usa
`continue-on-error` (la auditoría lo verifica). Si cualquier gate falla, **no hay despliegue**.

| Gate | Falla crítica que lo detiene |
|---|---|
| `pruebas` | una prueba falla o la cobertura baja del 100 % |
| `sonarcloud` | Quality Gate *Failed*, o falta el token |
| `imagen` | Trivy encuentra CVE CRITICAL/HIGH con parche |
| `cumplimiento` | Gitleaks encuentra un secreto, Trivy config encuentra un CRITICAL, o falla un control crítico de la auditoría |
| `observabilidad` | menos de 2 réplicas disponibles, errores 5xx ≥ 5 %, una alerta crítica activa, faltan las reglas de alerta o el dashboard |
| `orquestacion-k8s` | el rollout no queda listo o el pod borrado no se recrea |

### Evidencia real: fallas que detuvieron el pipeline durante el desarrollo

Estas detenciones ocurrieron de verdad mientras se construía el pipeline (no son simulaciones):

| Ejecución | Qué falló | Gate que detuvo | Cómo se corrigió |
|---|---|---|---|
| [46100882934](https://github.com/jocy1985/catalogo-svc-pr-main/actions/runs/46100882934) | 13 vulnerabilidades HIGH/CRITICAL en Tomcat y Jackson; SonarCloud sin autorización | `imagen` (Trivy) y `sonarcloud` | Se actualizaron Tomcat y Jackson en el `pom.xml`; dos CVE sin parche en Spring 6.2 quedaron como excepción documentada con vencimiento |
| [46104515354](https://github.com/jocy1985/catalogo-svc-pr-main/actions/runs/46104515354) | La versión de Tomcat elegida no existía en Maven Central | `pruebas` (build) | Se usó Tomcat 10.1.62 |
| [46105252651](https://github.com/jocy1985/catalogo-svc-pr-main/actions/runs/46105252651) | SonarCloud: *Not authorized*. El secret no tenía un token válido | `sonarcloud` | Se generó un token nuevo, se validó contra la API de SonarCloud (largo 40 y acceso a la organización) y luego se guardó |
| mismo run, reintento | **Quality Gate FAILED**: nota de seguridad C por acciones sin SHA y `npm install snyk@latest` | `sonarcloud` | Se fijaron todas las acciones por SHA y se cambió npm por el binario de Snyk con versión fija y SHA-256 |
| [46112145773](https://github.com/jocy1985/catalogo-svc-pr-main/actions/runs/46112145773) | Quality Gate FAILED: `curl` sin forzar HTTPS | `sonarcloud` | Se agregó `--proto '=https' --tlsv1.2` |
| [46112642099](https://github.com/jocy1985/catalogo-svc-pr-main/actions/runs/46112642099) | — | — | Pipeline completo en verde; luego PR #1 a `develop` y PR #2 a `main` |

En todos los casos el deploy **no se ejecutó** hasta que la falla se corrigió.
