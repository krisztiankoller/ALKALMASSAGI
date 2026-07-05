# app1

Consumes from Kafka topic $appName.source, writes audit events into SQL Server database ${appName}_audit, then forwards the message to $nextTopic.

Runtime configuration lives in src/main/resources/application.yaml.

Health endpoint: GET /actuator/health