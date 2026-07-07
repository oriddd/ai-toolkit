---
name: persistence
description: Wire the persistence layer of a Spring Boot service — Spring Data JPA repositories, JPA entities (records vs classes), Flyway migrations, transaction boundaries, optimistic locking, JPA auditing, soft deletes, and the Repository/Specification patterns. Use whenever a new service needs durable storage or a new aggregate is added to an existing one.
tier: should
applies_to: [rest, event, monolith]
depends_on: [code-structure, pluggable-architecture]
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Persistence Skill (public)

The persistence layer lives under `repository/` (Spring Data interfaces) +
`entity/` (JPA entities) + `db/migration/` (Flyway). Business code depends on
**repository interfaces**, never on the EntityManager.

```
src/main/java/<basePackage>/
├── entity/        # JPA @Entity types
├── repository/    # Spring Data interfaces + custom Specification classes
└── service/       # business logic — @Transactional boundary lives here
src/main/resources/
└── db/migration/  # Flyway: V001__init.sql, V002__add_status.sql, …
```

## Dependencies

```xml
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
<dependency><groupId>org.flywaydb</groupId><artifactId>flyway-core</artifactId></dependency>
<dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
```

## 1. Entities

```java
@Entity
@Table(name = "documents")
@Getter @NoArgsConstructor(access = PROTECTED)
@EntityListeners(AuditingEntityListener.class)
public class Document {

    @Id
    private String id;                              // application-assigned UUID, never auto-incremented

    @Version
    private long version;                            // optimistic locking — mandatory

    @Column(nullable = false)
    private String name;

    @Enumerated(EnumType.STRING)                     // never EnumType.ORDINAL
    @Column(nullable = false)
    private Status status;

    @CreatedDate  private Instant createdAt;
    @LastModifiedDate private Instant updatedAt;
    @CreatedBy    private String createdBy;
    @LastModifiedBy private String updatedBy;

    public Document(String id, String name) {
        this.id = id; this.name = name; this.status = Status.NEW;
    }
}
```

Rules:
- **Application-assigned IDs** (UUID v7 or ULID) — never DB sequences. Makes
  inserts non-blocking and IDs stable across environments.
- **`@Version`** on every aggregate root. Concurrent updates fail with
  `OptimisticLockingFailureException` — caught by the
  `@RestControllerAdvice` and mapped to `409 Conflict`.
- **Enums stored as `STRING`**, never ordinal (renaming breaks history).
- **JPA auditing** (`@EnableJpaAuditing` + `AuditorAware<String>`) fills
  `createdAt/Updated/By` automatically.
- **Soft delete** with a `@Where(clause = "deleted_at is null")` flag if
  hard-delete is forbidden by domain rules; otherwise hard-delete.
- **No bidirectional relationships** unless absolutely required; prefer a
  separate repository lookup. Bidirectional `@OneToMany` is a footgun.

## 2. Repositories

```java
public interface DocumentRepository
        extends JpaRepository<Document, String>, JpaSpecificationExecutor<Document> { }
```

Rules:
- Derive query methods (`findByStatusAndOwner`) only when the predicate is
  trivial. For composable filters, use **Specifications** (see below).
- Never expose `EntityManager` to callers. If a query needs `@Query`, write
  it on the repository interface.
- **No `findAll()` without a `Pageable`.** Always paginate (see
  `spring-boot-conventions` §6).

### Specification pattern (composable predicates)

```java
public final class DocumentSpecifications {
    private DocumentSpecifications() {}
    public static Specification<Document> hasStatus(Status s) {
        return (root, q, cb) -> cb.equal(root.get("status"), s);
    }
    public static Specification<Document> ownedBy(String userId) {
        return (root, q, cb) -> cb.equal(root.get("createdBy"), userId);
    }
}

// usage
repo.findAll(hasStatus(Status.READY).and(ownedBy("alice")), pageable);
```

This replaces the anti-pattern `findByStatusAndCreatedByAndTypeAndTagsIn…`.

## 3. Flyway migrations

Rules:
- **Forward-only.** Never edit a checked-in migration. Add a new one.
- **No DDL in code / Hibernate auto-DDL.** `spring.jpa.hibernate.ddl-auto=validate`
  in prod, `none` elsewhere — Flyway owns the schema.
- **Naming.** `V001__init.sql`, `V002__add_status_column.sql`. The
  underscore-pair after the version is mandatory.
- **Repeatable migrations** (`R__create_views.sql`) only for views and
  materialised views, never for tables.
- Add a **Testcontainer-based migration test** that runs all migrations
  against an empty database on every commit (see `integration-tests`).

## 3c. Multi-tenancy

When a service must manage data for multiple tenants (e.g., different organizations or customers), choose one of the following patterns:

1. **Discriminator Column (Shared Schema)**:
   - Add a `tenant_id` column to every table.
   - Use Hibernate `@Filter` and a `CurrentTenantContext` to automatically append `WHERE tenant_id = ?` to all queries.
   - **Pro**: Simple, low infra cost. **Con**: Risk of data leakage if filters are bypassed.

2. **Separate Schema (per tenant)**:
   - Every tenant has their own Postgres schema.
   - Use a `MultiTenantConnectionProvider` to switch schemas based on a tenant identifier in the request.
   - **Pro**: Stronger isolation. **Con**: Harder to run migrations across all schemas (Flyway needs a loop).

3. **Separate Database**:
   - Every tenant has their own DB instance.
   - **Pro**: Maximum isolation, no noisy neighbor. **Con**: Highest cost and complexity.

**Recommendation**: Start with **Discriminator Column** unless strict regulatory requirements demand otherwise.

## 4. Transactions

```java
@Service
public class DocumentService {
    @Transactional                              // write boundary
    public Document create(CreateRequest req) { … }

    @Transactional(readOnly = true)             // read boundary — important for replicas
    public Optional<Document> findById(String id) { … }
}
```

Rules:
- `@Transactional` lives in the **service** layer, never in the controller
  or repository.
- Read-only methods are annotated `readOnly = true` so the JDBC driver can
  hint the database.
- Never call a `@Transactional` method from another method of the same
  class — Spring proxying does not intercept it.
- A transaction never spans a network call to another service.

## 5. Anti-patterns to flag

❌ Bidirectional `@OneToMany` on an aggregate that has > 100 children
   (loads the whole list on access).
❌ `cascade = ALL` across aggregate boundaries.
❌ `FetchType.EAGER` — always `LAZY`. Fetch what you need with a
   `Specification` or `EntityGraph`.
❌ `findAll()` returning `List<T>` in production code.
❌ DTO ↔ Entity confusion — never serialize an entity as a JSON response,
   always map to a record DTO first (use MapStruct).
❌ N + 1 queries — caught by Hibernate's `org.hibernate.SQL` logger in tests
   or via the [datasource-proxy](https://github.com/jdbc-observations/datasource-proxy)
   spy in integration tests.

## 6. Templates

- [`BaseEntity.java.tmpl`](./templates/BaseEntity.java.tmpl) — Base class with ID and auditing.
- [`AuditConfig.java.tmpl`](./templates/AuditConfig.java.tmpl) — Sets up JPA auditing and AuditorAware.
- [`ExampleSpecifications.java.tmpl`](./templates/ExampleSpecifications.java.tmpl) — Reference implementation for Specification pattern.
