set -euo pipefail
mkdir -p src/main/java/com/example/orders src/main/resources src/test/java/com/example/orders
cat > pom.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId><version>3.5.6</version></parent>
  <groupId>com.example</groupId><artifactId>orders</artifactId><version>0.1.0</version>
  <properties><java.version>21</java.version></properties>
  <dependencies>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-validation</artifactId></dependency>
    <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
    <dependency><groupId>org.flywaydb</groupId><artifactId>flyway-core</artifactId></dependency>
    <dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><optional>true</optional></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>
  </dependencies>
</project>
EOF
cat > src/main/java/com/example/orders/OrdersApplication.java <<'EOF'
package com.example.orders;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
@SpringBootApplication
public class OrdersApplication { public static void main(String[] args) { SpringApplication.run(OrdersApplication.class, args); } }
EOF
cat > src/main/java/com/example/orders/OrderController.java <<'EOF'
package com.example.orders;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/api/v1/orders")
public class OrderController {
    private final OrderService orderService;
    public OrderController(OrderService orderService) { this.orderService = orderService; }
    @PostMapping
    public Order create(@RequestBody Order order) { return orderService.create(order); }
}
EOF
cat > src/main/java/com/example/orders/OrderService.java <<'EOF'
package com.example.orders;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
@Service
public class OrderService {
    @Value("${payment.base-url}") private String paymentBaseUrl;
    private final RestTemplate restTemplate = new RestTemplate();
    private final OrderRepository orderRepository;
    public OrderService(OrderRepository orderRepository) { this.orderRepository = orderRepository; }
    public Order create(Order order) {
        if (order.quantity() <= 0) throw new RuntimeException("bad quantity");
        orderRepository.save(new OrderEntity(order.id(), order.sku(), order.quantity()));
        restTemplate.postForObject(paymentBaseUrl + "/payments", order, String.class);
        return order;
    }
}
EOF
cat > src/main/java/com/example/orders/Order.java <<'EOF'
package com.example.orders;
public record Order(String id, String sku, int quantity) {}
EOF
cat > src/main/java/com/example/orders/OrderEntity.java <<'EOF'
package com.example.orders;
import jakarta.persistence.*;
@Entity
@Table(name = "orders")
public class OrderEntity {
    @Id private String id;
    private String sku;
    private int quantity;
    private String status;
    @Version private long version;
    protected OrderEntity() {}
    public OrderEntity(String id, String sku, int quantity) { this.id = id; this.sku = sku; this.quantity = quantity; this.status = "CREATED"; }
    public String getId() { return id; }
    public String getSku() { return sku; }
    public int getQuantity() { return quantity; }
    public String getStatus() { return status; }
}
EOF
cat > src/main/java/com/example/orders/OrderRepository.java <<'EOF'
package com.example.orders;
import org.springframework.data.jpa.repository.JpaRepository;
public interface OrderRepository extends JpaRepository<OrderEntity, String> {}
EOF
mkdir -p src/main/resources/db/migration
printf 'CREATE TABLE orders (id VARCHAR(36) PRIMARY KEY, sku VARCHAR(32) NOT NULL, quantity INT NOT NULL, status VARCHAR(16) NOT NULL, version BIGINT NOT NULL);\n' > src/main/resources/db/migration/V001__init.sql
printf 'payment:\n  base-url: http://localhost:8081\n' > src/main/resources/application.yaml
