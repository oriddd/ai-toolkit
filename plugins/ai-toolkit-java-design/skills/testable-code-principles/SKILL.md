---
name: testable-code-principles
description: >
  Java / Spring Boot: Foundational principles for writing testable code - LEGO Bricks (small, focused, self-explanatory components), SDK-like design (document through names not comments), SOLID principles mapped to testability, and avoiding testability anti-patterns (static methods, global state, hidden side effects). Use before writing any new class or when reviewing code quality. Principles only — the concrete package layout and templates live in `code-structure`.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-07-12
---

# Testable Code Principles Skill
This skill defines the **foundational principles** for writing code that is
easy to verify, maintain, and extend. Every class you write should be a
**LEGO brick** — small, focused, self-explanatory, and independently testable.

## When to use

- Before writing any new class or method.
- During code reviews to assess code quality.
- When refactoring legacy code to improve testability.
- As a reference when the code becomes difficult to test.

## Core principle: The LEGO Bricks Metaphor

Think of your code as LEGO bricks that snap together:

**✅ Each brick (class/method) should:**
- Have a **clear, single responsibility**
- Be **small and focused** (class ≤ 200 LOC, method ≤ 30 LOC)
- Have **self-explanatory names** → minimal or no comments needed
- Be **easily replaced or rearranged** without breaking the system
- Be **independently testable** with clear inputs and outputs

**❌ Anti-patterns:**
- Large "god classes" that do everything
- Methods with vague names requiring extensive comments
- Tight coupling that makes components inseparable
- Hidden dependencies that make testing difficult

## 1. What Makes Code Testable?

Code is testable when it exhibits these characteristics:

### 1a. Clear inputs and outputs
```java
// ✅ Good: Clear input → output contract
public InvoiceMetadata extractMetadata(byte[] document, String format) {
    // Easy to test: provide document bytes and format, verify metadata
}

// ❌ Bad: Hidden dependencies, unclear what triggers behavior
public void processInvoice() {
    String filePath = System.getProperty("doc.path");  // Hidden input
    byte[] data = readFromDisk(filePath);               // Side effect
    cachedResult = transform(data);                     // Global state
}
```

### 1b. Independence
Each component should work without depending on:
- Static methods that cannot be mocked
- Global state (singletons, static fields, system properties)
- File system, database, or network in business logic
- Other components' internal state

```java
// ✅ Good: Dependencies injected, testable in isolation
@Service
@RequiredArgsConstructor
public class InvoiceService {
    private final InvoiceValidator validator;
    private final InvoiceRepository repository;
    
    public Invoice save(Invoice invoice) {
        validator.validate(invoice);
        return repository.save(invoice);
    }
}

// ❌ Bad: Static dependencies, cannot test without real filesystem
public class InvoiceService {
    public void save(Invoice invoice) {
        if (InvoiceValidator.isValid(invoice)) {  // Static method
            FileUtils.writeToFile(invoice);         // Static utility, real I/O
        }
    }
}
```

### 1c. Predictable behavior
```java
// ✅ Good: Same inputs always produce same outputs
public int calculatePriority(Request request) {
    return request.isUrgent() ? 1 : request.getCategory().getPriority();
}

// ❌ Bad: Non-deterministic, depends on current time
public int calculatePriority(Request request) {
    if (LocalTime.now().getHour() < 9) {  // Time-dependent
        return 1;
    }
    return request.getCategory().getPriority();
}

// ✅ Better: Inject Clock for testability
public int calculatePriority(Request request, Clock clock) {
    if (LocalTime.now(clock).getHour() < 9) {
        return 1;
    }
    return request.getCategory().getPriority();
}
```

### 1d. No hidden side effects
Every method should do exactly what its name says, nothing more:

```java
// ✅ Good: Does what it says
public ValidationResult validate(Invoice invoice) {
    return validator.check(invoice);
}

// ❌ Bad: Hidden side effects (logging, caching, metrics)
public ValidationResult validate(Invoice invoice) {
    log.info("Validating {}", invoice.getId());     // Side effect
    metrics.increment("validation.count");       // Side effect
    ValidationResult result = validator.check(invoice);
    cache.put(invoice.getId(), result);              // Side effect
    return result;
}

// ✅ Better: Explicit about side effects via separate methods
public ValidationResult validate(Invoice invoice) {
    ValidationResult result = validator.check(invoice);
    recordValidation(invoice, result);  // Explicit side effect method
    return result;
}
```

## 2. SDK-Like Design: Document Through Names, Not Comments

Your code should be consumed by teammates as if it were an external SDK.

### 2a. Self-explanatory method names
```java
// ✅ Good: Name tells you everything
public List<Invoice> findPendingInvoicesAwaitingApproval() { }

// ❌ Bad: Requires comment to understand
// Gets all invoices that are pending
public List<Invoice> getInvoices() { }
```

### 2b. Fail fast on invalid input
```java
// ✅ Good: Validates immediately
public void processInvoice(Invoice invoice) {
    Objects.requireNonNull(invoice, "Invoice cannot be null");
    if (invoice.getContent() == null || invoice.getContent().length == 0) {
        throw new IllegalArgumentException("Invoice content cannot be empty");
    }
    // ... process
}

// ❌ Bad: Fails later with NullPointerException
public void processInvoice(Invoice invoice) {
    byte[] content = invoice.getContent();  // NPE if invoice is null
    transform(content);                  // NPE if content is null
}
```

### 2c. Small, focused public APIs
```java
// ✅ Good: Simple, clear public interface
public interface ExportRenderer {
    byte[] render(byte[] input);
    String getSupportedFormat();
}

// ❌ Bad: Kitchen-sink interface
public interface InvoiceProcessor {
    void initialize();
    void configure(Map<String, Object> config);
    byte[] render(byte[] input);
    void validate(byte[] input);
    String getFormat();
    void shutdown();
    // ... 10 more methods
}
```

### 2d. Favor composition over inheritance
```java
// ✅ Good: Composition, easy to test each piece
@Service
@RequiredArgsConstructor
public class InvoiceService {
    private final InvoiceValidator validator;
    private final InvoiceTransformer transformer;
    private final InvoiceRepository repository;
}

// ❌ Bad: Deep inheritance, hard to test
public class InvoiceService extends BaseService 
    extends AbstractService 
    extends GenericService<Invoice> {
    // Inherits complexity from 3 levels
}
```

## 3. SOLID Principles → Testability Mapping

Each SOLID principle directly improves testability:

### 3a. Single Responsibility Principle (SRP)
**Testability benefit:** One test suite per class, focused assertions.

```java
// ✅ Good: Single responsibility = single test suite
@Service
public class InvoiceValidator {
    public ValidationResult validate(Invoice invoice) { }
}

@Service  
public class InvoiceTransformer {
    public byte[] transform(byte[] input, Format target) { }
}

// ❌ Bad: Multiple responsibilities = complex test setup
@Service
public class InvoiceProcessor {
    public ValidationResult validate(Invoice invoice) { }
    public byte[] transform(byte[] input) { }
    public void save(Invoice invoice) { }
    public void sendNotification(String email) { }
}
```

### 3b. Open/Closed Principle (OCP)
**Testability benefit:** Add new behavior via new classes/tests, not by modifying existing ones.

```java
// ✅ Good: New format = new strategy + new test class
public interface ExportRenderer {
    byte[] render(byte[] input);
    boolean supports(String format);
}

@Component
public class PdfExporter implements ExportRenderer { }

@Component  
public class HtmlExporter implements ExportRenderer { }
// Add DocxExporter without touching existing code/tests

// ❌ Bad: New format = modify switch + update all existing tests
public byte[] render(byte[] input, String format) {
    switch (format) {
        case "PDF": return renderToPdf(input);
        case "HTML": return renderToHtml(input);
        // Adding DOCX requires modifying this method + all tests
    }
}
```

### 3c. Liskov Substitution Principle (LSP)
**Testability benefit:** Can replace implementations in tests without rewriting assertions.

```java
// ✅ Good: All implementations honor the contract
public interface InvoiceRepository {
    Optional<Invoice> findById(String id);  // Never throws, returns empty
}

// Can use real DB in integration tests, in-memory fake in unit tests
public class InMemoryInvoiceRepository implements InvoiceRepository { }
public class JpaInvoiceRepository implements InvoiceRepository { }

// ❌ Bad: Subclass violates contract, breaks tests
public class StrictInvoiceRepository implements InvoiceRepository {
    public Optional<Invoice> findById(String id) {
        if (id == null) throw new NullPointerException();  // Contract violation!
        // Base interface says "return empty", but this throws
    }
}
```

### 3d. Interface Segregation Principle (ISP)
**Testability benefit:** Smaller interfaces = easier to mock, fewer irrelevant methods in tests.

```java
// ✅ Good: Focused interfaces, mock only what you need
public interface InvoiceReader {
    Invoice read(String id);
}

public interface InvoiceWriter {
    void save(Invoice invoice);
}

// Test only needs InvoiceReader mock
@Test
void testInvoiceProcessor() {
    InvoiceReader reader = mock(InvoiceReader.class);
    // Don't need to mock save() methods
}

// ❌ Bad: Fat interface forces you to mock methods you don't use
public interface InvoiceRepository {
    Invoice read(String id);
    void save(Invoice invoice);
    void delete(String id);
    List<Invoice> findAll();
    void updateMetadata(String id, Metadata meta);
    // ... 10 more methods
}
```

### 3e. Dependency Inversion Principle (DIP)
**Testability benefit:** Inject mocks/stubs instead of using real classes.

```java
// ✅ Good: Depends on abstraction, easy to inject test double
@Service
@RequiredArgsConstructor
public class InvoiceService {
    private final InvoiceRepository repository;  // Interface
    
    public Invoice getInvoice(String id) {
        return repository.findById(id).orElseThrow();
    }
}

// Test injects mock
@Test
void testGetInvoice() {
    InvoiceRepository mockRepo = mock(InvoiceRepository.class);
    InvoiceService service = new InvoiceService(mockRepo);
    // Test with full control
}

// ❌ Bad: Depends on concrete class, creates its own dependencies
@Service
public class InvoiceService {
    private JpaInvoiceRepository repository = new JpaInvoiceRepository();
    // Cannot inject mock, must test with real database
}
```

## 4. Design Patterns That Support SOLID & Testability

| Pattern | SOLID Principles | Testability Benefit |
|---------|------------------|---------------------|
| **Strategy** | OCP, SRP | Add new behaviors via new classes + tests; test each strategy independently |
| **Factory** | DIP, SRP | Mock factory to return test doubles; decouple object creation |
| **Adapter** | LSP, OCP | Swap implementations in tests (real service vs stub) |
| **Decorator** | OCP, SRP | Add cross-cutting concerns (metrics, retry) without changing core logic or tests |
| **Observer** | OCP, DIP | Loosely coupled events; test publishers and listeners separately |
| **Builder** | SRP, DIP | Construct complex test data; immutable objects |

Reference implementation: See `code-structure` for Strategy + Registry pattern.

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

// ✅ Better: Instance-based, injectable configuration
@ConfigurationProperties(prefix = "app")
public record AppConfig(Map<String, String> settings) { }
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
    private final ProcessingConfig config;
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
    return ResponseEntity.ok(operation.createInvoice(request));
}
```

## 6. Checklist: Is Your Code Testable?

Before submitting code for review, verify:

- [ ] **Clear inputs/outputs** — No hidden dependencies on system state, files, time
- [ ] **Single responsibility** — Class/method name describes exactly one thing
- [ ] **No static methods** for business logic — Everything is injectable
- [ ] **No global state** — No static fields, singletons, or shared mutable state
- [ ] **Dependencies injected** — Constructor injection, not field injection or `new`
- [ ] **Predictable** — Same inputs always produce same outputs
- [ ] **No hidden side effects** — Method does what its name says, nothing more
- [ ] **Small** — Class ≤ 200 LOC, method ≤ 30 LOC, cyclomatic complexity ≤ 10
- [ ] **Self-explanatory names** — Minimal comments needed
- [ ] **Fail fast** — Validates inputs immediately at method entry

## 7. Cross-references

This skill is foundational and referenced by:
- `unit-tests` — Applies these principles when generating tests
- `quality-review` — Audits code against these principles
- [`code-structure`](../code-structure/SKILL.md) — Package layout and SOLID implementation
- `refactoring-playbook` — Migrations to testable patterns
- `external-client` — SDK-style design example

## 8. Summary

**Core philosophy:** Write code as if your teammates will consume it as an external SDK.

**LEGO Bricks mindset:**
- Small, focused components
- Self-explanatory names
- Clear responsibilities
- Easy to test, replace, and extend

**SOLID = Testable:**
- SRP → One test suite per class
- OCP → Add behavior without breaking tests
- LSP → Swap implementations in tests
- ISP → Easy to mock
- DIP → Inject test doubles

**Avoid:** Static methods, global state, hidden dependencies, mixed concerns.
