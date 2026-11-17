---
name: security-hardening
description: >
  Java / Spring Boot security beyond authn/authz — OWASP Top 10 checklist, CORS, security headers, secret management,
  dependency scanning, image signing. Use when a service exposes a public endpoint or handles sensitive data.
tier: must
applies_to: [rest, monolith]
depends_on: [permissions]
ships_templates: false
hitl: false
version: 1.1
last_reviewed: 2026-11-15
---

# Security Hardening Skill
`permissions` covers *who can do what*. This skill covers everything else:
*how the service resists abuse*.

## 1. Input validation (every layer)

- Controller: `@Valid` + JSR-380 (`@NotBlank`, `@Size(max = ...)`,
  `@Pattern(...)` for free-form fields).
- Validation layer: assert invariants a single field cannot express (cross-field rules
  via a Spring `Validator`, existence checks via a constraint backed by a `rule/` bean) —
  never as ad-hoc `if/throw` guards in the service (`input-validation`).
- Service/domain layer: re-asserts state-dependent invariants through domain exceptions (the controller cannot see them).
- Persistence: schema constraints (`NOT NULL`, `CHECK`, length limits) — the
  database is the last line of defence.

**Never** trust an upstream service's input either; validate at every
boundary.

## 2. OWASP Top 10 for Spring Boot

| Risk | Mitigation in this skill set |
| --- | --- |
| A01 Broken Access Control | `permissions` Strategy + Handler; `ArchUnit` rule that `SecurityContextHolder` only appears inside `permission/` (the JPA `AuditorAware` lives there too — `persistence` §1). |
| A02 Cryptographic Failures | All secrets via env / Vault, never in `application.yaml`; TLS termination is mandatory at ingress. |
| A03 Injection | Parameterized JPA queries; never `@Query(nativeQuery = true)` with concatenated strings; HTML output escaped by the templating engine. |
| A04 Insecure Design | `quality-review` audit + `ArchUnit` rules. |
| A05 Security Misconfiguration | Actuator endpoints exposed: `health,info,prometheus` only; never `env,beans,heapdump,httpexchanges` in prod. Default `management.endpoints.web.exposure.include` enumerates allow-list. |
| A06 Vulnerable & Outdated Components | Renovate + `dependency-check-maven` in CI; fail build on CVSS ≥ 7.0. |
| A07 Identification & Authentication | OAuth2 resource server, JWT validated with JWK Set rotation; never long-lived bearer tokens. |
| A08 Software & Data Integrity Failures | Cosign-signed container images; SBOM published; CI verifies signatures. |
| A09 Security Logging & Monitoring | Auth failures emit a `security.auth.failure` metric + structured log (`event=AUTH_FAILED`) — alerted in `observability`. The `permissions` `ProblemDetailSecurityHandler` template does both (§10). |
| A10 SSRF | Outbound HTTP clients have an **allow-list** of hosts; a client interceptor rejects others (`RestClient`: §10; a `WebClient` uses the same check in an `ExchangeFilterFunction`). |

## 3. CORS

Default: **deny all cross-origin**. Allow only the explicit front-end
origins:

```java
@ConfigurationProperties(prefix = "security.cors")
public record CorsProperties(List<String> allowedOrigins, boolean allowCredentials) {}   // register it: @EnableConfigurationProperties(CorsProperties.class) on the config class (or @ConfigurationPropertiesScan)

@Bean
public CorsConfigurationSource corsConfigurationSource(CorsProperties props) {
    var cfg = new CorsConfiguration();
    cfg.setAllowedOrigins(props.allowedOrigins());
    cfg.setAllowedMethods(List.of("GET","POST","PUT","PATCH","DELETE"));
    cfg.setAllowedHeaders(List.of("Authorization","Content-Type","Idempotency-Key"));
    // false by default: a stateless bearer-token API sends no cookies. Set true only for cookie/session auth.
    cfg.setAllowCredentials(props.allowCredentials());
    cfg.setMaxAge(Duration.ofHours(1));
    var src = new UrlBasedCorsConfigurationSource();
    src.registerCorsConfiguration("/api/**", cfg);
    return src;
}
```

Never `*` for origins when `allowCredentials = true`.

The bean only takes effect through Spring Security: the `permissions` `SecurityConfig` template calls
`.cors(Customizer.withDefaults())`, which picks up this `CorsConfigurationSource` bean. The path pattern is matched
without the servlet context path, so `/api/**` is right for a service under `server.servlet.context-path: /orders`.
Verified: a preflight from the listed origin answers 200 with `Access-Control-Allow-Origin`, `Max-Age: 3600` and no
`Allow-Credentials`; any other origin gets 403.

## 4. Rate limiting

Use the in-service approach of the **`rate-limiting`** skill (Bucket4j behind a `RateLimiterPort`, one bucket per
client key, Redis-backed when the limit must hold across pods) or an ingress-level limiter (Kong / Envoy) — one
approach per service. Per-route limits live in config.

If you use **bucket4j-spring-boot-starter** instead, it needs a JCache provider (e.g. Caffeine's `jcache`
module or a Redis JCache) and a per-client `cache-key` expression — without `cache-key` every caller shares
**one** global bucket:

```yaml
bucket4j:
  filters:
    - cache-name: rate-limits
      url: /api/.*                         # every API version — a v1-only pattern leaves /api/v2 unlimited
      rate-limits:
        - cache-key: "getRemoteAddr()"     # or the principal / API key — see rate-limiting §4 on trusted proxies
          bandwidths:
            - capacity: 100
              time: 1
              unit: minutes
```

Exceeded → `429 Too Many Requests` + `Retry-After` header (see `api-design`).

## 5. Secrets

- **At rest**: never in `application.yaml` or container images. Use env vars
  sourced from k8s Secrets (CSI driver to Vault / AWS Secrets Manager).
- **In transit**: TLS everywhere. mTLS for service-to-service if the mesh
  supports it.
- **Rotation**: tokens / DB passwords rotate on a schedule; the service
  re-reads via `@RefreshScope` (Spring Cloud) or container restart.

## 6. Security headers (response)

Configure them in Spring Security's `http.headers(...)` (it already sends `X-Content-Type-Options`, `X-Frame-Options`
and HSTS by default) rather than a hand-written `OncePerRequestFilter` that duplicates them:
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- `Content-Security-Policy: default-src 'self'` (when serving HTML)
- `X-Frame-Options: DENY`

```java
http.headers(h -> h
        .referrerPolicy(r -> r.policy(ReferrerPolicyHeaderWriter.ReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN))
        .httpStrictTransportSecurity(hsts -> hsts.includeSubDomains(true).maxAgeInSeconds(31_536_000)));
```

Spring Security writes HSTS only on HTTPS requests. Behind a TLS-terminating ingress the app sees HTTP, so set
`server.forward-headers-strategy=framework` (and let the ingress set `X-Forwarded-Proto`). Verified: without the
forwarded header the response has `Referrer-Policy`, `X-Content-Type-Options: nosniff` and `X-Frame-Options: DENY` but no
HSTS; with `X-Forwarded-Proto: https` it adds `Strict-Transport-Security: max-age=31536000 ; includeSubDomains`.

## 7. Actuator lockdown

These **replace** the template's `management.endpoints.web.exposure.include` / `management.endpoint.health.*` keys:
edit them in place instead of adding a second `management:` block.

```yaml
management:
  endpoints.web.exposure.include: health,info,prometheus
  endpoint.health.show-details: when_authorized
  endpoint.health.roles: ACTUATOR
```

The Prometheus endpoint may be public on the cluster network but blocked at
the ingress.

## 8. Dependency scanning in CI

These are **required**. The Jenkins `ci` templates ship the dependency-check and Trivy image-scan stages;
add the rest (cosign signing, SBOM) to your pipeline. Renovate ships via `create-repo`:

- **Renovate** for dependency upgrades (`create-repo` ships a `renovate.json`).
- **`dependency-check-maven`** breaks the build on known CVEs ≥ 7.0. Version 9+ downloads the NVD feed through
  the NVD API: pass the key with `nvdApiKeyEnvironmentVariable` (the name of a CI-secret env var — `nvdApiKey` on the command line shows in `ps` and Maven debug output), or CI is throttled and fails. OSV-based scanners or
  Trivy's filesystem scan are key-free alternatives.
- **Trivy** / **Grype** scans the container image; signed via **cosign**
  with key from KMS.
- **SBOM** generated (`syft`) and attached to the release.

## 9. Audit logging

Every action that mutates state emits:

```json
{ "event":"FOO_CREATED", "actor":"sub-7f3c9a…", "resource":"invoice/x-1",
  "outcome":"SUCCESS", "traceId":"…", "occurredAt":"…" }
```

`actor` is the pseudonymous subject id (the token's `sub`), never a username or e-mail (`data-privacy`).
Either as a structured log line consumed by SIEM, or as an event onto an
`audit` Kafka topic.

## 10. Filter-chain errors and outbound allow-list

**401 / 403 bodies.** Spring Security answers an unauthenticated or forbidden request inside the filter chain, before
the `@RestControllerAdvice` runs, so by default the body is empty — not the ProblemDetail every error must carry
(`exception-handling`). Register the `permissions` template
[`ProblemDetailSecurityHandler`](../permissions/templates/ProblemDetailSecurityHandler.java.tmpl) on the resource
server (`oauth2ResourceServer(o -> o.jwt(...).authenticationEntryPoint(h).accessDeniedHandler(h))`, as the
`SecurityConfig` template does): it keeps the `WWW-Authenticate: Bearer` header, writes an
`application/problem+json` body with `errorCode`, never echoes the exception message, and records the A09
`security.auth.failure` counter (tag `reason`) and `event=AUTH_FAILED` log line.

**SSRF allow-list (A10).** One `RestClientCustomizer` applies the check to Boot's `RestClient.Builder`, so every
client built from it (`external-client` clones that builder) refuses unlisted hosts before a connection is opened:

```java
/** SSRF guard (security-hardening A10): an outbound call to a host outside the configured allow-list is never sent. */
public class OutboundHostAllowList implements ClientHttpRequestInterceptor {
    private final Set<String> allowedHosts;

    public OutboundHostAllowList(Set<String> allowedHosts) {
        this.allowedHosts = allowedHosts.stream().map(h -> h.toLowerCase(Locale.ROOT)).collect(Collectors.toUnmodifiableSet());
    }

    @Override
    public ClientHttpResponse intercept(HttpRequest request, byte[] body, ClientHttpRequestExecution execution)
            throws IOException {
        String host = request.getURI().getHost();
        if (host == null || !allowedHosts.contains(host.toLowerCase(Locale.ROOT))) {
            throw new IllegalStateException("Outbound host is not in security.outbound.allowed-hosts: " + host);
        }
        return execution.execute(request, body);
    }
}

@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(OutboundHttpConfig.OutboundProperties.class)   // without it the record is no bean and startup fails
public class OutboundHttpConfig {

    @ConfigurationProperties(prefix = "security.outbound")
    public record OutboundProperties(Set<String> allowedHosts) {}

    @Bean
    RestClientCustomizer outboundHostAllowList(OutboundProperties props) {
        return builder -> builder.requestInterceptor(new OutboundHostAllowList(props.allowedHosts()));
    }
}
```

```yaml
security:
  outbound:
    allowed-hosts: ${OUTBOUND_ALLOWED_HOSTS}   # comma list, no default — an empty list blocks every outbound call
```

A refused call throws an unchecked `IllegalStateException` before any connection is opened (a misconfiguration, not an
outage, so it is not a domain exception). List every downstream host the service calls, including the ones only a readiness indicator probes
(`health-indicator` builds its client from the same builder).

## Do / Don't

✅ Default-deny: CORS, actuator, outbound hosts, file uploads (size + type
limits).
✅ Renovate + dep-check + Trivy + cosign in every CI pipeline (the `ci` Jenkins template ships dep-check and Trivy, `create-repo` ships Renovate; add cosign and the SBOM — §8).
✅ Validate at every boundary; the database is the last line of defence.
❌ Never log JWTs, passwords, PII without redaction.
❌ Never disable CSRF without justifying it in an ADR.
❌ Never check secrets into git — pre-commit hook + `gitleaks` in CI.

