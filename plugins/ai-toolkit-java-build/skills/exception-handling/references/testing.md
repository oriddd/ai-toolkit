# Exception Handling Skill — Tests

Part of the [`exception-handling`](../SKILL.md) skill. Section headings are stable; other skills cite them.

## Tests

For the handler, use the `unit-tests` skill with the
`@WebMvcTest(FooController.class)` slice (it picks up `@RestControllerAdvice`
beans automatically; add `@Import(GlobalExceptionHandler.class)` if you
narrow the scan) or a full
`MockMvcBuilders.standaloneSetup(controller).setControllerAdvice(handler)`
setup. A `@WebMvcTest` slice runs Boot's default security unless you `@Import` your `SecurityConfig` (and send
`.with(jwt())`), and it does not load the plain `@Component`s that a loaded advice, filter or interceptor injects —
`@Import` those too (`input-validation` §5c has the full example). Assert:

- Status code matches.
- `ProblemDetail.detail` equals the formatted message constant (4xx) or the
  generic text (5xx other than 503); `errorCode` equals the catalogue code.
- `ProblemDetail.title` / `status` are populated by the advice.
- Spring MVC's own errors carry `errorCode` too: a request to an unknown path (`ERR-NOT-FOUND`), a wrong verb (`ERR-METHOD-NOT-ALLOWED`)
  and a wrong `Content-Type` (`ERR-UNSUPPORTED-MEDIA-TYPE`) in a `@SpringBootTest` / component test.

For each thrown-exception path inside services, assert in unit tests that
the **correct subclass** is thrown (`assertThatThrownBy(…).isInstanceOf(ForbiddenException.class)`),
not just `BaseDomainException`. The HTTP mapping depends on the exact subclass.
Domain exceptions are checked: a test method that calls throwing code directly declares `throws Exception`, and a Mockito
`when(...).thenThrow(checked)` needs the stubbed method to declare it. Add one advice test that a plain `RuntimeException`
answers `500` with the generic detail, so the catch-all keeps covering unchecked failures.

Component tests (see `component-tests`) prove the end-to-end status
mapping for the full matrix (`200 / 400 / 403 / 404 / 406 / 409 / 500 / 503`).
