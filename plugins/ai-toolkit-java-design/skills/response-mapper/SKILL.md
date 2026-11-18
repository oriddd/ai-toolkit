---
name: response-mapper
description: >
  Java / Spring Boot API versioning and response projections via Strategy + Handler + Registry — version resolved from
  the URI or the Accept header; one MapperStrategy per version. Use when an API serves several versions or
  projections. For ?layout= use `response-layout`.
tier: should
applies_to: [rest, monolith]
depends_on: [code-structure, spring-boot-conventions, strategy-registry-pattern]
ships_templates: false
hitl: false
version: 1.1
last_reviewed: 2026-11-15
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
- **Resolver:** Reads the target version from the URI segment (`/api/v2/users`, the `api-design` §3 default) or, as
  the §7 variation, the `Accept` header — one scheme per API, never a `?version=` fallback. It also builds the
  "version not served" error, because the status depends on the scheme: an unknown URI version is a path that does
  not exist (404), an `Accept` version the API does not serve is 406 Not Acceptable
- **Strategy:** Maps entity → version-specific DTO
- **Handler:** Orchestrates resolver → registry → strategy, returns the DTO

## 3. Implementation

### `ApiVersion` (enum)

```java
public enum ApiVersion {
    V1, V2, V3;

    /** Empty for a version this API does not define; the resolver rejects it with its scheme's status. */
    public static Optional<ApiVersion> parse(final String version) {
        try {
            return Optional.of(ApiVersion.valueOf(version.trim().toUpperCase(Locale.ROOT)));   // Locale.ROOT: locale-independent
        } catch (final IllegalArgumentException e) {
            return Optional.empty();
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

### `UnsupportedApiVersionException` (406, media-type versioning)

Thrown only by the `Accept`-header resolver; with URI versioning an unknown version is the `NotFoundException` (404)
from `ExceptionMessages.resourceNotFound`. A domain exception in the `exception-handling` hierarchy (checked, built through the `ExceptionMessages` catalogue)
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

URI versioning — the `api-design` §3 default and guild rule 15 ("version in path"). Unversioned requests get the
pinned `defaultVersion()`, never silently the newest:

```java
@Component
public class MapperContextResolver {
    private static final Pattern URI_VERSION = Pattern.compile("^/api/(v\\d+)/");

    public ApiVersion resolve(final HttpServletRequest request) throws BaseDomainException {
        if (request == null || request.getRequestURI() == null) {
            return ApiVersion.defaultVersion();
        }
        // getRequestURI() includes server.servlet.context-path; the pattern is written without it
        final String path = request.getRequestURI().substring(request.getContextPath().length());
        final Matcher m = URI_VERSION.matcher(path);
        if (!m.find()) {
            return ApiVersion.defaultVersion();
        }
        final String requested = m.group(1);
        return ApiVersion.parse(requested).orElseThrow(() -> versionNotServed(requested));
    }

    /** URI versioning: /api/v9/… names a resource that does not exist — 404, like any unknown path. */
    public BaseDomainException versionNotServed(final String version) {
        return ExceptionMessages.resourceNotFound("API version", version.toLowerCase(Locale.ROOT));
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

    public ApiVersion resolve(final HttpServletRequest request) throws BaseDomainException {
        if (request == null) {
            return ApiVersion.defaultVersion();
        }
        final String accept = request.getHeader("Accept");
        if (accept != null) {
            final Matcher m = ACCEPT_VERSION.matcher(accept);
            if (m.find()) {
                final String requested = m.group(1);
                return ApiVersion.parse(requested).orElseThrow(() -> versionNotServed(requested));
            }
        }
        return ApiVersion.defaultVersion();   // one scheme per API: no ?version= fallback
    }

    /** Media-type versioning: the Accept header asks for a representation we do not serve — 406 Not Acceptable. */
    public BaseDomainException versionNotServed(final String version) {
        return ExceptionMessages.unsupportedApiVersion(Arrays.toString(ApiVersion.values()));
    }
}
```

### `MapperStrategy` (interface)

```java
public interface MapperStrategy<E, D> {
    @Nullable D map(@Nullable E entity);
    ApiVersion getSupportedVersion();
    Class<E> getEntityType();   // the registry is shared by every entity — this keeps User and other entities apart

    default boolean canHandle(final ApiVersion version) {
        return getSupportedVersion() != null
                && getSupportedVersion().equals(version);
    }
}
```

### `MapperRegistry`

One **non-generic** singleton for every entity. Spring injects every `MapperStrategy` (User, Order, …) and `find`
routes by the entity type and `canHandle(version)`. The constructor checks the declared (entity type, version) pairs
and fails at startup when two strategies claim the same pair. The generic type is restored in one place, `find(...)`,
where the entity-type match guarantees it.

```java
@Component
public class MapperRegistry {
    private record Key(Class<?> entityType, ApiVersion version) { }

    private final List<MapperStrategy<?, ?>> strategies;

    public MapperRegistry(final List<MapperStrategy<?, ?>> strategies) {
        final Map<Key, MapperStrategy<?, ?>> declared = new HashMap<>();
        for (final MapperStrategy<?, ?> strategy : strategies) {
            final MapperStrategy<?, ?> first =
                    declared.putIfAbsent(new Key(strategy.getEntityType(), strategy.getSupportedVersion()), strategy);
            if (first != null) {
                throw new IllegalStateException("Two mapper strategies for " + strategy.getEntityType().getSimpleName()
                        + "/" + strategy.getSupportedVersion() + ": " + first.getClass().getName()
                        + ", " + strategy.getClass().getName());
            }
        }
        this.strategies = List.copyOf(strategies);
    }

    @SuppressWarnings("unchecked")   // safe: the strategy's own getEntityType() equals entityType
    public <E> @Nullable MapperStrategy<E, ?> find(final Class<E> entityType, final ApiVersion version) {
        return (MapperStrategy<E, ?>) strategies.stream()
                .filter(s -> s.getEntityType().equals(entityType) && s.canHandle(version))
                .findFirst()
                .orElse(null);
    }
}
```

### `MapperHandler`

A version the client asked for but this entity does not serve is rejected by the resolver's scheme (404 for a URI
version, 406 for an `Accept` version) — never silently answered with another schema:

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class MapperHandler {
    private final MapperContextResolver resolver;
    private final MapperRegistry registry;

    /**
     * @param entityType passed explicitly — entity.getClass() can be a JPA proxy subclass
     * @param entity     not null in practice: the service already threw NotFoundException (404) for a missing resource
     */
    public <E> @Nullable Object handle(final Class<E> entityType, final E entity, final HttpServletRequest request)
            throws BaseDomainException {
        final ApiVersion version = resolver.resolve(request);   // unknown version → 404 (URI) / 406 (Accept)
        final MapperStrategy<E, ?> strategy = registry.find(entityType, version);
        if (strategy == null) {
            throw resolver.versionNotServed(version.name().toLowerCase(Locale.ROOT));   // never a silent fallback to latest()
        }
        return strategy.map(entity);
    }
}
```

### Concrete Strategies

One `@Component` per (entity, version): V1 legacy schema, V2 split name + email, V3 structured contact block — load
[`references/concrete-strategies.md`](./references/concrete-strategies.md) for the three implementations.

## 4. Controller Integration

```java
@RestController
@RequestMapping("/api/{apiVersion:v\\d+}/users")   // URI versioning (api-design §3, guild rule 15); the resolver reads the segment
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class UserController {
    private final UserService userService;
    private final MapperHandler mapperHandler;

    @GetMapping("/{id}")
    @ApiResponse(responseCode = "200", content = @Content(schema = @Schema(oneOf = {
            UserV1DTO.class, UserV2DTO.class, UserV3DTO.class })))
    public ResponseEntity<Object> getUser(@PathVariable final String id,
                                          final HttpServletRequest request) throws BaseDomainException {
        final User user = userService.getById(id);
        final Object dto = mapperHandler.handle(User.class, user, request);
        return ResponseEntity.ok(dto);
    }
}
```

DTOs are immutable records, e.g. `public record UserV1DTO(String id, String name) { }`. Every strategy's `map` starts
with `if (user == null) return null;` and is declared `@Nullable D map(@Nullable E entity)`, so the guard passes the
NullAway gate (`static-analysis`); in practice the service throws `NotFoundException` first and the handler never
passes `null`.

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
5. ✅ Implement `getSupportedVersion()`, `getEntityType()` and `map(entity)` (it inherits `canHandle`)
6. ✅ Write unit tests for the new strategy, including the null-entity guard
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
**Last Reviewed:** 2026-11-15
