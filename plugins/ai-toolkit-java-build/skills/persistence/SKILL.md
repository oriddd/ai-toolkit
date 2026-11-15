---
name: persistence
description: >
  Java / Spring Boot persistence — Spring Data JPA repositories and entities, Flyway migrations, transaction
  boundaries, optimistic locking, auditing, soft deletes, Specifications. Use when a service needs durable storage or
  a new entity, aggregate, migration or query.
tier: should
applies_to: [rest, event, monolith]
depends_on: [code-structure, pluggable-architecture]
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

# Persistence Skill
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
<!-- Flyway 10+ (Boot 3.5) ships database support as modules: without this, Postgres migrations fail at startup -->
<dependency><groupId>org.flywaydb</groupId><artifactId>flyway-database-postgresql</artifactId></dependency>
<dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
<!-- generates the typed metamodel (Invoice_) used by Specifications; versions come from the Boot BOM -->
<dependency><groupId>org.hibernate.orm</groupId><artifactId>hibernate-jpamodelgen</artifactId><scope>provided</scope></dependency>
<!-- @Nullable on the BaseEntity template (NullAway convention of static-analysis); not managed by the Boot 3.5 BOM -->
<dependency><groupId>org.jspecify</groupId><artifactId>jspecify</artifactId><version>1.0.0</version></dependency>
```

Also put the metamodel generator on the compiler's processor path, with its transitive JAXB jars (on the plain classpath
`spring-boot-starter-test` wins the `jakarta.xml.bind-api` mediation as `test` scope and compilation fails with
`NoClassDefFoundError: jakarta/xml/bind/JAXBException`). Explicit processor paths switch off classpath discovery, so
list Lombok too:

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-compiler-plugin</artifactId>
    <configuration>
        <annotationProcessorPaths>
            <path><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><version>${lombok.version}</version></path>
            <path><groupId>org.hibernate.orm</groupId><artifactId>hibernate-jpamodelgen</artifactId><version>${hibernate.version}</version></path>
        </annotationProcessorPaths>
    </configuration>
</plugin>
```

> **Boot 4 note:** Boot 4 moves Flyway auto-configuration into
> `spring-boot-starter-flyway`; `flyway-core` alone no longer runs migrations there.

## 1. Entities

```java
@Entity
@Table(name = "invoices")
@Getter
public class Invoice extends BaseEntity {           // BaseEntity (template): @Version Long version + audit columns
                                                     // (createdAt/updatedAt/createdBy/updatedBy) + AuditingEntityListener
    @Id
    private UUID id;                                 // application-assigned UUID v7, never auto-incremented

    @Column(nullable = false)
    private String name;

    @Column(name = "owner_id", nullable = false)
    private UUID ownerId;                            // explicit ownership — never infer it from the audit column createdBy

    @Enumerated(EnumType.STRING)                     // never EnumType.ORDINAL
    @Column(nullable = false)
    private Status status;

    @SuppressWarnings("NullAway.Init")              // JPA-only constructor: Hibernate sets every field right after it
    protected Invoice() {}

    public Invoice(UUID id, UUID ownerId, String name) {
        this.id = id; this.ownerId = ownerId; this.name = name; this.status = Status.NEW;
    }

    @Override public boolean equals(Object o) {      // identity = id; a new (null-id) entity equals only itself
        return this == o || (o instanceof Invoice other && id != null && id.equals(other.getId()));   // getter: works on a lazy proxy
    }
    @Override public int hashCode() { return getClass().hashCode(); }   // stable across persist / merge
}
```

Rules:
- **Application-assigned IDs** (UUID v7 or ULID) — never DB sequences. Makes
  inserts non-blocking and IDs stable across environments. Store them as
  `UUID` (Postgres `uuid` column), not `String`. Generate them with a UUID v7
  generator, e.g. `Generators.timeBasedEpochGenerator().generate()` from
  `com.fasterxml.uuid:java-uuid-generator`, behind a small `IdGenerator` bean
  so tests can fix the value; Hibernate's `@UuidGenerator` is an option if
  your Hibernate version offers a v7 style (check before relying on it).
- **Every entity extends `BaseEntity`** (template) — never repeat the
  version and audit columns per entity.
- **`equals` / `hashCode` are id-based**: `equals` compares a non-null `id`,
  `hashCode` returns a constant per class. Read the other side through
  `getId()`, never `other.id`: on a Hibernate lazy proxy the field is `null`
  and only the getter returns the id. Never use Lombok `@Data` /
  `@EqualsAndHashCode` on entities (they touch lazy fields and change the
  hash after persist).
- **The JPA no-arg constructor is written by hand**, `protected`, with
  `@SuppressWarnings("NullAway.Init")` — not Lombok `@NoArgsConstructor`:
  NullAway (`static-analysis`) rejects a constructor that leaves non-null
  fields unset, and Hibernate fills them right after calling it. Fields that
  really can be null (the `BaseEntity` version and audit columns) are
  `@Nullable` instead.
- **`@Version` is a `Long` wrapper**, not a primitive `long`: Spring Data decides "new vs existing" from a null version. With an assigned id
  and a primitive version it falls back to the id check, treats the entity as existing, runs `merge()` (an extra SELECT) and never fills `createdAt` / `createdBy`.
- **`@Version`** on every aggregate root. Concurrent updates fail with
  `OptimisticLockingFailureException` — caught by the
  `@RestControllerAdvice` and mapped to `409 Conflict` — add an `@ExceptionHandler(OptimisticLockingFailureException.class)` returning `409`; the
  catch-all handler would otherwise turn it into a `500`.
- **Enums stored as `STRING`**, never ordinal (renaming breaks history).
- **JPA auditing** (`@EnableJpaAuditing` + `AuditorAware<String>`) fills
  `createdAt/Updated/By` automatically. The `AuditorAware` bean
  (`SecurityAuditorAware` template) lives in `permission/`, the only package
  that reads `SecurityContextHolder`; `AuditConfig` in `config/` only enables
  auditing. It records an opaque subject id, falls back to `"system"` only
  outside an HTTP request (schedulers, consumers), and returns empty for an
  unauthenticated request. `AuditConfig` carries `@Profile("!component-test")`:
  component tests that exclude the DataSource / JPA auto-configuration would
  otherwise fail at startup (`JPA metamodel must not be empty`); remove it if
  your component tests run against a real database.
- **Soft delete** with `@SQLRestriction("deleted_at is null")` (Hibernate 6.3+; `@Where` is deprecated) and an `@SQLDelete` that sets `deleted_at`,
  if hard-delete is forbidden by domain rules; otherwise hard-delete.
  A soft-deleted row still holds its PII: on a right-to-be-forgotten request
  scrub or anonymise the PII columns (and audit `createdBy`/`updatedBy` if
  they identify a person) — see `data-privacy` §4. The same applies to
  outbox rows (`messaging` §3).
- **No bidirectional relationships** unless absolutely required; prefer a
  separate repository lookup. Bidirectional `@OneToMany` is a footgun.

## 2. Repositories

```java
public interface InvoiceRepository
        extends JpaRepository<Invoice, UUID>, JpaSpecificationExecutor<Invoice> { }
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
public final class InvoiceSpecifications {
    private InvoiceSpecifications() {}
    public static Specification<Invoice> hasStatus(Status s) {
        return (root, q, cb) -> cb.equal(root.get(Invoice_.status), s);      // typed metamodel, no string paths
    }
    public static Specification<Invoice> ownedBy(UUID ownerId) {
        return (root, q, cb) -> cb.equal(root.get(Invoice_.ownerId), ownerId); // explicit owner, not createdBy
    }
}

// usage — opaque ids, never a username or e-mail
repo.findAll(hasStatus(Status.READY).and(ownedBy(callerId)), pageable);
```

Never build a `Specification` from a field name supplied by the caller
(`root.get(request.sortField())`): map allowed names to metamodel attributes.

This replaces the anti-pattern `findByStatusAndCreatedByAndTypeAndTagsIn…`.

## 3. Flyway migrations

Rules:
- **Forward-only.** Never edit a checked-in migration. Add a new one.
- **No DDL in code / Hibernate auto-DDL.** `spring.jpa.hibernate.ddl-auto=validate`
  in every profile that has a real schema — prod **and** tests (Testcontainers),
  so a missing migration fails the build, not the deploy. `none` only where no
  database exists. Flyway owns the schema.
- **Naming.** `V001__init.sql`, `V002__add_status_column.sql`. The
  underscore-pair after the version is mandatory.
- **Repeatable migrations** (`R__create_views.sql`) only for views and
  materialised views, never for tables.
- Add a **Testcontainer-based migration test** that runs all migrations
  against an empty database on every commit (see `integration-tests`).

## 3a. Multi-tenancy

When a service must manage data for multiple tenants (e.g., different organizations or customers), choose one of the following patterns:

1. **Discriminator Column (Shared Schema)**:
   - Add a `tenant_id` column to every table.
   - Mark it with Hibernate 6 `@TenantId` and register a `CurrentTenantIdentifierResolver`
     that reads the tenant from the request (via `permission/`). Hibernate then adds the
     tenant to every entity query **including `findById` / `getReferenceById`** and sets it on insert.
   - Do **not** rely on Hibernate `@Filter` alone: filters do not apply to `find` by id,
     `getReferenceById`, native queries or bulk updates, so tenants' data leaks.
   - Native and bulk queries still bypass `@TenantId`: add `tenant_id` to them by hand, or
     enforce isolation in the database with Postgres row-level security (RLS).
   - Add a test that tenant A's `findById` on tenant B's id returns empty.
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
public class InvoiceService {
    @Transactional                              // write boundary
    public Invoice create(CreateRequest req) { … }

    @Transactional(readOnly = true)             // read boundary — important for replicas
    public Optional<Invoice> findById(UUID id) { … }
}
```

Rules:
- `@Transactional` lives in the **service** layer, never in the controller
  or repository.
- Read-only methods are annotated `readOnly = true` so the JDBC driver can
  hint the database and Hibernate skips dirty checking and flushing. It does
  **not** route to a replica by itself: that needs a routing `DataSource`
  (e.g. `AbstractRoutingDataSource` keyed on the read-only flag).
- **Domain exceptions are unchecked** (`exception-handling`), so
  `@Transactional` rolls back on them by default. Never catch and swallow a
  failure inside the boundary. If a method throws a **checked** exception
  (e.g. from a third-party API), declare `rollbackFor` for it, or wrap it in
  a domain exception — a checked exception otherwise commits.
- Never call a `@Transactional` method from another method of the same
  class — Spring proxying does not intercept it.
- A transaction never spans a network call to another service.

## 5. Anti-patterns to flag

❌ Bidirectional `@OneToMany` on an aggregate that has > 100 children
   (loads the whole list on access).
❌ `cascade = ALL` across aggregate boundaries.
❌ `FetchType.EAGER` — always `LAZY`. Fetch what you need with a
   `Specification` or `EntityGraph`. `@ManyToOne` / `@OneToOne` default to
   EAGER, so write `fetch = FetchType.LAZY` on them explicitly.
❌ `findAll()` returning `List<T>` in production code.
❌ DTO ↔ Entity confusion — never serialize an entity as a JSON response,
   always map to a record DTO first (use MapStruct).
❌ N + 1 queries — caught by Hibernate's `org.hibernate.SQL` logger in tests
   or via the [datasource-proxy](https://github.com/jdbc-observations/datasource-proxy)
   spy in integration tests.

## 6. Templates

- [`BaseEntity.java.tmpl`](./templates/BaseEntity.java.tmpl) — Base class with ID and auditing.
- [`AuditConfig.java.tmpl`](./templates/AuditConfig.java.tmpl) — Enables JPA auditing (in `config/`).
- [`SecurityAuditorAware.java.tmpl`](./templates/SecurityAuditorAware.java.tmpl) — The `AuditorAware` bean (in `permission/`).
- [`ExampleSpecifications.java.tmpl`](./templates/ExampleSpecifications.java.tmpl) — Reference implementation for Specification pattern.
