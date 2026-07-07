# Add a new appN service

Ez a dokumentum azt irja le, hogyan lehet uj Spring Boot alkalmazast hozzaadni a jelenlegi Podman/Kafka/SQL/offline projekthez.

Pelda uj app:

```text
app7
```

## Mitol mukodik egy app ebben a rendszerben?

Egy app akkor illeszkedik jol, ha:

- Spring Boot JAR-t lehet belole buildelni.
- Van health endpointja: `/actuator/health`.
- Podman kontenerben `server.port` szerint hallgat.
- Kafka-bol olvas egy source topicot.
- Kafka-ba tovabbit egy destination topicot.
- SQL Serverbe audit sort ir.
- Minden kapcsolat `application.yaml`-bol vagy environment variable-bol jon.
- A konkret Kafka topic es audit DB nevek a `services.json`-ban vannak.
- Van `src/main/resources/security` konyvtara JKS fajloknak.

## App nev konvencio

Javasolt nev:

```text
app7
app8
app9
```

Keruld a szokozos es specialis karakteres neveket, mert a nevbol lesz:

- Podman container nev
- Podman network alias
- DBGate connection key
- audit adatbazis nev alapja

Jo:

```text
app7
customer
payment
```

Kerulendo:

```text
customer-service-v2
customer service
customer.service
```

## 1. App konyvtar elhelyezese

Ha uj appot hozol letre ebben a projektben:

```text
.\app7
```

Ha az app mar letezik egy masik repoban, ket egyszeru lehetoseg van:

1. Masold be a repo tartalmat `.\app7` ala.
2. Tartsd kulon, de akkor a `services.json` `projectDir` erteke mutasson arra a konyvtarra.

A hordozhatosag miatt a legjobb, ha az app a projektmappan belul van:

```text
.\app7
```

Igy a teljes projekt fajlmasolassal atviheto masik gepre.

## 2. Root pom.xml frissitese

Ha a `scripts\build-apps-with-podman.ps1` scriptet akarod hasznalni, az uj app legyen Maven module a root `pom.xml`-ben.

Pelda:

```xml
<modules>
    <module>app1</module>
    <module>app2</module>
    <module>app3</module>
    <module>app4</module>
    <module>app5</module>
    <module>app6</module>
    <module>app7</module>
</modules>
```

Ha a letezo repo sajat parent POM-mal mukodik, ket ut van:

- Beilleszted Maven module-kent es igazodsz a root POM-hoz.
- Kulon buildelt JAR-t hasznalsz, es a `services.json`-ban megadod a `jarPath` mezot.

Offline, host Java/Maven nelkuli mukodeshez a Maven module-os megoldas a legkenyelmesebb.

## 3. App pom.xml kovetelmenyek

Minimum hasznos dependency-k:

```xml
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
```

Spring Boot repackage plugin:

```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
        </plugin>
    </plugins>
</build>
```

## 4. application.yaml

Az uj appban legyen:

```text
app7\src\main\resources\application.yaml
```

Ha mas runtime konfiguracio fajlnevet szeretnel, hasznalhatsz peldaul ilyet is:

```text
app7\src\main\resources\application-local.yaml
```

Ekkor a `services.json` app7 service bejegyzeseben add meg:

```json
"applicationYaml": "application-local.yaml"
```

A deploy script ezt a fajlt mountolja majd a kontenerbe
`/app/config/application.yaml` neven, ezert a Spring Boot alkalmazasnak nem kell
tudnia a host oldali fajlnevrol.

Fontos reszek:

```yaml
spring:
  application:
    name: app7
  datasource:
    url: '${SPRING_DATASOURCE_URL:jdbc:sqlserver://mssql:1433;databaseName=master;encrypt=false;trustServerCertificate=true}'
    username: '${SPRING_DATASOURCE_USERNAME:sa}'
    password: '${SPRING_DATASOURCE_PASSWORD:Alkalmassagi_2026!}'
  kafka:
    bootstrap-servers: '${SPRING_KAFKA_BOOTSTRAP_SERVERS:kafka:9092}'
    consumer:
      group-id: app7-group
      auto-offset-reset: earliest

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

local-health:
  file:
    enabled: true
    path: '${APP_HEALTH_FILE_PATH:/tmp/app-health/ready}'
    refresh-interval-ms: 5000
    initial-delay-ms: 5000

pipeline:
  resource-refs:
    database: app7Audit
  service-name: '${PIPELINE_SERVICE_NAME}'
  database-name: '${PIPELINE_DATABASE_NAME}'
  schema-name: '${PIPELINE_SCHEMA_NAME}'
  audit-table-name: '${PIPELINE_AUDIT_TABLE_NAME}'
  source-topic: app7.source
  destination-topic: app8.final
  topic-partitions: '${PIPELINE_TOPIC_PARTITIONS}'
  topic-replicas: '${PIPELINE_TOPIC_REPLICAS}'
  forward-timeout-seconds: 30
```

Fontos: az adatbazis `PIPELINE_*` ertekeit nem kezzel kell Windows env-be
allitani. A `scripts\deploy-springboot-pods.ps1` az app YAML `resource-refs`
adatbazis referenciat oldja fel a `services.json` resource katalogusabol. A
Kafka topic nevek es a consumer group ID kozvetlenul az app YAML-ben vannak.

## 5. Kafka lanc frissitese

Ha az uj appot a jelenlegi lanc vegere teszed:

Eddig:

```text
app1.source -> app2.source -> app3.source -> app4.source -> app5.source -> app6.source -> app7.final
```

Uj `app7`-tel:

```text
app1.source -> app2.source -> app3.source -> app4.source -> app5.source -> app6.source -> app7.source -> app8.final
```

Ehhez az app6 `application.yaml` fajljaban modositsd a cel topic nevet:

```yaml
pipeline:
  destination-topic: app7.source
```

Az uj app7 `application.yaml` pedig igy induljon tovabb:

```yaml
pipeline:
  source-topic: app7.source
  destination-topic: app8.final
```

## 6. Security/JKS konyvtar

Legyen:

```text
app7\src\main\resources\security
```

Ide kerulhetnek:

```text
sqlserver-truststore.jks
kafka.client.truststore.jks
kafka.client.keystore.jks
rest-client-truststore.jks
rest-client-keystore.jks
soap-client-truststore.jks
soap-client-keystore.jks
```

YAML hivatkozas:

```yaml
classpath:security/rest-client-truststore.jks
```

## 7. services.json frissitese

Adj hozza a topicot a `kafkaTopics` katalogushoz:

```json
"app7Source": {
  "name": "app7.source",
  "partitions": 1,
  "replicas": 1
},
"app8Final": {
  "name": "app8.final",
  "partitions": 1,
  "replicas": 1
}
```

Adj hozza az audit adatbazist a `databases` katalogushoz:

```json
"app7Audit": {
  "name": "app7_audit",
  "schema": "dbo",
  "managed": true,
  "connectionString": "jdbc:sqlserver://mssql:1433;databaseName=app7_audit;encrypt=false;trustServerCertificate=true",
  "username": "sa",
  "password": "Alkalmassagi_2026!",
  "schemaScript": "sql/app7-audit.sql"
}
```

A `schemaScript` mindig app/DB-specifikus, statikus SQL fajl legyen. Ne legyen
benne token vagy helyettesito valtozo. A lenyeg, hogy tobbszor is lefuthasson
hiba es duplikalt objektum letrehozasa nelkul.

Kulso adatbazisnal:

```json
"app7Audit": {
  "name": "app7_audit",
  "schema": "dbo",
  "managed": false,
  "connectionString": "jdbc:sqlserver://kulso-sql-ceg.local:1433;databaseName=app7_audit;encrypt=true;trustServerCertificate=false",
  "username": "app7_user",
  "password": "app7_password",
  "schemaScript": "sql/app7-audit.sql"
}
```

`managed: false` eseten a lokalis infra script nem hozza letre es nem torli a DB-t.
Az app es a DB admin kapcsolat ettol meg a megadott `connectionString`,
`username`, `password` ertekekkel fog menni.

Idempotens SQL pelda:

```sql
USE [app7_audit];

IF OBJECT_ID(N'dbo.audit_events', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[audit_events] (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY
    );
END;
```

Vegul adj hozza uj service bejegyzest a `services` listahoz:

```json
{
      "name": "app7",
      "projectDir": "app7",
      "hostPort": 40012,
      "containerPort": 8080,
      "imageTag": "local/app7:dev",
      "applicationYaml": "application.yaml",
      "env": {
        "SPRING_PROFILES_ACTIVE": "podman",
        "JAVA_OPTS": "-Xms128m -Xmx512m"
  }
}
```

Ha a JAR nem a szokasos `target` konyvtarban van, adhatsz meg `jarPath`-ot:

```json
{
  "name": "app7",
  "projectDir": "app7",
  "jarPath": "app7/target/app7-0.0.1-SNAPSHOT.jar",
  "hostPort": 40012,
  "containerPort": 8080,
  "imageTag": "local/app7:dev",
  "applicationYaml": "application-local.yaml"
}
```

Fontos: a service bejegyzesben nincs `databaseRef`, `sourceTopicRef` vagy
`destinationTopicRef`, es nincs `consumerGroupId` sem. A Kafka topic nevek es a
consumer group ID az app sajat `application.yaml` fajljaban vannak.
Az `applicationYaml` csak a host oldali runtime YAML fajlnevet valasztja ki.

## 8. DB admin kapcsolat

A `scripts\deploy-infra-pods.ps1` a `services.json` `databases` katalogusa
alapjan epiti a DB admin kapcsolatokat, es ugyanitt hozza letre az audit
adatbazisokat/táblákat.

Ha van `app7Audit` a `services.json` `databases` reszeben, akkor a DB admin
UI-ban megjelenik:

```text
app7_audit
```

A kapcsolat az SQL Server `app7_audit` adatbazisara mutat.

Emlkezteto SQL cimekhez:

```text
Az app podbol: mssql:1433
Windows hostrol / SSMS / Azure Data Studio: localhost,40000
```

Reszletes SQL kapcsolodasi leiras: `SQL-SERVER-CONNECTION.md`.

## 9. Build

Host Java/Maven nelkul:

Ha Maven dependency-ket proxy mogott kell letolteni, elobb toltsd ki a projekt gyokerben a `proxy.config.json` fajlt. A build parancs nem valtozik.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 -SkipTests
```

Ez Podman alatt, a `java-build-pod` podban futtatja a Maven buildet.

## 10. App image-ek es podok inditasa

Ha mar megvan az infra:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json
```

Ha az image-ek mar keszen vannak es csak ujrainditas kell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json `
  -SkipBuild
```

## 11. Offline bundle ujrageneralasa

Ha uj appot adsz hozza, mindig uj offline bundle kell:

Ha a gep proxy mogott van, a `proxy.config.json` legyen kitoltve es `enabled: true`. Az export script automatikusan olvassa.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests
```

Mit jelent az, hogy bekerul az uj app image?

A `services.json` minden apphoz tartalmaz egy `imageTag` mezot. App7 pelda:

```text
local/app7:dev
```

Ez nem fajlnev es nem konyvtarnev, hanem a helyi Podman image neve.

Pelda `services.json` reszlet:

```json
{
  "name": "app7",
  "projectDir": "app7",
  "hostPort": 40012,
  "containerPort": 8080,
  "imageTag": "local/app7:dev",
  "env": {
    "SPRING_PROFILES_ACTIVE": "podman",
    "JAVA_OPTS": "-Xms128m -Xmx512m"
  }
}
```

Az `app7Audit` DB kapcsolat nem itt van, hanem az
`app7\src\main\resources\application.yaml` `pipeline.resource-refs` reszeben.
A Kafka routing ugyanabban az `application.yaml` fajlban kozvetlen topic nevvel
szerepel, peldaul `source-topic: app7.source` es `destination-topic: app8.final`.

Az export script ezt csinalja:

1. Megnezi a `services.json` fajlban az app7 bejegyzest.
2. Megkeresi az app7 JAR-t, peldaul:

```text
app7\target\app7-0.0.1-SNAPSHOT.jar
```

3. A `Containerfile.spring-boot-jar` alapjan Podman image-et buildel belole.
4. Az image neve az lesz, amit az `imageTag` mezoben megadtal:

```text
local/app7:dev
```

5. Ezt az image-et is beleteszi az offline image archive-ba:

```text
offline-bundle\images\podman-images.tar
```

Ezert kell uj offline bundle, ha uj appot adsz hozza. A masik gep internet nelkul csak abbol tud dolgozni, ami ebben a tar fajlban benne van.

Ha nem `app7`, hanem mas nev kell, akkor mindharom helyen legyen kovetkezetes:

```text
name: appN
projectDir: appN
imageTag: local/appN:dev
```

Ha egy letezo repo neve mas, peldaul `customer-service`, akkor lehet ilyen is:

```json
{
  "name": "customer-service",
  "projectDir": "customer-service",
  "hostPort": 40012,
  "containerPort": 8080,
  "imageTag": "local/customer-service:dev"
}
```

Ilyenkor a pod neve `customer-service-pod`, a kontener neve `customer-service`, az image neve pedig `local/customer-service:dev` lesz.

Ellenorzes a forras gepen export utan:

```powershell
podman image exists local/app7:dev
if ($LASTEXITCODE -eq 0) { "OK: local/app7:dev letezik" }
```

Az offline target gepre utana a teljes `offline-bundle` mappat kell atmasolni.

## 12. Ellenorzes

Pod:

```powershell
podman pod ps
```

App health:

```text
http://localhost:40012/actuator/health
```

Kafka UI:

```text
http://localhost:40002
```

DB admin UI:

```text
http://localhost:40003
```

Log:

```powershell
podman logs app7
```

Webes log viewer:

```text
http://localhost:40004
```

Apache NiFi file-to-Kafka:

```text
http://localhost:40011/nifi
```

Ha az uj apphoz uj Kafka topic is kell, add hozza a `nifi-flows.yaml`
`flows` listajahoz, majd generald ujra a NiFi flow-t:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-nifi-file-to-kafka.ps1
```

## 13. Letezo repo illesztese checklist

Ha az `app7` mar letezik valahol repokent, ezt nezd vegig:

- Spring Boot JAR buildelheto Mavenbol.
- Java verzio kompatibilis a builder image-dzsel.
- Van `/actuator/health`.
- Van YAML konfiguracio, alapbol `application.yaml`. Ha mas a neve, a
  `services.json` service bejegyzesben szerepel az `applicationYaml`.
- DB kapcsolat YAML-bol jon.
- Kafka bootstrap YAML-bol jon.
- Topic nevek es consumer group ID az app YAML-ben vannak.
- Az audit DB kapcsolati adatai a `services.json` adatbazis katalogusabol jonnek.
- App port YAML-bol jon.
- JKS fajlok `src/main/resources/security` alatt vannak.
- Proxy beallitas nincs a forrasba egetve; ha kell, a projekt gyokerben levo `proxy.config.json` kezeli.
- Nincs beegetett abszolut Windows utvonal.
- Nincs beegetett gepnev/IP, amit masik gepen at kellene irni.
- `services.json` tartalmazza az appot.
- `services.json` `kafkaTopics` tartalmazza az uj source/cel topicokat.
- `services.json` `databases` tartalmazza az uj audit adatbazist.
- `nifi-flows.yaml` tartalmazza az apphoz tartozo file-to-Kafka topicot, ha fajlbol is akarsz uzenetet kuldeni ra.
- Root `pom.xml` tartalmazza Maven module-kent, vagy `services.json` tartalmaz `jarPath`-ot.
- Offline bundle ujra lett generalva.

## 14. Gyakori hibak

### Missing application YAML

Az app alatt nincs:

```text
src\main\resources\application.yaml
```

Megoldas: hozd letre, vagy javitsd a `services.json` `projectDir` /
`applicationYaml` erteket.

### No runnable JAR found

Nincs buildelt JAR az app `target` konyvtaraban.

Megoldas:

```powershell
.\scripts\build-apps-with-podman.ps1 -SkipTests
```

Vagy adj meg `jarPath`-ot a `services.json`-ban.

### Health check nem indul

Ellenorizd:

- `server.port`
- `services.json` `containerPort`
- actuator dependency
- `/actuator/health` exposure

### DB adminban nem latszik az app adatbazisa

Ellenorizd, hogy az app szerepel-e a `services.json`-ban, majd futtasd ujra az infrat:

```powershell
.\scripts\deploy-infra-pods.ps1 -SqlPassword "Alkalmassagi_2026!" -ExternalHostName localhost
```

Offline bundle-ben:

```powershell
.\scripts\run-offline.ps1 -SqlPassword "Alkalmassagi_2026!" -ExternalHostName localhost
```
