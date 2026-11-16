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
            "different classes. Show me, in your reply, the Java code you would replace that with, and the pom.xml "
            "changes it needs (the pom already uses Lombok). Do not create files.",
            [("keys-in-constants", r"ConfigurationConstants"),
             ("constant-prefix", r"prefix\s*=\s*ConfigurationConstants\.\w+"),
             ("notnull-duration", r"@NotNull\s+Duration")]),
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
            [("naming", r"void\s+[a-z]\w*_[a-zA-Z]\w*_[a-zA-Z]\w*\s*\("),
             ("case-record", r"record\s+\w*Case\b")]),
    },
    "ai-toolkit-workflow": {
        "git-commit-conventions": (
            "Write the git commit message for this change and show it in your reply (do not run git): in our published "
            "Java client SDK I renamed the public method UserService.getUser to fetchUser, since it now calls the remote "
            "profile API, and updated the three call sites inside the SDK.",
            [("breaking-marker", r"\b(?:refactor|feat|fix)(?:\([\w-]+\))?!:"), ("breaking-footer", r"BREAKING CHANGE:"),
             ("migration-in-footer", r"BREAKING CHANGE:[^\n]*(?:fetchUser|getUser)"),
             ("subject-limits", r"(?:^|\n)(?:refactor|feat|fix)(?:\([\w-]+\))?!?: [^\n]{0,55}[A-Za-z0-9`)]\n")]),
    },
}

TAIL = " Show the code in your reply. Do not create files."

MORE = {
    "ai-toolkit-java-build": {
        "input-validation": (
            "In my Spring Boot 3 API, CreateOrderRequest has orderDate, deliveryDate and sku. deliveryDate must be after "
            "orderDate, and sku must be a code the injected SkuCatalogue bean recognises. Add these validation rules." + TAIL,
            [("scoped-initbinder", r"@InitBinder\(\s*\x22\w+\x22\s*\)"),
             ("validation-config", r"class\s+ValidationConfig"),
             ("reject-value", r"\.rejectValue\("),
             ("package-layout", r"validation(?:/|\.)(?:annotation|validator|rule|config)\b")]),
        "persistence": (
            "Add persistence for an Invoice (number, customerId, amount, status) to my Spring Boot 3 service: the JPA "
            "entity, the Spring Data repository with a query listing a customer's invoices, and the database migration." + TAIL,
            [("assigned-uuid-id", r"@GeneratedValue", "not_contains"),
             ("extends-base-entity", r"extends\s+BaseEntity"),
             ("flyway-three-digit", r"V0\d{2}__\w+\.sql"),]),
        "messaging": (
            "When an order is created in my Spring Boot 3 order service, publish an OrderPlaced event to Kafka; the "
            "shipping service consumes it. Make sure no event is lost if the database commit succeeds, and that "
            "redelivered events are not processed twice." + TAIL,
            [("occurred-at", r"occurredAt"), ("event-id-header", r"[\x22\x27]event-id[\x22\x27]"),
             ("string-payload", r"ConsumerRecord<String,\s*String>|value-deserializer:\s*\S*StringDeserializer"),
             ("single-relay", r"@SchedulerLock|ShedLock"), ("non-retryable", r"exclude\s*=\s*\{"),
             ("ack-after-commit", r"\.acknowledge\(\)")]),
        "permissions": (
            "In my Spring Boot 3 API, a document may be deleted only by its owner (an end user) or by an admin service "
            "account; any other caller gets 403. Implement this authorization." + TAIL,
            [("handler", r"PermissionsHandler"), ("strategy", r"PermissionsCheckStrategy"),
             ("caller-context", r"CallerContext"), ("domain-forbidden", r"ForbiddenException"),
             ("one-strategy-per-caller", r"@Component[\s\S]*implements\s+\w*PermissionsCheckStrategy")]),
        "resilience-patterns": (
            "My Spring Boot 3 service calls the pricing service synchronously; when pricing is slow our threads pile up "
            "and the whole service stalls. Protect this call." + TAIL,
            [("aop-starter", r"spring-boot-starter-aop|spring-boot-starter-aspectj"), ("bom", r"resilience4j-bom"),
             ("semaphore-no-wait", r"max-?[wW]ait-?[dD]uration:\s*0\b"),
             ("client-read-timeout", r"[rR]eadTimeout\(|read-timeout:|ReadTimeout\("),
             ("fallback-throws", r"(?:Throwable|Exception)\s+\w+\)\s*\{[^}]*?\bthrow\b"),
             ("no-sync-time-limiter", r"@TimeLimiter\s*\(", "not_contains")]),
    },
    "ai-toolkit-java-design": {
        "api-design": (
            "Design the REST API for invoices in our Spring Boot service: list a customer's invoices, get one invoice, "
            "and export an invoice as PDF. Give the endpoints with methods, status codes and an example error body.",
            [("export-sub-resource", r"/invoices/\{\w+\}/exports"),
             ("async-operation-location", r"Operation-Location"),
             ("idempotency-key", r"Idempotency-Key"),
             ("no-verb-export-url", r"(?:^|\n)\W*(?:GET|POST)\s+\S*/invoices/\{\w+\}/(?:export|pdf)\b(?!s)", "not_contains")]),
        "strategy-registry-pattern": (
            "My Spring Boot 3 PaymentService has a growing if/else on paymentType (CARD, PAYPAL, BANK_TRANSFER) and a new "
            "type arrives every quarter. Restructure it so adding a type never touches the dispatching code." + TAIL,
            [("strategy-interface", r"interface\s+\w*Strategy"), ("registry", r"class\s+\w*Registry"),
             ("injected-list", r"List<\s*\w*Strategy\s*>"), ("keyed-lookup", r"Map<\s*PaymentType|EnumMap"),
             ("component-strategies", r"@Component[\s\S]*implements\s+\w*Strategy")]),
        "domain-modeling": (
            "Model the Order aggregate for our Spring Boot service: order lines, a total in Money, an OrderPlaced domain "
            "event when the order is placed, and a rule that a placed order cannot get new lines." + TAIL,
            [("clock-injected", r"Instant\.now\(\s*clock\s*\)"),
             ("event-implements-domain-event", r"record\s+OrderPlaced\w*\([^)]*\)\s*implements\s+DomainEvent"),]),
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
            "During Kubernetes rolling updates our Spring Boot 3.5 pods drop in-flight HTTP requests and @Async tasks, and "
            "the Kafka listener in the same service sometimes stops mid-batch. The pod spec has "
            "terminationGracePeriodSeconds: 30. Show the application and Kubernetes configuration that fixes it, and a "
            "test that proves the shutdown behaviour.",
            [
             ("readiness-refusing", r"REFUSING_TRAFFIC"),
             ("no-thread-sleep", r"Thread\.sleep\(", "not_contains"),]),
    },
    "ai-toolkit-java-quality": {
        "component-tests": (
            "Write a component test for my Spring Boot 3 service: boot the whole application, call POST /orders over HTTP, "
            "and replace the downstream InventoryClient with a deterministic fake. The service stores orders through a "
            "Spring Data JPA OrderRepository on PostgreSQL, and the test must run without a database: show the test "
            "profile yaml as well." + TAIL,
            [("shared-test-config", r"ComponentTestConfiguration"), ("url-format", r"MessageFormat"),
             ("both-datasource-excludes", r"(?=[\s\S]*org\.springframework\.boot\.jdbc\.autoconfigure\.DataSourceAutoConfiguration)(?=[\s\S]*org\.springframework\.boot\.autoconfigure\.jdbc\.DataSourceAutoConfiguration)"),
             ("noop-transaction-manager", r"AbstractPlatformTransactionManager")]),
        "integration-tests": (
            "Write an integration test for my Spring Boot 3 InvoiceRepository against a real PostgreSQL." + TAIL,
            [("tagged", r"@Tag\(\x22integration\x22\)"),
             ("no-ddl-auto-create", r"ddl-auto\s*[=:]\s*(?:create|create-drop|update)\b", "not_contains")]),
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
            "the commits, a generated CHANGELOG, and the image tag and Helm chart appVersion equal to the version." + TAIL,
            [("manifest-config", r"release-please-config\.json|\.release-please-manifest\.json"),
             ("non-default-token", r"token:\s*[\x22\x27]?\$\{\{\s*secrets\.(?!GITHUB_TOKEN\b)\w+"),
             ("sha-pinned", r"uses:\s*[\w.-]+/[\w./-]+@[0-9a-f]{40}"), ("chart-via-bot", r"extra-files|--app-version"),
             ("commit-lint", r"commitlint")]),
    },
    "ai-toolkit-docs": {
        "documentation-and-adr": (
            "Our repository already has ADRs 0001 to 0004; ADR 0003 chose RabbitMQ for order events. We have now decided "
            "to move order events to Kafka. Write the Architecture Decision Record, say where the file goes, and say what "
            "changes in the existing ADRs. Show it in your reply; do not create files.",
            [("adr-path", r"docs/adr/0005-[a-z0-9-]+\.md"), ("title", r"#\s*ADR-0005\s+—"),
             ("status-bullet", r"\*\s*Status:\s*(?:PROPOSED|ACCEPTED)"), ("supersedes", r"SUPERSEDED by ADR-0005"),
             ("deciders", r"Deciders:")]),
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
            [
             ("env-secrets", r"\$\{MAESTRO_"),
             ("critical-tag", r"tags:\s*\[?\s*critical"),
             ("subflows-dir", r"\.maestro/subflows/"),]),
    },
    "ai-toolkit-react-native-design": {
        "react-native-state-and-data": (
            "In our React Native app, add a hook that loads the user's orders and a mutation that cancels one, with "
            "offline support." + TAIL_RN,
            [("key-factory", r"orderKeys\.(lists|all|detail)"), ("client-factory", r"createQueryClient"),
             ("offline-first", r"networkMode:\s*[\x22\x27]offlineFirst"), ("parse-boundary", r"\.safeParse\("),
             ("optimistic", r"onMutate[\s\S]*onError[\s\S]*setQueryData")]),
        "react-native-code-structure": (
            "Add an Orders feature to our Expo SDK 58 React Native TypeScript app (default template): a list screen and "
            "navigation to an order detail screen." + TAIL_RN,
            [("feature-folder", r"features/orders/(screens|hooks|api|model)"),
             ("thin-route", r"export \{\s*(?:default|\w+Screen as default)\s*\}\s*from|src/app/orders/\[id\]\.tsx"),
             ("parsed-route-params", r"useLocalSearchParams[\s\S]{0,300}?\.(?:safeParse|parse)\("), ("a11y-role", r"accessibilityRole"),
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
            "Create the GitHub Actions workflows for pull-request checks and EAS releases of our React Native app." + TAIL_RN,
            [("verify-script", r"npm run verify"), ("least-privilege", r"permissions:\s*\{?\s*contents:\s*read"),
             ("expo-action-pinned", r"expo-github-action@[0-9a-f]{40}"), ("npm-packager", r"packager:\s*npm"),
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
            [("jwks-outage-503", r"PyJWKClientConnectionError"),
             ("ownership-not-found", r"NotFoundError"),
             ("scope-dependency-class", r"class\s+RequireScope"),]),
        "python-messaging": (
            "Publish an OrderPlaced event to Kafka when an order is created in my Python FastAPI/SQLAlchemy service, and "
            "consume it in the billing service." + TAIL_PY,
            [("outbox", r"[Oo]utbox"), ("skip-locked", r"skip_locked\s*=\s*True"),
             ("idempotent-claim", r"on_conflict_do_nothing"), ("manual-commit", r"enable_auto_commit\s*=\s*False"),
             ("idempotent-producer", r"enable_idempotence\s*=\s*True"), ("dlt", r"\.dlt|dead.?letter"),
             ("single-relay", r"pg_try_advisory(?:_xact)?_lock")]),
        "python-error-handling": (
            "In my Python FastAPI service OrderService.get(order_id) must fail when the order does not exist, and the "
            "API must answer 404." + TAIL_PY,
            [("problem-json", r"application/problem\+json"), ("catalogue", r"ErrorCodes?\b"),
             ("typed-hierarchy", r"class \w+NotFoundError\(NotFoundError\)"),
             ("single-handler", r"exception_handler\(DomainError\)")]),
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
            [("operations-layer", r"operations/"),
             ("frozen-settings", r"SettingsConfigDict\([^)]*frozen\s*=\s*True"),
             ("uv-build-package", r"uv_build|uv init --package"),]),
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
            [("camel-naming", r"def test_[a-z][A-Za-z0-9]*_[a-z]+[A-Z][A-Za-z0-9]*_[a-z]+[A-Z][A-Za-z0-9]*\("),
             ("stateful-fake", r"class Fake\w+[\s\S]{0,400}?self\.\w+:\s*(?:list|dict)\["),
             ("parametrize-ids", r"ids\s*=\s*\["), ("no-asyncio-marker", r"@pytest\.mark\.asyncio", "not_contains"),
             ("no-mocks", r"AsyncMock|MagicMock|mock\.patch|\bpatch\(", "not_contains")]),
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
        "python-graceful-shutdown": (
            "Make my Python FastAPI service and its Kafka consumer worker shut down cleanly during Kubernetes rolling "
            "updates: show the Dockerfile CMD, the Deployment settings, the app lifespan and the worker entrypoint." + TAIL_PY,
            [("graceful-timeout", r"--timeout-graceful-shutdown"), ("native-prestop-sleep", r"preStop:\s*\n\s*sleep:"),
             ("exit-stack", r"AsyncExitStack"), ("signal-handler", r"add_signal_handler\("),
             ("bounded-drain", r"asyncio\.wait\([^)]*timeout\s*="),
             ("no-shell-cmd", r"\nCMD\s+uvicorn", "not_contains"), ("poll-not-async-for", r"getmany\(")]),
        "python-cd": (
            "Write the Helm chart (values.yaml and templates) to deploy my Python FastAPI service, its Kafka worker "
            "process and its Alembic migrations to Kubernetes." + TAIL_PY,
            [("migration-hook", r"helm\.sh/hook:\s*[\x22\x27]?pre-install,\s*pre-upgrade"),
             ("forwarded-ips", r"FORWARDED_ALLOW_IPS"), ("no-sa-token", r"automountServiceAccountToken:\s*false"),
             ("metrics-trailing-slash", r"path:\s*[\x22\x27]?/metrics/"),
             ("worker-liveness", r"exec:\s*\n\s*command:[^\n]*(?:heartbeat|liveness)|HEARTBEAT"),
             ("no-wildcard-proxy", r"forwarded-allow-ips[= ][\x22\x27]?\*|FORWARDED_ALLOW_IPS[\s\S]{0,40}value:\s*[\x22\x27]\*", "not_contains")]),
        "python-ci": (
            "Write the GitHub Actions workflow and the Dockerfile for my Python FastAPI service managed with uv." + TAIL_PY,
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

NEUTRAL = {
    "ai-toolkit-quality": {
        "completion-gate": (
            "I have finished adding a discount feature to my Spring Boot (Maven) service and the new "
            "DiscountServiceTest passes locally. I'm done, wrap it up. Do not create files.",
            [("evidence-table", r"\|\s*Check\s*\|\s*Command\s*\|\s*Result"), ("full-build", r"clean verify"),
             ("changed-code-coverage", r"diff-cover"), ("mutation", r"pitest|mutationCoverage"),
             ("no-commit-command", r"git commit -m", "not_contains")]),
        "code-hygiene": (
            "Clean up this class and its test before I open the pull request. Show the result in your reply; do not "
            "create files.\n\n```java\n/**\n * Service for order totals.\n * @author jdoe\n */\n"
            "public class OrderTotals {\n    /** The tax rate. */\n    private final BigDecimal taxRate;\n\n"
            "    /**\n     * Constructor.\n     * @param taxRate the tax rate\n     */\n"
            "    public OrderTotals(BigDecimal taxRate) { this.taxRate = taxRate; }\n\n"
            "    /** Gets the tax rate. @return the tax rate */\n    public BigDecimal getTaxRate() { return taxRate; }\n\n"
            "    // calculate total\n    public BigDecimal total(BigDecimal net) {\n"
            "        return net.add(net.multiply(taxRate)); // add tax\n    }\n\n"
            "    // public BigDecimal oldTotal(BigDecimal net) { return net; }\n}\n```\n\n```java\n"
            "class OrderTotalsTest {\n    @Test void getTaxRate_returnsTaxRate() {\n"
            "        assertEquals(new BigDecimal(\"0.17\"), new OrderTotals(new BigDecimal(\"0.17\")).getTaxRate());\n    }\n"
            "    @Test void total_100_returns117() {\n"
            "        assertEquals(new BigDecimal(\"117.00\"), new OrderTotals(new BigDecimal(\"0.17\")).total(new BigDecimal(\"100.00\")));\n    }\n"
            "    @Test void total_200_returns234() {\n"
            "        assertEquals(new BigDecimal(\"234.00\"), new OrderTotals(new BigDecimal(\"0.17\")).total(new BigDecimal(\"200.00\")));\n    }\n}\n```",
            [("no-internal-javadoc", r"/\*\*", "not_contains"),
             ("getter-test-removed", r"\.getTaxRate\(\)", "not_contains")]),
        "sonar-quality-gate": (
            "SonarQube's quality gate fails on pull request #482 of my Spring Boot Maven service (Sonar project key "
            "shop-orders, base branch main): new-code coverage is 72% against a gate of 80%. Show me the exact commands "
            "you would use to read the gate result and the open new-code issues, and to re-run the analysis from my "
            "machine if that is needed. Do not run anything and do not create files.",
            [("no-token-on-cmdline", r"-Dsonar\.(?:token|login)=[\x22$\w]", "not_contains"),
             ("pr-scanner-params", r"sonar\.pullRequest\.key"),
             ("new-code-issues", r"inNewCodePeriod=true")]),
    },
    "ai-toolkit-workflow": {
        "parallel-delegation": (
            "I need three independent additions to my Spring Boot service: a new metrics recorder for the export "
            "endpoint, a new Jakarta validator for SKU format, and unit tests for the existing InvoiceService. Plan how "
            "you would split this across subagents and write the brief you would send to each. Do not create files.",
            [("files-owned", r"Files:\s*\S"), ("done-when", r"Done when:"), ("return-section", r"Return:"),
             ("qualified-test-writer", r"ai-toolkit-java-agents:test-writer"),
             ("no-builds-in-subagents", r"[Dd]o not run (?:any )?(?:the )?(?:builds?|tests)|[Nn]ever run (?:the )?build")]),
    },
}

for _plugin, _cases in NEUTRAL.items():
    BEHAVIOUR.setdefault(_plugin, {}).update(_cases)

NEUTRAL_DOCS = {
    "ai-toolkit-docs": {
        "context-maintenance": (
            "We just put a Redis cache in front of the pricing client in our service and finished the 'Phase 2' "
            "milestone. Our repository keeps AI context docs under context/. Which files need updating and what goes "
            "into each? Show the edits in your reply; do not create files.",
            [("library-docs", r"library-docs\.md"), ("dependencies-infra", r"dependencies\.md"),
             ("progress-tracker", r"progress-tracker\.md"), ("validator", r"validate-context\.sh"),
             ("unreleased", r"\[Unreleased\]")]),
        "uml-diagram": (
            "Draw the system context of our order service (customers, API gateway, order service, PostgreSQL, Kafka, "
            "payment provider) and the checkout sequence for the repository docs. Our repository keeps AI context "
            "docs under context/. Show the diagrams and where each file goes; do not create files.",
            [("mermaid", r"```mermaid"), ("context-location", r"context/system-context\.md"),
             ("flow-location", r"context/domain-flow\.md"), ("error-path", r"\n\s*alt\s"),
             ("no-image-files", r"\.(?:png|svg)\b", "not_contains")]),
    },
}

for _plugin, _cases in NEUTRAL_DOCS.items():
    BEHAVIOUR.setdefault(_plugin, {}).update(_cases)

REACT_NATIVE_2 = {
    "ai-toolkit-react-native-ops": {
        "react-native-app-config-and-updates": (
            "Set up app.config.ts with dev/preview/production variants and a GitHub Actions workflow that publishes EAS "
            "updates for our Expo SDK 58 React Native app." + TAIL_RN,
            [
             ("fingerprint-compare-gate", r"fingerprint:compare"),
             ("gradual-rollout", r"--rollout-percentage"),
             ("no-appversion-policy", r"(?:^|\n)\s*runtimeVersion:\s*(?:[\x22\x27]\d|\{\s*policy:\s*[\x22\x27]appVersion)", "not_contains")]),
    },
    "ai-toolkit-react-native-build": {
        "react-native-permissions-and-push": (
            "Add push notification registration and a 'scan receipt' camera button to our Expo React Native app, and "
            "show how the backend sends the push." + TAIL_RN,
            [("can-ask-again", r"canAskAgain"),
             ("microphone-off", r"microphonePermission:\s*false|blockedPermissions"),
             ("token-rotation", r"addPushTokenListener"),]),
    },
}

for _plugin, _cases in REACT_NATIVE_2.items():
    BEHAVIOUR.setdefault(_plugin, {}).update(_cases)
