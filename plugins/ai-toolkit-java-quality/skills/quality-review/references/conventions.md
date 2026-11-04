# this Quality Review Skill — Checklist C: cross-cutting conventions

Part of the [`quality-review`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

### C. Cross-cutting conventions

9a. **Nullable fetch → filtered stream.** Any collaborator whose
    contract documents `null` on error (graceful degradation) must be
    filtered with `.filter(Objects::nonNull)` at the call-site before
    downstream `map` / `flatMap`. Flag streams that call such methods
    without a null filter.
    *Fix:* add the filter; or promote the return type to `Optional<T>`
    and force the caller to unwrap.

9b. **No `@EnableXxx` on `@SpringBootApplication`.**
    `@EnableScheduling`, `@EnableAsync`, `@EnableCaching`,
    `@EnableConfigurationPropertiesScan` must live on dedicated
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
    `service/`, `repository/`, `analyzer/`, and its own logger. Flag any
    scheduler that injects a `*Client`, `WebClient`, SDK stub, or reads
    infrastructure `@Value` fields directly.

9. **Exceptions** — Throw-site uses a domain exception (`*Exception`,
   `*BadRequestException`, `*ForbiddenException`, `*NotFoundException`) with
   a `MessageFormat`-formatted message from `ExceptionMessages`. The HTTP
   mapping lives only in the `@RestControllerAdvice`. (See
   `exception-handling`.) Flag any `throw new RuntimeException("…")`
   in business code or inline error string.

10. **Logging** — `@Slf4j` / `@Log4j2`; no `System.out`; no logging of secrets
    or full URLs with credentials; `log.debug` for happy-path detail,
    `log.warn` for recoverable, `log.error` for unexpected with exception as
    last arg (not concatenated).

11. **Constants** — Utility classes are `final` with
    `@NoArgsConstructor(access = PRIVATE)`; magic strings live in a `*Constants`
    class; config keys live in `ConfigurationConstants` as
    `${prop.name}` / SpEL `#{'${prop.list}'.split(',')}`. Flag inline
    `@Value("${…}")` literals that occur more than once.

12. **Concurrency** — Any `ExecutorService` field has:
    - a `@PreDestroy` that calls `shutdown()` → `awaitTermination(…)` →
      `shutdownNow()`;
    - `InterruptedException` handlers restore the flag with
      `Thread.currentThread().interrupt()`.
    `CompletableFuture` chains unwrap the cause when rethrowing (see
    `HeavyStartupOrchestrator.awaitLicenseSettingTasksCompletion`).
    Flag `Thread.sleep` outside of tests, raw `Thread.start()`,
    unmanaged thread pools.

13. **Reactive boundary** — `Mono`/`Flux` are confined to `client/`; the rest
    of the code is synchronous. If a `.block()` appears outside `client/`,
    flag it.

14. **Configuration** — every `@Value`/`@ConfigurationProperties` key has a
    matching `${ENV:default}` entry in `application.yaml`, a Helm env var,
    and (for downstream URLs) a `HealthIndicator`.
