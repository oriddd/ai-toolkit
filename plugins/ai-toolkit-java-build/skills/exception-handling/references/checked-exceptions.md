# Exception Handling Skill — checked-exception rules

Part of the [`exception-handling`](../SKILL.md) skill. Section heading is stable; other skills cite it.

## 1a. Checked-exception rules

- **Declare what you throw.** A method that throws a domain exception, or calls one that does, declares the narrowest
  type (`throws NotFoundException`) or `throws BaseDomainException` at a service / operation / port boundary. Controller
  methods may declare it too: the advice maps it.
- **Ports and SPIs declare it.** A port method that an adapter can fail on (`CachePort.get`) is `throws BaseDomainException`
  so every adapter, including a future one, can report an outage.
- **Where a checked exception cannot cross, throw it after the lambda, not inside.** Lambdas passed to `stream()`,
  `RestClient.exchange`, `Supplier`, `CompletableFuture`: return a result (status, body) from the lambda and throw outside
  it, or use a `for` loop instead of a stream. `Optional.orElseThrow(() -> factoryMethod())` is fine; the enclosing
  method declares the throws.
- **`ConstraintValidator.isValid`, servlet `Filter`s and `AuthenticationEntryPoint`s cannot declare it.** A validator wraps
  the exception (`throw new IllegalStateException(e)`): the advice finds an `UnavailableException` anywhere in the cause
  chain and answers 503. A filter writes the `ProblemDetail` itself (see `permissions`).
- **Transactions.** Spring rolls back `@Transactional` on unchecked exceptions only; a checked domain exception would
  **commit** a half-done transaction. Every `@Transactional` method and class declares
  `rollbackFor = Exception.class`, including `readOnly = true` ones for consistency. The `ArchitectureTest` template
  enforces this (`code-structure`), so there is no wrapper annotation to remember.
- **Tests.** Mockito `thenThrow(checkedException)` needs the stubbed method to declare it; test methods that call
  throwing code declare `throws Exception`. Assert the exact subclass with `assertThatThrownBy`.
