"""Behaviour cases: plugin -> skill -> (prompt, [(grader name, regex the answer must match)])."""

BEHAVIOUR = {
    "ai-toolkit-java-build": {
        "exception-handling": (
            "In my Spring Boot 3 service, OrderService.getOrder(id) should fail when the order does not exist, and the API "
            "must answer 404. Show me, in your reply, the Java code for the exception and how it becomes the HTTP response. "
            "Do not create files.",
            [("problem-detail", r"ProblemDetail"), ("controller-advice", r"@RestControllerAdvice"),
             ("message-catalogue", r"ExceptionMessages"), ("message-format", r"MessageFormat"),
             ("typed-hierarchy", r"extends\s+(Base\w*Exception|NotFound\w*Exception|\w*DomainException)")]),
        "external-client": (
            "My Spring Boot 3 service must call the Inventory REST API: GET /items/{id} returns an item, and a 404 means "
            "the item does not exist. Show me, in your reply, the Java package and classes you would write for this "
            "integration (class names and their code). Do not create files.",
            [("client-config", r"InventoryClientConfig"), ("typed-properties", r"InventoryProperties"),
             ("injected-builder", r"RestClient\.Builder\s+\w+"), ("builder-clone", r"\.clone\(\)"),
             ("transport-not-by-type", r"@Qualifier\(|new\s+Inventory\w*Client\(\s*\w*[rR]est[cC]lient\b"), ("non-2xx-mapped", r"onStatus|exchange\(")]),
    },
    "ai-toolkit-java-design": {
        "spring-boot-conventions": (
            "My Spring Boot 3 service reads payment.base-url, payment.timeout and payment.retries with @Value in three "
            "different classes. Show me, in your reply, the Java code you would replace that with. Do not create files.",
            [("configuration-properties", r"@ConfigurationProperties"), ("record", r"record\s+\w*Properties"),
             ("validated", r"@Validated"), ("registered", r"@ConfigurationPropertiesScan|@EnableConfigurationProperties"),
             ("duration-type", r"Duration\s+\w*[tT]imeout"), ("keys-in-constants", r"ConfigurationConstants")]),
    },
    "ai-toolkit-java-quality": {
        "unit-tests": (
            "Write JUnit 5 unit tests, in your reply, for this Spring Boot class. Do not create files.\n\n"
            "```java\n@Service\n@RequiredArgsConstructor\npublic class DiscountCalculator {\n"
            "    private final CustomerTierClient tierClient;\n\n"
            "    public BigDecimal discountFor(String customerId, BigDecimal amount) {\n"
            "        if (amount.signum() < 0) throw new IllegalArgumentException(\"amount must not be negative\");\n"
            "        Tier tier = tierClient.tierOf(customerId);\n"
            "        return switch (tier) {\n"
            "            case GOLD -> amount.multiply(new BigDecimal(\"0.10\"));\n"
            "            case SILVER -> amount.multiply(new BigDecimal(\"0.05\"));\n"
            "            case NONE -> BigDecimal.ZERO;\n"
            "        };\n    }\n}\n```",
            [("naming", r"void\s+[a-z]\w*_[a-zA-Z]\w*_[a-zA-Z]\w*\s*\("), ("assertj", r"assertThat\("),
             ("assertj-throws", r"assertThatThrownBy|assertThatIllegalArgumentException"),
             ("mockito-extension", r"@ExtendWith\(MockitoExtension\.class\)"),
             ("every-tier", r"(?=[\s\S]*GOLD)(?=[\s\S]*SILVER)(?=[\s\S]*NONE)")]),
    },
    "ai-toolkit-workflow": {
        "git-commit-conventions": (
            "Write the git commit message for this change and show it in your reply (do not run git): I renamed "
            "UserService.getUser to fetchUser because it now calls the remote profile API, and updated the three call sites.",
            [("conventional-type", r"\b(refactor|feat)(\([\w-]+\))?!?: [a-z]"),
             ("imperative-subject", r"(refactor|feat)(\([\w-]+\))?!?: (rename|fetch|use|call|switch)"),
             ("body-explains-why", r"(because|remote|profile API|so that|now calls)")]),
    },
}

TAIL = " Show the code in your reply. Do not create files."

MORE = {
    "ai-toolkit-java-build": {
        "input-validation": (
            "In my Spring Boot 3 API, CreateOrderRequest has orderDate, deliveryDate and sku. deliveryDate must be after "
            "orderDate, and sku must be a code the injected SkuCatalogue bean recognises. Add these validation rules." + TAIL,
            [("constraint-validator", r"ConstraintValidator<"), ("custom-message-safe", r"disableDefaultConstraintViolation|^(?![\s\S]*buildConstraintViolationWithTemplate)"),
             ("rule-bean", r"class\s+\w+Rule\b"), ("cross-field-validator", r"@InitBinder|implements\s+(org\.springframework\.validation\.)?Validator\b"),
             ("constraint-annotation", r"@Constraint\(")]),
        "persistence": (
            "Add persistence for an Invoice (number, customerId, amount, status) to my Spring Boot 3 service: the JPA "
            "entity, the Spring Data repository with a query listing a customer's invoices, and the database migration." + TAIL,
            [("optimistic-lock", r"@Version"), ("paged-query", r"Pageable|Page<|Slice<"),
             ("flyway", r"V0*\d+__\w+\.sql"), ("auditing", r"@CreatedDate|@LastModifiedDate|AuditingEntityListener"),
             ("entity", r"@Entity")]),
        "messaging": (
            "When an order is created in my Spring Boot 3 order service, publish an OrderPlaced event to Kafka; the "
            "shipping service consumes it. Make sure no event is lost if the database commit succeeds, and that "
            "redelivered events are not processed twice." + TAIL,
            [("outbox", r"[Oo]utbox"), ("event-record", r"record\s+OrderPlaced"),
             ("idempotent-consumer", r"[Pp]rocessed_?[Ee]vents?|ProcessedEvent|existsBy\w*EventId|eventId"),
             ("dead-letter", r"DeadLetterPublishingRecoverer|\.DLT|-dlt|dead-letter"), ("transactional", r"@Transactional")]),
        "permissions": (
            "In my Spring Boot 3 API, a document may be deleted only by its owner (an end user) or by an admin service "
            "account; any other caller gets 403. Implement this authorization." + TAIL,
            [("handler", r"PermissionsHandler"), ("strategy", r"PermissionsCheckStrategy"),
             ("caller-context", r"CallerContext"), ("domain-forbidden", r"ForbiddenException"),
             ("one-strategy-per-caller", r"@Component[\s\S]*implements\s+\w*PermissionsCheckStrategy")]),
        "resilience-patterns": (
            "My Spring Boot 3 service calls the pricing service synchronously; when pricing is slow our threads pile up "
            "and the whole service stalls. Protect this call." + TAIL,
            [("circuit-breaker", r"@CircuitBreaker|CircuitBreaker"), ("bulkhead", r"@Bulkhead|Bulkhead"),
             ("timeout", r"@TimeLimiter|timeout-duration|[Tt]imeout"), ("fallback", r"fallbackMethod")]),
    },
    "ai-toolkit-java-design": {
        "api-design": (
            "Design the REST API for invoices in our Spring Boot service: list a customer's invoices, get one invoice, "
            "and export an invoice as PDF. Give the endpoints with methods, status codes and an example error body.",
            [("versioned-uri", r"/api/v1/"), ("export-sub-resource", r"/invoices/\{\w+\}/exports"),
             ("paginated", r"page=|size=|cursor"), ("problem-detail", r"ProblemDetail|problem\+json")]),
        "strategy-registry-pattern": (
            "My Spring Boot 3 PaymentService has a growing if/else on paymentType (CARD, PAYPAL, BANK_TRANSFER) and a new "
            "type arrives every quarter. Restructure it so adding a type never touches the dispatching code." + TAIL,
            [("strategy-interface", r"interface\s+\w*Strategy"), ("registry", r"class\s+\w*Registry"),
             ("injected-list", r"List<\s*\w*Strategy\s*>"), ("keyed-lookup", r"Map<\s*PaymentType|EnumMap"),
             ("component-strategies", r"@Component[\s\S]*implements\s+\w*Strategy")]),
        "domain-modeling": (
            "Model the Order aggregate for our Spring Boot service: order lines, a total in Money, an OrderPlaced domain "
            "event when the order is placed, and a rule that a placed order cannot get new lines." + TAIL,
            [("id-value-object", r"record\s+OrderId"), ("money-value-object", r"record\s+Money"),
             ("domain-event", r"record\s+OrderPlaced"), ("event-registration", r"registerEvent|AbstractAggregateRoot|domainEvents"),
             ("invariant", r"throw\s+new\s+\w+Exception")]),
        "feature-flags": (
            "We want to ship a new invoice-pricing algorithm in our Spring Boot service switched off, then enable it for "
            "some tenants without redeploying, and remove the old algorithm later." + TAIL,
            [("toggle-port", r"FeatureTogglePort|interface\s+\w*Toggle\w*"), ("kebab-flag-name", r"enable-[a-z0-9-]+"), ("cleanup", r"[Rr]emov|[Dd]elet|zombie|[Cc]lean ?up|[Ee]xpir|[Rr]etire")]),
    },
    "ai-toolkit-java-ops": {
        "request-metrics": (
            "Add a Micrometer timer for POST /orders in my Spring Boot 3 service, tagged with the client id and the "
            "response status; more endpoints will get their own timers later." + TAIL,
            [("filter", r"OncePerRequestFilter"), ("recorder", r"MetricsRecorder"), ("tag-constants", r"MonitoringConstants"),
             ("skip-actuator", r"shouldNotFilter"), ("finally", r"finally\s*\{")]),
        "graceful-shutdown": (
            "During Kubernetes rolling updates our Spring Boot 3 pods drop in-flight requests and @Async tasks. Show the "
            "application and Kubernetes configuration that fixes it.",
            [("graceful", r"shutdown:\s*graceful|server\.shutdown=graceful"), ("phase-timeout", r"timeout-per-shutdown-phase"),
             ("grace-period", r"terminationGracePeriodSeconds"), ("pre-stop", r"preStop"),
             ("executor-drain", r"await-termination|setWaitForTasksToCompleteOnShutdown|awaitTermination")]),
    },
    "ai-toolkit-java-quality": {
        "component-tests": (
            "Write a component test for my Spring Boot 3 service: boot the whole application, call POST /orders over HTTP, "
            "and replace the downstream InventoryClient with a deterministic fake." + TAIL,
            [("shared-test-config", r"ComponentTestConfiguration"), ("random-port", r"@LocalServerPort|RANDOM_PORT"),
             ("url-format", r"MessageFormat"), ("http-client", r"TestRestTemplate|RestClient|WebTestClient"),
             ("test-profile", r"@ActiveProfiles")]),
        "integration-tests": (
            "Write an integration test for my Spring Boot 3 InvoiceRepository against a real PostgreSQL." + TAIL,
            [("tagged", r"@Tag\(\"integration\"\)"), ("it-suffix", r"class\s+\w+IT\b"),
             ("container", r"PostgreSQLContainer"), ("wiring", r"@ServiceConnection|@DynamicPropertySource")]),
    },
    "ai-toolkit-workflow": {
        "pr-description": (
            "Write the pull request description for my branch. It adds retry with exponential backoff to "
            "PaymentClient (max 3 attempts), makes the backoff configurable in application.yaml, and adds "
            "PaymentClientRetryTest. Show it in your reply; do not call any git host.",
            [("problem", r"## Problem"), ("solution", r"## Solution"), ("key-changes", r"## Key Changes"),
             ("testing", r"## Testing"), ("names-test", r"PaymentClientRetryTest")]),
        "release-versioning": (
            "Set up automated releases for our Spring Boot service's GitHub repository: semantic versions derived from "
            "the commits, a generated CHANGELOG, and the image tag equal to the version." + TAIL,
            [("release-tool", r"release-please|semantic-release"), ("conventional-commits", r"[Cc]onventional [Cc]ommits"),
             ("changelog", r"CHANGELOG"), ("tag-equals-version", r"v?\$\{\{?\s*[\w.]*version|tag[\s\S]{0,40}version")]),
    },
    "ai-toolkit-docs": {
        "documentation-and-adr": (
            "We decided to move our order events from RabbitMQ to Kafka. Write the Architecture Decision Record for the "
            "repository and say where the file goes. Show it in your reply; do not create files.",
            [("adr-path", r"docs/adr/\d{4}-[a-z0-9-]+\.md"), ("status", r"## Status|Status:"),
             ("context", r"## Context"), ("decision", r"## Decision"), ("consequences", r"## Consequences")]),
    },
}

for _plugin, _cases in MORE.items():
    BEHAVIOUR.setdefault(_plugin, {}).update(_cases)

TAIL_RN = " Show the code in your reply. Do not create files."

REACT_NATIVE = {
    "ai-toolkit-react-native-quality": {
        "react-native-unit-tests": (
            "Write Jest tests for the useOrders hook (TanStack Query) and the OrderCard component in our Expo SDK 58 "
            "React Native app, including the jest setup file and the test provider helper." + TAIL_RN,
            [("async-render", r"await\s+render(Hook)?\("), ("mutation-gc", r"mutations:\s*\{\s*gcTime:\s*Infinity"),
             ("msw-strict", r"onUnhandledRequest:\s*[\x22\x27]error[\x22\x27]"), ("role-queries", r"getByRole\("),
             ("test-renderer", r"test-renderer")]),
        "react-native-static-analysis": (
            "Set up ESLint, Prettier and a verify script for our Expo TypeScript React Native app that uses feature "
            "folders." + TAIL_RN,
            [("boundaries-v7", r"boundaries/dependencies"), ("eslint-10", r"\"eslint\":\s*\"\^10"),
             ("zero-warnings", r"--max-warnings[ =]0"), ("strict-type-checked", r"strictTypeChecked"),
             ("unused-directives", r"reportUnusedDisableDirectives")]),
        "react-native-e2e-tests": (
            "Write a Maestro end-to-end flow for the sign-up journey of our React Native app." + TAIL_RN,
            [("clean-state", r"clearState:\s*true"), ("stable-ids", r"id:\s*[\x22\x27]?signup-"),
             ("waits", r"extendedWaitUntil|assertVisible"), ("env-secrets", r"\$\{MAESTRO_"),
             ("subflows", r"runFlow")]),
    },
    "ai-toolkit-react-native-design": {
        "react-native-state-and-data": (
            "In our React Native app, add a hook that loads the user's orders and a mutation that cancels one, with "
            "offline support." + TAIL_RN,
            [("key-factory", r"orderKeys\.(lists|all|detail)"), ("client-factory", r"createQueryClient"),
             ("offline-first", r"networkMode:\s*[\x22\x27]offlineFirst"), ("parse-boundary", r"\.safeParse\("),
             ("optimistic", r"onMutate[\s\S]*onError[\s\S]*setQueryData")]),
        "react-native-code-structure": (
            "Add an Orders feature to our React Native TypeScript app: a list screen and navigation to an order detail "
            "screen." + TAIL_RN,
            [("feature-folder", r"features/orders/(screens|hooks|api|model)"), ("typed-screen", r"NativeStackScreenProps<"),
             ("global-param-list", r"namespace ReactNavigation"), ("a11y-role", r"accessibilityRole"),
             ("public-index", r"features/orders/index\.ts|from [\x22\x27]@/features/orders[\x22\x27]")]),
    },
    "ai-toolkit-react-native-build": {
        "react-native-error-handling": (
            "In our React Native app, map API failures to user-facing messages and add crash reporting for render "
            "errors." + TAIL_RN,
            [("message-catalogue", r"Record<ErrorCode,\s*string>"), ("http-mapping", r"mapHttpError"),
             ("retryable-flag", r"retryable"), ("reportable-filter", r"isReportable"),
             ("fallback", r"FallbackComponent")]),
        "react-native-input-validation": (
            "Build a sign-up form (email, password, confirm password) in our React Native app and show the server's "
            "422 field errors." + TAIL_RN,
            [("resolver", r"zodResolver"), ("cross-field", r"\.refine\("), ("zod4-email", r"z\.email\("),
             ("root-server-error", r"setError\(\s*[\x22\x27]root\.server"), ("wire-key-map", r"new Map<string")]),
        "react-native-security": (
            "In our React Native app, store the auth token securely and handle https://app.example.com/orders?orderId= "
            "deep links." + TAIL_RN,
            [("keychain-accessibility", r"WHEN_UNLOCKED_THIS_DEVICE_ONLY"), ("logout-clears-cache", r"queryClient\.clear\(\)"),
             ("uuid-param", r"z\.uuid\(\)"), ("host-check", r"hostname\s*!==|hostname\s*===")]),
    },
    "ai-toolkit-react-native-ops": {
        "react-native-observability": (
            "Add Sentry crash reporting and product analytics to our React Native app." + TAIL_RN,
            [("scrub-events", r"beforeSend:\s*scrubEvent"), ("scrub-breadcrumbs", r"beforeBreadcrumb"),
             ("wrap-root", r"Sentry\.wrap"), ("release-dist", r"dist:"),
             ("typed-events", r"type AnalyticsEvent\s*=")]),
        "react-native-ci": (
            "Create the GitHub Actions workflows for pull-request checks and EAS releases of our React Native app.",
            [("verify-script", r"npm run verify"), ("least-privilege", r"permissions:\s*\{?\s*contents:\s*read"),
             ("expo-action-v9", r"expo-github-action@v9"), ("npm-packager", r"packager:\s*npm"),
             ("protected-env", r"environment:\s*production")]),
    },
}

for _plugin, _cases in REACT_NATIVE.items():
    BEHAVIOUR.setdefault(_plugin, {}).update(_cases)

TAIL_PY = " Show the code in your reply. Do not create files."

PYTHON = {
    "ai-toolkit-python-build": {
        "python-external-client": (
            "My Python FastAPI service must call the Inventory API: GET /items/{item_id}; a 404 means the item does not "
            "exist." + TAIL_PY,
            [("timeout", r"httpx\.Timeout\("), ("retry", r"AsyncRetrying|tenacity"), ("quote-path", r"quote\("),
             ("respx", r"respx"), ("cause-kept", r"raise \w+Error\([^)]*\) from \w+"), ("closed-in-lifespan", r"aclose\(\)")]),
        "python-security": (
            "Protect POST /v1/orders in my Python FastAPI service with JWT bearer tokens from our Keycloak; only callers "
            "with scope orders:write may create, and customers may read only their own orders." + TAIL_PY,
            [("alg-allowlist", r"algorithms\s*=\s*\["), ("www-authenticate", r"WWW-Authenticate"),
             ("bearer-no-autoerror", r"HTTPBearer\(auto_error=False\)"), ("required-claims", r'"require"\s*:'),
             ("ownership-not-found", r"NotFoundError")]),
        "python-messaging": (
            "Publish an OrderPlaced event to Kafka when an order is created in my Python FastAPI/SQLAlchemy service, and "
            "consume it in the billing service." + TAIL_PY,
            [("outbox", r"[Oo]utbox"), ("skip-locked", r"skip_locked\s*=\s*True"),
             ("idempotent-claim", r"on_conflict_do_nothing"), ("manual-commit", r"enable_auto_commit\s*=\s*False"),
             ("idempotent-producer", r"enable_idempotence\s*=\s*True"), ("dlt", r"\.dlt|dead.?letter")]),
        "python-error-handling": (
            "In my Python FastAPI service OrderService.get(order_id) must fail when the order does not exist, and the "
            "API must answer 404." + TAIL_PY,
            [("problem-json", r"application/problem\+json"), ("catalogue", r"ErrorCodes?\b"),
             ("typed-hierarchy", r"class \w+NotFoundError\(NotFoundError\)"),
             ("single-handler", r"exception_handler\(DomainError\)"),
             ("framework-404", r"starlette\.exceptions import HTTPException")]),
        "python-input-validation": (
            "Validate a Python FastAPI booking request: a valid email, guests between 1 and 10, and check_out must be "
            "after check_in." + TAIL_PY,
            [("forbid-extra", r'extra\s*=\s*"forbid"'), ("custom-error", r"PydanticCustomError"),
             ("after-validator", r'model_validator\(mode="after"\)'), ("frozen", r"frozen\s*=\s*True"),
             ("reusable-type", r"Annotated\[")]),
        "python-persistence": (
            "Add an orders table to my Python FastAPI service with SQLAlchemy 2.0 async, a repository and an Alembic "
            "migration; concurrent updates must not overwrite each other." + TAIL_PY,
            [("version-col", r"version_id_col"), ("uow", r"UnitOfWork"), ("expire", r"expire_on_commit\s*=\s*False"),
             ("pkg-script-location", r"script_location\s*=\s*\w+:alembic")]),
    },
    "ai-toolkit-python-design": {
        "python-code-structure": (
            "Lay out a new Python 3.12 FastAPI orders service: folders, settings, and how services get their "
            "collaborators." + TAIL_PY,
            [("src-layout", r"src/\w+/"), ("settings", r"BaseSettings"), ("secret", r"SecretStr"),
             ("protocol", r"Protocol"), ("import-linter", r"import-linter|lint-imports|importlinter")]),
        "python-fastapi-conventions": (
            "Add a paginated GET /orders endpoint to my Python FastAPI service." + TAIL_PY,
            [("query-model", r"Annotated\[\w+,\s*Query\(\)\]"), ("bounded", r"le\s*=\s*\d+"), ("cursor", r"next_cursor"),
             ("depends-annotated", r"Annotated\[\w+,\s*Depends\(")]),
    },
    "ai-toolkit-python-quality": {
        "python-unit-tests": (
            "Write pytest unit tests, in your reply, for this Python class. Do not create files.\n\n"
            "```python\nclass TierClient(Protocol):\n    async def tier_of(self, customer_id: str) -> Tier: ...\n\n\n"
            "class DiscountCalculator:\n    def __init__(self, tiers: TierClient) -> None:\n        self._tiers = tiers\n\n"
            "    async def discount_for(self, customer_id: str, amount: Decimal) -> Decimal:\n"
            "        if amount < 0:\n            raise ValueError(\"amount must not be negative\")\n"
            "        tier = await self._tiers.tier_of(customer_id)\n"
            "        return amount * {Tier.GOLD: Decimal(\"0.10\"), Tier.SILVER: Decimal(\"0.05\")}.get(tier, Decimal(0))\n```",
            [("naming", r"def test_[a-z]\w*_[a-z][A-Za-z0-9]*_[a-z][A-Za-z0-9]*\("), ("fake", r"class Fake\w+"),
             ("parametrize", r"pytest\.mark\.parametrize"), ("typed", r"-> None:"), ("raises", r"pytest\.raises")]),
        "python-integration-tests": (
            "Integration-test my Python SqlOrderRepository (SQLAlchemy async) against a real PostgreSQL." + TAIL_PY,
            [("community-module", r"testcontainers\.(community\.)?postgres"), ("savepoint", r"create_savepoint|begin_nested"),
             ("alembic", r"command\.(upgrade|check)"), ("pinned-image", r"postgres:\d+"), ("docker-skip", r"pytest\.skip\(")]),
        "python-static-analysis": (
            "Configure ruff, mypy and architecture checks for my Python FastAPI project." + TAIL_PY,
            [("strict", r"strict\s*=\s*true"), ("layers", r'type\s*=\s*"layers"'), ("mypy-path", r"mypy_path"),
             ("ruff-check-hook", r"id:\s*ruff-check"), ("ann", r'"ANN"')]),
    },
    "ai-toolkit-python-ops": {
        "python-ci": (
            "Write the GitHub Actions workflow and the Dockerfile for my Python FastAPI service managed with uv.",
            [("locked", r"uv sync --locked"), ("non-editable", r"--no-editable"), ("non-root", r"USER \w+|useradd"),
             ("exit5", r"\$\? -eq 5"), ("migrations", r"alembic upgrade head")]),
        "python-observability": (
            "Add JSON logging with request IDs and Prometheus metrics to my Python FastAPI app." + TAIL_PY,
            [("contextvars", r"merge_contextvars"), ("request-id", r"[Xx]-[Rr]equest-[Ii][Dd]"),
             ("route-template", r'scope\.get\("route"\)|\.path_format|route\.path'),
             ("stdlib-bridge", r"ProcessorFormatter"), ("trace-join", r"trace_id")]),
    },
}

for _plugin, _cases in PYTHON.items():
    BEHAVIOUR.setdefault(_plugin, {}).update(_cases)
