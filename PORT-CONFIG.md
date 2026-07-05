# Port configuration

Ez a dokumentum azt irja le, hol es hogyan lehet atallitani a portokat.

## Port tipusok

Ketfele port van:

- Infra host portok: SQL Server, Kafka external listener, Kafka UI, DB admin UI, log viewer UI, NiFi UI.
- App host portok: `app1` - `app6`, illetve kesobb `appN`.

A kontenerek egymas kozott a Podman networkon belul belso neveket hasznalnak, peldaul:

```text
mssql:1433
kafka:9092
app1:8080
```

Ezeket altalaban nem kell atallitani. A Windows bongeszobol vagy kulso eszkozbol hasznalt `localhost` portokat kell modositani, ha port utkozes van.

## Jelenlegi alap portok

```text
40000  SQL Server host port
40001  Kafka external host port
40002  Kafka UI host port
40003  DB admin UI host port
40004  Log viewer UI host port
40005  app1 host port
40006  app2 host port
40007  app3 host port
40008  app4 host port
40009  app5 host port
40010  app6 host port
40011  Apache NiFi UI host port
```

## Port foglaltsag ellenorzese

PowerShell:

```powershell
netstat -ano | findstr ":40000 :40001 :40002 :40003 :40004 :40005 :40006 :40007 :40008 :40009 :40010 :40011"
```

Ha egy port foglalt, vagy allitsd le a masik programot, vagy allitsd at az itt dokumentalt portot.

## Infra portok atallitasa online/local inditasnal

Pelda:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost `
  -MssqlHostPort 41000 `
  -KafkaExternalHostPort 41001 `
  -KafkaUiHostPort 41002 `
  -SqlAdminHostPort 41003 `
  -LogViewerHostPort 41004 `
  -NifiHostPort 41011
```

Ekkor ezek lesznek a bongeszoben vagy Windows hostrol hasznalhato cimek:

```text
SQL Server: localhost,41000
Kafka external: localhost:41001
Kafka UI: http://localhost:41002
DB admin UI: http://localhost:41003
Log viewer UI: http://localhost:41004
Apache NiFi UI: http://localhost:41011/nifi
```

Fontos: a kontenerek belul tovabbra is ezeket hasznaljak:

```text
mssql:1433
kafka:9092
```

Ezert az appok `application.yaml` fajljaban a Podmanon beluli alap kapcsolatokat nem kell megvaltoztatni.

## Infra portok atallitasa offline bundle inditasnal

Az offline indito ugyanazokat a kapcsolokat fogadja:

```powershell
cd "<ahova-masoltad>\offline-bundle"

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost `
  -MssqlHostPort 41000 `
  -KafkaExternalHostPort 41001 `
  -KafkaUiHostPort 41002 `
  -SqlAdminHostPort 41003 `
  -LogViewerHostPort 41004 `
  -NifiHostPort 41011
```

Ezek a portvaltoztatasok nem igenyelnek uj image buildet.

## App portok atallitasa

Az app host portok a `services.json` fajlban vannak.

Pelda `app1` alap beallitas:

```json
{
  "name": "app1",
  "projectDir": "app1",
  "hostPort": 40005,
  "containerPort": 8080,
  "imageTag": "local/app1:dev"
}
```

Ha az `app1` Windows host portjat 8181-re akarod tenni:

```json
{
  "name": "app1",
  "projectDir": "app1",
  "hostPort": 8181,
  "containerPort": 8080,
  "imageTag": "local/app1:dev"
}
```

Ekkor a health URL:

```text
http://localhost:8181/actuator/health
```

Fontos: a `containerPort` maradhat `8080`, ha az app `server.port` erteke is `8080`.

## Mikor kell a containerPortot is allitani?

Csak akkor, ha az app konteneren beluli portja is mas.

Pelda:

```yaml
server:
  port: 8090
```

Ehhez a `services.json`-ban:

```json
{
  "name": "app1",
  "hostPort": 8181,
  "containerPort": 8090,
  "imageTag": "local/app1:dev"
}
```

Ha a `server.port` es a `containerPort` nem egyezik, a pod health check es a port mapping hibazhat.

## Kafka portok

Kafka ket fontos cimet hasznal:

```text
kafka:9092          konteneren beluli appoknak
localhost:40001      Windows hostrol, Kafka UI-n kivuli klienseknek
```

Az appok alapbol ezt hasznaljak:

```yaml
spring:
  kafka:
    bootstrap-servers: '${SPRING_KAFKA_BOOTSTRAP_SERVERS:kafka:9092}'
```

Ezt nem kell atallitani, ha az appok podban futnak.

Ha Windows hostrol akarsz Kafka klienssel csatlakozni es atallitottad a host portot, akkor az uj portot hasznald:

```text
localhost:41001
```

Offline/local inditasnal ehhez:

```powershell
-KafkaExternalHostPort 41001
```

## SQL Server portok

Az appok kontenerbol ezt hasznaljak:

```text
jdbc:sqlserver://mssql:1433
```

Ez akkor is marad, ha a Windows host portot peldaul `41000`-ra allitod.

Windows hostrol DB klienssel:

```text
localhost,41000
```

## DB admin es Kafka UI URL-ek portvaltas utan

Ha ezeket adtad meg:

```powershell
-KafkaUiHostPort 41002
-SqlAdminHostPort 41003
-LogViewerHostPort 41004
-NifiHostPort 41011
```

A bongeszoben:

```text
http://localhost:41002
http://localhost:41003
http://localhost:41004
```

A `browser-start.html` es a dokumentalt fix URL-ek alap portokat mutatnak. Ha portot valtoztatsz, a bongeszoben az uj portokat kell hasznalni, vagy frissiteni kell a linkgyujtemenyt.

## LAN eleres es admin jog

`localhost` hasznalathoz nem kell admin jog.

LAN elereshez Windows firewall es portproxy kellhet. Ez admin jogot igenyel:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-lan-firewall.ps1
```

Ha infra portokat is atallitottal, add at oket:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-lan-firewall.ps1 `
  -InfraPorts @(41000, 41001, 41002, 41003, 41004, 41011)
```

Az app portokat a script a `services.json`-bol olvassa.

## Gyors peldak

Csak app port modositas:

1. Modositsd a `services.json` `hostPort` ertekeit.
2. Futtasd ujra:

```powershell
.\scripts\deploy-springboot-pods.ps1 -ServicesFile .\services.json -SkipBuild
```

Offline bundle-ben:

```powershell
.\scripts\deploy-springboot-pods.ps1 -ServicesFile .\services.json -SkipBuild
```

Infra es app port modositas offline:

```powershell
.\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost `
  -MssqlHostPort 41000 `
  -KafkaExternalHostPort 41001 `
  -KafkaUiHostPort 41002 `
  -SqlAdminHostPort 41003 `
  -LogViewerHostPort 41004 `
  -NifiHostPort 41011
```
