# language: es
Característica: Servicio Catálogo (microservicio catalogo del caso caso09)
  Los escenarios validan el contrato REST del microservicio alineado a sus endpoints.

  Escenario: el listado del recurso responde 200
    Dado el servicio "Catálogo" está disponible
    Cuando consulto el listado de "productos"
    Entonces el listado responde con código 200

  Escenario: ciclo de vida completo del recurso
    Dado un nuevo "producto" con nombre "hola-cucumber"
    Cuando consulto el "producto" recién creado
    Entonces el recurso tiene nombre "hola-cucumber" y código 200
    Cuando actualizo el "producto" con nombre "cucumber-actualizado"
    Entonces el recurso queda con nombre "cucumber-actualizado" y código 200
    Cuando elimino el "producto"
    Entonces la eliminación responde con código 204
    Y al consultar el "producto" eliminado responde 404
