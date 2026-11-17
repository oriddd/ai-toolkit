# Data Privacy Skill — `EncryptionConverter` (AES-256-GCM, key versions)

Part of the [`data-privacy`](../SKILL.md) skill (§3). Hand-written `Cipher` code is the fallback when no vetted library
(Tink `Aead`, the KMS SDK) is available; the stored format and the key-version rule below apply either way.

The converter is a Spring `@Component`: Hibernate resolves `@Convert(converter = EncryptionConverter.class)` through Spring's
bean container, so the `FieldKeyProvider` is constructor-injected. The provider is the port to the KMS / Vault
(`pluggable-architecture`): it returns the current key version and the key of any version.

```java
public interface FieldKeyProvider {
    int currentVersion();
    SecretKey key(int version);          // 256-bit AES key, unwrapped from the KMS; cache it, never log it
}

@Component
@Converter
public class EncryptionConverter implements AttributeConverter<String, String> {
    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int IV_BYTES = 12;
    private static final int TAG_BITS = 128;

    private final FieldKeyProvider keys;
    private final SecureRandom random = new SecureRandom();

    public EncryptionConverter(final FieldKeyProvider keys) { this.keys = keys; }

    @Override
    public @Nullable String convertToDatabaseColumn(final @Nullable String plaintext) {
        if (plaintext == null) { return null; }
        try {
            final int version = keys.currentVersion();
            final byte[] iv = new byte[IV_BYTES];
            random.nextBytes(iv);                                            // fresh IV for every value
            final Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.ENCRYPT_MODE, keys.key(version), new GCMParameterSpec(TAG_BITS, iv));
            final byte[] encrypted = cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));
            final byte[] payload = ByteBuffer.allocate(iv.length + encrypted.length).put(iv).put(encrypted).array();
            return version + ":" + Base64.getEncoder().encodeToString(payload);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("Field encryption failed", e);
        }
    }

    @Override
    public @Nullable String convertToEntityAttribute(final @Nullable String stored) {
        if (stored == null) { return null; }
        try {
            final int separator = stored.indexOf(':');
            final int version = Integer.parseInt(stored.substring(0, separator));
            final byte[] payload = Base64.getDecoder().decode(stored.substring(separator + 1));
            final Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.DECRYPT_MODE, keys.key(version), new GCMParameterSpec(TAG_BITS, payload, 0, IV_BYTES));
            return new String(cipher.doFinal(payload, IV_BYTES, payload.length - IV_BYTES), StandardCharsets.UTF_8);
        } catch (GeneralSecurityException | IllegalArgumentException e) {
            throw new IllegalStateException("Field decryption failed", e);
        }
    }
}
```

The column is `varchar` sized for `<version>:<base64(12 + n + 16 bytes)>`: plan for roughly 1.4 × the plaintext length plus 40.
An unparsable or tampered value fails closed (`IllegalStateException`) — the GCM tag rejects any modified byte.

Verified (JPA + H2, Spring Boot 3.5, Error Prone + NullAway clean): the column holds `1:…` with no plaintext; two equal
e-mails store different ciphertexts; after `currentVersion()` moves to 2 new rows are written as `2:…` and rows written
under version 1 still read back; a modified ciphertext is rejected; `null` maps to `null` both ways.

## Masking serializer

The `@Mask` annotation on a record component, the `JacksonAnnotationIntrospector` override and `MaskingSerializer` from
SKILL.md §2 were run on a record: the dedicated mapper writes `"email":"a***"`, a plain `ObjectMapper` still writes the
real value (so API responses are unaffected), and the record's `toString()` carries no PII.
