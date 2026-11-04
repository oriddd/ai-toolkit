# this Quality Review Skill — Checklist A–B: SOLID and lego-brick packaging

Part of the [`quality-review`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

### A. SOLID

1. **SRP** — Does the class have one reason to change?
   *Smell:* >200 LOC, mixed responsibilities (HTTP + DTO build + business
   logic), method names spanning unrelated nouns.
   *Fix template:* extract a `*Parser` / `*Builder` / `*Transformer` /
   `*ResponseHandler` companion class — exactly as
   `FooDependencyRequestBuilder` and `BarResponseTransformer`
   were extracted from their clients.

2. **OCP** — To add a new behaviour, do you add a class or modify a switch?
   *Smell:* `if/else` on a type discriminator (`if (ctx == USER) … else if (ctx == SERVICE) …`),
   `switch` on an enum that lists business cases.
   *Fix:* replace with the Strategy + Registry pattern (see
   `code-structure` Pattern A and
   `permission/PermissionsHandler`, `renderer/registry/ExportRendererRegistry`).

3. **LSP** — Do subclasses preserve the contract of their supertype?
   *Smell:* subclass throws on inherited method, narrows accepted input,
   strengthens preconditions.
   *Fix:* prefer composition; or hoist the differing behaviour into a
   dedicated sub-interface (e.g. `FooRendererToHtml extends FooRenderer`
   fixes only `getTargetFormat()` — see "lego sub-interface" below).

4. **ISP** — Are interfaces narrow and single-purpose?
   *Smell:* an interface with >3 methods that no single implementation uses
   together.
   *Fix:* split. Reference: `TrivialSpi` has **one** method;
   `PermissionsCheckStrategy` has two and they are inseparable.

5. **DIP** — Does the class depend on abstractions, not concretions?
   *Smell:* field injection (`@Autowired` field), `new ConcreteClient()` in
   business code, static singletons.
   *Fix:* constructor injection only — either
   `@RequiredArgsConstructor(onConstructor = @__(@Autowired))` or an explicit
   `@Autowired` constructor. **One** style per class.

### B. Lego-brick packaging

6. **Package hierarchy** matches `code-structure` §1
   (`controller / operation / service / client / renderer / permission / monitor / model / exception / health / constant`).

7. **External dependency wrapping** — every outbound call goes through a
   `client/<dep>/` sub-package with `*Config + *Client + *RequestBuilder +
   *ResponseHandler (+ transformer)`. See `external-client`. Detect
   leaks: any `WebClient` / `RestTemplate` / gRPC stub injected outside
   `client/`.

8. **Lego sub-interface trick** — when many implementations of a strategy
   share a common axis (target format, supported context, …), the axis is
   factored into a sub-interface with a `default` method:
   ```java
   public interface FooRendererToHtml extends FooRenderer {
       @Override default String getTargetFormat() { return HTML.getFileExtension(); }
   }
   ```
   so concrete classes only declare the dimension that actually varies. Flag
   if N concrete classes repeat the same method literally.
