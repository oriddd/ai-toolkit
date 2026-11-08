# Testable Code Principles Skill — SDK-like design

Part of the [`testable-code-principles`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

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
// ✅ Good: Fails immediately — request rules ("content not empty") are enforced
// before this call by the validation layer (@Valid + validators, see input-validation),
// and Invoice rejects empty content in its own constructor (domain invariant).
// The method only guards what it relies on.
public void processInvoice(Invoice invoice) {
    Objects.requireNonNull(invoice, "Invoice cannot be null");
    // ... process
}

// Invariant lives in the domain type, not in every service method
public record Invoice(String id, byte[] content) {
    public Invoice {
        Objects.requireNonNull(content, "content");
        if (content.length == 0) {
            throw new IllegalArgumentException("Invoice content cannot be empty");
        }
    }
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
public class InvoiceService extends BaseService { }   // BaseService extends AbstractService,
                                                    // which extends GenericService<Invoice>
// Inherits complexity (and hidden state) from 3 levels
```
