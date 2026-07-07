# Application YAML configuration

Minden Spring Boot app sajat konfiguracios fajlja:

- `app1/src/main/resources/application.yaml`
- `app2/src/main/resources/application.yaml`
- `app3/src/main/resources/application.yaml`
- `app4/src/main/resources/application.yaml`
- `app5/src/main/resources/application.yaml`
- `app6/src/main/resources/application.yaml`

Ha mas fajlnevet szeretnel hasznalni, peldaul `application-local.yaml`, akkor
az adott app service bejegyzeseben add meg:

```json
{
  "name": "app1",
  "projectDir": "app1",
  "applicationYaml": "application-local.yaml"
}
```

Ha az `applicationYaml` csak fajlnev, akkor a script az adott app
`src/main/resources` konyvtaraban keresi. Relativ utvonal eseten a `projectDir`
konyvtarahoz kepest ertelmezi. A kontenerben mindig
`/app/config/application.yaml` neven lesz mountolva, igy Spring Boot oldalon nem
kell plusz beallitas.

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

### Kafka consumer group

```yaml
spring:
  kafka:
    consumer:
      group-id: app1-group
```

Minden consumer group ID kozvetlenul az adott app `application.yaml` fajljaban
van. A `services.json` service bejegyzeseiben nincs `consumerGroupId`.
Minden mas Spring Kafka consumer beallitas tovabbra is szabadon tarthato az
`application.yaml` fajlban.
Reszletek: `SQL-SERVER-CONNECTION.md`.

### Kafka

```yaml
spring:
  kafka:
    bootstrap-servers: '${SPRING_KAFKA_BOOTSTRAP_SERVERS:kafka:9092}'
```

Kulsos Kafka clusternel itt kell megadni a broker cimeket.

### Topicok es audit adatbazisok

```yaml
pipeline:
  resource-refs:
    database: app1Audit
  service-name: '${PIPELINE_SERVICE_NAME}'
  database-name: '${PIPELINE_DATABASE_NAME}'
  schema-name: '${PIPELINE_SCHEMA_NAME}'
  audit-table-name: '${PIPELINE_AUDIT_TABLE_NAME}'
  source-topic: app1.source
  destination-topic: app2.source
  topic-partitions: '${PIPELINE_TOPIC_PARTITIONS}'
  topic-replicas: '${PIPELINE_TOPIC_REPLICAS}'
  forward-timeout-seconds: 30
```

Az app YAML `resource-refs` blokkja most az audit adatbazis resource kulcsat
mondja meg. A Kafka topic nevek kozvetlenul az `application.yaml` fajlban
vannak, hogy az app routingja ranezesre lathato legyen.

A `services.json` tovabbra is tartalmazza a Kafka topic katalogust, mert az
infra script ebbol hozza letre es tartja karban a topicokat. Az audit
adatbazisok szinten a projekt gyokerben levo `services.json` fajlban vannak:

```json
{
  "kafkaTopics": {
    "app1Source": {
      "name": "app1.source",
      "partitions": 1,
      "replicas": 1
    }
  },
  "databases": {
    "app1Audit": {
      "name": "app1_audit",
      "schema": "dbo",
      "managed": true,
      "connectionString": "jdbc:sqlserver://mssql:1433;databaseName=app1_audit;encrypt=false;trustServerCertificate=true",
      "username": "sa",
      "password": "Alkalmassagi_2026!",
      "schemaScript": "sql/app1-audit.sql"
    }
  },
  "services": [
    {
      "name": "app1",
      "projectDir": "app1",
      "hostPort": 40005,
      "containerPort": 8080,
      "imageTag": "local/app1:dev",
      "applicationYaml": "application-local.yaml"
    }
  ]
}
```

A `scripts\deploy-springboot-pods.ps1` az app YAML `resource-refs` ertekeit
oldja fel a `services.json` adatbazis katalogusabol, es `PIPELINE_*` env
valtozokent adja at az app kontenernek. Kafka topic nevet es consumer group ID-t
nem ad at, ezek az app YAML-bol jonnek.

Fontos: a `services.json` service bejegyzeseiben nincs kozvetlen
`databaseRef`, `sourceTopicRef`, `destinationTopicRef` vagy `consumerGroupId`.
A service lista csak az app pod metadataja: nev, konyvtar, port, image, env.
Az `applicationYaml` is ide tartozik: ez csak azt mondja meg, melyik host oldali
YAML fajlt mountolja a script az app kontenerbe.

Az `auditTable` nem a `services.json` resze. Az appok a
`PIPELINE_AUDIT_TABLE_NAME` default erteket hasznaljak, ami `audit_events`.
Ha ezt at akarod irni, azt app runtime konfiguracioban tedd, ne a resource
katalogusban.

A resource-ok letrehozasat es torleset az infra script vegzi:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

Az infra script a `services.json` `kafkaTopics` es `databases` katalogusait
tekinti kezelt resource listanak. Amit korabban o kezelt, de mar nincs a
JSON-ben, azt torli. A kezelt lista state fajlja:

```text
data\managed-resources.json
```

A `schemaScript` SQL fajl minden infra inditaskor lefut az adott DB-ben. Ezert
idempotensnek kell lennie: ellenorizze, hogy a schema, tabla, oszlop, index vagy
egyeb objektum letezik-e, es csak akkor hozza letre vagy modositsa, ha kell.

Fontos: az SQL scriptek statikusak. Ne hasznalj bennuk projekt-szintu
helyettesito valtozokat vagy tokeneket. Minden adatbazishoz sajat script tartozik,
peldaul `sql/app1-audit.sql`, `sql/app2-audit.sql`.

Kulso MSSQL hasznalatahoz a database resource-ban allitsd at:

```json
"managed": false,
"connectionString": "jdbc:sqlserver://kulso-sql-ceg.local:1433;databaseName=app1_audit;encrypt=true;trustServerCertificate=false",
"username": "app1_user",
"password": "app1_password"
```

Ilyenkor az infra script nem hozza letre es nem torli az adatbazist. Az app es a
DB admin felulet viszont ezt a kapcsolati adatot hasznalja.

### Podman health check extra csomag nelkul

Az app image nem telepit `wget` vagy `curl` csomagot. Az app sajat maga frissit
egy lokalis health fajlt a Spring Actuator `HealthEndpoint` eredmenye alapjan,
a Podman health check pedig csak ezt nezi shell bepitett parancsokkal.

```yaml
local-health:
  file:
    enabled: true
    path: '${APP_HEALTH_FILE_PATH:/tmp/app-health/ready}'
    refresh-interval-ms: 5000
    initial-delay-ms: 5000
```

A deploy script alapbol ezt adja at a kontenernek:

```text
APP_HEALTH_FILE_PATH=/tmp/app-health/ready
```

Ha mas utvonalat akarsz, a `services.json` adott app `env` reszeben ugyanazt az
`APP_HEALTH_FILE_PATH` valtozot allitsd be, es az `application.yaml` is ezt fogja
hasznalni.

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
