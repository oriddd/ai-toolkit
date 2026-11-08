---
name: testable-code-principles
description: >
  Java / Spring Boot testability principles — small LEGO-brick classes, names over comments, SOLID mapped to testing,
  no static methods, global state or hidden side effects. Use before writing a new class or when reviewing code
  quality. Package layout lives in `code-structure`.
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

## Reference map — load only the part you are working on

Sections below keep their numbers but live in `references/` so this file stays small. Read only the file you need; do not load them all.

| Sections | Topic | Load when | File |
| --- | --- | --- | --- |
| §2 | document through names, not comments | naming or documenting a class | [`sdk-like-design.md`](./references/sdk-like-design.md) |
| §3 | each SOLID principle with before/after code | reviewing a class against SOLID | [`solid-mapping.md`](./references/solid-mapping.md) |
| §5 | static methods, global state, hidden side effects | a class is hard to test | [`anti-patterns.md`](./references/anti-patterns.md) |

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
- `code-structure` — Package layout and SOLID implementation
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
