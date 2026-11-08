# Response Mapper Skill — Testing

Part of the [`response-mapper`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 8. Testing

Test each strategy in isolation (pure mapping, no Spring context) and the handler with a hand-built registry —
plain constructors, no Spring context and no mocks:
```java
private final MapperHandler mapperHandler = new MapperHandler(
        new MapperContextResolver(),
        new MapperRegistry(List.of(new V1UserMapperStrategy(), new V2UserMapperStrategy())));   // no V3 for User
private final User sampleUser = UserFixtures.sampleUser();   // test-data builder for the User entity

@Test
void handle_v2Path_returnsV2Dto() {
    final var request = new MockHttpServletRequest("GET", "/api/v2/users/u-1");

    final Object dto = mapperHandler.handle(User.class, sampleUser, request);

    assertThat(dto).isInstanceOf(UserV2DTO.class);
}

@Test
void handle_knownVersionWithoutStrategy_isRejected() {
    final var request = new MockHttpServletRequest("GET", "/api/v3/users/u-1");   // V3 exists, but not for User here
    assertThatThrownBy(() -> mapperHandler.handle(User.class, sampleUser, request))
            .isInstanceOf(UnsupportedApiVersionException.class);
}

@Test
void registry_twoStrategiesForSameVersion_failsAtStartup() {
    assertThatThrownBy(() -> new MapperRegistry(List.of(new V1UserMapperStrategy(), new V1UserMapperStrategy())))
            .isInstanceOf(IllegalStateException.class);
}
```

With the media-type resolver variation (the handler is built with that `MapperContextResolver` instead):
```java
@Test
void handle_v1AcceptHeader_returnsV1Dto() {
    final var request = new MockHttpServletRequest();
    request.addHeader("Accept", "application/vnd.example.v1+json");

    final Object dto = mapperHandler.handle(User.class, sampleUser, request);

    assertThat(dto).isInstanceOf(UserV1DTO.class);
}

@Test
void handle_noVersion_returnsDefaultVersion() {
    final var request = new MockHttpServletRequest();   // no version hints
    final Object dto = mapperHandler.handle(User.class, sampleUser, request);
    assertThat(dto).isInstanceOf(UserV1DTO.class);       // defaultVersion(), never silently latest()
}

@Test
void handle_unknownVersion_isRejected() {
    final var request = new MockHttpServletRequest();
    request.addHeader("Accept", "application/vnd.example.v9+json");
    assertThatThrownBy(() -> mapperHandler.handle(User.class, sampleUser, request))
            .isInstanceOf(UnsupportedApiVersionException.class);
}
```

See strategy-registry-pattern and unit-tests for the full testing contract.
