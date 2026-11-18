# Component Tests Skill — Services with persistence

Part of the [`component-tests`](../SKILL.md) skill. Headings are stable; other skills cite them.

## 3b. Services with persistence

Keep the database out of the component-test context and replace the repositories at the boundary:

```yaml
# src/test/resources/application-component-test.yaml
spring:
  autoconfigure:
    exclude:
      - org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration
      - org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration
      - org.springframework.boot.autoconfigure.flyway.FlywayAutoConfiguration
      # Keep ALL SIX lines: the three names above are Boot 3.5, the three below are Boot 4. Each set is ignored by the other
      # version, not an error. Dropping a set silently starts Hikari + H2 in the component-test context on that version.
      - org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration
      - org.springframework.boot.hibernate.autoconfigure.HibernateJpaAutoConfiguration
      - org.springframework.boot.flyway.autoconfigure.FlywayAutoConfiguration
  kafka:                              # services with messaging: no broker in component tests
    listener.auto-startup: false
    admin.auto-create: false
```

- Excluding JPA also removes the `PlatformTransactionManager`, so `@Transactional` and an injected
  `TransactionTemplate` fail at startup (a messaging consumer injects one). `ComponentTestConfiguration.java.tmpl` ships
  the no-op `AbstractPlatformTransactionManager` bean inside its `// [persistence:begin]` … `// [persistence:end]`
  block: keep it with persistence, remove it (and its `[persistence]` imports) without. The fakes hold the state, so
  there is nothing to begin, commit or roll back.
- With messaging, also drop listener startup and topic creation (above) and fake the `KafkaTemplate` /
  publisher port; `@RetryableTopic` and `@KafkaListener` containers otherwise retry `localhost:9092` in every context.

- Without a `DataSource` Boot creates no `EntityManagerFactory` and no Spring Data repositories, so each repository
  the service injects needs a bean in `ComponentTestConfiguration` — an in-process fake when the repository is a
  narrow domain interface, otherwise a deterministic mock (a `JpaRepository` has too many methods to fake by hand):

  ```java
  @Bean
  public InvoiceRepository invoiceRepository() {   // the only InvoiceRepository: none is created without a DataSource
      final InvoiceRepository mock = mock(InvoiceRepository.class);
      doAnswer(inv -> "inv-1".equals(inv.getArgument(0))
              ? Optional.of(new Invoice("inv-1", "acme")) : Optional.empty())
          .when(mock).findById(anyString());
      return mock;
  }
  ```
- `@EnableJpaAuditing` fails without JPA ("JPA metamodel must not be empty"): the `persistence` `AuditConfig` carries
  `@Profile("!component-test")`. Any other configuration that needs the `EntityManager` gets the same profile guard.
- Repository queries, mappings and migrations are proved against a real database in `*IT` tests (`integration-tests`).
- **The default-profile context test needs the real database too.** `ApplicationContextTest` (create-repo step 10, auth = yes)
  boots the production configuration, so with persistence the `component-test` guards above do not apply to it: with no
  `DB_URL` the datasource placeholder is unresolved, and excluding the DataSource / JPA auto-configuration instead
  fails `AuditConfig` with `JPA metamodel must not be empty`. Write it as **`ApplicationContextIT`** (Failsafe, `mvn verify`):
  `@SpringBootTest`, `@MockitoBean JwtDecoder`, the `issuer-uri` property and a `@Container @ServiceConnection`
  `PostgreSQLContainer` (`integration-tests`), and assert the 401 on a protected path. Without persistence it stays a
  plain `ApplicationContextTest` in `mvn test`.
