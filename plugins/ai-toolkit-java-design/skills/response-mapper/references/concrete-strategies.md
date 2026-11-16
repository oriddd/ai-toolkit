# Response Mapper Skill — Concrete strategies

Part of the [`response-mapper`](../SKILL.md) skill (§3, Implementation). Headings are stable; other skills cite them.

### Concrete Strategies

**V1 — legacy schema (kept for backward compatibility):**
```java
@Component
public class V1UserMapperStrategy implements MapperStrategy<User, UserV1DTO> {
    @Override
    public ApiVersion getSupportedVersion() {
        return ApiVersion.V1;
    }

    @Override
    public Class<User> getEntityType() {
        return User.class;
    }

    @Override
    public UserV1DTO map(final User user) {
        return new UserV1DTO(user.getId(), user.getFullName());     // V1 flattened name
    }
}
```

**V2 — split name, adds email:**
```java
@Component
public class V2UserMapperStrategy implements MapperStrategy<User, UserV2DTO> {
    @Override
    public ApiVersion getSupportedVersion() {
        return ApiVersion.V2;
    }

    @Override
    public Class<User> getEntityType() {
        return User.class;
    }

    @Override
    public UserV2DTO map(final User user) {
        return new UserV2DTO(user.getId(), user.getFirstName(), user.getLastName(), user.getEmail());
    }
}
```

**V3 — latest schema, adds structured contact block:**
```java
@Component
public class V3UserMapperStrategy implements MapperStrategy<User, UserV3DTO> {
    @Override
    public ApiVersion getSupportedVersion() {
        return ApiVersion.V3;
    }

    @Override
    public Class<User> getEntityType() {
        return User.class;
    }

    @Override
    public UserV3DTO map(final User user) {
        return new UserV3DTO(
                user.getId(),
                user.getFirstName(),
                user.getLastName(),
                new ContactDTO(user.getEmail(), user.getPhone()));
    }
}
```
