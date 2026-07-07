---
name: domain-modeling
description: Tactical Domain-Driven Design vocabulary every Java microservice should adopt — Bounded Context, Aggregate Root, Entity, Value Object, Domain Event, Domain Service, Repository, Anti-Corruption Layer (ACL), Specification. Optional but encouraged when the service represents a non-trivial business concept. Use during initial design or when adding a new aggregate to an existing service.
tier: should
applies_to: [rest, event, monolith]
depends_on: [code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Domain Modeling Skill (public)

Optional layer of vocabulary that pays off when the business logic is
non-trivial. Pure CRUD services do not need DDD; anything with invariants,
workflows, or interesting business rules does.

## 1. Bounded Context = the microservice

One microservice ≈ one Bounded Context. Its **ubiquitous language** is
documented in `docs/GLOSSARY.md`.

If two terms have different meanings in two contexts (e.g. `Order` means
something different to billing vs. shipping), they live in **different
services**, never the same one.

## 2. Aggregate Root

The entry-point of a consistency boundary. **All mutations** to entities
inside the aggregate go through the root.

```java
public class Document {                        // Aggregate Root
    private final DocumentId id;               // Value Object
    private String name;
    private Status status;
    private final List<File> files = new ArrayList<>();

    public void rename(String newName) {        // invariant: name not blank, doc not deleted
        requireNotDeleted();
        if (newName == null || newName.isBlank()) throw new InvariantViolationException(...);
        this.name = newName;
        registerEvent(new DocumentRenamedEvent(id, newName, Instant.now()));
    }

    public List<File> files() { return List.copyOf(files); }   // immutable view
}
```

Rules:
- One transaction = one aggregate. Cross-aggregate consistency is **eventual**
  via Domain Events (see `messaging` outbox).
- Repositories only return aggregate roots, never inner entities.
- The root **encapsulates state**: callers tell it to do something, never
  ask for its internals to do it themselves (Tell, Don't Ask — see
  `code-structure` §4f).

## 3. Value Object

Immutable type identified by its **value**, not identity. Records are the
natural fit:

```java
public record Money(BigDecimal amount, Currency currency) {
    public Money { Objects.requireNonNull(currency); if (amount.signum() < 0) throw …; }
    public Money plus(Money other) { … }
}
```

Examples: `Money`, `DocumentId`, `EmailAddress`, `DateRange`, `Coordinates`.
**Never** pass primitive `String id` around — wrap in a `DocumentId` so the
compiler catches mix-ups.

## 4. Domain Event

A record describing **something that happened**, past tense. Lives in
`event/`. Published via the outbox (see `messaging`).

```java
public record DocumentRenamedEvent(DocumentId id, String newName, Instant occurredAt)
        implements DomainEvent {}
```

## 5. Domain Service

When behaviour does not naturally belong to one aggregate (e.g. transferring
balance between two accounts):

```java
@Component
public class TransferService {
    public void transfer(Account from, Account to, Money amount) { … }
}
```

Lives in `domain/`. Never injects repositories — receives loaded
aggregates as parameters.

## 6. Repository

The collection-like illusion for aggregates. Spring Data repositories are
acceptable as long as their interfaces return aggregate roots only.

```java
public interface DocumentRepository extends Repository<Document, DocumentId> {
    Optional<Document> findById(DocumentId id);
    void save(Document doc);
}
```

## 7. Anti-Corruption Layer (ACL)

Between this Bounded Context and an external system whose model is
incompatible (legacy API, third-party SDK, partner service). The ACL
translates **their** language into ours.

```
operation/    ─► acl/PartnerCustomerAdapter ─► client/partner/PartnerClient
                       (their Customer → our Account)
```

Without an ACL, the partner's concepts leak into your domain and the
re-platforming cost compounds. This is the strict version of the `Adapter`
pattern from `external-client`.

## 8. Specification

Composable business rules expressed as objects (see `persistence` §2):

```java
public final class DocumentSpecs {
    public static Specification<Document> overdueFor(Instant cutoff) { … }
    public static Specification<Document> ownedBy(UserId u)          { … }
}
```

`overdueFor(now).and(ownedBy(alice))` — readable, testable, composable.

## 9. When DDD is overkill

Skip aggregate / value-object discipline when:
- The service is pure CRUD over external data.
- The business has fewer than 5 concepts.
- The team is < 3 engineers and the service is < 6 months old.

Adopt incrementally; the rest of the skill set still applies.

## Do / Don't

✅ Wrap identifiers in Value Objects; the type system catches half of all
bugs.
✅ One aggregate per transaction; cross-aggregate consistency is async.
✅ Document the ubiquitous language in `docs/GLOSSARY.md` and keep it
synced.
❌ Never share an aggregate between two services. If you need to, you have
the wrong bounded contexts.
❌ Never expose an aggregate as a JSON response — map to a DTO.
❌ Never put repositories inside aggregates (anaemic + circular).

