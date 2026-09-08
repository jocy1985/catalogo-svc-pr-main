package cl.duoc.caso09.catalogo.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import cl.duoc.caso09.catalogo.model.Producto;

public interface ProductoRepository extends JpaRepository<Producto, Long> {
}
