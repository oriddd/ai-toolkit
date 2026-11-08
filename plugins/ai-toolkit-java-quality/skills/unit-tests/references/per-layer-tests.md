# Unit Tests Skill — Test every LEGO brick — positive and negative paths

Part of the [`unit-tests`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## Test Every LEGO Brick — Positive & Negative Paths

Every method should have tests covering both the **positive (happy)** path
and the **negative (error)** paths. This is the foundation of meaningful
coverage.

### Positive Tests (Happy Path)
Verify the **intended behavior** when inputs are valid and conditions are met:

```java
// Positive test: caller allowed → the selected strategy verified the resource
@Test
void handle_allowedCaller_delegatesToSelectedStrategy() {
    // given
    when(callerContextResolver.resolve()).thenReturn(CallerContext.USER);
    when(permissionsRegistry.getStrategy(CallerContext.USER)).thenReturn(Optional.of(userStrategy));

    // when
    handler.handle("invoice-42");

    // then
    verify(userStrategy).verifyPermissions("invoice-42");
}

// Positive test: valid data → expected transformation
@Test
void render_validPdf_returnsHtmlContent() {
    // given
    byte[] pdfBytes = loadTestPdf();

    // when
    byte[] result = renderer.render(pdfBytes, "HTML");

    // then
    assertThat(result).isNotEmpty();
    assertThat(new String(result, StandardCharsets.UTF_8)).contains("<html>");
}
```

**Naming convention:** `methodName_condition_expectedResult()` (see the
`unit-tests` SKILL), e.g.:
- `methodName_validInput_producesExpectedResult()`
- `methodName_conditionIsTrue_doesNotThrowException()`
- `methodName_multipleValidItems_processesAll()`

### Negative Tests (Error Conditions)
Verify that **error cases are handled correctly** — exceptions thrown,
validation failures returned, fallback logic invoked. Domain exceptions are
the unchecked hierarchy from `exception-handling` (here `ForbiddenException`,
built by `ExceptionMessages`):

```java
// Negative test: no strategy for the caller context → 403 exception
@Test
void handle_unrecognizedCallerContext_throwsForbiddenException() {
    // given
    when(callerContextResolver.resolve()).thenReturn(CallerContext.EXTERNAL_SYSTEM);
    when(permissionsRegistry.getStrategy(CallerContext.EXTERNAL_SYSTEM)).thenReturn(Optional.empty());

    // when / then
    assertThatThrownBy(() -> handler.handle("invoice-42"))
        .isInstanceOf(ForbiddenException.class)
        .hasMessageContaining("Unrecognized caller context");

    verifyNoInteractions(userStrategy);  // short-circuit check
}

// Negative test: null input → exception
@Test
void render_nullInput_throwsIllegalArgumentException() {
    assertThatThrownBy(() -> renderer.render(null, "HTML"))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("Input cannot be null");
}

// Negative test: invalid state (misconfiguration) → exception
@Test
void handle_noStrategiesConfigured_throwsForbiddenException() {
    // given: a real registry built from an empty strategy list
    when(callerContextResolver.resolve()).thenReturn(CallerContext.USER);
    PermissionsHandler emptyHandler =
        new PermissionsHandler(callerContextResolver, new PermissionsRegistry(Collections.emptyList()));

    // when / then
    assertThatThrownBy(() -> emptyHandler.handle("invoice-42"))
        .isInstanceOf(ForbiddenException.class);
}
```

**Naming convention:** Make the error condition explicit:
- `methodName_nullInput_throwsException()`
- `methodName_invalidState_throwsException()`
- `methodName_authorizationFails_throwsForbiddenException()`

### Negative Tests — Strategy Pattern Example

When testing a **Strategy + Handler** pattern (see `code-structure` and the
`permissions` skill), cover:
- **No caller context resolved**
- **No matching strategy found**
- **Strategy found but verification fails**
- **Empty strategy list** (handler misconfiguration)

```java
import {{basePackage}}.exception.ForbiddenException;
import {{basePackage}}.exception.constants.ExceptionMessages;

@ExtendWith(MockitoExtension.class)
class PermissionsHandlerTest {
    @Mock private CallerContextResolver callerContextResolver;
    @Mock private PermissionsRegistry permissionsRegistry;
    @Mock private PermissionsCheckStrategy userStrategy;

    @InjectMocks private PermissionsHandler handler;

    // Positive: the strategy selected for the caller context is the one that runs
    @Test
    void handle_allowedCaller_delegatesToSelectedStrategy() {
        when(callerContextResolver.resolve()).thenReturn(CallerContext.USER);
        when(permissionsRegistry.getStrategy(CallerContext.USER)).thenReturn(Optional.of(userStrategy));

        handler.handle("invoice-42");

        verify(userStrategy).verifyPermissions("invoice-42");
    }

    // Negative: no caller context
    @Test
    void handle_noCallerContext_throwsForbiddenException() {
        when(callerContextResolver.resolve()).thenReturn(null);

        assertThatThrownBy(() -> handler.handle("invoice-42"))
            .isInstanceOf(ForbiddenException.class);
        verifyNoInteractions(permissionsRegistry);
    }

    // Negative: no match
    @Test
    void handle_unrecognizedCallerContext_throwsForbiddenException() {
        when(callerContextResolver.resolve()).thenReturn(CallerContext.EXTERNAL_SYSTEM);
        when(permissionsRegistry.getStrategy(CallerContext.EXTERNAL_SYSTEM)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> handler.handle("invoice-42"))
            .isInstanceOf(ForbiddenException.class);
        verifyNoInteractions(userStrategy);
    }

    // Negative: strategy fails verification — its exception propagates unchanged
    @Test
    void handle_strategyDeniesAccess_propagatesForbiddenException() {
        when(callerContextResolver.resolve()).thenReturn(CallerContext.USER);
        when(permissionsRegistry.getStrategy(CallerContext.USER)).thenReturn(Optional.of(userStrategy));
        ForbiddenException denied = ExceptionMessages.accessDenied("invoice-42");
        doThrow(denied).when(userStrategy).verifyPermissions("invoice-42");

        assertThatThrownBy(() -> handler.handle("invoice-42")).isSameAs(denied);
    }

    // Negative: configuration error — no strategies registered
    @Test
    void handle_noStrategiesConfigured_throwsForbiddenException() {
        when(callerContextResolver.resolve()).thenReturn(CallerContext.USER);
        PermissionsHandler emptyHandler =
            new PermissionsHandler(callerContextResolver, new PermissionsRegistry(Collections.emptyList()));

        assertThatThrownBy(() -> emptyHandler.handle("invoice-42"))
            .isInstanceOf(ForbiddenException.class)
            .hasMessageContaining("Unrecognized caller context");
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
