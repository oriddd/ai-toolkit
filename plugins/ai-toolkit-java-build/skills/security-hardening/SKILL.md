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
version: 1.0
last_reviewed: 2026-11-11
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
| A09 Security Logging & Monitoring | Auth failures emit a `security.auth.failure` metric + structured log (`event=AUTH_FAILED`) — alerted in `observability`. |
| A10 SSRF | Outbound HTTP clients have an **allow-list** of hosts; `WebClient` filter rejects others. |

## 3. CORS

Default: **deny all cross-origin**. Allow only the explicit front-end
origins:

```java
@ConfigurationProperties(prefix = "security.cors")
public record CorsProperties(List<String> allowedOrigins, boolean allowCredentials) {}

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
`.cors(Customizer.withDefaults())`, which picks up this `CorsConfigurationSource` bean.

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
`server.forward-headers-strategy=framework` (and let the ingress set `X-Forwarded-Proto`).

## 7. Actuator lockdown

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

## Do / Don't

✅ Default-deny: CORS, actuator, outbound hosts, file uploads (size + type
limits).
✅ Renovate + dep-check + Trivy + cosign in every CI pipeline (the `ci` Jenkins template ships dep-check and Trivy, `create-repo` ships Renovate; add cosign and the SBOM — §8).
✅ Validate at every boundary; the database is the last line of defence.
❌ Never log JWTs, passwords, PII without redaction.
❌ Never disable CSRF without justifying it in an ADR.
❌ Never check secrets into git — pre-commit hook + `gitleaks` in CI.

