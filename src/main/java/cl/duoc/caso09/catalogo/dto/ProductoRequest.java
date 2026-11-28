package cl.duoc.caso09.catalogo.dto;

import cl.duoc.caso09.catalogo.model.Producto;
import jakarta.validation.constraints.NotBlank;
import java.math.BigDecimal;

/**
 * Datos que el cliente puede enviar para crear o actualizar un producto.
 * Se usa en vez de la entidad JPA para que el cliente no pueda fijar campos
 * internos como el id (regla de seguridad S4684 de SonarQube).
 */
public record ProductoRequest(
        @NotBlank(message = "El nombre es obligatorio") String nombre,
        String marca,
        BigDecimal precio) {

    public Producto toEntity() {
        Producto producto = new Producto();
        producto.setNombre(nombre());
        producto.setMarca(marca());
        producto.setPrecio(precio());
        return producto;
    }
}