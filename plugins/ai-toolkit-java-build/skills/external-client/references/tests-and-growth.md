# External Client — tests and growth path (§11, §11b)

Part of the [`external-client`](../SKILL.md) skill. Section numbers are stable; other skills cite them.

## 11. Tests

- **`*FilterMapBuilderTest`** — plain unit test; every `with*()` combination,
  `build()` returns an unmodifiable map.
- **`*RequestBuilderTest`** — pure unit; every overload, every branch in
  filter assembly.
- **`*ResponseVerifierTest`** — null response, empty hit list, non-empty hit list.
- **`*ResponseParserTest`** — null doc, missing nested field, found nested field.
- **`*ClientTest`** — mock `WebClient` exchange (use `MockWebServer` or
  `exchangeFunction(...)`): assert URI/body/headers built; assert domain
  exception thrown on 4xx/5xx; assert deserialized response on 200.
- **`*ServiceTest`** — mock `CoreService`; assert domain-language methods
  guard blank inputs and call core methods correctly.

For component tests, provide a `@MockBean` of the `*Service` (not the
transport) in `ComponentTestConfiguration` — tests drive domain semantics,
not HTTP.

## 11b. Growth path — when the integration outgrows `client/<dep>/`

The five-layer sub-package above is calibrated for a **pure transport**
integration: build request → call remote → parse response. Some
integrations grow beyond that — a payment provider, a search index, a job
scheduler, a search backend — and start to accumulate:

- multiple *fetch shapes* (`fetchByStatus`, `fetchById`, `fetchOrderStatus`);
- pure-function *analysis* on the data returned (totals calculation,
  counters, status reduction);
- *background monitoring* jobs that periodically poll the dependency;
- *domain-language DTOs* consumed by controllers and other services.

**Do not** bloat `client/<dep>/` to host all of that. Promote each new
responsibility to its canonical top-level package instead:

| Responsibility | Package (from `code-structure` §1) | Suffix |
| --- | --- | --- |
| Transport, request/response, SDK config | `client/<dep>/` (stays here) | `*Client`, `*RequestBuilder`, `*ResponseParser` |
| One-per-shape data-access method on top of the client | `repository/` | `*Fetcher` (e.g. `*OrderListFetcher`, `*OrderDetailsFetcher`, `*OrderStatusFetcher`) |
| Remote-DTO → domain-DTO conversion | `mapper/` | `*Converter`, `*Builder` |
| Pure-function domain analysis | `analyzer/` | `*Calculator`, `*Analyzer` |
| Periodic polling / monitoring | `scheduler/` | `*Scheduler`, `*Task` |
| Public API used by `operation/` | `service/` | `*Service` (thin facade over the above) |

Configuration for the dependency remains **one** `@ConfigurationProperties`
record (or `@Configuration` bean) in `config/` — never scattered `@Value`
across every fetcher / scheduler / analyzer. Every collaborator injects the
same properties bean.

**Warning signs that trigger this split:**

- The `client/<dep>/` sub-package exceeds ~10 classes.
- A scheduler under `client/<dep>/` is building queries, calling the SDK
  directly, or duplicating a repository method.
- Two classes under `client/<dep>/` iterate the same status list
  with nearly identical `switch` statements — that's an `*Analyzer` waiting
  to be extracted.
- A DTO from the SDK is being passed to a controller — that means `mapper/`
  is missing.
- The same property (`namespace`, `taskQueue`, `topic`, `bucketName`) is
  read via `@Value` in more than one class.

**Layering after the split:**

```
controller ──► service ──► repository ──► client/<dep>/  (transport only)
                 │              │
                 └──► mapper    └──► analyzer   (pure functions)
                        │
scheduler ──► service / repository / analyzer
```

The scheduler never calls `client/<dep>/` directly, and the client never
imports from `mapper/`, `analyzer/`, or `scheduler/`.
