# Quality Review Skill — Checklist A–B: SOLID and lego-brick packaging

Part of the [`quality-review`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

### A. SOLID

1. **SRP** — Does the class have one reason to change?
   *Smell:* >200 LOC, mixed responsibilities (HTTP + DTO build + business
   logic), method names spanning unrelated nouns.
   *Fix template:* extract a `*Parser` / `*Builder` / `*Transformer` /
   `*ResponseHandler` companion class — exactly as
   `FooDependencyRequestBuilder` and `BarResponseTransformer`
   (illustrative names) were extracted from their clients.

2. **OCP** — To add a new behaviour, do you add a class or modify a switch?
   *Smell:* `if/else` on a type discriminator (`if (ctx == USER) … else if (ctx == SERVICE) …`),
   `switch` on an enum that lists business cases.
   *Fix:* replace with the Strategy + Registry pattern (see
   `code-structure` Pattern A and
   `permission/PermissionsHandler` from `permissions`; a registry such as
   `renderer/registry/ExportRendererRegistry` is an illustrative name).

3. **LSP** — Do subclasses preserve the contract of their supertype?
   *Smell:* subclass throws on inherited method, narrows accepted input,
   strengthens preconditions.
   *Fix:* prefer composition; or hoist the differing behaviour into a
   dedicated sub-interface (e.g. `FooRendererToHtml extends FooRenderer`
   fixes only `getTargetFormat()` — see "lego sub-interface" below).

4. **ISP** — Are interfaces narrow and single-purpose?
   *Smell:* an interface with >3 methods that no single implementation uses
   together.
   *Fix:* split. Reference: a trivial SPI (illustrative `TrivialSpi`) has
   **one** method; `PermissionsCheckStrategy` (`permissions`) has two and they
   are inseparable.

5. **DIP** — Does the class depend on abstractions, not concretions?
   *Smell:* field injection (`@Autowired` field), `new ConcreteClient()` in
   business code, static singletons.
   *Fix:* constructor injection only — either Lombok
   `@RequiredArgsConstructor` (a single constructor needs no `@Autowired`) or an
   explicit constructor. **One** style per class.

### B. Lego-brick packaging

6. **Package hierarchy** matches `code-structure` §1 (golden-path #1):
   core `controller / operation / service / client / config / constant /
   renderer / permission / monitor / mapper / model / exception / health /
   repository / analyzer / scheduler`, plus the feature packages created only
   when used — `spi/<capability>/`, `adapter/<capability>/<vendor>/` (guild #20),
   `validation/` (guild #22), `layout/`, `entity/`, `domain/`, `acl/`,
   `event/`, `messaging/`. Event-driven and scheduler services may rename the
   entry/orchestrator packages to `consumer/`, `handler/`, `job/`, `producer/`
   (`project-types`); the same layering applies to them.

7. **External dependency wrapping** — every outbound call goes through a
   `client/<dep>/` sub-package whose pattern matches the integration's scale
   (`external-client` §0, guild #23): Simple Wrapper (`<Dep>Client` +
   `<Dep>ClientConfig` + `<Dep>Properties`), Lite Client, or Full 5-Layer
   (`<Dep>Service` facade, `<Dep>CoreService`, `<Dep>Client`,
   `<Dep>RequestBuilder` / `<Dep>FilterMapBuilder`, `<Dep>ResponseParser` /
   `<Dep>ResponseVerifier`, `<Dep>Constants`). Flag a pattern heavier or lighter
   than the scale calls for, not merely a missing layer. Detect leaks: any
   `WebClient` / `RestClient` / `RestTemplate` / gRPC stub injected outside
   `client/` (or an `adapter/` behind a port).

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
