#!/usr/bin/env bash
# Maintainer pre-release check for the Java skills (NOT CI: the integration step needs Docker).
# Renders EVERY shipped Java template into one fresh Spring Boot service, merges the pom pieces the skills tell a
# developer to merge (static-analysis plugins, the dependencies of each skill), writes a tiny sample domain, runs
# `spotless:apply` once (the skills require it before the first verify) and then `mvn verify`:
#   Spotless check, Error Prone + NullAway (ERROR), SpotBugs, Checkstyle, unit + component + ArchUnit tests,
#   JaCoCo per-class gate (85 % line / 75 % branch), PIT mutation gate (>= 75 %).
# With --with-it it also runs the Testcontainers integration test (Postgres 16 + apache/kafka:3.9.1).
#
# Usage: tools/render-java-proof.sh [--target DIR] [--with-it] [--online] [--render-only]
#   --target DIR    project directory to (re)create (default: a fresh temp dir; an existing one must be empty or a previous proof)
#   --with-it       run the *IT tests too (needs a running Docker daemon)
#   --online        let Maven download missing artifacts (default: try offline first when the Boot parent is cached)
#   --render-only   stop after rendering and spotless:apply
# Env: JAVA_HOME (default: an installed JDK 21), MVN (default: mvn).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS="$ROOT/plugins"
TARGET=""
WITH_IT=0
ONLINE=0
RENDER_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --with-it) WITH_IT=1; shift ;;
    --online) ONLINE=1; shift ;;
    --render-only) RENDER_ONLY=1; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ -z "${JAVA_HOME:-}" ] || ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -q 'version "21'; then
  for candidate in "$HOME"/Library/Java/JavaVirtualMachines/*21*/Contents/Home /usr/lib/jvm/*21* ; do
    [ -x "$candidate/bin/java" ] && JAVA_HOME="$candidate" && break
  done
fi
[ -n "${JAVA_HOME:-}" ] && "$JAVA_HOME/bin/java" -version 2>&1 | grep -q 'version "21' || { echo "JDK 21 not found: set JAVA_HOME" >&2; exit 2; }
export JAVA_HOME
MVN="${MVN:-mvn}"
command -v "$MVN" >/dev/null || MVN=/opt/homebrew/opt/maven/bin/mvn

BOOT_VERSION=3.5.16
BASE_PACKAGE=com.example.orders
BASE_PATH=com/example/orders
ARTIFACT=orders-service
CONTEXT_PATH=/orders-service

if [ -z "$TARGET" ]; then TARGET="$(mktemp -d "${TMPDIR:-/tmp}/java-proof.XXXXXX")/$ARTIFACT"; fi
mkdir -p "$TARGET"
if [ -n "$(ls -A "$TARGET")" ] && [ ! -f "$TARGET/.render-java-proof" ]; then
  echo "refusing to overwrite $TARGET: not empty and not a previous proof" >&2; exit 2
fi
rm -rf "$TARGET"
mkdir -p "$TARGET"
touch "$TARGET/.render-java-proof"
TARGET="$(cd "$TARGET" && pwd)"
echo "== rendering into $TARGET"

render() {
  sed -e "s|{{basePackagePath}}|$BASE_PATH|g" \
      -e "s|{{basePackage}}|$BASE_PACKAGE|g" \
      -e "s|{{applicationClassName}}|OrdersApplication|g" \
      -e "s|{{groupId}}|com.example|g" \
      -e "s|{{artifactId}}|$ARTIFACT|g" \
      -e "s|{{repoName}}|$ARTIFACT|g" \
      -e "s|{{serviceDisplayName}}|Orders Service|g" \
      -e "s|{{springBootVersion}}|$BOOT_VERSION|g" \
      -e "s|{{contextPath}}|$CONTEXT_PATH|g" \
      -e "s|{{appPort}}|8800|g" \
      -e "s|{{defaultScopes}}|read|g" \
      -e "s|{{Dep}}|Inventory|g" \
      -e "s|{{indicatorBeanName}}|inventory|g" \
      -e "s|{{dependencyDisplayName}}|Inventory|g" \
      -e "s|{{configKey}}|inventory|g" \
      -e "s|{{cacheSeconds}}|30|g" \
      -e "s|{{successStatusCode}}|200|g" \
      -e "s|{{baseUrlPath}}||g" \
      -e "s|{{readinessEndpoint}}|/actuator/health/readiness|g" \
      -e "s|{{ControllerClass}}|InvoiceController|g" \
      -e "s|{{OperationClass}}|InvoiceOperation|g" \
      -e "s|{{apiPath}}|/api/v1/invoices|g" \
      "$1"
}

# Tag strip recipe of exception-handling SKILL.md section 3a: every dependency is present except request-metrics
# (its classes are prose-only references, so the [request-metrics] lines of SecurityTest are stripped).
strip_tag() {
  sed -e "/\[$1:begin\]/,/\[$1:end\]/d" -e "/\[$1\]/d"
}

# put <skill-relative template> : renders it to src/main|test/java/<its package>/<name>
put() {
  local src="$PLUGINS/$1" name pkg root dir
  [ -f "$src" ] || { echo "missing template $1" >&2; exit 1; }
  name="$(basename "$src" .tmpl)"
  pkg="$(grep -m1 '^package ' "$src" | sed -e 's/^package //' -e 's/;.*//' | render /dev/stdin)"
  case "$name" in
    *Test.java|*IT.java|ComponentTestConfiguration.java) root=src/test/java ;;
    *) root=src/main/java ;;
  esac
  dir="$TARGET/$root/$(echo "$pkg" | tr . /)"
  mkdir -p "$dir"
  if [ "$name" = "SecurityTest.java" ]; then
    render "$src" | strip_tag request-metrics > "$dir/$name"
  else
    render "$src" > "$dir/$name"
  fi
}

BUILD="ai-toolkit-java-build/skills"
DESIGN="ai-toolkit-java-design/skills"
OPS="ai-toolkit-java-ops/skills"
QUALITY="ai-toolkit-java-quality/skills"
SCAFFOLD="ai-toolkit-java-scaffold/skills"

# ---------------------------------------------------------------- pom + build config
python3 - "$ROOT" "$TARGET" "$BASE_PACKAGE" "$BOOT_VERSION" <<'PY'
import re, sys, pathlib
root, target, base_package, boot = sys.argv[1:5]
plugins = pathlib.Path(root) / "plugins"

def sub(text):
    for k, v in {"{{groupId}}": "com.example", "{{artifactId}}": "orders-service", "{{serviceDisplayName}}": "Orders Service",
                 "{{springBootVersion}}": boot, "{{basePackage}}": base_package}.items():
        text = text.replace(k, v)
    return text

def fences(path, lang):
    blocks, current, open_lang = [], None, None
    for line in (plugins / path).read_text().splitlines(keepends=True):
        if line.startswith("```"):
            if current is None:
                current, open_lang = [], line[3:].strip()
            else:
                if open_lang == lang:
                    blocks.append("".join(current))
                current = None
        elif current is not None:
            current.append(line)
    return blocks

pom = sub((plugins / "ai-toolkit-java-ops/skills/ci/templates/pom.xml.tmpl").read_text())
static = "ai-toolkit-java-quality/skills/static-analysis/SKILL.md"
blocks = fences(static, "xml")
wiring = next(b for b in blocks if "<build>" in b and "spotless-maven-plugin" in b)
plugin_list = re.search(r"<plugins>\n(.*)</plugins>", wiring, re.S).group(1)
processors = """
          <path><groupId>org.hibernate.orm</groupId><artifactId>hibernate-jpamodelgen</artifactId><version>${hibernate.version}</version></path>
          <path><groupId>org.springframework.boot</groupId><artifactId>spring-boot-configuration-processor</artifactId></path>
        """
plugin_list = plugin_list.replace("</annotationProcessorPaths>", processors + "</annotationProcessorPaths>", 1)
pom = pom.replace("        <plugins>\n", "        <plugins>\n" + sub(plugin_list), 1) if "        <plugins>\n" in pom else pom.replace("<plugins>", "<plugins>\n" + sub(plugin_list), 1)

def dep(group, artifact, version=None, scope=None, optional=False):
    v = f"<version>{version}</version>" if version else ""
    s = f"<scope>{scope}</scope>" if scope else ""
    return f"        <dependency><groupId>{group}</groupId><artifactId>{artifact}</artifactId>{v}{s}</dependency>"

boot_g = "org.springframework.boot"
deps = [
    dep(boot_g, "spring-boot-starter-validation"),
    dep(boot_g, "spring-boot-starter-oauth2-resource-server"),
    dep(boot_g, "spring-boot-starter-oauth2-client"),
    dep(boot_g, "spring-boot-starter-data-jpa"),
    dep("org.flywaydb", "flyway-core"),
    dep("org.flywaydb", "flyway-database-postgresql"),
    dep("org.postgresql", "postgresql", scope="runtime"),
    dep("org.hibernate.orm", "hibernate-jpamodelgen", scope="provided"),
    dep("org.springframework.kafka", "spring-kafka"),
    dep("net.javacrumbs.shedlock", "shedlock-spring", "6.10.0"),
    dep("net.javacrumbs.shedlock", "shedlock-provider-jdbc-template", "6.10.0"),
    dep("io.micrometer", "micrometer-tracing-bridge-otel"),
    dep(boot_g, "spring-boot-testcontainers", scope="test"),
    dep("org.testcontainers", "junit-jupiter", scope="test"),
    dep("org.testcontainers", "postgresql", scope="test"),
    dep("org.testcontainers", "kafka", scope="test"),
    dep("org.springframework.security", "spring-security-test", scope="test"),
]
pom = pom.replace("<!-- ADDITIONAL DEPENDENCIES GO HERE -->", "\n".join(deps))
t = pathlib.Path(target)
(t / "pom.xml").write_text(pom)

xml = [b for b in blocks if "<module name=\"Checker\">" in b]
(t / "checkstyle.xml").write_text(sub(xml[0]))
exclude = next(b for b in blocks if "<FindBugsFilter>" in b)
(t / "spotbugs-exclude.xml").write_text(sub(exclude))
jvm = next(b for b in fences(static, "") if b.startswith("--add-exports"))
(t / ".mvn").mkdir(exist_ok=True)
(t / ".mvn" / "jvm.config").write_text(jvm.strip() + "\n")
lombok = next(b for b in fences("ai-toolkit-java-ops/skills/ci/SKILL.md", "properties") if "addLombokGeneratedAnnotation" in b)
(t / "lombok.config").write_text(lombok)
PY

# ---------------------------------------------------------------- templates, skill by skill
put "$DESIGN/code-structure/templates/Application.java.tmpl"
mv "$TARGET/src/main/java/$BASE_PATH/Application.java" "$TARGET/src/main/java/$BASE_PATH/OrdersApplication.java"
put "$DESIGN/code-structure/templates/ArchitectureTest.java.tmpl"

for t in BadRequestException BaseDomainException ConflictException DependencyException ForbiddenException NotFoundException \
         TooManyRequestsException UnavailableException UnsupportedApiVersionException ExceptionMessages GlobalExceptionHandler \
         ExceptionHierarchyTest ExceptionMessagesTest GlobalExceptionHandlerTest; do
  put "$BUILD/exception-handling/templates/$t.java.tmpl"
done

for t in CallerContext CallerContextResolver SpringSecurityCallerContextResolver PermissionsProperties ScopeBasedPermissionsCheck \
         PermissionsCheckStrategy PermissionsHandler PermissionsRegistry SecurityConfig ProblemDetailSecurityHandler \
         IdentityProviderUnavailableFilter PermissionsHandlerTest PermissionsRegistryTest ScopeBasedPermissionsCheckTest \
         SpringSecurityCallerContextResolverTest ProblemDetailSecurityHandlerTest IdentityProviderUnavailableFilterTest; do
  put "$BUILD/permissions/templates/$t.java.tmpl"
done

for t in BaseEntity AuditConfig SecurityAuditorAware ExampleSpecifications BaseEntityTest ExampleSpecificationsTest SecurityAuditorAwareTest; do
  put "$BUILD/persistence/templates/$t.java.tmpl"
done

for t in OutboxEntity OutboxRepository OutboxProperties OutboxWriter OutboxMarker OutboxRelay IdempotentConsumer DlqHandler KafkaConfig \
         ShedLockConfig OutboxWriterTest OutboxMarkerTest OutboxRelayTest IdempotentConsumerTest DlqHandlerTest; do
  put "$BUILD/messaging/templates/$t.java.tmpl"
done

for t in CachePort CacheKey CacheClient CacheClientConfig CacheEntryConverter CacheEntryResponse HttpCacheAdapter HttpCacheProperties \
         CacheKeyTest CacheClientTest CacheEntryConverterTest HttpCacheAdapterTest; do
  put "$BUILD/external-client/templates/$t.java.tmpl"
done

for t in AbstractReadinessIndicator HealthIndicator ReadinessClientConfig ReadinessProperties HealthIndicatorTest ReadinessGroupComponentTest; do
  put "$OPS/health-indicator/templates/$t.java.tmpl"
done
mv "$TARGET/src/main/java/$BASE_PATH/health/indicator/HealthIndicator.java" "$TARGET/src/main/java/$BASE_PATH/health/indicator/InventoryHealthIndicator.java"
mv "$TARGET/src/test/java/$BASE_PATH/health/indicator/HealthIndicatorTest.java" "$TARGET/src/test/java/$BASE_PATH/health/indicator/InventoryHealthIndicatorTest.java"
mv "$TARGET/src/main/java/$BASE_PATH/health/config/ReadinessProperties.java" "$TARGET/src/main/java/$BASE_PATH/health/config/InventoryReadinessProperties.java"

put "$QUALITY/component-tests/templates/ComponentTestConfiguration.java.tmpl"
put "$QUALITY/component-tests/templates/SecurityTest.java.tmpl"
mv "$TARGET/src/test/java/$BASE_PATH/security/SecurityTest.java" "$TARGET/src/test/java/$BASE_PATH/security/InvoiceControllerSecurityTest.java"

MIGRATIONS="$TARGET/src/main/resources/db/migration"
mkdir -p "$MIGRATIONS"
render "$PLUGINS/$BUILD/messaging/templates/outbox-migration.sql.tmpl" > "$MIGRATIONS/V002__create_outbox.sql"
render "$PLUGINS/$BUILD/messaging/templates/shedlock-migration.sql.tmpl" > "$MIGRATIONS/V003__create_shedlock.sql"
mkdir -p "$TARGET/src/main/resources" "$TARGET/src/test/resources"
render "$PLUGINS/$DESIGN/code-structure/templates/application.yaml.tmpl" > "$TARGET/src/main/resources/application.yaml"

# ---------------------------------------------------------------- what the skills tell a developer to write
SRC="$TARGET/src/main/java/$BASE_PATH"
TST="$TARGET/src/test/java/$BASE_PATH"
mkdir -p "$SRC"/{controller,dto,entity,event,operation,repository,service,config} "$TST"/{controller,entity,operation,service,component,it}

cat >> "$TARGET/src/main/resources/application.yaml" <<'YAML'

spring.datasource.url: ${DB_URL}
spring.datasource.username: ${DB_USER}
spring.datasource.password: ${DB_PASSWORD}
spring.jpa.hibernate.ddl-auto: validate
spring.jpa.open-in-view: false
spring.security.oauth2.resourceserver.jwt.issuer-uri: ${JWT_ISSUER_URI}
spring.security.oauth2.resourceserver.jwt.audiences: ${JWT_AUDIENCE:orders-service}
spring.kafka.bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS:localhost:9092}
spring.kafka.consumer.key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
spring.kafka.consumer.value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
spring.kafka.consumer.enable-auto-commit: false
spring.kafka.consumer.auto-offset-reset: earliest
spring.kafka.producer.key-serializer: org.apache.kafka.common.serialization.StringSerializer
spring.kafka.producer.value-serializer: org.apache.kafka.common.serialization.StringSerializer
spring.kafka.producer.acks: all
spring.kafka.listener.ack-mode: manual
spring.kafka.listener.missing-topics-fatal: false
spring.kafka.template.observation-enabled: true
spring.kafka.listener.observation-enabled: true

management.endpoint.health.group.readiness.include: readinessState,inventory

permissions.service-account.allowed-scopes: ${PERMISSIONS_ALLOWED_SCOPES:read}

kafka.topics.example:
  name: invoices
  group-id: orders
kafka.retry:
  attempts: 5
  delay-ms: 1000
  multiplier: 2
  max-delay-ms: 30000

outbox.relay.topics.invoice: invoices

inventory:
  base-url: ${INVENTORY_BASE_URL:http://localhost:9999}
  readiness-endpoint: /actuator/health/readiness
YAML

cat > "$TARGET/src/test/resources/application-component-test.yaml" <<'YAML'
spring:
  autoconfigure:
    exclude:
      - org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration
      - org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration
      - org.springframework.boot.autoconfigure.flyway.FlywayAutoConfiguration
      - org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration
      - org.springframework.boot.hibernate.autoconfigure.HibernateJpaAutoConfiguration
      - org.springframework.boot.flyway.autoconfigure.FlywayAutoConfiguration
  kafka:
    listener.auto-startup: false
    admin.auto-create: false
  security.oauth2.resourceserver.jwt.issuer-uri: https://issuer.example.test
YAML

cat > "$MIGRATIONS/V001__create_invoices.sql" <<'SQL'
CREATE TABLE invoices (
    id         uuid         PRIMARY KEY,
    name       varchar(255) NOT NULL,
    owner_id   uuid         NOT NULL,
    status     varchar(255) NOT NULL,
    version    bigint       NOT NULL,
    created_at timestamptz,
    updated_at timestamptz,
    created_by varchar(255),
    updated_by varchar(255)
);
SQL

cat > "$SRC/config/ClockConfig.java" <<'JAVA'
package {{basePackage}}.config;

import java.time.Clock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class ClockConfig {
    @Bean
    Clock clock() {
        return Clock.systemUTC();
    }
}
JAVA

cat > "$SRC/entity/Invoice.java" <<'JAVA'
package {{basePackage}}.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.util.UUID;
import lombok.Getter;

@Entity
@Table(name = "invoices")
@Getter
public class Invoice extends BaseEntity {
    public enum Status {
        NEW,
        READY
    }

    @Id private UUID id;

    @Column(nullable = false)
    private String name;

    @Column(name = "owner_id", nullable = false)
    private UUID ownerId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Status status;

    @SuppressWarnings("NullAway.Init")
    protected Invoice() {}

    public Invoice(UUID id, UUID ownerId, String name) {
        this.id = id;
        this.ownerId = ownerId;
        this.name = name;
        this.status = Status.NEW;
    }
}
JAVA

cat > "$SRC/event/InvoiceCreatedEvent.java" <<'JAVA'
package {{basePackage}}.event;

import java.time.Instant;
import java.util.UUID;

public record InvoiceCreatedEvent(UUID invoiceId, String name, Instant occurredAt) {}
JAVA

cat > "$SRC/repository/InvoiceRepository.java" <<'JAVA'
package {{basePackage}}.repository;

import {{basePackage}}.entity.Invoice;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;

public interface InvoiceRepository extends JpaRepository<Invoice, UUID>, JpaSpecificationExecutor<Invoice> {}
JAVA

cat > "$SRC/service/InvoiceService.java" <<'JAVA'
package {{basePackage}}.service;

import {{basePackage}}.entity.Invoice;
import {{basePackage}}.event.InvoiceCreatedEvent;
import {{basePackage}}.exception.BaseDomainException;
import {{basePackage}}.exception.constants.ExceptionMessages;
import {{basePackage}}.messaging.OutboxWriter;
import {{basePackage}}.repository.InvoiceRepository;
import java.time.Clock;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class InvoiceService {
    static final int MAX_LISTED = 50;

    private final InvoiceRepository repository;
    private final OutboxWriter outbox;
    private final Clock clock;

    @Transactional(rollbackFor = Exception.class)
    public Invoice create(UUID id, UUID ownerId, String name) throws BaseDomainException {
        if (repository.existsById(id)) {
            throw ExceptionMessages.versionConflict("Invoice", id.toString());
        }
        Invoice invoice = repository.save(new Invoice(id, ownerId, name));
        outbox.append("invoice", id.toString(), new InvoiceCreatedEvent(id, name, clock.instant()));
        return invoice;
    }

    @Transactional(readOnly = true, rollbackFor = Exception.class)
    public Invoice get(UUID id) throws BaseDomainException {
        return repository.findById(id).orElseThrow(() -> ExceptionMessages.resourceNotFound("Invoice", id.toString()));
    }

    @Transactional(readOnly = true, rollbackFor = Exception.class)
    public List<Invoice> list() {
        return repository.findAll(PageRequest.of(0, MAX_LISTED)).getContent();
    }
}
JAVA

cat > "$SRC/operation/InvoiceOperation.java" <<'JAVA'
package {{basePackage}}.operation;

import {{basePackage}}.entity.Invoice;
import {{basePackage}}.exception.BaseDomainException;
import {{basePackage}}.permission.PermissionsHandler;
import {{basePackage}}.service.InvoiceService;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class InvoiceOperation {
    static final String COLLECTION_RESOURCE = "invoices";

    private final PermissionsHandler permissionsHandler;
    private final InvoiceService service;

    public Invoice get(UUID id) throws BaseDomainException {
        permissionsHandler.handle(id.toString());
        return service.get(id);
    }

    public Invoice create(UUID id, UUID ownerId, String name) throws BaseDomainException {
        permissionsHandler.handle(id.toString());
        return service.create(id, ownerId, name);
    }

    public List<Invoice> list() throws BaseDomainException {
        permissionsHandler.handle(COLLECTION_RESOURCE);
        return service.list();
    }
}
JAVA

cat > "$SRC/dto/CreateInvoiceRequest.java" <<'JAVA'
package {{basePackage}}.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.util.UUID;

public record CreateInvoiceRequest(@NotNull UUID id, @NotNull UUID ownerId, @NotBlank String name) {}
JAVA

cat > "$SRC/dto/InvoiceResponse.java" <<'JAVA'
package {{basePackage}}.dto;

import {{basePackage}}.entity.Invoice;
import java.util.UUID;

public record InvoiceResponse(UUID id, String name, String status) {
    public static InvoiceResponse from(Invoice invoice) {
        return new InvoiceResponse(invoice.getId(), invoice.getName(), invoice.getStatus().name());
    }
}
JAVA

cat > "$SRC/controller/InvoiceController.java" <<'JAVA'
package {{basePackage}}.controller;

import {{basePackage}}.dto.CreateInvoiceRequest;
import {{basePackage}}.dto.InvoiceResponse;
import {{basePackage}}.exception.BaseDomainException;
import {{basePackage}}.operation.InvoiceOperation;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/invoices")
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class InvoiceController {
    private final InvoiceOperation operation;

    @GetMapping
    public List<InvoiceResponse> list() throws BaseDomainException {
        return operation.list().stream().map(InvoiceResponse::from).toList();
    }

    @GetMapping("/{id}")
    public InvoiceResponse get(@PathVariable UUID id) throws BaseDomainException {
        return InvoiceResponse.from(operation.get(id));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public InvoiceResponse create(@Valid @RequestBody CreateInvoiceRequest request) throws BaseDomainException {
        return InvoiceResponse.from(operation.create(request.id(), request.ownerId(), request.name()));
    }
}
JAVA

cat > "$TST/entity/InvoiceTest.java" <<'JAVA'
package {{basePackage}}.entity;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;
import org.junit.jupiter.api.Test;

class InvoiceTest {

    @Test
    void constructor_newInvoice_startsAsNewWithTheGivenFields() {
        final UUID id = UUID.randomUUID();
        final UUID ownerId = UUID.randomUUID();

        final Invoice invoice = new Invoice(id, ownerId, "acme");

        assertThat(invoice.getId()).isEqualTo(id);
        assertThat(invoice.getOwnerId()).isEqualTo(ownerId);
        assertThat(invoice.getName()).isEqualTo("acme");
        assertThat(invoice.getStatus()).isEqualTo(Invoice.Status.NEW);
    }

    @Test
    void jpaConstructor_isAvailableToTheProviderAndLeavesTheStateEmpty() {
        assertThat(new Invoice().getName()).isNull();
    }
}
JAVA

cat > "$TST/service/InvoiceServiceTest.java" <<'JAVA'
package {{basePackage}}.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import {{basePackage}}.entity.Invoice;
import {{basePackage}}.event.InvoiceCreatedEvent;
import {{basePackage}}.exception.ConflictException;
import {{basePackage}}.exception.NotFoundException;
import {{basePackage}}.messaging.OutboxWriter;
import {{basePackage}}.repository.InvoiceRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;

@ExtendWith(MockitoExtension.class)
class InvoiceServiceTest {

    private static final Instant NOW = Instant.parse("2026-01-02T03:04:05Z");
    private static final UUID ID = UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static final UUID OWNER = UUID.fromString("00000000-0000-0000-0000-0000000000a1");

    @Mock private InvoiceRepository repository;
    @Mock private OutboxWriter outbox;

    private InvoiceService service;

    @BeforeEach
    void setUp() {
        service = new InvoiceService(repository, outbox, Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    void create_newInvoice_savesItAndAppendsTheCreatedEventToTheOutbox() throws Exception {
        when(repository.existsById(ID)).thenReturn(false);
        when(repository.save(any(Invoice.class))).thenAnswer(invocation -> invocation.getArgument(0));

        final Invoice created = service.create(ID, OWNER, "acme");

        assertThat(created.getId()).isEqualTo(ID);
        assertThat(created.getName()).isEqualTo("acme");
        verify(outbox).append("invoice", ID.toString(), new InvoiceCreatedEvent(ID, "acme", NOW));
    }

    @Test
    void create_existingId_throwsConflictAndWritesNothing() {
        when(repository.existsById(ID)).thenReturn(true);

        assertThatThrownBy(() -> service.create(ID, OWNER, "acme")).isInstanceOf(ConflictException.class);

        verify(repository, never()).save(any());
        verify(outbox, never()).append(any(), any(), any());
    }

    @Test
    void get_existingInvoice_returnsIt() throws Exception {
        final Invoice invoice = new Invoice(ID, OWNER, "acme");
        when(repository.findById(ID)).thenReturn(Optional.of(invoice));

        assertThat(service.get(ID)).isSameAs(invoice);
    }

    @Test
    void get_unknownInvoice_throwsNotFoundNamingTheId() {
        when(repository.findById(ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.get(ID)).isInstanceOf(NotFoundException.class).hasMessageContaining(ID.toString());
    }

    @Test
    void list_returnsEveryInvoice() {
        final List<Invoice> all = List.of(new Invoice(ID, OWNER, "acme"));
        when(repository.findAll(PageRequest.of(0, InvoiceService.MAX_LISTED))).thenReturn(new PageImpl<>(all));

        assertThat(service.list()).isEqualTo(all);
    }
}
JAVA

cat > "$TST/operation/InvoiceOperationTest.java" <<'JAVA'
package {{basePackage}}.operation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import {{basePackage}}.entity.Invoice;
import {{basePackage}}.exception.ForbiddenException;
import {{basePackage}}.exception.constants.ExceptionMessages;
import {{basePackage}}.permission.PermissionsHandler;
import {{basePackage}}.service.InvoiceService;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class InvoiceOperationTest {

    private static final UUID ID = UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static final UUID OWNER = UUID.fromString("00000000-0000-0000-0000-0000000000a1");

    @Mock private PermissionsHandler permissionsHandler;
    @Mock private InvoiceService service;
    @InjectMocks private InvoiceOperation operation;

    @Test
    void get_authorized_checksPermissionsBeforeLoading() throws Exception {
        final Invoice invoice = new Invoice(ID, OWNER, "acme");
        when(service.get(ID)).thenReturn(invoice);

        assertThat(operation.get(ID)).isSameAs(invoice);

        final InOrder order = inOrder(permissionsHandler, service);
        order.verify(permissionsHandler).handle(ID.toString());
        order.verify(service).get(ID);
    }

    @Test
    void get_forbidden_neverReachesTheService() throws Exception {
        doThrow(ExceptionMessages.accessDenied("x")).when(permissionsHandler).handle(ID.toString());

        assertThatThrownBy(() -> operation.get(ID)).isInstanceOf(ForbiddenException.class);

        verifyNoInteractions(service);
    }

    @Test
    void create_authorized_checksPermissionsThenCreates() throws Exception {
        final Invoice invoice = new Invoice(ID, OWNER, "acme");
        when(service.create(ID, OWNER, "acme")).thenReturn(invoice);

        assertThat(operation.create(ID, OWNER, "acme")).isSameAs(invoice);

        final InOrder order = inOrder(permissionsHandler, service);
        order.verify(permissionsHandler).handle(ID.toString());
        order.verify(service).create(ID, OWNER, "acme");
    }

    @Test
    void create_forbidden_neverReachesTheService() throws Exception {
        doThrow(ExceptionMessages.accessDenied("x")).when(permissionsHandler).handle(ID.toString());

        assertThatThrownBy(() -> operation.create(ID, OWNER, "acme")).isInstanceOf(ForbiddenException.class);

        verifyNoInteractions(service);
    }

    @Test
    void list_authorized_checksTheCollectionPermissionThenLists() throws Exception {
        final List<Invoice> all = List.of(new Invoice(ID, OWNER, "acme"));
        when(service.list()).thenReturn(all);

        assertThat(operation.list()).isEqualTo(all);

        final InOrder order = inOrder(permissionsHandler, service);
        order.verify(permissionsHandler).handle("invoices");
        order.verify(service).list();
    }

    @Test
    void list_forbidden_neverReachesTheService() throws Exception {
        doThrow(ExceptionMessages.accessDenied("x")).when(permissionsHandler).handle("invoices");

        assertThatThrownBy(() -> operation.list()).isInstanceOf(ForbiddenException.class);

        verifyNoInteractions(service);
    }
}
JAVA

cat > "$TST/controller/InvoiceControllerTest.java" <<'JAVA'
package {{basePackage}}.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import {{basePackage}}.dto.CreateInvoiceRequest;
import {{basePackage}}.dto.InvoiceResponse;
import {{basePackage}}.entity.Invoice;
import {{basePackage}}.operation.InvoiceOperation;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class InvoiceControllerTest {

    private static final UUID ID = UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static final UUID OWNER = UUID.fromString("00000000-0000-0000-0000-0000000000a1");

    @Mock private InvoiceOperation operation;
    @InjectMocks private InvoiceController controller;

    @Test
    void get_existingInvoice_mapsItToTheResponseDto() throws Exception {
        when(operation.get(ID)).thenReturn(new Invoice(ID, OWNER, "acme"));

        assertThat(controller.get(ID)).isEqualTo(new InvoiceResponse(ID, "acme", "NEW"));
    }

    @Test
    void create_validRequest_passesTheFieldsToTheOperation() throws Exception {
        when(operation.create(ID, OWNER, "acme")).thenReturn(new Invoice(ID, OWNER, "acme"));

        assertThat(controller.create(new CreateInvoiceRequest(ID, OWNER, "acme"))).isEqualTo(new InvoiceResponse(ID, "acme", "NEW"));
    }

    @Test
    void list_invoices_mapsEachToTheResponseDto() throws Exception {
        when(operation.list()).thenReturn(List.of(new Invoice(ID, OWNER, "acme")));

        assertThat(controller.list()).containsExactly(new InvoiceResponse(ID, "acme", "NEW"));
    }
}
JAVA

python3 - "$TARGET/src/test/java/$BASE_PATH/testconfig/ComponentTestConfiguration.java" "$BASE_PACKAGE" <<'PY'
import sys, re
path, base = sys.argv[1:3]
s = open(path).read()
imports = f"""import {base}.entity.Invoice;
import {base}.exception.constants.ExceptionMessages;
import {base}.messaging.OutboxWriter;
import {base}.permission.PermissionsHandler;
import {base}.repository.InvoiceRepository;
import java.util.Optional;
import java.util.UUID;
"""
s = s.replace("import org.springframework.boot.test.context.TestConfiguration;", imports + "import org.springframework.boot.test.context.TestConfiguration;", 1)
beans = f"""
    static final UUID KNOWN_ID = UUID.fromString("00000000-0000-0000-0000-000000000001");
    static final UUID FORBIDDEN_ID = UUID.fromString("00000000-0000-0000-0000-000000000009");

    @Bean
    @Primary
    public PermissionsHandler permissionsHandler() throws Exception {{
        final var mock = mock(PermissionsHandler.class);
        doAnswer(inv -> {{
            final String resourceId = inv.getArgument(0);
            if (FORBIDDEN_ID.toString().equals(resourceId)) {{
                throw ExceptionMessages.accessDenied(resourceId);
            }}
            return null;
        }}).when(mock).handle(anyString());
        return mock;
    }}

    @Bean
    @Primary
    public InvoiceRepository invoiceRepository() {{
        final var mock = mock(InvoiceRepository.class);
        when(mock.findById(any())).thenAnswer(inv -> KNOWN_ID.equals(inv.getArgument(0))
                ? Optional.of(new Invoice(KNOWN_ID, KNOWN_ID, "acme")) : Optional.empty());
        when(mock.existsById(any())).thenAnswer(inv -> KNOWN_ID.equals(inv.getArgument(0)));
        when(mock.save(any())).thenAnswer(inv -> inv.getArgument(0));
        return mock;
    }}

    @Bean
    @Primary
    public OutboxWriter outboxWriter() {{
        return mock(OutboxWriter.class);
    }}
}}
"""
idx = s.rstrip().rfind("}")
s = s[:idx].rstrip() + "\n" + beans
s = s.replace("import static org.mockito.ArgumentMatchers.anyString;", "import static org.mockito.ArgumentMatchers.any;\nimport static org.mockito.ArgumentMatchers.anyString;")
open(path, "w").write(s)
PY

cat > "$TST/component/InvoiceComponentTest.java" <<'JAVA'
package {{basePackage}}.component;

import static org.assertj.core.api.Assertions.assertThat;

import {{basePackage}}.testconfig.ComponentTestConfiguration;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.actuate.observability.AutoConfigureObservability;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureObservability
@Import(ComponentTestConfiguration.class)
@ActiveProfiles("component-test")
class InvoiceComponentTest {

    private static final String KNOWN = "00000000-0000-0000-0000-000000000001";
    private static final String FORBIDDEN = "00000000-0000-0000-0000-000000000009";

    @LocalServerPort private int port;
    @Autowired private TestRestTemplate restTemplate;

    private String url(final String path) {
        return "http://localhost:" + port + "/orders-service" + path;
    }

    private ResponseEntity<String> post(final String id, final String name) {
        final HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        final String body = "{\"id\":\"" + id + "\",\"ownerId\":\"" + UUID.randomUUID() + "\",\"name\":\"" + name + "\"}";
        return restTemplate.exchange(url("/api/v1/invoices"), HttpMethod.POST, new HttpEntity<>(body, headers), String.class);
    }

    @Test
    void get_knownInvoice_returns200WithTheInvoice() {
        final ResponseEntity<String> response = restTemplate.getForEntity(url("/api/v1/invoices/" + KNOWN), String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).contains("\"name\":\"acme\"").contains("\"status\":\"NEW\"");
    }

    @Test
    void get_unknownInvoice_returns404ProblemWithErrorCode() {
        final ResponseEntity<String> response =
                restTemplate.getForEntity(url("/api/v1/invoices/00000000-0000-0000-0000-000000000002"), String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(response.getBody()).contains("ERR-NOT-FOUND");
    }

    @Test
    void get_forbiddenInvoice_returns403() {
        final ResponseEntity<String> response = restTemplate.getForEntity(url("/api/v1/invoices/" + FORBIDDEN), String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(response.getBody()).contains("ERR-FORBIDDEN");
    }

    @Test
    void get_malformedId_returns400() {
        assertThat(restTemplate.getForEntity(url("/api/v1/invoices/not-a-uuid"), String.class).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    void create_newInvoice_returns201() {
        final ResponseEntity<String> response = post(UUID.randomUUID().toString(), "globex");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(response.getBody()).contains("globex");
    }

    @Test
    void create_existingId_returns409() {
        assertThat(post(KNOWN, "acme").getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
    }

    @Test
    void create_blankName_returns400WithFieldErrors() {
        final ResponseEntity<String> response = post(UUID.randomUUID().toString(), "");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody()).contains("errors");
    }

    @Test
    void unknownPath_returns404WithErrorCode() {
        final ResponseEntity<String> response = restTemplate.getForEntity(url("/api/v1/nothing"), String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(response.getBody()).contains("errorCode");
    }

    @Test
    void prometheus_withObservabilityEnabled_exposesTheMetrics() {
        final ResponseEntity<String> response = restTemplate.getForEntity(url("/actuator/prometheus"), String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).contains("http_server_requests");
    }
}
JAVA

# ---------------------------------------------------------------- render sample sources, then check nothing was left unrendered
while IFS= read -r f; do
  tmp="$(mktemp)"; render "$f" > "$tmp"; mv "$tmp" "$f"
done < <(grep -rl '{{' "$TARGET/src" "$TARGET/pom.xml" 2>/dev/null || true)

if [ $WITH_IT -eq 1 ]; then
  cat > "$TST/it/OrdersFlowIT.java" <<'JAVA'
package {{basePackage}}.it;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import org.jspecify.annotations.Nullable;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.actuate.observability.AutoConfigureObservability;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtDecoderInitializationException;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.kafka.KafkaContainer;

@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
            "spring.security.oauth2.resourceserver.jwt.issuer-uri=https://issuer.example.test",
            "management.endpoint.health.show-components=always"
        })
@AutoConfigureObservability
@Testcontainers
class OrdersFlowIT {

    @Container @ServiceConnection static PostgreSQLContainer<?> db = new PostgreSQLContainer<>("postgres:16-alpine");

    @Container @ServiceConnection static KafkaContainer kafka = new KafkaContainer("apache/kafka:3.9.1");

    @MockitoBean private JwtDecoder jwtDecoder;
    @LocalServerPort private int port;
    @Autowired private TestRestTemplate rest;
    @Autowired private JdbcTemplate jdbc;

    private String url(final String path) {
        return "http://localhost:" + port + "/orders-service" + path;
    }

    private HttpEntity<String> entity(final String token, @Nullable final String body) {
        final HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(token);
        headers.setContentType(MediaType.APPLICATION_JSON);
        return new HttpEntity<>(body, headers);
    }

    private void tokenFor(final String token, final String subject, final String authorizedParty, final String scope) {
        final Jwt jwt =
                Jwt.withTokenValue(token)
                        .header("alg", "none")
                        .subject(subject)
                        .claim("azp", authorizedParty)
                        .claim("scope", scope)
                        .issuedAt(Instant.now())
                        .expiresAt(Instant.now().plusSeconds(60))
                        .build();
        when(jwtDecoder.decode(token)).thenReturn(jwt);
    }

    @Test
    void protectedPath_withoutToken_is401ProblemJson() {
        final ResponseEntity<String> response = rest.getForEntity(url("/api/v1/invoices"), String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        assertThat(response.getBody()).contains("ERR-UNAUTHORIZED");
    }

    @Test
    void protectedPath_identityProviderDown_is503WithRetryAfter() {
        when(jwtDecoder.decode("idp-down")).thenThrow(new JwtDecoderInitializationException("down", new RuntimeException()));

        final ResponseEntity<String> response = rest.exchange(url("/api/v1/invoices"), HttpMethod.GET, entity("idp-down", null), String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        assertThat(response.getHeaders().getFirst("Retry-After")).isEqualTo("30");
    }

    @Test
    void endUserWithoutStrategy_is403() {
        tokenFor("user", "alice", "web", "openid");

        final ResponseEntity<String> response = rest.exchange(url("/api/v1/invoices"), HttpMethod.GET, entity("user", null), String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void serviceAccountWithoutAllowedScope_is403() {
        tokenFor("sa-write", "svc", "svc", "write");

        final ResponseEntity<String> response = rest.exchange(url("/api/v1/invoices"), HttpMethod.GET, entity("sa-write", null), String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void createInvoice_persistsAuditsPublishesThroughTheOutboxAndTheConsumerDeduplicates() {
        tokenFor("sa", "svc", "svc", "read");
        final String id = UUID.randomUUID().toString();
        final String body = "{\"id\":\"" + id + "\",\"ownerId\":\"" + UUID.randomUUID() + "\",\"name\":\"acme\"}";

        final ResponseEntity<String> created = rest.exchange(url("/api/v1/invoices"), HttpMethod.POST, entity("sa", body), String.class);

        assertThat(created.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        await().atMost(Duration.ofSeconds(60)).untilAsserted(() -> {
            assertThat(jdbc.queryForObject("select count(*) from outbox where published_at is not null and aggregate_id = ?", Integer.class, id)).isEqualTo(1);
            assertThat(jdbc.queryForObject("select count(*) from processed_events", Integer.class)).isGreaterThanOrEqualTo(1);
        });
        assertThat(jdbc.queryForObject("select created_by from invoices where id = ?::uuid", String.class, id)).isEqualTo("svc");
        assertThat(jdbc.queryForObject("select count(*) from shedlock", Integer.class)).isGreaterThanOrEqualTo(1);
        final ResponseEntity<String> fetched = rest.exchange(url("/api/v1/invoices/" + id), HttpMethod.GET, entity("sa", null), String.class);
        assertThat(fetched.getStatusCode()).isEqualTo(HttpStatus.OK);
        final ResponseEntity<String> duplicate = rest.exchange(url("/api/v1/invoices"), HttpMethod.POST, entity("sa", body), String.class);
        assertThat(duplicate.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
    }

    @Test
    void actuator_readinessReportsTheInventoryIndicatorAndPrometheusIsServed() {
        final ResponseEntity<String> readiness = rest.getForEntity(url("/actuator/health/readiness"), String.class);
        assertThat(readiness.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        assertThat(readiness.getBody()).contains("inventory");
        assertThat(rest.getForEntity(url("/actuator/prometheus"), String.class).getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(rest.getForEntity(url("/actuator/env"), String.class).getStatusCode().value()).isIn(401, 403, 404);
    }
}
JAVA
  render "$TST/it/OrdersFlowIT.java" > "$TST/it/OrdersFlowIT.java.rendered" && mv "$TST/it/OrdersFlowIT.java.rendered" "$TST/it/OrdersFlowIT.java"
fi

# ---------------------------------------------------------------- gates
MVN_ARGS=(-B -ntp)
if [ $ONLINE -eq 0 ] && [ -d "$HOME/.m2/repository/org/springframework/boot/spring-boot-starter-parent/$BOOT_VERSION" ]; then MVN_ARGS+=(-o); fi

cd "$TARGET"
echo "== spotless:apply (required once before the first verify: the templates are not pre-formatted)"
"$MVN" "${MVN_ARGS[@]}" -q spotless:apply
[ $RENDER_ONLY -eq 1 ] && { echo "== rendered and formatted: $TARGET"; exit 0; }

if [ $WITH_IT -eq 1 ]; then
  docker info >/dev/null 2>&1 || { echo "--with-it needs a running Docker daemon" >&2; exit 2; }
  if [ -z "${DOCKER_HOST:-}" ] && [ ! -S /var/run/docker.sock ]; then
    DOCKER_HOST="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
    if [ -n "$DOCKER_HOST" ]; then export DOCKER_HOST TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock; fi
  fi
  VERIFY_ARGS=(-DskipITs=false)
else
  VERIFY_ARGS=(-DskipITs)
fi

echo "== mvn verify ${VERIFY_ARGS[*]:-}"
LOG="$TARGET/verify.log"
set +e
"$MVN" "${MVN_ARGS[@]}" "${VERIFY_ARGS[@]}" verify 2>&1 | tee "$LOG" | grep -E '^\[(INFO|WARNING|ERROR)\] (Tests run:|BUILD|Rule violated|.*(Spotless|SpotBugs|Checkstyle|PIT|Mutation|Generated|Line coverage|Mutations|Test strength|Analyzed bundle|All coverage checks))|Tests run:.*Fail|ERROR.*\.java|error:'
status=${PIPESTATUS[0]}
set -e

echo
echo "== summary ($TARGET)"
grep -E "^\[(INFO|ERROR)\] Tests run: [0-9]+, Failures: [0-9]+, Errors: [0-9]+, Skipped: [0-9]+$" "$LOG" | sed -e 's/^\[[A-Z]*\] Tests run:/tests:/' || true
if [ -f target/site/jacoco/jacoco.csv ]; then
  python3 - target/site/jacoco/jacoco.csv <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1])))
def ratio(kind):
    covered = sum(int(r[kind + "_COVERED"]) for r in rows)
    total = covered + sum(int(r[kind + "_MISSED"]) for r in rows)
    return f"{covered}/{total} ({100 * covered / total:.1f}%)" if total else "n/a"
print(f"jacoco: {len(rows)} classes, line {ratio('LINE')}, branch {ratio('BRANCH')}; per-class gate 85% line / 75% branch")
PY
fi
grep -E "All coverage checks" "$LOG" | sed -e 's/^\[INFO\] /jacoco: /' || true
grep -E "^>> (Generated [0-9]+ mutations|Line Coverage|Mutations with no coverage)" "$LOG" | sed -e 's/^>> /pit: /' | tail -3 || true
if [ $status -eq 0 ]; then echo "GREEN: every shipped Java template, applied together, passes the toolkit's own gates"; else echo "RED: see $LOG"; fi
exit $status
