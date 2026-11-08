# Quality Review Skill — Checklist C: cross-cutting conventions

Part of the [`quality-review`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

### C. Cross-cutting conventions

9. **Exceptions** — Throw-site uses a domain exception from the project's
   **unchecked** hierarchy (`BaseDomainException` → `BadRequestException`,
   `ForbiddenException`, `NotFoundException`, …), built by an
   `ExceptionMessages` factory method that supplies the error code and the
   `MessageFormat`-formatted message (guild #4). The HTTP
   mapping lives only in the `@RestControllerAdvice`. (See
   `exception-handling`.) Flag any `throw new RuntimeException("…")`
   in business code, any inline error string, any exception type outside the
   hierarchy, and `throws` clauses for domain exceptions.

9a. **Nullable fetch → filtered stream.** Any collaborator whose
    contract documents `null` on error (graceful degradation) must be
    filtered with `.filter(Objects::nonNull)` at the call-site before
    downstream `map` / `flatMap`. Flag streams that call such methods
    without a null filter.
    *Fix:* add the filter; or promote the return type to `Optional<T>`
    and force the caller to unwrap.

9b. **No `@EnableXxx` on `@SpringBootApplication`.**
    `@EnableScheduling`, `@EnableAsync` and `@EnableCaching`
    must live on dedicated
    `@Configuration` classes (`SchedulingConfig`, `AsyncConfig`, …) so
    test slices can opt out. See `spring-boot-conventions` §7b.

9c. **One properties bean per dependency.** No infrastructure property
    key (`*.endpoint`, `*.namespace`, `*.topic`, `*.timeout-ms`) may be
    read via `@Value` in more than one class. Flag any such duplicate;
    the fix is a shared `@ConfigurationProperties` record.

9d. **Layer duplication.** Two classes in different packages
    implementing the same capability (list-by-status query, status
    reduction) is a smell — one must be the canonical implementation, the
    other deleted. Flag any pair of classes that share ≥ 80 % of a
    switch statement or query-building expression across packages.

9e. **Scheduler purity.** A `@Scheduled` bean may only depend on
    `service/`, `repository/`, `analyzer/` (or the `job/` / `handler/`
    packages a scheduler-type service uses, see `project-types`), and its own logger. Flag any
    scheduler that injects a `*Client`, `WebClient`, SDK stub, or reads
    infrastructure `@Value` fields directly.

10. **Logging** — `@Slf4j` (or `@Log4j2`, only when the service uses
    `spring-boot-starter-log4j2` instead of the default Logback); no `System.out`; no logging of secrets
    or full URLs with credentials; `log.debug` for happy-path detail,
    `log.warn` for recoverable, `log.error` for unexpected with exception as
    last arg (not concatenated).

11. **Constants** — Utility classes are `final` with
    `@NoArgsConstructor(access = AccessLevel.PRIVATE)` (or Lombok `@UtilityClass`); magic strings live in a `*Constants`
    class; configuration is bound through `@ConfigurationProperties` records
    (golden-path #2, `spring-boot-conventions` §1). Where a lone `@Value`
    remains for a single ungrouped key, the key lives in
    `ConfigurationConstants` as `${prop.name}` / SpEL
    `#{'${prop.list}'.split(',')}`. Flag inline `@Value("${…}")` literals
    that occur more than once, and any `@Value` used for grouped properties.

12. **Concurrency** — Any `ExecutorService` field has:
    - a `@PreDestroy` that calls `shutdown()` → `awaitTermination(…)` →
      `shutdownNow()`;
    - `InterruptedException` handlers restore the flag with
      `Thread.currentThread().interrupt()`.
    `CompletableFuture` chains unwrap the cause when rethrowing (illustrative:
    catch `ExecutionException` / `CompletionException` and rethrow `e.getCause()`
    wrapped in a domain exception).
    Flag `Thread.sleep` outside of tests, raw `Thread.start()`,
    unmanaged thread pools.

13. **Reactive boundary** — `Mono`/`Flux` are confined to `client/`; the rest
    of the code is synchronous. If a `.block()` appears outside `client/`,
    flag it.

14. **Configuration** — every `@Value`/`@ConfigurationProperties` key has a
    matching `${ENV:default}` entry in `application.yaml`, a Helm env var,
    and (for downstream URLs) a `HealthIndicator`. **Secrets** are the
    exception: `${DB_PASSWORD}` with **no** default (or a secret store) — a
    default such as `${DB_PASSWORD:changeme}` ships a credential (guild #16).
