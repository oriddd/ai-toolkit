# Unit Tests Skill — Test every LEGO brick — positive and negative paths

Part of the [`unit-tests`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## Test Every LEGO Brick — Positive & Negative Paths

Every method should have tests covering both the **positive (happy)** path
and the **negative (error)** paths. This is the foundation of meaningful
coverage.

### Positive Tests (Happy Path)
Verify the **intended behavior** when inputs are valid and conditions are met:

```java
// Positive test: valid permissions → no exception
@Test
void handleDoesNotThrowExceptionWhenPermissionsAreValid() {
    // given
    when(strategy.supports(request)).thenReturn(true);
    when(strategy.verify(request)).thenReturn(true);
    
    // when / then
    assertDoesNotThrow(() -> handler.handle(request));
    verify(strategy).verify(request);
}

// Positive test: valid data → expected transformation
@Test
void renderPdfToHtmlReturnsHtmlContent() {
    // given
    byte[] pdfBytes = loadTestPdf();
    
    // when
    byte[] result = renderer.render(pdfBytes, "HTML");
    
    // then
    assertThat(result).isNotEmpty();
    assertThat(new String(result)).contains("<html>");
}
```

**Naming convention:** Use descriptive names that clearly state the scenario:
- `methodName_validInput_producesExpectedResult()`
- `methodName_whenConditionIsTrue_doesNotThrowException()`
- `methodName_withMultipleValidItems_processesAll()`

### Negative Tests (Error Conditions)
Verify that **error cases are handled correctly** — exceptions thrown,
validation failures returned, fallback logic invoked:

```java
// Negative test: no matching strategy → exception
@Test
void handleThrowsExceptionWhenNoMatchingStrategyIsFound() {
    // given
    when(strategy.supports(request)).thenReturn(false);
    
    // when / then
    assertThatThrownBy(() -> handler.handle(request))
        .isInstanceOf(PermissionsDeniedException.class)
        .hasMessageContaining("No matching strategy");
    
    verify(strategy, never()).verify(request);  // short-circuit check
}

// Negative test: null input → exception
@Test
void renderThrowsExceptionWhenInputIsNull() {
    assertThatThrownBy(() -> renderer.render(null, "HTML"))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("Input cannot be null");
}

// Negative test: invalid state → exception
@Test
void handleThrowsExceptionWhenStrategyListIsEmpty() {
    // given
    PermissionsHandler emptyHandler = new PermissionsHandler(Collections.emptyList());
    
    // when / then
    assertThatThrownBy(() -> emptyHandler.handle(request))
        .isInstanceOf(IllegalStateException.class);
}
```

**Naming convention:** Make the error condition explicit:
- `methodName_nullInput_throwsException()`
- `methodName_invalidState_throwsException()`
- `methodName_whenAuthorizationFails_throwsPermissionsDeniedException()`

### Negative Tests — Strategy Pattern Example

When testing a **Strategy + Handler** pattern (see `code-structure`), cover:
- **No matching strategy found**
- **Strategy found but verification fails**
- **Empty strategy list** (handler misconfiguration)

```java
@ExtendWith(MockitoExtension.class)
class PermissionsHandlerTest {
    @Mock private PermissionsStrategy strategy1;
    @Mock private PermissionsStrategy strategy2;
    
    private PermissionsHandler handler;
    
    @BeforeEach
    void setUp() {
        handler = new PermissionsHandler(List.of(strategy1, strategy2));
    }
    
    // Positive
    @Test
    void handleDoesNotThrowExceptionWhenPermissionsAreValid() {
        when(strategy1.supports(any())).thenReturn(true);
        when(strategy1.verify(any())).thenReturn(true);
        
        assertDoesNotThrow(() -> handler.handle(mockRequest));
    }
    
    // Negative: no match
    @Test
    void handleThrowsExceptionWhenNoMatchingStrategyIsFound() {
        when(strategy1.supports(any())).thenReturn(false);
        when(strategy2.supports(any())).thenReturn(false);
        
        assertThatThrownBy(() -> handler.handle(mockRequest))
            .isInstanceOf(PermissionsDeniedException.class);
    }
    
    // Negative: strategy fails verification
    @Test
    void handleThrowsExceptionWhenStrategyFailsVerification() {
        when(strategy1.supports(any())).thenReturn(true);
        when(strategy1.verify(any())).thenReturn(false);
        
        assertThatThrownBy(() -> handler.handle(mockRequest))
            .isInstanceOf(PermissionsDeniedException.class);
    }
    
    // Negative: configuration error
    @Test
    void handleThrowsExceptionWhenStrategyListIsEmpty() {
        PermissionsHandler emptyHandler = new PermissionsHandler(Collections.emptyList());
        
        assertThatThrownBy(() -> emptyHandler.handle(mockRequest))
            .isInstanceOf(IllegalStateException.class)
            .hasMessageContaining("No strategies configured");
    }
}
```

### Positive & Negative Checklist

For every public method, ensure you have:

- [ ] **Positive:** At least one test for the happy path with valid inputs
- [ ] **Negative:** One test per declared exception type
- [ ] **Negative:** Tests for null/empty/invalid inputs (if applicable)
- [ ] **Negative:** Tests for boundary conditions (min/max values, empty collections)
- [ ] **Negative:** Tests for state violations (calling methods in wrong order)
- [ ] **Short-circuit:** Verify subsequent collaborators are not called when early failures occur (`verify(..., never())`)

### Real-World Example Structure

For a typical service class with multiple methods:

```java
@ExtendWith(MockitoExtension.class)
class InvoiceServiceTest {
    
    // ===== Positive Tests =====
    @Test
    void processInvoice_validInput_returnsProcessedInvoice() { }
    
    @Test
    void processInvoice_multipleInvoices_processesAllSuccessfully() { }
    
    // ===== Negative Tests =====
    @Test
    void processInvoice_nullInput_throwsIllegalArgumentException() { }
    
    @Test
    void processInvoice_emptyContent_throwsValidationException() { }
    
    @Test
    void processInvoice_unsupportedFormat_throwsUnsupportedFormatException() { }
    
    @Test
    void processInvoice_whenValidationFails_doesNotCallTransformer() { }
}
```

Group your tests with comments (`// ===== Positive Tests =====`) for clarity
when the test class grows large.
