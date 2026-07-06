package hu.alkalmassagi.pipeline;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.actuate.health.HealthEndpoint;
import org.springframework.boot.actuate.health.Status;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.ContextClosedEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
class LocalHealthFileUpdater {
    private static final Logger log = LoggerFactory.getLogger(LocalHealthFileUpdater.class);

    private final HealthEndpoint healthEndpoint;
    private final boolean enabled;
    private final Path healthFilePath;

    LocalHealthFileUpdater(
        HealthEndpoint healthEndpoint,
        @Value("${local-health.file.enabled:true}") boolean enabled,
        @Value("${local-health.file.path:/tmp/app-health/ready}") String healthFilePath
    ) {
        this.healthEndpoint = healthEndpoint;
        this.enabled = enabled;
        this.healthFilePath = Path.of(healthFilePath);
    }

    @EventListener(ApplicationReadyEvent.class)
    void onApplicationReady() {
        refreshHealthFile();
    }

    @Scheduled(
        fixedDelayString = "${local-health.file.refresh-interval-ms:5000}",
        initialDelayString = "${local-health.file.initial-delay-ms:5000}"
    )
    void refreshHealthFile() {
        if (!enabled) {
            deleteHealthFile();
            return;
        }

        try {
            if (Status.UP.equals(healthEndpoint.health().getStatus())) {
                writeHealthFile();
            }
            else {
                deleteHealthFile();
            }
        }
        catch (Exception ex) {
            deleteHealthFile();
            log.warn("Health file refresh failed: {}", ex.getMessage());
        }
    }

    @EventListener(ContextClosedEvent.class)
    void onContextClosed() {
        deleteHealthFile();
    }

    private void writeHealthFile() throws IOException {
        Path parent = healthFilePath.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        Files.writeString(healthFilePath, "UP " + Instant.now());
    }

    private void deleteHealthFile() {
        try {
            Files.deleteIfExists(healthFilePath);
        }
        catch (IOException ex) {
            log.debug("Could not delete health file {}: {}", healthFilePath, ex.getMessage());
        }
    }
}
