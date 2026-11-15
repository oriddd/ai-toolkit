# Component Tests Skill — response-body assertions

Part of the [`component-tests`](../SKILL.md) skill.

## Response-body assertions — JsonPath

For JSON responses, prefer JsonPath assertions over deserializing the body
into a DTO that mirrors the contract (which double-counts the test):

```java
mvc.perform(get("/api/v1/foo/123"))
   .andExpect(status().isOk())
   .andExpect(jsonPath("$.id").value("123"))
   .andExpect(jsonPath("$.items.length()").value(3))
   .andExpect(jsonPath("$.items[*].status", everyItem(equalTo("READY"))));
```

For `TestRestTemplate` (no `MockMvc`), request the body as a `String`
(`restTemplate.exchange(url, GET, HttpEntity.EMPTY, String.class)`) and
assert with AssertJ + JsonPath (`com.jayway.jsonpath`, in `spring-boot-starter-test`):

```java
assertThat(response.getBody()).isNotNull();
DocumentContext json = JsonPath.parse(response.getBody());
assertThat(json.<String>read("$.id")).isEqualTo("123");
```

## Snapshot / golden-file pattern

When the response is a large stable JSON / XML document (e.g. an export
endpoint), assert against a **golden file** in
`src/test/resources/__snapshots__/` rather than inlining the expected text:

```java
String actual   = response.getBody();
String expected = TestsResourcesHolder.getInstance().readString("__snapshots__/foo-export-happy.json");
JSONAssert.assertEquals(expected, actual, JSONCompareMode.LENIENT);
```

`readString` is a small helper on the `TestsResourcesHolder` from the Layout
(read the classpath resource as UTF-8). There is no built-in update switch:
update a snapshot intentionally by overwriting the file with the new
response, then review the diff in the PR. Snapshots make contract drift visible.
