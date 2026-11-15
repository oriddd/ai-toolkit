---
name: domain-modeling
description: >
  Java / Spring Boot tactical DDD — bounded context, aggregate root, entity, value object, domain event, domain
  service, repository, anti-corruption layer, specification. Use during initial design or when adding a new aggregate
  to a service.
tier: should
applies_to: [rest, event, monolith]
depends_on: [code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

# Domain Modeling Skill
Optional layer of vocabulary that pays off when the business logic is
non-trivial. Pure CRUD services do not need DDD; anything with invariants,
workflows, or interesting business rules does.

## 1. Bounded Context = the microservice

One microservice ≈ one Bounded Context. Its **ubiquitous language** is
documented in `docs/GLOSSARY.md`.

If two terms have different meanings in two contexts (e.g. `Order` means
something different to billing vs. shipping), they live in **different
bounded contexts** — a separate service, or a separate module of a modular
monolith (`code-structure` §4k, Pattern D) — never in the same model.

## 2. Aggregate Root

The entry-point of a consistency boundary. **All mutations** to entities
inside the aggregate go through the root.

```java
public class Invoice extends AbstractAggregateRoot<Invoice> {   // Aggregate Root; registerEvent(...) comes from Spring Data
    private final InvoiceId id;               // Value Object
    private String name;
    private Status status;
    private final List<InvoiceLine> lines = new ArrayList<>();

    public void rename(String newName, Clock clock) {   // invariant: name not blank, invoice not deleted
        requireNotDeleted();
        if (newName == null || newName.isBlank()) throw ExceptionMessages.invalidField("name", "must not be blank");   // exception-handling catalogue → 400
        this.name = newName;
        registerEvent(new InvoiceRenamedEvent(id, newName, Instant.now(clock)));   // caller passes its injected Clock, never Instant.now()
    }

    public List<InvoiceLine> lines() { return List.copyOf(lines); }   // immutable view
}
```

`registerEvent` is inherited from Spring Data's `AbstractAggregateRoot`: the
events are published **in-process** (as application events) when **this object**
is passed to a Spring Data repository's `save()` / `saveAll()` / `delete()`, and
they are not durable. For events that must leave the service, bridge them to
the outbox: a `@TransactionalEventListener(phase = BEFORE_COMMIT)` (or a plain
`@EventListener`) writes the outbox row in the same transaction (see `messaging`).

This is a **domain class**, not a JPA entity: `final` fields and no no-arg
constructor are deliberate. Pick one mapping:

- **The root is the `@Entity`** (keeps `AbstractAggregateRoot`): annotate it,
  add a `protected` no-arg constructor and drop `final` on the persistent fields
  (JPA needs both). `repository.save(invoice)` publishes the events.
- **A separate JPA entity in `entity/`**, mapped in the repository adapter. Then
  `AbstractAggregateRoot` publishes **nothing**: the adapter saves the
  `InvoiceEntity`, which carries no events, so they — and the outbox rows a
  `BEFORE_COMMIT` listener would write — are silently lost. Do not extend
  `AbstractAggregateRoot` here (its `domainEvents()` is `protected`); the root
  keeps its own list and the adapter publishes it in the same transaction:

```java
public class Invoice {                                         // no AbstractAggregateRoot in this variant
    private final List<DomainEvent> domainEvents = new ArrayList<>();
    public void rename(String newName, Clock clock) { …; domainEvents.add(new InvoiceRenamedEvent(id, newName, Instant.now(clock))); }
    public List<DomainEvent> pullDomainEvents() {             // returns and clears, so a second save never republishes
        List<DomainEvent> events = List.copyOf(domainEvents);
        domainEvents.clear();
        return events;
    }
}

@Repository
@RequiredArgsConstructor
class JpaInvoiceRepositoryAdapter implements InvoiceRepository {
    private final InvoiceJpaRepository jpa;                    // Spring Data, over entity/InvoiceEntity
    private final InvoiceEntityMapper mapper;
    private final ApplicationEventPublisher events;

    @Override
    @Transactional(propagation = Propagation.MANDATORY)        // runs inside the service's transaction
    public void save(Invoice invoice) {
        jpa.save(mapper.toEntity(invoice));
        invoice.pullDomainEvents().forEach(events::publishEvent);   // BEFORE_COMMIT listeners see them in this transaction
    }
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
    public Money {
        Objects.requireNonNull(amount, "amount");
        Objects.requireNonNull(currency, "currency");
        // normalise the scale: BigDecimal.equals compares scale, so 10.0 and 10.00 would not be equal records
        amount = amount.setScale(currency.getDefaultFractionDigits(), RoundingMode.HALF_EVEN);
        // add `if (amount.signum() < 0) throw …;` only where the domain forbids negatives
        // (a price may, a balance or a refund must not)
    }
    public Money plus(Money other) { … }
}
```

Examples: `Money`, `InvoiceId`, `EmailAddress`, `DateRange`, `Coordinates`.
**Inside the domain, never** pass primitive `String id` around — wrap in an
`InvoiceId` so the compiler catches mix-ups. At the edges (controller path
variables, API DTOs, downstream client calls) a `String` / `UUID` id is fine;
convert it to the Value Object at the boundary.

## 4. Domain Event

A record describing **something that happened**, past tense. Lives in
`event/`. Published via the outbox (see `messaging`).

```java
public record InvoiceRenamedEvent(InvoiceId id, String newName, Instant occurredAt)
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

Changing **two** aggregates in one transaction breaks §2's "one transaction =
one aggregate". Either record it as a deliberate, documented exception (both
aggregates in the same database and the business needs strong consistency, see
`documentation-and-adr`), or make it eventually consistent: debit `from`,
publish a `BalanceDebitedEvent` via the outbox, and credit `to` in its own
transaction, with a compensating step on failure (a saga).

## 6. Repository

The collection-like illusion for aggregates. Spring Data repositories are
acceptable as long as their interfaces return aggregate roots only.

```java
public interface InvoiceRepository extends Repository<Invoice, InvoiceId> {
    Optional<Invoice> findById(InvoiceId id);
    void save(Invoice invoice);
}
```

A Value Object id only works as a Spring Data / JPA id when it is mapped:
make `InvoiceId` an `@Embeddable` and the field an `@EmbeddedId` (records work
as embeddables on Hibernate 6.2+), or keep the JPA entity separate with a raw
`UUID` id and convert to `InvoiceId` in the repository adapter.

## 7. Anti-Corruption Layer (ACL)

Between this Bounded Context and an external system whose model is
incompatible (legacy API, third-party SDK, partner service). The ACL
translates **their** language into ours.

```
operation/    ─► acl/SupplierAdapter ─► client/supplier/SupplierClient
                       (their SupplierInvoice → our Invoice)
```

Without an ACL, the partner's concepts leak into your domain and the
re-platforming cost compounds. This is the strict version of the `Adapter`
pattern from `external-client`.

## 8. Specification

Composable business rules expressed as objects (see `persistence` §2):

```java
public final class InvoiceSpecs {
    public static Specification<Invoice> overdueFor(Instant cutoff) { … }
    public static Specification<Invoice> ownedBy(UserId u)          { … }
}
```

`overdueFor(now).and(ownedBy(callerId))` — readable, testable, composable.

## 9. When DDD is overkill

Skip aggregate / value-object discipline when:
- The service is pure CRUD over external data.
- The business has fewer than 5 concepts.
- The team is < 3 engineers and the service is < 6 months old.

Adopt incrementally; the rest of the skill set still applies.

## Do / Don't

✅ Wrap identifiers in Value Objects inside the domain; the type system
catches half of all bugs.
✅ One aggregate per transaction; cross-aggregate consistency is async.
✅ Document the ubiquitous language in `docs/GLOSSARY.md` and keep it
synced.
❌ Never share an aggregate between two services. If you need to, you have
the wrong bounded contexts.
❌ Never expose an aggregate as a JSON response — map to a DTO.
❌ Never put repositories inside aggregates (anaemic + circular).

