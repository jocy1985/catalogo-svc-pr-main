# syntax=docker/dockerfile:1
# =============================================================================
# Dockerfile multi-stage — Microservicio Catálogo (caso09 SubBox)   [IE1]
#
# Etapa 1 (build):   Maven + JDK 21 compila y empaqueta el .jar.
# Etapa 2 (runtime): solo JRE 21 sobre Alpine, sin Maven ni código fuente.
# =============================================================================

# ── Etapa 1: build ───────────────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-26 AS build
WORKDIR /app

# Primero solo el pom: si no cambian las dependencias, Docker reutiliza esta
# capa y el build siguiente es mucho más rápido.
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline

COPY src ./src
# Las pruebas no se corren aquí porque ya las corre el job de tests del pipeline.
RUN mvn -B -q package -DskipTests \
 && cp target/catalogo-svc-*.jar /app/app.jar

# ── Etapa 2: runtime ─────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine

# Metadatos OCI: permiten saber desde qué commit se construyó la imagen
# (trazabilidad, IE4). El pipeline les pasa los valores reales.
ARG GIT_COMMIT=local
ARG APP_VERSION=local
LABEL org.opencontainers.image.title="catalogo-svc" \
      org.opencontainers.image.description="Microservicio Catálogo - caso09 SubBox" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.version="${APP_VERSION}"

# Parches de seguridad del SO (para que Trivy no encuentre CVE con fix) y
# curl para el HEALTHCHECK.
RUN apk --no-cache upgrade && apk --no-cache add curl

# Usuario sin privilegios con UID fijo: el proceso nunca corre como root y
# Kubernetes puede verificarlo (runAsNonRoot).
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app app
WORKDIR /app
COPY --from=build --chown=app:app /app/app.jar app.jar
USER 10001:10001

ENV GIT_COMMIT=${GIT_COMMIT} \
    APP_VERSION=${APP_VERSION}

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -fs http://localhost:8080/actuator/health || exit 1

# La JVM respeta el límite de memoria del contenedor (75% para el heap).
# Si se queda sin memoria, el proceso termina y el orquestador lo reinicia.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-XX:+ExitOnOutOfMemoryError", "-jar", "app.jar"]
