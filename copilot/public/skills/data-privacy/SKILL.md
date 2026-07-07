---
name: data-privacy
description: Handle PII (Personally Identifiable Information) and GDPR requirements in a Java microservice — field-level encryption, masking in logs, data retention/TTL, right-to-be-forgotten (delete/anonymize), and data-privacy-by-design principles. Use whenever a service processes user data.
tier: must
applies_to: [rest, event, monolith]
depends_on: [persistence, observability, pluggable-architecture]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Data Privacy Skill

This skill ensures that the microservice respects data privacy regulations (GDPR, CCPA) and follows the principle of **privacy by design**.

## 1. PII Identification

Identify any fields that contain Personally Identifiable Information (PII):
- Names, Email addresses, Phone numbers.
- IP addresses, Device IDs.
- Location data.
- Financial or health information.

## 2. PII in Logs (Masking)

**Never log PII in plain text.** Use a masking approach at the logging layer.

### Rule: Masking by Annotation
Use a custom `@Mask` annotation on DTO fields and a corresponding Jackson `JsonSerializer` or a Logback/Log4j2 pattern converter to mask these fields.

```java
public record UserProfile(
    String id,
    @Mask String email,
    @Mask String phoneNumber
) {}
```

#### Jackson Masking Implementation
```java
public class MaskingSerializer extends JsonSerializer<String> {
    @Override
    public void serialize(String value, JsonGenerator gen, SerializerProvider serializers) throws IOException {
        if (value == null) {
            gen.writeNull();
            return;
        }
        gen.writeString(value.replaceAll(".(?=.{4})", "*"));
    }
}
```

## 3. PII in Database (Encryption)

Sensitive PII should be encrypted at rest. Use **JPA Attribute Converters** with a secure key management system (AES-256).

```java
@Entity
public class UserEntity {
    @Id private String id;
    
    @Convert(converter = EncryptionConverter.class)
    private String email;
}
```

**Key Rotation**: Ensure your `EncryptionConverter` supports multiple key versions to allow for background migration/rotation.

## 4. Right to be Forgotten (Deletion/Anonymization)

Implement a mechanism to handle data deletion requests. Use a **Deletion Coordinator** pattern:

1. **Trigger**: Receive a `UserDeletedEvent` (see [messaging](../messaging/SKILL.md)).
2. **Phase 1 (Sync)**: Mark user as `DELETED`, scramble PII fields in the main DB.
3. **Phase 2 (Async)**: Trigger background jobs to purge audit logs, backups, and secondary stores.
4. **Finalize**: Emit `UserPurgedEvent` once all data traces are removed.

## 5. Data Retention (TTL)

Define and enforce data retention periods.
- Use **TTL (Time To Live)** on database rows where supported (e.g., DynamoDB, Redis).
- Use a **Scheduled Job** (see [spring-boot-conventions](../spring-boot-conventions/SKILL.md)) to purge expired data from SQL databases.

## 6. Data Access Auditing

Every access to PII should be logged.
- Use the [observability](../observability/SKILL.md) skill to ensure that "who accessed whose data" is captured in audit logs.

## Do / Don't

✅ Identify PII during the design phase.
✅ Mask PII in logs by default.
✅ Use field-level encryption for sensitive data.
✅ Implement a clear data retention policy.
❌ Never use PII in cache keys or URL parameters.
❌ Never log raw request/response bodies that might contain PII.
❌ Never store PII in plaintext in local development environments.
