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
void map_nullEntity_returnsNull() {
    assertThat(new V1UserMapperStrategy().map(null)).isNull();
    assertThat(new V2UserMapperStrategy().map(null)).isNull();
    assertThat(new V3UserMapperStrategy().map(null)).isNull();
}

@Test
void canHandle_onlyTheDeclaredVersion() {
    assertThat(new V2UserMapperStrategy().canHandle(ApiVersion.V2)).isTrue();
    assertThat(new V2UserMapperStrategy().canHandle(ApiVersion.V1)).isFalse();
    assertThat(new V2UserMapperStrategy().canHandle(null)).isFalse();
}

@Test
void registry_noStrategyForTheEntity_returnsNull() {
    assertThat(new MapperRegistry(List.of(new V1UserMapperStrategy())).find(Order.class, ApiVersion.V1)).isNull();
}

@Test
void handle_v2Path_returnsV2Dto() throws Exception {
    final var request = new MockHttpServletRequest("GET", "/api/v2/users/u-1");

    final Object dto = mapperHandler.handle(User.class, sampleUser, request);

    assertThat(dto).isInstanceOf(UserV2DTO.class);
}

@Test
void handle_knownVersionWithoutStrategy_isNotFound() {
    final var request = new MockHttpServletRequest("GET", "/api/v3/users/u-1");   // V3 exists, but not for User here
    assertThatThrownBy(() -> mapperHandler.handle(User.class, sampleUser, request))
            .isInstanceOf(NotFoundException.class);                                // URI versioning: 404
}

@Test
void handle_unknownPathVersion_isNotFound() {
    final var request = new MockHttpServletRequest("GET", "/api/v9/users/u-1");
    assertThatThrownBy(() -> mapperHandler.handle(User.class, sampleUser, request))
            .isInstanceOf(NotFoundException.class);
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
void handle_v1AcceptHeader_returnsV1Dto() throws Exception {
    final var request = new MockHttpServletRequest();
    request.addHeader("Accept", "application/vnd.example.v1+json");

    final Object dto = mapperHandler.handle(User.class, sampleUser, request);

    assertThat(dto).isInstanceOf(UserV1DTO.class);
}

@Test
void handle_noVersion_returnsDefaultVersion() throws Exception {
    final var request = new MockHttpServletRequest();   // no version hints
    final Object dto = mapperHandler.handle(User.class, sampleUser, request);
    assertThat(dto).isInstanceOf(UserV1DTO.class);       // defaultVersion(), never silently latest()
}

@Test
void handle_unknownVersion_isNotAcceptable() {
    final var request = new MockHttpServletRequest();
    request.addHeader("Accept", "application/vnd.example.v9+json");
    assertThatThrownBy(() -> mapperHandler.handle(User.class, sampleUser, request))
            .isInstanceOf(UnsupportedApiVersionException.class);                   // media-type versioning: 406
}

@Test
void handle_versionQueryParam_isIgnored() throws Exception {
    final var request = new MockHttpServletRequest();
    request.setParameter("version", "v2");                                          // one scheme per API
    assertThat(mapperHandler.handle(User.class, sampleUser, request)).isInstanceOf(UserV1DTO.class);
}
```

See strategy-registry-pattern and unit-tests for the full testing contract.
