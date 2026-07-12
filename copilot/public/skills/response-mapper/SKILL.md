---
name: response-mapper
description: Wire API versioning and response projection mapping into a Spring Boot REST API using the Strategy + Handler + Registry pattern. A MapperHandler resolves the target version/projection from the request (Accept header, URI, query param), routes to the appropriate MapperStrategy via a registry, and returns a tailored DTO. Add new versions or projections by adding one new MapperStrategy — the handler and registry never change. Apply when APIs must support multiple versions or different response projections for the same entity.
tier: should
applies_to: [rest, monolith]
depends_on: [code-structure, spring-boot-conventions, strategy-registry-pattern]
ships_templates: false
hitl: false
version: 1.1
last_reviewed: 2026-07-12
---

# Response Mapper Skill (public)

> **Pattern Foundation:** This skill is a concrete application of the [strategy-registry-pattern](../strategy-registry-pattern/SKILL.md) skill.
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

See [strategy-registry-pattern](../strategy-registry-pattern/SKILL.md) for detailed component responsibilities.

**Mapper-specific mapping:**
- **Discriminator:** `ApiVersion` enum (V1 / V2 / V3), or a `Projection` enum
- **Resolver:** Reads the target version from the `Accept` header, URI segment, or `?version=` query param
- **Strategy:** Maps entity → version-specific DTO
- **Handler:** Orchestrates resolver → registry → strategy, returns the DTO

## 3. Implementation

### `ApiVersion` (enum)

```java
public enum ApiVersion {
    V1, V2, V3;

    public static ApiVersion fromString(final String version) {
        if (StringUtils.isBlank(version)) {
            return latest();   // unversioned requests get the newest schema
        }
        try {
            return ApiVersion.valueOf(version.toUpperCase());
        } catch (final IllegalArgumentException e) {
            return latest();   // unknown version → newest, never fail hard here
        }
    }

    public static ApiVersion latest() {
        return V3;
    }
}
```

### `MapperContextResolver`

```java
@Component
public class MapperContextResolver {

    // e.g. Accept: application/vnd.api.v2+json
    private static final Pattern ACCEPT_VERSION =
            Pattern.compile("application/vnd\\.api\\.(v\\d+)\\+json", Pattern.CASE_INSENSITIVE);

    public ApiVersion resolve(final HttpServletRequest request) {
        if (request == null) {
            return ApiVersion.latest();
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

    default boolean canHandle(final ApiVersion version) {
        return getSupportedVersion() != null
                && getSupportedVersion().equals(version);
    }
}
```

### `MapperRegistry`

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class MapperRegistry<E, D> {
    private final List<MapperStrategy<E, D>> strategies;

    public MapperStrategy<E, D> getStrategy(final ApiVersion version) {
        return strategies.stream()
                .filter(s -> s.canHandle(version))
                .findFirst()
                .orElse(null);
    }
}
```

### `MapperHandler`

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
@Slf4j
public class MapperHandler<E, D> {
    private final MapperContextResolver resolver;
    private final MapperRegistry<E, D> registry;

    public D handle(final E entity, final HttpServletRequest request) {
        final ApiVersion version = resolver.resolve(request);
        final MapperStrategy<E, D> strategy = registry.getStrategy(version);

        if (strategy == null) {
            log.warn("No mapper strategy for version {}, falling back to latest", version);
            final MapperStrategy<E, D> fallback = registry.getStrategy(ApiVersion.latest());
            if (fallback == null) {
                throw new IllegalStateException("No mapper strategy for latest version (mandatory)");
            }
            return fallback.map(entity);
        }
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
    public UserV1DTO map(final User user) {
        if (user == null) return null;
        return UserV1DTO.builder()
                .id(user.getId())
                .name(user.getFullName())     // V1 flattened name
                .build();
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
    public UserV2DTO map(final User user) {
        if (user == null) return null;
        return UserV2DTO.builder()
                .id(user.getId())
                .firstName(user.getFirstName())
                .lastName(user.getLastName())
                .email(user.getEmail())
                .build();
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
    public UserV3DTO map(final User user) {
        if (user == null) return null;
        return UserV3DTO.builder()
                .id(user.getId())
                .firstName(user.getFirstName())
                .lastName(user.getLastName())
                .contact(new ContactDTO(user.getEmail(), user.getPhone()))
                .build();
    }
}
```

## 4. Controller Integration

```java
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class UserController {
    private final UserService userService;
    private final MapperHandler<User, ?> mapperHandler;

    @GetMapping("/{id}")
    public ResponseEntity<?> getUser(@PathVariable final String id,
                                     final HttpServletRequest request) {
        final User user = userService.getById(id);
        final Object dto = mapperHandler.handle(user, request);
        return ResponseEntity.ok(dto);
    }
}
```

**Rules:**
- Wildcard `?` for DTO type — handler returns the version-specific DTO
- Pass `HttpServletRequest` to the handler for version resolution
- Service returns the **entity**; mapping is a presentation-layer concern
- Keep the version discriminator out of the service and domain layers

## 5. Adding a New Version

**Checklist:**
1. ✅ Add the new `ApiVersion` enum value (e.g. `V4`) and update `latest()` if it becomes newest
2. ✅ Create the new DTO class (e.g. `UserV4DTO`)
3. ✅ Create `V4UserMapperStrategy implements MapperStrategy`
4. ✅ Annotate it `@Component`
5. ✅ Implement `getSupportedVersion()` and `map(entity)`
6. ✅ Write unit tests for the new strategy
7. ✅ Update OpenAPI docs and the deprecation policy for the retired version

**Zero changes needed:**
- ❌ MapperHandler, MapperRegistry, MapperContextResolver, existing strategies

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

### Version from URI segment
Resolve the version from `/api/v2/users` instead of the `Accept` header:
```java
@Component
public class MapperContextResolver {
    private static final Pattern URI_VERSION = Pattern.compile("/api/(v\\d+)/");

    public ApiVersion resolve(final HttpServletRequest request) {
        final Matcher m = URI_VERSION.matcher(request.getRequestURI());
        return m.find() ? ApiVersion.fromString(m.group(1)) : ApiVersion.latest();
    }
}
```

### Projection instead of version
Swap the `ApiVersion` discriminator for a `Projection` enum (`SUMMARY` / `DETAILED` / `FULL`) resolved from `?projection=`. This overlaps with [response-layout](../response-layout/SKILL.md) — prefer `response-layout` when the choice is purely a field-set concern, and `response-mapper` when whole schemas evolve across versions.

## 8. Testing

Test each strategy in isolation (pure mapping, no Spring context) and the handler with a fake registry:
```java
@Test
void handle_v1AcceptHeader_returnsV1Dto() {
    final var request = new MockHttpServletRequest();
    request.addHeader("Accept", "application/vnd.api.v1+json");

    final Object dto = mapperHandler.handle(sampleUser, request);

    assertThat(dto).isInstanceOf(UserV1DTO.class);
}

@Test
void handle_unknownVersion_fallsBackToLatest() {
    final var request = new MockHttpServletRequest();   // no version hints
    final Object dto = mapperHandler.handle(sampleUser, request);
    assertThat(dto).isInstanceOf(UserV3DTO.class);       // latest()
}
```

See [strategy-registry-pattern](../strategy-registry-pattern/SKILL.md) and [unit-tests](../unit-tests/SKILL.md) for the full testing contract.

---

**Version:** 1.1  
**Last Reviewed:** 2026-07-12
