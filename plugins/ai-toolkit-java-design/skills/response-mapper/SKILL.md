---
name: response-mapper
description: >
  Java / Spring Boot API versioning and response projections via Strategy + Handler + Registry — version resolved from
  Accept header, URI or query param; one MapperStrategy per version. Use when an API serves several versions or
  projections. For ?layout= use `response-layout`.
tier: should
applies_to: [rest, monolith]
depends_on: [code-structure, spring-boot-conventions, strategy-registry-pattern]
ships_templates: false
hitl: false
version: 1.1
last_reviewed: 2026-07-12
---

# Response Mapper Skill
> **Pattern Foundation:** This skill is a concrete application of the strategy-registry-pattern skill.
> Read that skill first to understand the foundational pattern, then return here for the mapper-specific implementation.

REST APIs often need to support:
- **Multiple API versions** (v1, v2, v3) with different response schemas
- **Different projections** (summary, detailed, full) of the same entity
- **Backward compatibility** while evolving the domain model

This skill provisions a **version and projection-aware response mapping** layer using the Strategy + Handler + Registry pattern.
Add a new version or projection by adding one `@Component` strategy — the handler and registry never change.

> **Pattern Application:** This follows the **Handler-based variation** of the strategy-registry-pattern.
> Components: Handler → Resolver (ApiVersion/Projection from Accept header/URI) → Registry → Strategy (entity→DTO mapping)

## 1. Package structure

```
mapper/
├── ApiVersion.java                    # Discriminator enum: V1 / V2 / V3
├── MapperConstants.java               # header names / media types as constants
├── MapperContextResolver.java         # Resolver: extracts ApiVersion from request
├── MapperStrategy.java                # Strategy interface: map(entity) + canHandle()
├── MapperHandler.java                 # Handler: orchestrates resolver → registry → strategy
├── MapperRegistry.java                # Registry: routes ApiVersion → strategy
└── strategy/
    ├── V1UserMapperStrategy.java      # Strategy: User → UserV1DTO
    ├── V2UserMapperStrategy.java      # Strategy: User → UserV2DTO
    └── V3UserMapperStrategy.java      # Strategy: User → UserV3DTO
```

## 2. Pattern Components

See strategy-registry-pattern for detailed component responsibilities.

**Mapper-specific mapping:**
- **Discriminator:** `ApiVersion` enum (V1 / V2 / V3), or a `Projection` enum
- **Resolver:** Reads the target version from the URI segment (`/api/v2/users`, the `api-design` §3 default), or the
  `Accept` header / `?version=` query param (§7 variation)
- **Strategy:** Maps entity → version-specific DTO
- **Handler:** Orchestrates resolver → registry → strategy, returns the DTO

## 3. Implementation

### `ApiVersion` (enum)

```java
public enum ApiVersion {
    V1, V2, V3;

    public static ApiVersion fromString(final String version) {
        if (version == null || version.isBlank()) {
            return defaultVersion();   // unversioned requests get the pinned default, never silently the newest
        }
        try {
            return ApiVersion.valueOf(version.trim().toUpperCase(Locale.ROOT));   // Locale.ROOT: locale-independent
        } catch (final IllegalArgumentException e) {
            // unknown version → reject; mapped to 406 Not Acceptable by the @RestControllerAdvice (see below)
            throw ExceptionMessages.unsupportedApiVersion(Arrays.toString(values()));
        }
    }

    public static ApiVersion latest() {
        return V3;
    }

    // Served when the client sends no version. Moves forward only through the
    // api-design §3 deprecation process (old version kept ≥ 6 months), never on release.
    public static ApiVersion defaultVersion() {
        return V1;
    }
}
```

### `UnsupportedApiVersionException` (406)

A domain exception in the `exception-handling` hierarchy (unchecked, built through the `ExceptionMessages` catalogue)
plus its advice mapping. The `exception-handling` templates ship all three; shown here for reference:

```java
// {{basePackage}}.exception.UnsupportedApiVersionException
public class UnsupportedApiVersionException extends BaseDomainException {
    public UnsupportedApiVersionException(String errorCode, String message) { super(errorCode, message); }
}

// {{basePackage}}.exception.constants.ExceptionMessages
public static UnsupportedApiVersionException unsupportedApiVersion(String supportedVersions) {
    // lists the supported versions; never echoes the caller's raw input back
    return new UnsupportedApiVersionException(ERR_UNSUPPORTED_API_VERSION,
            MessageFormat.format(UNSUPPORTED_API_VERSION, supportedVersions));
}
// caller: ExceptionMessages.unsupportedApiVersion(Arrays.toString(ApiVersion.values()))

// {{basePackage}}.exception.handler.GlobalExceptionHandler (@RestControllerAdvice)
@ExceptionHandler(UnsupportedApiVersionException.class)
public ProblemDetail onUnsupportedApiVersion(UnsupportedApiVersionException e) {
    return build(HttpStatus.NOT_ACCEPTABLE, e);
}
```

### `MapperContextResolver`

URI versioning — the `api-design` §3 default and guild rule 15 ("version in path"):

```java
@Component
public class MapperContextResolver {
    private static final Pattern URI_VERSION = Pattern.compile("^/api/(v\\d+)/");

    public ApiVersion resolve(final HttpServletRequest request) {
        if (request == null || request.getRequestURI() == null) {
            return ApiVersion.defaultVersion();
        }
        // getRequestURI() includes server.servlet.context-path; the pattern is written without it
        final String path = request.getRequestURI().substring(request.getContextPath().length());
        final Matcher m = URI_VERSION.matcher(path);
        return m.find() ? ApiVersion.fromString(m.group(1)) : ApiVersion.defaultVersion();
    }
}
```

**Variation — media-type versioning** (`Accept: application/vnd.example.v2+json`, the other `api-design` §3 option):

```java
@Component
public class MapperContextResolver {

    // media-type versioning (api-design §3), e.g. Accept: application/vnd.example.v2+json
    private static final Pattern ACCEPT_VERSION =
            Pattern.compile("application/vnd\\.example\\.(v\\d+)\\+json", Pattern.CASE_INSENSITIVE);

    public ApiVersion resolve(final HttpServletRequest request) {
        if (request == null) {
            return ApiVersion.defaultVersion();
        }
        final String accept = request.getHeader("Accept");
        if (accept != null) {
            final Matcher m = ACCEPT_VERSION.matcher(accept);
            if (m.find()) {
                return ApiVersion.fromString(m.group(1));
            }
        }
        // fall back to ?version=v2 query param
        return ApiVersion.fromString(request.getParameter("version"));
    }
}
```

### `MapperStrategy` (interface)

```java
public interface MapperStrategy<E, D> {
    D map(E entity);
    ApiVersion getSupportedVersion();
    Class<E> getEntityType();   // the registry is shared by every entity — this keeps User and other entities apart

    default boolean canHandle(final ApiVersion version) {
        return getSupportedVersion() != null
                && getSupportedVersion().equals(version);
    }
}
```

### `MapperRegistry`

One **non-generic** singleton for every entity. Spring injects every `MapperStrategy` (User, Order, …), so the
registry indexes them by (entity type, version) and fails at startup when two strategies claim the same pair. The
generic type is restored in one place, `find(...)`, where the key guarantees it.

```java
@Component
public class MapperRegistry {
    private record Key(Class<?> entityType, ApiVersion version) { }

    private final Map<Key, MapperStrategy<?, ?>> strategies;

    public MapperRegistry(final List<MapperStrategy<?, ?>> strategies) {
        this.strategies = strategies.stream().collect(Collectors.toUnmodifiableMap(
                s -> new Key(s.getEntityType(), s.getSupportedVersion()),
                Function.identity(),
                (first, second) -> {
                    throw new IllegalStateException("Two mapper strategies for " + first.getEntityType().getSimpleName()
                            + "/" + first.getSupportedVersion() + ": " + first.getClass().getName()
                            + ", " + second.getClass().getName());
                }));
    }

    @SuppressWarnings("unchecked")   // safe: the key's entity type is the strategy's own getEntityType()
    public <E> Optional<MapperStrategy<E, ?>> find(final Class<E> entityType, final ApiVersion version) {
        return Optional.ofNullable((MapperStrategy<E, ?>) strategies.get(new Key(entityType, version)));
    }
}
```

### `MapperHandler`

A version the client asked for but this entity does not serve is rejected (406) — never silently answered with
another schema:

```java
@Component
@RequiredArgsConstructor
public class MapperHandler {
    private final MapperContextResolver resolver;
    private final MapperRegistry registry;

    /** @param entityType passed explicitly — entity.getClass() can be a JPA proxy subclass */
    public <E> Object handle(final Class<E> entityType, final E entity, final HttpServletRequest request) {
        if (entity == null) {
            return null;
        }
        final ApiVersion version = resolver.resolve(request);   // unknown version → 406
        final MapperStrategy<E, ?> strategy = registry.find(entityType, version)
                .orElseThrow(() -> ExceptionMessages.unsupportedApiVersion(Arrays.toString(ApiVersion.values())));   // 406, never a silent fallback to latest()
        return strategy.map(entity);
    }
}
```

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
        if (user == null) return null;
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
        if (user == null) return null;
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
        if (user == null) return null;
        return new UserV3DTO(
                user.getId(),
                user.getFirstName(),
                user.getLastName(),
                new ContactDTO(user.getEmail(), user.getPhone()));
    }
}
```

## 4. Controller Integration

```java
@RestController
@RequestMapping("/api/{apiVersion:v\\d+}/users")   // URI versioning (api-design §3, guild rule 15); the resolver reads the segment
@RequiredArgsConstructor
public class UserController {
    private final UserService userService;
    private final MapperHandler mapperHandler;

    @GetMapping("/{id}")
    @ApiResponse(responseCode = "200", content = @Content(schema = @Schema(oneOf = {
            UserV1DTO.class, UserV2DTO.class, UserV3DTO.class })))
    public ResponseEntity<Object> getUser(@PathVariable final String id,
                                          final HttpServletRequest request) {
        final User user = userService.getById(id);
        final Object dto = mapperHandler.handle(User.class, user, request);
        return ResponseEntity.ok(dto);
    }
}
```

DTOs are immutable records, e.g. `public record UserV1DTO(String id, String name) { }`.

**Rules:**
- The response type is `Object` — the handler returns the version-specific DTO. Without the `oneOf` `@ApiResponse`
  springdoc publishes no schema, so declare every version's DTO there (or publish one OpenAPI group per version).
- **openapi-first:** a generated `UserApi` method has one fixed return type, so this controller cannot implement it
  as is — generate one interface per version instead, or don't use this skill there.
- **Media-type versioning** (§3 variation): the response varies by a request header, so add `Vary: Accept`
  (`ResponseEntity.ok().varyBy(HttpHeaders.ACCEPT).body(dto)`), or shared caches serve one version to every client.
- Pass `HttpServletRequest` to the handler for version resolution
- Service returns the **entity**; mapping is a presentation-layer concern
- Keep the version discriminator out of the service and domain layers
- Align with the versioning scheme chosen in `api-design` §3: URI segment (this example, `/api/v1/users`) or
  media type (`application/vnd.example.vN+json`, the resolver variation in §3)

## 5. Adding a New Version

**Checklist:**
1. ✅ Add the new `ApiVersion` enum value (e.g. `V4`) and update `latest()` if it becomes newest
2. ✅ Create the new DTO class (e.g. `UserV4DTO`)
3. ✅ Create `V4UserMapperStrategy implements MapperStrategy`
4. ✅ Annotate it `@Component`
5. ✅ Implement `getSupportedVersion()`, `getEntityType()` and `map(entity)`
6. ✅ Write unit tests for the new strategy
7. ✅ Update OpenAPI docs and the deprecation policy for the retired version

**Zero changes needed:**
- ❌ MapperHandler, MapperRegistry, MapperContextResolver, existing strategies, the controller (its path accepts any `v<N>`)

## 6. When to Use

✅ **Use when:**
- Supporting multiple API versions with different schemas
- Different projections for the same entity (summary/detailed/full)
- Backward compatibility while evolving the domain
- Client-specific response shapes

❌ **Don't use when:**
- Only one API version — use a single DTO
- Versions differ by 1–2 fields — use `@JsonView`
- Compile-time version selection — use separate endpoints/controllers

## 7. Variations

### Version from URI segment or `Accept` header
The URI-segment resolver is the main example in §3; the `Accept` header resolver (media-type versioning) is shown
there as its variation. Use exactly one scheme per API (`api-design` §3).

### Projection instead of version
Swap the `ApiVersion` discriminator for a `Projection` enum (`SUMMARY` / `DETAILED` / `FULL`) resolved from `?projection=`. This overlaps with `response-layout` — prefer `response-layout` when the choice is purely a field-set concern, and `response-mapper` when whole schemas evolve across versions.

## 8. Testing

Handler, registry and strategy tests (hand-built registry, no Spring context) — load [`references/testing.md`](./references/testing.md) when writing the tests.

---

**Version:** 1.1  
**Last Reviewed:** 2026-07-12
