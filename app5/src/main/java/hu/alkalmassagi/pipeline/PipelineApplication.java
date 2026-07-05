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
