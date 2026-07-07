---
name: feature-flags
description: Implement feature toggles (flags) to decouple deployment from release. Covers local configuration toggles, remote flag providers (Unleash, LaunchDarkly), and the "Toggle-at-the-Edge" vs "Toggle-in-Logic" patterns. Includes guidance on flag lifecycle management to prevent technical debt.
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
- **Ops Toggles**: Circuit breakers or killing heavy features (long-lived, see [resilience-patterns](../resilience-patterns/SKILL.md)).
- **Permission Toggles**: Early access for specific users (long-lived).

## 2. Toggle-in-Logic Pattern

Implement flags using a dedicated `FeatureStore` or a client library:

```java
if (features.isEnabled("new-algorithm")) {
    return applyNewAlgorithm(input);
} else {
    return applyLegacyAlgorithm(input);
}
```

### 2b. Structural Toggles (@ConditionalOnProperty)
For larger changes, switch entire bean implementations:

```java
@Bean
@ConditionalOnProperty(name = "features.storage.use-s3", havingValue = "true")
public StorageClient s3Client() { return new S3StorageClient(); }

@Bean
@ConditionalOnProperty(name = "features.storage.use-s3", havingValue = "false", matchIfMissing = true)
public StorageClient localClient() { return new LocalStorageClient(); }
```

## 3. Remote Flag Providers

While `application.yaml` works for static toggles, use a remote provider for dynamic control:
- **Unleash / LaunchDarkly**: Provide SDKs for real-time updates without restart.
- **Spring Cloud Config**: Supports refreshable beans.

## 4. Flag Lifecycle (Technical Debt)

**Feature flags are temporary.**
- Define a "removal task" in your backlog the moment a flag is created.
- A flag is ready for removal once the feature is 100% rolled out and stable.

## 5. Testing with Flags

Test both states of the flag:
- Unit tests: Mock the `FeatureToggleProvider` to return `true` and `false`.
- Component tests: Run the test suite with the flag in the expected state for that environment (see [component-tests](../component-tests/SKILL.md)).

## Do / Don't

✅ Move the toggle check as close to the business logic as possible.
✅ Use meaningful names (e.g., `enable-document-batch-v2`).
✅ Add a default value (usually `false`) in case the provider is unreachable.
❌ Never use nested feature flags.
❌ Never leave "zombie flags" (flags that are 100% on or off for months).
❌ Never use feature flags as a substitute for proper branch management.
