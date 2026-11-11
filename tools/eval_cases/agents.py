"""Agent cases: project fixtures, delegation prompts that name the agent, and the skill each agent must load."""

FIXTURES = {
    "java": r"""set -euo pipefail
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
""",
    "python": r"""set -euo pipefail
mkdir -p src/orders/api tests
cat > pyproject.toml <<'EOF'
[project]
name = "orders"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["fastapi>=0.115", "pydantic>=2.9", "sqlalchemy>=2.0"]
EOF
touch src/orders/__init__.py src/orders/api/__init__.py
cat > src/orders/main.py <<'EOF'
from fastapi import FastAPI
from orders.api.orders import router

app = FastAPI()
app.include_router(router)
EOF
cat > src/orders/api/orders.py <<'EOF'
from fastapi import APIRouter
import requests

router = APIRouter(prefix="/api/v1/orders")
PAYMENT_URL = "http://localhost:8081"
ORDERS: dict[str, dict] = {}


@router.post("")
def create(order: dict):
    if order.get("quantity", 0) <= 0:
        raise Exception("bad quantity")
    ORDERS[order["id"]] = order
    requests.post(PAYMENT_URL + "/payments", json=order)
    return order
EOF
""",
    "react-native": r"""set -euo pipefail
mkdir -p src/screens src/api
cat > package.json <<'EOF'
{
  "name": "shop-app",
  "version": "0.1.0",
  "private": true,
  "dependencies": { "react": "19.1.0", "react-native": "0.81.4", "@tanstack/react-query": "^5.0.0", "@react-navigation/native": "^7.1.0", "@react-navigation/native-stack": "^7.3.0", "zod": "^4.0.0" },
  "devDependencies": { "typescript": "~6.0.0", "jest": "^30.0.0" }
}
EOF
printf '{ "compilerOptions": { "strict": true, "jsx": "react-native" } }\n' > tsconfig.json
mkdir -p src/navigation src/types
cat > src/api/client.ts <<'EOF'
const BASE_URL = 'https://api.example.com';

export async function apiGet<T>(path: string): Promise<T> {
  const res = await fetch(BASE_URL + path);
  if (!res.ok) throw new Error(`GET ${path} failed: ${res.status}`);
  return (await res.json()) as T;
}

export async function apiSend<T>(method: 'POST' | 'DELETE', path: string, body?: unknown): Promise<T> {
  const res = await fetch(BASE_URL + path, { method, body: body ? JSON.stringify(body) : undefined, headers: { 'Content-Type': 'application/json' } });
  if (!res.ok) throw new Error(`${method} ${path} failed: ${res.status}`);
  return (await res.json()) as T;
}
EOF
cat > src/navigation/RootNavigator.tsx <<'EOF'
import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { LoginScreen } from '../screens/LoginScreen';
import { OrdersScreen } from '../screens/OrdersScreen';

export type RootStackParamList = { Login: undefined; Orders: undefined };
const Stack = createNativeStackNavigator<RootStackParamList>();

export function RootNavigator() {
  return (
    <NavigationContainer>
      <Stack.Navigator>
        <Stack.Screen name="Login" component={LoginScreen} />
        <Stack.Screen name="Orders" component={OrdersScreen} />
      </Stack.Navigator>
    </NavigationContainer>
  );
}
EOF
cat > src/screens/OrdersScreen.tsx <<'EOF'
import React from 'react';
import { Text, View } from 'react-native';

export function OrdersScreen() {
  return (
    <View>
      <Text>Orders</Text>
    </View>
  );
}
EOF
cat > src/screens/LoginScreen.tsx <<'EOF'
import React, { useState } from 'react';
import { Button, Text, TextInput, View } from 'react-native';

export function LoginScreen() {
  const [email, setEmail] = useState('');
  const [error, setError] = useState('');
  const login = async () => {
    const res = await fetch('https://api.example.com/login', { method: 'POST', body: JSON.stringify({ email }) });
    if (!res.ok) setError('Login failed');
  };
  return (
    <View>
      <TextInput value={email} onChangeText={setEmail} />
      {error ? <Text>{error}</Text> : null}
      <Button title="Log in" onPress={login} />
    </View>
  );
}
EOF
""",
}

AGENTS = {
    "ai-toolkit-java-agents": ("java", {
        "code-review": "Use the code-review agent: Review my changes to OrderController.java and OrderService.java against our Java standards before I open the pull request. Do not change anything.",
        "new-endpoint": "Use the new-endpoint agent: Add a GET /api/v1/orders/{id} endpoint to this service, from controller to tests. Orders are stored through OrderRepository (Spring Data JPA, PostgreSQL); the API is internal and needs no authorization.",
        "new-feature": "Use the new-feature agent: Implement order cancellation end to end in this service: a new endpoint, persisting the cancellation, notifying the payment service over HTTP, validation, tests and docs. Orders are stored through OrderRepository (Spring Data JPA, PostgreSQL); the API is internal and needs no authorization.",
        "new-kafka-consumer": "Use the new-kafka-consumer agent: Add a Kafka consumer to this service for PaymentCompleted events that marks the order as paid. Orders are stored through OrderRepository (Spring Data JPA, PostgreSQL); the API is internal and needs no authorization.",
        "new-metric": "Use the new-metric agent: Add a Micrometer timer metric for the POST /api/v1/orders endpoint of this service. Orders are stored through OrderRepository (Spring Data JPA, PostgreSQL); the API is internal and needs no authorization.",
        "new-microservice-client": "Use the new-microservice-client agent: Integrate the Inventory service's REST API (GET /items/{id}) into this service as a new downstream client. Orders are stored through OrderRepository (Spring Data JPA, PostgreSQL); the API is internal and needs no authorization.",
        "new-validation": "Use the new-validation agent: Add a validation rule to this service: an order's quantity must be between 1 and 100, and its sku must match the format ABC-12345 (three capital letters, a dash, five digits). Orders are stored through OrderRepository (Spring Data JPA, PostgreSQL); the API is internal and needs no authorization.",
        "refactor": "Use the refactor agent: OrderService in this repo uses @Value fields, a hand-built RestTemplate and raw RuntimeExceptions. Migrate it to our canonical patterns safely, step by step. Orders are stored through OrderRepository (Spring Data JPA, PostgreSQL); the API is internal and needs no authorization.",
        "test-writer": "Use the test-writer agent: The production code is done. Write the JUnit tests for the existing OrderService and OrderController classes. Orders are stored through OrderRepository (Spring Data JPA, PostgreSQL); the API is internal and needs no authorization.",
    }),
    "ai-toolkit-python-agents": ("python", {
        "python-code-review": "Use the python-code-review agent: Review my changes to src/orders/api/orders.py against our Python standards before I open the pull request. Do not change anything.",
        "python-new-endpoint": "Use the python-new-endpoint agent: Add a GET /api/v1/orders/{order_id} endpoint to this FastAPI service, from router to tests. The service is internal and needs no authorization; keep orders in the existing in-memory store for now.",
        "python-new-feature": "Use the python-new-feature agent: Implement order cancellation end to end in this FastAPI service: endpoint, persistence, a call to the payment service, validation, tests and docs. The service is internal and needs no authorization; keep orders in the existing in-memory store for now.",
        "python-refactor": "Use the python-refactor agent: src/orders/api/orders.py has business logic in the router, a module-level URL constant and bare Exceptions. Migrate it to our canonical patterns safely, step by step. The service is internal and needs no authorization; keep orders in the existing in-memory store for now.",
        "python-test-writer": "Use the python-test-writer agent: The production code is done. Write the pytest tests for the existing src/orders/api/orders.py module. The service is internal and needs no authorization; keep orders in the existing in-memory store for now.",
    }),
    "ai-toolkit-react-native-agents": ("react-native", {
        "react-native-code-review": "Use the react-native-code-review agent: Review my changes to src/screens/LoginScreen.tsx against our React Native standards before I open the pull request. Do not change anything.",
        "react-native-new-feature": "Use the react-native-new-feature agent: Implement a wishlist feature end to end in this React Native app: a Wishlist screen in the root stack, the data layer on the existing api client (src/api/client.ts) — GET /wishlist returns { items: { productId: string, name: string }[] }, POST /wishlist { productId } adds, DELETE /wishlist/{productId} removes — with optimistic add/remove, validation, error handling and tests. No authentication changes are needed.",
        "react-native-new-screen": "Use the react-native-new-screen agent: Add an OrderDetails screen to this React Native app, added to the root stack in src/navigation/RootNavigator.tsx with an orderId param and opened from OrdersScreen. It shows one order from GET /orders/{id} on the existing api client (src/api/client.ts), which returns { id: string, status: 'PENDING' | 'SHIPPED', total: number }. No authentication changes are needed.",
        "react-native-refactor": "Use the react-native-refactor agent: LoginScreen.tsx fetches inside the component and handles errors ad hoc. Migrate it to our canonical patterns safely, one step at a time. The backend API already exists at https://api.example.com; no authentication changes are needed.",
        "react-native-test-writer": "Use the react-native-test-writer agent: The production code is done. Write the Jest and React Native Testing Library tests for the existing LoginScreen component. The backend API already exists at https://api.example.com; no authentication changes are needed.",
    }),
    "ai-toolkit-docs": ("java", {
        "update-context": "Use the update-context agent: I just added order creation to this service — POST /api/v1/orders in OrderController, OrderService saves through OrderRepository and notifies the payment service, and migration V001__init.sql creates the orders table. Bring the project's context docs, progress tracker and CHANGELOG in line with that change; create them if they do not exist yet.",
    }),
}

NO_DELEGATE = {
    "ai-toolkit-java-agents": [
        ("no-delegate-scaffold-repo", "java", "scaffold-repo",
         "Create a brand-new Spring Boot microservice repository for a notifications service.",
         "`scaffold-repo` is main-session only (`claude --agent`); a subagent cannot ask the developer anything"),
    ],
}

UNRELATED_AGENT_PROMPT = "In two sentences, what is the difference between a process and a thread?"

AGENT_SKILLS = {
    "code-review": ["quality-review", "golden-path"],
    "new-endpoint": ["api-design", "code-structure"],
    "new-feature": ["golden-path", "code-structure"],
    "new-kafka-consumer": ["messaging"],
    "new-metric": ["request-metrics"],
    "new-microservice-client": ["external-client"],
    "new-validation": ["input-validation", "validation-pattern"],
    "refactor": ["refactoring-playbook", "quality-review", "spring-boot-conventions"],
    "test-writer": ["unit-tests", "component-tests"],
    "python-code-review": ["python-code-structure", "code-hygiene"],
    "python-new-endpoint": ["python-fastapi-conventions"],
    "python-new-feature": ["python-code-structure", "python-fastapi-conventions"],
    "python-refactor": ["python-code-structure"],
    "python-test-writer": ["python-unit-tests"],
    "react-native-code-review": ["react-native-code-structure", "react-native-state-and-data", "code-hygiene"],
    "react-native-new-feature": ["react-native-code-structure", "react-native-state-and-data"],
    "react-native-new-screen": ["react-native-code-structure", "react-native-state-and-data"],
    "react-native-refactor": ["react-native-code-structure", "react-native-state-and-data"],
    "react-native-test-writer": ["react-native-unit-tests"],
    "update-context": ["context-maintenance"],
}
