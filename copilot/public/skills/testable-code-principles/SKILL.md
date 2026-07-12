---
name: testable-code-principles
description: Foundational principles for writing testable code - LEGO Bricks (small, focused, self-explanatory components), SDK-like design (document through names not comments), SOLID principles mapped to testability, and avoiding testability anti-patterns (static methods, global state, hidden side effects). Use before writing any new class or when reviewing code quality.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-07-12
---

# Testable Code Principles Skill (public)

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
public DocumentMetadata extractMetadata(byte[] document, String format) {
    // Easy to test: provide document bytes and format, verify metadata
}

// ❌ Bad: Hidden dependencies, unclear what triggers behavior
public void processDocument() {
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
public class DocumentService {
    private final DocumentValidator validator;
    private final DocumentRepository repository;
    
    public Document save(Document doc) {
        validator.validate(doc);
        return repository.save(doc);
    }
}

// ❌ Bad: Static dependencies, cannot test without real filesystem
public class DocumentService {
    public void save(Document doc) {
        if (DocumentValidator.isValid(doc)) {  // Static method
            FileUtils.writeToFile(doc);         // Static utility, real I/O
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
public ValidationResult validate(Document doc) {
    return validator.check(doc);
}

// ❌ Bad: Hidden side effects (logging, caching, metrics)
public ValidationResult validate(Document doc) {
    log.info("Validating {}", doc.getId());     // Side effect
    metrics.increment("validation.count");       // Side effect
    ValidationResult result = validator.check(doc);
    cache.put(doc.getId(), result);              // Side effect
    return result;
}

// ✅ Better: Explicit about side effects via separate methods
public ValidationResult validate(Document doc) {
    ValidationResult result = validator.check(doc);
    recordValidation(doc, result);  // Explicit side effect method
    return result;
}
```

## 2. SDK-Like Design: Document Through Names, Not Comments

Your code should be consumed by teammates as if it were an external SDK.

### 2a. Self-explanatory method names
```java
// ✅ Good: Name tells you everything
public List<Document> findPendingDocumentsAwaitingApproval() { }

// ❌ Bad: Requires comment to understand
// Gets all docs that are pending
public List<Document> getDocs() { }
```

### 2b. Fail fast on invalid input
```java
// ✅ Good: Validates immediately
public void processDocument(Document doc) {
    Objects.requireNonNull(doc, "Document cannot be null");
    if (doc.getContent() == null || doc.getContent().length == 0) {
        throw new IllegalArgumentException("Document content cannot be empty");
    }
    // ... process
}

// ❌ Bad: Fails later with NullPointerException
public void processDocument(Document doc) {
    byte[] content = doc.getContent();  // NPE if doc is null
    transform(content);                  // NPE if content is null
}
```

### 2c. Small, focused public APIs
```java
// ✅ Good: Simple, clear public interface
public interface DocumentConverter {
    byte[] convert(byte[] input);
    String getSupportedFormat();
}

// ❌ Bad: Kitchen-sink interface
public interface DocumentProcessor {
    void initialize();
    void configure(Map<String, Object> config);
    byte[] convert(byte[] input);
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
public class DocumentService {
    private final DocumentValidator validator;
    private final DocumentTransformer transformer;
    private final DocumentRepository repository;
}

// ❌ Bad: Deep inheritance, hard to test
public class DocumentService extends BaseService 
    extends AbstractService 
    extends GenericService<Document> {
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
public class DocumentValidator {
    public ValidationResult validate(Document doc) { }
}

@Service  
public class DocumentTransformer {
    public byte[] transform(byte[] input, Format target) { }
}

// ❌ Bad: Multiple responsibilities = complex test setup
@Service
public class DocumentProcessor {
    public ValidationResult validate(Document doc) { }
    public byte[] transform(byte[] input) { }
    public void save(Document doc) { }
    public void sendNotification(String email) { }
}
```

### 3b. Open/Closed Principle (OCP)
**Testability benefit:** Add new behavior via new classes/tests, not by modifying existing ones.

```java
// ✅ Good: New format = new strategy + new test class
public interface DocumentConverter {
    byte[] convert(byte[] input);
    boolean supports(String format);
}

@Component
public class PdfConverter implements DocumentConverter { }

@Component  
public class HtmlConverter implements DocumentConverter { }
// Add DocxConverter without touching existing code/tests

// ❌ Bad: New format = modify switch + update all existing tests
public byte[] convert(byte[] input, String format) {
    switch (format) {
        case "PDF": return convertToPdf(input);
        case "HTML": return convertToHtml(input);
        // Adding DOCX requires modifying this method + all tests
    }
}
```

### 3c. Liskov Substitution Principle (LSP)
**Testability benefit:** Can replace implementations in tests without rewriting assertions.

```java
// ✅ Good: All implementations honor the contract
public interface DocumentRepository {
    Optional<Document> findById(String id);  // Never throws, returns empty
}

// Can use real DB in integration tests, in-memory fake in unit tests
public class InMemoryDocumentRepository implements DocumentRepository { }
public class JpaDocumentRepository implements DocumentRepository { }

// ❌ Bad: Subclass violates contract, breaks tests
public class StrictDocumentRepository implements DocumentRepository {
    public Optional<Document> findById(String id) {
        if (id == null) throw new NullPointerException();  // Contract violation!
        // Base interface says "return empty", but this throws
    }
}
```

### 3d. Interface Segregation Principle (ISP)
**Testability benefit:** Smaller interfaces = easier to mock, fewer irrelevant methods in tests.

```java
// ✅ Good: Focused interfaces, mock only what you need
public interface DocumentReader {
    Document read(String id);
}

public interface DocumentWriter {
    void save(Document doc);
}

// Test only needs DocumentReader mock
@Test
void testDocumentProcessor() {
    DocumentReader reader = mock(DocumentReader.class);
    // Don't need to mock save() methods
}

// ❌ Bad: Fat interface forces you to mock methods you don't use
public interface DocumentRepository {
    Document read(String id);
    void save(Document doc);
    void delete(String id);
    List<Document> findAll();
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
public class DocumentService {
    private final DocumentRepository repository;  // Interface
    
    public Document getDocument(String id) {
        return repository.findById(id).orElseThrow();
    }
}

// Test injects mock
@Test
void testGetDocument() {
    DocumentRepository mockRepo = mock(DocumentRepository.class);
    DocumentService service = new DocumentService(mockRepo);
    // Test with full control
}

// ❌ Bad: Depends on concrete class, creates its own dependencies
@Service
public class DocumentService {
    private JpaDocumentRepository repository = new JpaDocumentRepository();
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
public class DocumentUtils {
    public static boolean isValid(Document doc) {
        // Business logic in static method
    }
}

// ✅ Better: Injectable service
@Component
public class DocumentValidator {
    public boolean isValid(Document doc) { }
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
public class DocumentService {
    public void process() {
        String mode = System.getProperty("processing.mode");  // Hidden!
    }
}

// ✅ Better: Explicit injection
@Service
@RequiredArgsConstructor
public class DocumentService {
    private final ProcessingConfig config;
}
```

### ❌ 5d. Mixed concerns in one method
```java
// ❌ Bad: HTTP parsing + business logic + database access in one method
@PostMapping("/documents")
public ResponseEntity<?> create(@RequestBody Map<String, Object> body) {
    Document doc = new Document();
    doc.setTitle((String) body.get("title"));          // Parsing
    
    if (doc.getTitle().length() > 100) {               // Validation
        return ResponseEntity.badRequest().build();
    }
    
    entityManager.persist(doc);                        // Persistence
    log.info("Created document {}", doc.getId());      // Logging
    
    return ResponseEntity.ok(doc);
}

// ✅ Better: Each concern in its own layer
@PostMapping("/documents")
public ResponseEntity<DocumentDto> create(@Valid @RequestBody CreateDocumentRequest request) {
    return ResponseEntity.ok(operation.createDocument(request));
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
- [`unit-tests`](../unit-tests/SKILL.md) — Applies these principles when generating tests
- [`quality-review`](../quality-review/SKILL.md) — Audits code against these principles
- [`code-structure`](../code-structure/SKILL.md) — Package layout and SOLID implementation
- [`refactoring-playbook`](../refactoring-playbook/SKILL.md) — Migrations to testable patterns
- [`external-client`](../external-client/SKILL.md) — SDK-style design example

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
