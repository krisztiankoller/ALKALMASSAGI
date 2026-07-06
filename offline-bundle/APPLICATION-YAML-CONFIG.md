# Application YAML configuration

Minden Spring Boot app sajat konfiguracios fajlja:

- `app1/src/main/resources/application.yaml`
- `app2/src/main/resources/application.yaml`
- `app3/src/main/resources/application.yaml`
- `app4/src/main/resources/application.yaml`
- `app5/src/main/resources/application.yaml`
- `app6/src/main/resources/application.yaml`

Minden app sajat JAR-ba csomagolt security/JKS konyvtara:

- `app1/src/main/resources/security/`
- `app2/src/main/resources/security/`
- `app3/src/main/resources/security/`
- `app4/src/main/resources/security/`
- `app5/src/main/resources/security/`
- `app6/src/main/resources/security/`

Ide kerulhetnek peldaul:

- `sqlserver-truststore.jks`
- `kafka.client.truststore.jks`
- `kafka.client.keystore.jks`
- `external-client-truststore.jks`
- `external-client-keystore.jks`

YAML-bol classpath-kent hivatkozz ra:

```yaml
classpath:security/kafka.client.truststore.jks
```

A deploy script ezeket kulso Spring Boot configkent mountolja:

`/app/config/application.yaml`

Ez azt jelenti, hogy YAML-only valtoztatas utan nem kell Maven build. Eleg az app podokat ujrainditani:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 -ServicesFile .\services.json -SkipBuild
```

JKS fajl csereje utan viszont kell Maven build, mert a JKS fajlok a JAR reszei.

## Fontos mezok

### SQL Server

```yaml
spring:
  datasource:
    url: '${SPRING_DATASOURCE_URL:jdbc:sqlserver://mssql:1433;databaseName=master;encrypt=false;trustServerCertificate=true}'
    username: '${SPRING_DATASOURCE_USERNAME:sa}'
    password: '${SPRING_DATASOURCE_PASSWORD:Alkalmassagi_2026!}'
```

Kulsos SQL Serverhez itt kell atirni a hostot, portot, adatbazist es TLS beallitasokat.

Fontos kulonbseg:

```text
Podman kontenerbol: mssql:1433
Windows hostrol: localhost,40000
```

Az appok `application.yaml` fajljaiban alapbol a konteneres `mssql:1433`
kapcsolat legyen, mert az appok podban futnak. SSMS, Azure Data Studio vagy mas
Windowsos SQL kliens eseten a host portot kell hasznalni: `localhost,40000`.
Reszletek: `SQL-SERVER-CONNECTION.md`.

### Kafka

```yaml
spring:
  kafka:
    bootstrap-servers: '${SPRING_KAFKA_BOOTSTRAP_SERVERS:kafka:9092}'
```

Kulsos Kafka clusternel itt kell megadni a broker cimeket.

### Topicok es audit tabla

```yaml
pipeline:
  service-name: app1
  database-name: app1_audit
  schema-name: dbo
  audit-table-name: audit_events
  source-topic: app1.source
  destination-topic: app2.source
  topic-partitions: 1
  topic-replicas: 1
  forward-timeout-seconds: 30
  create-database: true
  create-audit-table: true
```

Itt allithato minden app sajat forras topicja, cel topicja, audit DB-je, tabla neve es topic letrehozasi parametere.

## Security peldak

Az `application.yaml` fajlok kommentben tartalmaznak peldakat, es ezek mar az app JAR-ba csomagolt `security/` konyvtarra hivatkoznak:

- SQL Server TLS/JKS truststore
- Kafka SSL JKS truststore/keystore
- Kafka SASL/SCRAM
- kulsos HTTP szolgaltatas URL es JKS helye

Ezek kommentek, tehat csak akkor aktivalodnak, ha kiveszed eloluk a `#` jelet es kitoltod a sajat ertekeidet.

## Mi nem ide tartozik?

A Podman/Maven internetes proxy beallitasa nem app runtime konfiguracio, ezert nem az appok `application.yaml` fajljaiban van.

Ha a build vagy offline export proxy mogott fut, a projekt gyokerben levo egyetlen fajlt kell kitolteni:

```text
.\proxy.config.json
```

Reszletek: `PROXY-CONFIG.md`.
