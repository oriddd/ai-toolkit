# Testable Code Principles Skill — Testability anti-patterns

Part of the [`testable-code-principles`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 5. Testability Anti-Patterns (Avoid These)

### ❌ 5a. Static methods for business logic
```java
// ❌ Bad: Cannot mock static methods easily
public class InvoiceUtils {
    public static boolean isValid(Invoice invoice) {
        // Business logic in static method
    }
}

// ✅ Better: Injectable service
@Component
public class InvoiceValidator {
    public boolean isValid(Invoice invoice) { }
}
```

### ❌ 5b. Global state / Singletons
```java
// ❌ Bad: Global state makes tests interfere with each other
public class ConfigManager {
    private static final Map<String, String> GLOBAL_CONFIG = new HashMap<>();
    
    public static void set(String key, String value) {
        GLOBAL_CONFIG.put(key, value);  // Test pollution!
    }
}

// ✅ Better: Instance-based, typed, injectable configuration
@ConfigurationProperties(prefix = "app.processing")
public record ProcessingProperties(ProcessingMode mode, Duration timeout) { }
// registered by @ConfigurationPropertiesScan on the Application class (code-structure §6)
```

### ❌ 5c. Hidden dependencies
```java
// ❌ Bad: Hidden system property dependency
public class InvoiceService {
    public void process() {
        String mode = System.getProperty("processing.mode");  // Hidden!
    }
}

// ✅ Better: Explicit injection
@Service
@RequiredArgsConstructor
public class InvoiceService {
    private final ProcessingProperties processing;
}
```

### ❌ 5d. Mixed concerns in one method
```java
// ❌ Bad: HTTP parsing + business logic + database access in one method
@PostMapping("/invoices")
public ResponseEntity<?> create(@RequestBody Map<String, Object> body) {
    Invoice invoice = new Invoice();
    invoice.setTitle((String) body.get("title"));          // Parsing
    
    if (invoice.getTitle().length() > 100) {               // Validation
        return ResponseEntity.badRequest().build();
    }
    
    entityManager.persist(invoice);                        // Persistence
    log.info("Created invoice {}", invoice.getId());      // Logging
    
    return ResponseEntity.ok(invoice);
}

// ✅ Better: Each concern in its own layer
@PostMapping("/invoices")
public ResponseEntity<InvoiceDto> create(@Valid @RequestBody CreateInvoiceRequest request) {
    InvoiceDto created = createInvoiceOperation.execute(request);
    URI location = ServletUriComponentsBuilder.fromCurrentRequest()
            .path("/{id}").buildAndExpand(created.id()).toUri();
    return ResponseEntity.created(location).body(created);   // 201 + Location (api-design)
}
```
