# Testable Code Principles Skill — SOLID → testability mapping

Part of the [`testable-code-principles`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

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
public class InvoicePdfRenderer implements ExportRenderer { }

@Component  
public class InvoiceHtmlRenderer implements ExportRenderer { }
// Add InvoiceDocxRenderer without touching existing code/tests

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
