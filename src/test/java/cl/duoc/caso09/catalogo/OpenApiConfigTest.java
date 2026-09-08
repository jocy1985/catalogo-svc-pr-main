package cl.duoc.caso09.catalogo;

import org.junit.jupiter.api.Test;
import cl.duoc.caso09.catalogo.config.OpenApiConfig;

import static org.assertj.core.api.Assertions.assertThat;

class OpenApiConfigTest {

    @Test
    void beanOpenApiGenerado() {
        assertThat(new OpenApiConfig().customOpenAPI()).isNotNull();
    }
}
