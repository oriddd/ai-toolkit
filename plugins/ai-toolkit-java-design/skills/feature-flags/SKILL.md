---
name: feature-flags
description: >
  Java / Spring Boot feature toggles — local config toggles, remote providers (Unleash, LaunchDarkly),
  toggle-at-the-edge vs toggle-in-logic, flag lifecycle and cleanup. Use when a change must be toggled at runtime or
  released dark.
tier: should
applies_to: [rest, event, monolith]
depends_on: [code-structure, pluggable-architecture]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Feature Flags Skill

Feature flags allow you to merge code to `main` and deploy to production without immediately exposing the new functionality to users.

## 1. Toggle Types

- **Release Toggles**: Safeguard for incomplete features (short-lived).
- **Experiment Toggles**: A/B testing (medium-lived).
- **Ops Toggles**: Circuit breakers or killing heavy features (long-lived, see resilience-patterns).
- **Permission Toggles**: Early access for specific users (long-lived).

## 2. Toggle-in-Logic Pattern

Implement flags behind a dedicated `FeatureTogglePort` (the port named in `pluggable-architecture`; its adapter wraps local config or a remote client library):

```java
// flag keys are constants (or an enum) — never inline string literals
public final class FeatureFlags {
    public static final String ENABLE_INVOICE_PRICING_V2 = "enable-invoice-pricing-v2";
    private FeatureFlags() {}
}

if (features.isEnabled(FeatureFlags.ENABLE_INVOICE_PRICING_V2)) {
    return applyNewAlgorithm(input);
} else {
    return applyLegacyAlgorithm(input);
}
```

### 2b. Structural Toggles (@ConditionalOnProperty)
For larger changes, switch entire bean implementations. Select by a provider key (an enum in the typed
properties, see `pluggable-architecture` §5), not a boolean such as `use-s3`.

Choosing **which vendor** backs a capability (S3 vs local disk) is provider selection, not a release flag: it is
wired exactly as `pluggable-architecture` §3 describes — a `*Port` in `spi/`, one adapter per vendor, the vendor
client injected as a bean rather than created with `new` in the config. Keep structural toggles for switching
**behaviour** (old vs new implementation of the same port), and give them the same lifecycle as any other flag (§4):

```java
@Bean
@ConditionalOnProperty(name = "features.storage.provider", havingValue = "s3")
public ObjectStorePort s3ObjectStore(S3Client s3) { return new S3ObjectStoreAdapter(s3); }

@Bean
@ConditionalOnProperty(name = "features.storage.provider", havingValue = "local", matchIfMissing = true)
public ObjectStorePort localObjectStore(ObjectStoreProperties props) { return new LocalObjectStoreAdapter(props.rootDir()); }
```

### 2c. Toggle-at-the-Edge Pattern

Evaluate the flag **once, at the entry point** (controller, message listener, scheduled job) and route to the old
or new use case; the code below the edge has no flag checks:

```java
@GetMapping("/{id}/price")
public ResponseEntity<PriceResponse> price(@PathVariable String id) {
    var operation = features.isEnabled(FeatureFlags.ENABLE_INVOICE_PRICING_V2)
            ? pricingV2Operation : pricingOperation;          // both implement the same PricingUseCase
    return ResponseEntity.ok(operation.execute(id));
}
```

Pick the edge when the whole request path changes (new endpoint behaviour, new pipeline) and per-user targeting
is needed — removing the flag later deletes one branch at one place. Pick toggle-in-logic (§2) when the change is a
single decision deep inside a use case.

## 3. Remote Flag Providers

While `application.yaml` works for static toggles, use a remote provider for dynamic control:
- **Unleash / LaunchDarkly**: Provide SDKs for real-time updates without restart.
- **Spring Cloud Config**: Supports refreshable beans.
- **OpenFeature**: the vendor-neutral (CNCF) flag-evaluation API with providers for Unleash, LaunchDarkly, flagd and
  others. A `FeatureTogglePort` adapter backed by the OpenFeature Java SDK keeps the vendor swappable by
  configuration.

## 4. Flag Lifecycle (Technical Debt)

**Feature flags are temporary.**
- Define a "removal task" in your backlog the moment a flag is created.
- A flag is ready for removal once the feature is 100% rolled out and stable.

## 5. Testing with Flags

Test both states of the flag:
- Unit tests: Mock the `FeatureTogglePort` to return `true` and `false`.
- Component tests: Run the test suite with the flag in the expected state for that environment (see component-tests),
  and run the **critical paths in both states** (e.g. a second test class or `@TestPropertySource` with the flag
  flipped) so the off-path still works on the day the flag is turned off or removed.

## Do / Don't

✅ Move the toggle check as close to the business logic as possible.
✅ Use meaningful names (e.g., `enable-invoice-batch-v2`).
✅ Add a default value (usually `false`) in case the provider is unreachable.
❌ Never use nested feature flags.
❌ Never leave "zombie flags" (flags that are 100% on or off for months).
❌ Never use feature flags as a substitute for proper branch management.
