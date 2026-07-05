param(
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    @'
generate-spring-pipeline-apps.ps1

Cel:
  Belso/private generator script, amely a projekt Spring Boot pipeline app
  vazat generalja: root pom.xml, app1-app6 modulok, Java forrasok,
  application.yaml fajlok es kapcsolodo resource-ok.

FIGYELEM:
  Ez nem napi hasznalatu script. Meglevo app forrasokat, pom.xml-t es
  konfiguraciokat felulirhat. Csak akkor futtasd, ha tudatosan ujra akarod
  generalni a projekt app skeletonjat.

Hasznalat:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\private\generate-spring-pipeline-apps.ps1

Help:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\private\generate-spring-pipeline-apps.ps1 --help

Mit csinal:
  1. A scripts\private konyvtar ket szinttel feljebb levo mappajat projektgyokernek veszi.
  2. Letrehozza vagy felulirja a root pom.xml fajlt.
  3. Letrehozza/frissiti az app1 ... app6 Maven modulokat.
  4. General Spring Boot Java kodot Kafka consumer/producer pipeline-hoz.
  5. General audit DB iras logikat SQL Serverhez.
  6. General application.yaml fajlokat apponkent.
  7. Letrehozza a security konyvtarak helyet JKS fajloknak.

Mikor hasznald:
  - Ha nullarol ujra akarod generalni a demo pipeline appokat.
  - Ha elfogadhato, hogy a generator felulir app forrasokat.

Mikor ne hasznald:
  - Normal buildhez.
  - Offline bundle futtatashoz.
  - Ha mar kezzel modositottad az app forrasokat es nem akarod oket elvesziteni.

Helyette normal hasznalathoz:
  .\scripts\build-apps-with-podman.ps1
  .\scripts\deploy-springboot-pods.ps1
  .\scripts\export-offline-bundle.ps1
'@
}

if ($Help) {
    Show-Help
    exit 0
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$groupId = "hu.alkalmassagi"
$bootVersion = "3.3.6"

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Content
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$rootPom = @"
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>$bootVersion</version>
        <relativePath/>
    </parent>

    <groupId>$groupId</groupId>
    <artifactId>alkalmassagi-pipeline</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <packaging>pom</packaging>

    <modules>
        <module>app1</module>
        <module>app2</module>
        <module>app3</module>
        <module>app4</module>
        <module>app5</module>
        <module>app6</module>
    </modules>

    <properties>
        <java.version>21</java.version>
        <maven.compiler.release>21</maven.compiler.release>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>
</project>
"@

Write-Utf8File -Path (Join-Path $projectRoot "pom.xml") -Content $rootPom

$javaSource = @'
package hu.alkalmassagi.pipeline;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;

import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.header.Header;
import org.apache.kafka.common.header.internals.RecordHeader;
import org.apache.kafka.common.header.internals.RecordHeaders;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.config.TopicBuilder;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;

import jakarta.annotation.PostConstruct;

@SpringBootApplication
@EnableConfigurationProperties(PipelineProperties.class)
public class PipelineApplication {
    public static void main(String[] args) {
        SpringApplication.run(PipelineApplication.class, args);
    }

    @Bean
    org.apache.kafka.clients.admin.NewTopic sourceTopic(PipelineProperties properties) {
        return TopicBuilder.name(properties.sourceTopic())
            .partitions(properties.topicPartitions())
            .replicas(properties.topicReplicas())
            .build();
    }

    @Bean
    org.apache.kafka.clients.admin.NewTopic destinationTopic(PipelineProperties properties) {
        return TopicBuilder.name(properties.destinationTopic())
            .partitions(properties.topicPartitions())
            .replicas(properties.topicReplicas())
            .build();
    }
}

@ConfigurationProperties(prefix = "pipeline")
record PipelineProperties(
    String serviceName,
    String databaseName,
    String schemaName,
    String auditTableName,
    String sourceTopic,
    String destinationTopic,
    int topicPartitions,
    short topicReplicas,
    long forwardTimeoutSeconds,
    boolean createDatabase,
    boolean createAuditTable
) {
}

@org.springframework.stereotype.Service
class AuditService {
    private static final Logger log = LoggerFactory.getLogger(AuditService.class);
    private static final Pattern SAFE_IDENTIFIER = Pattern.compile("[A-Za-z0-9_]+");

    private final JdbcTemplate jdbc;
    private final PipelineProperties properties;
    private String auditTableName;

    AuditService(JdbcTemplate jdbc, PipelineProperties properties) {
        this.jdbc = jdbc;
        this.properties = properties;
    }

    @PostConstruct
    void initialize() {
        String databaseName = safeIdentifier(properties.databaseName(), "databaseName");
        String schemaName = safeIdentifier(properties.schemaName(), "schemaName");
        String tableName = safeIdentifier(properties.auditTableName(), "auditTableName");
        this.auditTableName = "[" + databaseName + "].[" + schemaName + "].[" + tableName + "]";

        if (properties.createDatabase()) {
            jdbc.execute("IF DB_ID(N'" + databaseName + "') IS NULL CREATE DATABASE [" + databaseName + "]");
        }

        if (properties.createAuditTable()) {
            jdbc.execute("""
                IF OBJECT_ID(N'%s.%s.%s', N'U') IS NULL
                EXEC(N'CREATE TABLE %s (
                    id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
                    event_time DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
                    service_name NVARCHAR(128) NOT NULL,
                    direction NVARCHAR(32) NOT NULL,
                    source_topic NVARCHAR(255) NULL,
                    destination_topic NVARCHAR(255) NULL,
                    message_key NVARCHAR(512) NULL,
                    payload NVARCHAR(MAX) NULL,
                    status NVARCHAR(64) NOT NULL,
                    error_message NVARCHAR(MAX) NULL
                )')
                """.formatted(databaseName, schemaName, tableName, auditTableName));
        }

        log.info("Audit database and table are ready: {}", auditTableName);
    }

    void record(String direction, String sourceTopic, String destinationTopic, String messageKey, String payload, String status, String errorMessage) {
        jdbc.update("""
            INSERT INTO %s
                (service_name, direction, source_topic, destination_topic, message_key, payload, status, error_message)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """.formatted(auditTableName),
            properties.serviceName(),
            direction,
            sourceTopic,
            destinationTopic,
            messageKey,
            payload,
            status,
            errorMessage);
    }

    private String safeIdentifier(String value, String fieldName) {
        if (value == null || !SAFE_IDENTIFIER.matcher(value).matches()) {
            throw new IllegalArgumentException(fieldName + " must contain only letters, numbers and underscore.");
        }

        return value;
    }
}

@org.springframework.stereotype.Service
class PipelineMessageHandler {
    private static final Logger log = LoggerFactory.getLogger(PipelineMessageHandler.class);

    private final PipelineProperties properties;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final AuditService auditService;

    PipelineMessageHandler(PipelineProperties properties, KafkaTemplate<String, String> kafkaTemplate, AuditService auditService) {
        this.properties = properties;
        this.kafkaTemplate = kafkaTemplate;
        this.auditService = auditService;
    }

    @KafkaListener(topics = "${pipeline.source-topic}", groupId = "${spring.kafka.consumer.group-id}")
    void consume(ConsumerRecord<String, String> record) {
        String key = record.key();
        String payload = record.value();

        log.info("Received message from topic={} partition={} offset={} key={} payload={}",
            record.topic(), record.partition(), record.offset(), key, payload);

        auditService.record("RECEIVED", record.topic(), properties.destinationTopic(), key, payload, "OK", null);

        try {
            RecordHeaders headers = copyHeaders(record);
            headers.add(new RecordHeader("processed-by", properties.serviceName().getBytes(StandardCharsets.UTF_8)));
            headers.add(new RecordHeader("source-topic", record.topic().getBytes(StandardCharsets.UTF_8)));

            ProducerRecord<String, String> producerRecord = new ProducerRecord<>(
                properties.destinationTopic(),
                null,
                key,
                payload,
                headers);

            SendResult<String, String> result = kafkaTemplate
                .send(producerRecord)
                .get(properties.forwardTimeoutSeconds(), TimeUnit.SECONDS);

            RecordMetadata metadata = result.getRecordMetadata();
            log.info("Forwarded message to topic={} partition={} offset={} key={}",
                metadata.topic(), metadata.partition(), metadata.offset(), key);

            auditService.record("FORWARDED", record.topic(), properties.destinationTopic(), key, payload, "OK", null);
        }
        catch (Exception ex) {
            log.error("Failed to forward message from {} to {}", record.topic(), properties.destinationTopic(), ex);
            auditService.record("FAILED", record.topic(), properties.destinationTopic(), key, payload, "ERROR", ex.getMessage());
            throw new IllegalStateException("Kafka forwarding failed", ex);
        }
    }

    private RecordHeaders copyHeaders(ConsumerRecord<String, String> record) {
        RecordHeaders headers = new RecordHeaders();
        for (Header header : record.headers()) {
            headers.add(header);
        }

        return headers;
    }
}

'@

$childPomTemplate = @'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>hu.alkalmassagi</groupId>
        <artifactId>alkalmassagi-pipeline</artifactId>
        <version>0.0.1-SNAPSHOT</version>
    </parent>

    <artifactId>__APP_NAME__</artifactId>
    <name>__APP_NAME__</name>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-jdbc</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.kafka</groupId>
            <artifactId>spring-kafka</artifactId>
        </dependency>
        <dependency>
            <groupId>com.microsoft.sqlserver</groupId>
            <artifactId>mssql-jdbc</artifactId>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-configuration-processor</artifactId>
            <optional>true</optional>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.springframework.kafka</groupId>
            <artifactId>spring-kafka-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
'@

for ($i = 1; $i -le 6; $i++) {
    $appName = "app$i"
    $nextTopic = if ($i -lt 6) { "app$($i + 1).source" } else { "app7.final" }
    $appDir = Join-Path $projectRoot $appName
    $sourceDir = Join-Path $appDir "src\main\java\hu\alkalmassagi\pipeline"
    $resourcesDir = Join-Path $appDir "src\main\resources"
    $securityDir = Join-Path $resourcesDir "security"
    $port = 8080 + $i

    Write-Utf8File -Path (Join-Path $appDir "pom.xml") -Content ($childPomTemplate.Replace("__APP_NAME__", $appName))
    Write-Utf8File -Path (Join-Path $sourceDir "PipelineApplication.java") -Content $javaSource
    Write-Utf8File -Path (Join-Path $securityDir "README.md") -Content @"
# Security resources

Ide kerulhetnek az app JAR-ba csomagolt JKS fajlok.

Pelda fajlnevek:

- `sqlserver-truststore.jks`
- `kafka.client.truststore.jks`
- `kafka.client.keystore.jks`
- `external-client-truststore.jks`
- `external-client-keystore.jks`

YAML hivatkozas pelda:

`classpath:security/kafka.client.truststore.jks`

JKS fajl csereje utan uj Maven build kell, mert ezek a fajlok a JAR reszei.
"@

    Remove-Item -LiteralPath (Join-Path $resourcesDir "application.properties") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $resourcesDir "application.yml") -Force -ErrorAction SilentlyContinue

    $yaml = @"
spring:
  application:
    name: $appName
  datasource:
    # Local Podman default. Change this URL when SQL Server is outside the Podman network.
    url: '`${SPRING_DATASOURCE_URL:jdbc:sqlserver://mssql:1433;databaseName=master;encrypt=false;trustServerCertificate=true}'
    username: '`${SPRING_DATASOURCE_USERNAME:sa}'
    password: '`${SPRING_DATASOURCE_PASSWORD:Alkalmassagi_2026!}'
    hikari:
      maximum-pool-size: 5
      # Example for SQL Server TLS with a JKS truststore packaged in this JAR.
      # Put the file here: src/main/resources/security/sqlserver-truststore.jks
      # Reference it as: classpath:security/sqlserver-truststore.jks
      # Some JDBC drivers expect a filesystem path for trustStore. Keep this as
      # the intended project location; adapt the driver property if needed.
      # data-source-properties:
      #   encrypt: true
      #   trustServerCertificate: false
      #   trustStore: classpath:security/sqlserver-truststore.jks
      #   trustStorePassword: changeit
      #   trustStoreType: JKS
  kafka:
    # Local Podman default. Change this when Kafka is outside the Podman network.
    bootstrap-servers: '`${SPRING_KAFKA_BOOTSTRAP_SERVERS:kafka:9092}'
    consumer:
      group-id: $appName-group
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.StringSerializer
    listener:
      ack-mode: record
    # Examples for secured Kafka. Put JKS files under:
    # src/main/resources/security/
    #
    # Direct Kafka client JKS property example:
    # properties:
    #   security.protocol: SSL
    #   ssl.truststore.location: classpath:security/kafka.client.truststore.jks
    #   ssl.truststore.password: changeit
    #   ssl.truststore.type: JKS
    #   ssl.keystore.location: classpath:security/kafka.client.keystore.jks
    #   ssl.keystore.password: changeit
    #   ssl.keystore.type: JKS
    #   ssl.key.password: changeit
    #
    # SASL/SCRAM example:
    # properties:
    #   security.protocol: SASL_SSL
    #   sasl.mechanism: SCRAM-SHA-512
    #   sasl.jaas.config: org.apache.kafka.common.security.scram.ScramLoginModule required username="user" password="password";

server:
  port: 8080

management:
  endpoints:
    web:
      exposure:
        include: health,info
  endpoint:
    health:
      probes:
        enabled: true
  health:
    kafka:
      enabled: true
    db:
      enabled: true

logging:
  level:
    root: INFO
    hu.alkalmassagi: DEBUG
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss.SSS} %-5level [%thread] %logger{36} - %msg%n"

pipeline:
  service-name: $appName
  database-name: ${appName}_audit
  schema-name: dbo
  audit-table-name: audit_events
  source-topic: $appName.source
  destination-topic: $nextTopic
  topic-partitions: 1
  topic-replicas: 1
  forward-timeout-seconds: 30
  create-database: true
  create-audit-table: true

# Example custom outbound services for future integrations.
# Nothing in the current code calls these yet, but this is the recommended
# place to configure external URLs and client TLS/security settings.
external-services:
  audit-export:
    enabled: false
    base-url: '`${AUDIT_EXPORT_BASE_URL:http://localhost:9000}'
    connect-timeout: 5s
    read-timeout: 30s
    # jks:
    #   trust-store: classpath:security/external-client-truststore.jks
    #   trust-store-password: changeit
    #   key-store: classpath:security/external-client-keystore.jks
    #   key-store-password: changeit
"@

    Write-Utf8File -Path (Join-Path $resourcesDir "application.yaml") -Content $yaml

    $readme = @"
# $appName

Consumes from Kafka topic `$appName.source`, writes audit events into SQL Server database `${appName}_audit`, then forwards the message to `$nextTopic`.

Runtime configuration lives in `src/main/resources/application.yaml`.

Health endpoint: GET /actuator/health
"@

    Write-Utf8File -Path (Join-Path $appDir "README.md") -Content $readme
}

$services = @()
for ($i = 1; $i -le 6; $i++) {
    $appName = "app$i"
    $services += [ordered]@{
        name = $appName
        projectDir = $appName
        hostPort = 8080 + $i
        containerPort = 8080
        imageTag = "local/${appName}:dev"
        env = [ordered]@{
            SPRING_PROFILES_ACTIVE = "podman"
            JAVA_OPTS = "-Xms128m -Xmx512m"
        }
    }
}

$servicesJson = $services | ConvertTo-Json -Depth 10
Write-Utf8File -Path (Join-Path $projectRoot "services.json") -Content $servicesJson

Write-Output "Generated 6 Spring Boot services in $projectRoot"
