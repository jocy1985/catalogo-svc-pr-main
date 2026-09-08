# Catálogo — Microservicio de riesgo catalogo

Microservicio correspondiente al **caso caso09 — SubBox** (E-commerce por suscripción) de la Evaluación Parcial N°1.

| | |
|---|---|
| Stack | Spring Boot 3.3 · Java 21 · Maven · Spring Data JPA · H2 · springdoc-openapi |
| Calidad | JaCoCo cobertura LINE 100% · Cucumber (BDD) alineado a endpoints REST |
| Entrega | Docker / Docker Compose |

## Responsabilidad (SRP)

administra los datos y la lógica del dominio de Catálogo del caso caso09 (SubBox). Su base de datos es una **H2 en memoria** (un solo microservicio por base), cumpliendo aislamiento de datos por dominio.

## Página de presentación

Al ejecutar el servicio, `http://localhost:8080/` muestra la página de presentación del microservicio con documentación y enlaces a:

- **Swagger UI**: `/swagger-ui/index.html`
- **OpenAPI (yaml)**: `/v3/api-docs.yaml`
- **ReDoc**: `/redoc.html`
- **H2 Console**: `/h2-console`

## Endpoints

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/api/productos` | Lista todos los recursos |
| GET | `/api/productos/{id}` | Obtiene un recurso por id |
| POST | `/api/productos` | Crea un recurso |
| PUT | `/api/productos/{id}` | Actualiza un recurso |
| DELETE | `/api/productos/{id}` | Elimina un recurso |

## Documentación del proyecto

La documentación completa está en la carpeta [`docs/`](docs/):

- [`docs/00_Resumen.md`](docs/00_Resumen.md) — propósito, responsabilidad y tecnologías
- [`docs/01_Arquitectura.md`](docs/01_Arquitectura.md) — componentes, arquitectura y patrones
- [`docs/02_API.md`](docs/02_API.md) — contrato REST y ejemplos curl
- [`docs/03_Pruebas.md`](docs/03_Pruebas.md) — tests unitarios, cobertura y Cucumber
- [`docs/04_Despliegue.md`](docs/04_Despliegue.md)
- [`docs/05_Justificacion.md`](docs/05_Justificacion.md) — justificación del servicio: RF/RNF/seguridad cubiertos, stack y por qué cada tecnología AWS
- [`docs/diagramas/`](docs/diagramas/) — C4 (contexto, contenedores, componentes), secuencia e infraestructura AWS — Docker, Docker Compose e integración

## Cómo ejecutar locmente

```bash
mvn spring-boot:run
```

## Cómo ejecutar con Docker

```bash
docker compose up --build
# http://localhost:8080
```

## Cómo ejecutar las pruebas

```bash
mvn test      # unit tests + Cucumber
mvn verify    # + verificación de cobertura JaCoCo (100% LINE, falla si baja)
```

## Modelo de ramificación (IE1)

**Modelo elegido: GitFlow** (`main` + `develop` + `feature/<nombre>` + `hotfix/<nombre>`).

Elegimos GitFlow porque el curso se desarrolla durante todo el semestre y cada entrega
(EP01, EP02, EP03) es un hito estable sobre el mismo repositorio. La rama `develop`
permite integrar cambios de funcionalidad sin ensuciar `main`, y la rama `hotfix/`
deja corregir un problema detectado en la versión estable sin interrumpir el trabajo
en curso sobre `develop`. Además, GitFlow separa explícitamente el código estable
(`main`, siempre desplegable) del código en integración (`develop`), lo que da
trazabilidad clara frente a lo que exige la rúbrica de esta evaluación (IE5).

| Modelo | Cómo funciona | Por qué no se eligió |
|--------|---------------|------------------------|
| **GitFlow** ✅ | `main` + `develop` + `feature/` + `hotfix/` | — |
| GitHub Flow | solo `main` + `feature/` + PR | No distingue un estado "en integración" de uno "estable"; más pensado para despliegue continuo sin hitos de evaluación intermedios |
| Trunk-based | rama única de vida corta | Exige integración casi diaria y un pipeline de pruebas maduro; no calza con el ritmo de entregas EP01/EP02/EP03 del curso |

### Estructura de ramas

| Rama | Origen | Propósito | ¿Se borra? |
|------|--------|-----------|------------|
| `main` | inicial | Código estable, siempre listo para producción | No |
| `develop` | `main` | Integración de cambios (features) terminados | No |
| `feature/<nombre>` | `develop` | Un cambio de funcionalidad o documentación | Sí, al fusionarse |
| `hotfix/<nombre>` | `main` | Corrección urgente de un problema en la versión estable | Sí, al fusionarse |

## Convenciones y buenas prácticas (IE5)

### Convención de commits

Formato: `tipo(alcance): descripcion-corta`, en minúsculas y sin tildes.

| Tipo | Para qué | Ejemplo |
|------|----------|---------|
| `feat` | Nueva funcionalidad | `feat(ui): agregar version al pie de pagina` |
| `fix` | Corrección de bug | `fix(docs): corregir typo en README` |
| `docs` | Documentación | `docs: agregar changelog` |
| `chore` | Tareas / CI | `chore(ci): agregar workflow hola mundo` |

### Naming de ramas

`feature/<nombre-corto>` y `hotfix/<nombre-corto>`, en minúsculas y con guiones.
Ejemplos usados en este repositorio: `feature/version-footer`, `feature/changelog`,
`hotfix/typo-readme`.

### Estructura de carpetas

```
catalogo-svc/
├── src/main/java/.../catalogo/        # controller, service, repository, model
├── src/main/resources/static/         # página de presentación (index.html)
├── src/test/java/.../catalogo/        # tests unitarios + steps de Cucumber
├── docs/                              # arquitectura, API, pruebas, despliegue, justificación, diagramas C4
├── .github/workflows/                 # pipeline de GitHub Actions
├── Dockerfile / docker-compose.yml
└── README.md / CHANGELOG.md
```

### Control de versiones

- Un commit = un cambio lógico; nunca mezclar refactor + feature en el mismo commit.
- Cambios en código Java siempre acompañados de su prueba (JaCoCo exige 100% LINE).
- Tags semánticos (`vX.Y.Z`) para marcar parches de hotfix, por ejemplo `v1.0.1`.

### Flujo de merge

- Features y hotfix siempre entran por pull request, nunca push directo a `main` o `develop`.
- Se necesita al menos 1 aprobación antes de fusionar.
- Usar merge commit (se conserva la trazabilidad del PR) y borrar la rama después de fusionar.
- Todo hotfix fusionado en `main` se sincroniza de inmediato a `develop`.

### Estrategia de revisión

- El autor abre el PR con una descripción breve del cambio.
- El revisor comenta, aprueba o pide cambios; nunca se fusiona un PR sin revisión.
- Antes de cada PR: confirmar que `mvn test` pasa y revisar la diff completa.
