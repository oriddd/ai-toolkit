---
name: security-hardening
description: Cross-cutting security beyond authentication & authorization — input validation, OWASP Top 10 checklist tailored to Spring Boot, CORS, rate limiting, secret management at rest and in transit, dependency vulnerability scanning, container image signing, security headers. Use whenever a service exposes a public endpoint or handles sensitive data.
tier: must
applies_to: [rest, monolith]
depends_on: [permissions]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Security Hardening Skill (public)

`permissions` covers *who can do what*. This skill covers everything else:
*how the service resists abuse*.

## 1. Input validation (every layer)

- Controller: `@Valid` + JSR-380 (`@NotBlank`, `@Size(max = ...)`,
  `@Pattern(...)` for free-form fields).
- Service: assert invariants the controller cannot see (cross-field rules,
  existence checks).
- Persistence: schema constraints (`NOT NULL`, `CHECK`, length limits) — the
  database is the last line of defence.

**Never** trust an upstream service's input either; validate at every
boundary.

## 2. OWASP Top 10 for Spring Boot

| Risk | Mitigation in this skill set |
| --- | --- |
| A01 Broken Access Control | `permissions` Strategy + Handler; `ArchUnit` rule that `SecurityContextHolder` only appears inside `permission/`. |
| A02 Cryptographic Failures | All secrets via env / Vault, never in `application.yaml`; TLS termination is mandatory at ingress. |
| A03 Injection | Parameterized JPA queries; never `@Query(nativeQuery = true)` with concatenated strings; HTML output escaped by the templating engine. |
| A04 Insecure Design | `quality-review` audit + `ArchUnit` rules. |
| A05 Security Misconfiguration | Actuator endpoints exposed: `health,info,prometheus` only; never `env,beans,heapdump` in prod. Default `management.endpoints.web.exposure.include` enumerates allow-list. |
| A06 Vulnerable & Outdated Components | Renovate + `dependency-check-maven` in CI; fail build on CVSS ≥ 7.0. |
| A07 Identification & Authentication | OAuth2 resource server, JWT validated with JWK Set rotation; never long-lived bearer tokens. |
| A08 Software & Data Integrity Failures | Cosign-signed container images; SBOM published; CI verifies signatures. |
| A09 Security Logging & Monitoring | Auth failures emit a `security.auth.failure` metric + structured log (`event=AUTH_FAILED`) — alerted in `observability`. |
| A10 SSRF | Outbound HTTP clients have an **allow-list** of hosts; `WebClient` filter rejects others. |

## 3. CORS

Default: **deny all cross-origin**. Allow only the explicit front-end
origins:

```java
@Bean
public CorsConfigurationSource corsConfigurationSource(@Value("${security.cors.allowed-origins}") List<String> origins) {
    var cfg = new CorsConfiguration();
    cfg.setAllowedOrigins(origins);
    cfg.setAllowedMethods(List.of("GET","POST","PUT","PATCH","DELETE"));
    cfg.setAllowedHeaders(List.of("Authorization","Content-Type","Idempotency-Key"));
    cfg.setAllowCredentials(true);
    cfg.setMaxAge(Duration.ofHours(1));
    var src = new UrlBasedCorsConfigurationSource();
    src.registerCorsConfiguration("/api/**", cfg);
    return src;
}
```

Never `*` for origins when `allowCredentials = true`.

## 4. Rate limiting

Use **bucket4j-spring-boot-starter** or an ingress-level limiter (Kong /
Envoy). Per-route limits live in config:

```yaml
bucket4j:
  filters:
    - cache-name: rate-limits
      url: /api/v1/.*
      rate-limits:
        - bandwidths:
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

A `OncePerRequestFilter` adds:
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- `Content-Security-Policy: default-src 'self'` (when serving HTML)
- `X-Frame-Options: DENY`

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

- **Renovate** for dependency upgrades (already in `ci`).
- **`dependency-check-maven`** breaks the build on known CVEs ≥ 7.0.
- **Trivy** / **Grype** scans the container image; signed via **cosign**
  with key from KMS.
- **SBOM** generated (`syft`) and attached to the release.

## 9. Audit logging

Every action that mutates state emits:

```json
{ "event":"FOO_CREATED", "actor":"alice", "resource":"document/x-1",
  "outcome":"SUCCESS", "traceId":"…", "occurredAt":"…" }
```

Either as a structured log line consumed by SIEM, or as an event onto an
`audit` Kafka topic.

## Do / Don't

✅ Default-deny: CORS, actuator, outbound hosts, file uploads (size + type
limits).
✅ Renovate + dep-check + Trivy + cosign in every CI pipeline.
✅ Validate at every boundary; the database is the last line of defence.
❌ Never log JWTs, passwords, PII without redaction.
❌ Never disable CSRF without justifying it in an ADR.
❌ Never check secrets into git — pre-commit hook + `gitleaks` in CI.

