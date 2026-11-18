# Exception Handling Skill — Tests

Part of the [`exception-handling`](../SKILL.md) skill. Section headings are stable; other skills cite them.

## Tests

**Shipped classes are tested.** `ExceptionHierarchyTest`, `ExceptionMessagesTest` and `GlobalExceptionHandlerTest` ship as templates
(`MockMvc` `standaloneSetup` with a throwing controller: every mapped status, `Retry-After` rounding, the 5xx generic detail,
the Spring MVC `errorCode`, the validation shapes, the security rethrow). Copy them with the classes; without them the
per-class JaCoCo gate fails on `ExceptionMessages` and `GlobalExceptionHandler` and the exception classes, and the build is red
on a fresh skeleton. Add a case there whenever you add an exception, a factory method or a handler.

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

## Tag strip matrix (`[validation]`, `[security]`, `[persistence]`)

Handler and test carry the same three tags, so any combination of kept and removed tags must compile and pass `mvn verify`
(JaCoCo 85 % / 75 % per class, PIT). Prove it after changing either template: for each of the 8 combinations render the two
templates (`{{basePackage}}` substituted), run the §3a `sed` recipe with the literal tag on both files for every removed tag
**before** `spotless:apply` (formatting wraps tagged lines and loses the tag), drop the matching starters from the POM, then run
`mvn verify`. Run it under `bash`, not `zsh` (zsh history-expands `$t:end`):

```sh
mask=5   # one fresh copy of both files per mask 0..7; bit 0 = validation, 1 = security, 2 = persistence, set bit = tag removed
for f in GlobalExceptionHandler.java GlobalExceptionHandlerTest.java; do
    (( mask & 1 )) && sed -e '/\[validation:begin\]/,/\[validation:end\]/d' -e '/\[validation\]/d' "$f" > g.tmp && mv g.tmp "$f"
    (( mask & 2 )) && sed -e '/\[security:begin\]/,/\[security:end\]/d' -e '/\[security\]/d' "$f" > g.tmp && mv g.tmp "$f"
    (( mask & 4 )) && sed -e '/\[persistence:begin\]/,/\[persistence:end\]/d' -e '/\[persistence\]/d' "$f" > g.tmp && mv g.tmp "$f"
done
```
