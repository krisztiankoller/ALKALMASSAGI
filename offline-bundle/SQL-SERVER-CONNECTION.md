# SQL Server connection

Ez a dokumentum azt irja le, hogyan lehet az MSSQL szerverhez csatlakozni
Windows hostrol, Podman kontenerbol es a webes DbGate SQL adminbol.

## Windows hostrol

Ha az alap portokat hasznalod, a Windows gepen futo kliensbol ezt add meg:

```text
Server: localhost,40000
User: sa
Password: Alkalmassagi_2026!
Trust server certificate: yes
Encrypt: optional / false
```

SSMS vagy Azure Data Studio beallitas:

```text
Server name: localhost,40000
Authentication: SQL Login
Login / User name: sa
Password: Alkalmassagi_2026!
Trust server certificate: checked
Encrypt: optional vagy false
```

Connection string pelda:

```text
Server=localhost,40000;Database=master;User Id=sa;Password=Alkalmassagi_2026!;TrustServerCertificate=True;Encrypt=False;
```

Az app audit adatbazisok:

```text
app1_audit
app2_audit
app3_audit
app4_audit
app5_audit
app6_audit
```

Ha mas SQL host portot adtal meg, peldaul `-MssqlHostPort 41000`, akkor a
Windows hostrol hasznalt cim:

```text
localhost,41000
```

## Podman kontenerekbol

A kontenerek a Podman `devnet` halozaton belul nem a Windows host portot
hasznaljak, hanem a belso DNS nevet es portot:

```text
mssql:1433
```

Spring Boot JDBC URL pelda:

```text
jdbc:sqlserver://mssql:1433;databaseName=app1_audit;encrypt=false;trustServerCertificate=true
```

Ez akkor is marad `mssql:1433`, ha Windows host oldalon atallitod a portot
40000-rol masikra.

## Webes SQL admin

A DbGate SQL admin jelszo nelkul nyilik:

```text
http://localhost:40003
```

Elore beallitott kapcsolatok:

```text
Local MSSQL
app1_audit
app2_audit
app3_audit
app4_audit
app5_audit
app6_audit
```

A DbGate kontener maga is a belso `mssql:1433` cimen kapcsolodik az SQL
szerverhez. A script automatikusan atadja neki az `ENGINE_*`, `SERVER_*`,
`DATABASE_*`, `USER_*`, `PASSWORD_*` es `PORT_*` beallitasokat.

## Gyors ellenorzes PowerShellbol

Port figyeles ellenorzese:

```powershell
netstat -ano | findstr ":40000"
```

MSSQL kontener allapot:

```powershell
podman ps --filter name=mssql
```

Adatbazisok ellenorzese a kontener sajat `sqlcmd` eszkozevel:

```powershell
podman exec mssql /opt/mssql-tools18/bin/sqlcmd `
  -S localhost `
  -U sa `
  -P "Alkalmassagi_2026!" `
  -C `
  -Q "select name from sys.databases where name like 'app%_audit' or name='master' order by name"
```

DbGate konfiguracio ellenorzese:

```powershell
podman exec sql-admin sh -lc "env | sort | grep -E '^(CONNECTIONS|ENGINE_|SERVER_|DATABASE_|USER_|PORT_)'"
```

## Ha nem tudsz csatlakozni

Ellenorizd ezt a sorrendet:

1. Fut-e az MSSQL kontener: `podman ps --filter name=mssql`
2. Szabad-e es figyel-e a host port: `netstat -ano | findstr ":40000"`
3. Jo-e a kliensben a szervernev: `localhost,40000`
4. SQL Login van-e kivalasztva, nem Windows Authentication
5. A `sa` jelszo ugyanaz-e, amivel inditottad a stacket
6. Be van-e kapcsolva a `Trust server certificate`
7. Ha portot allitottal, a kliensben is az uj portot hasznalod-e

## MSSQL indulasi hiba uj gepen: `/.system` Access Denied

Hiba pelda:

```text
Error The system directory [/.system] could not be created
File LinuxDirectory.cpp 420 Access Denied
```

Ok: az SQL Server Linux kontener nem root felhasznalokent fut. Uj gepen vagy
regi Podman volume ujrahasznositasakor elofordulhat, hogy az `mssql-data`
volume tulajdonosa/jogosultsaga nem irhato a kontener SQL Server
felhasznalojanak.

A friss `deploy-infra-pods.ps1` ezt automatikusan javitja:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

Offline bundle alol:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

Mit csinal a script:

- ha hianyzik, az `mssql-data` volume-ot SQL Server-kompatibilis
  tulajdonossal hozza letre;
- ha mar letezik, egy rovid root helper kontenerrel beallitja a volume-on:
  `chown -R 10001:0` es `chmod -R g=u`;
- hozzaadja az MSSQL kontenerhez a `HOME=/var/opt/mssql` beallitast.

Ez nem torli az adatbazisokat. Csak a volume jogosultsagait javitja.

Csak akkor torold a volume-ot, ha biztosan nullarol akarod kezdeni es nem kell
semmilyen korabbi SQL adat:

```powershell
podman pod rm -f mssql-pod
podman volume rm mssql-data
```

Ezutan futtasd ujra az infra vagy offline indito scriptet.

## MSSQL verzio downgrade: `A downgrade path is not supported`

Hiba pelda:

```text
The database 'master' cannot be opened because it is version 957.
This server supports version 904 and earlier.
A downgrade path is not supported.
```

Ok: az `mssql-data` volume ujabb SQL Serverrel keszult, mint amit most
inditasz. Pelda: SQL Server 2022 utan SQL Server 2019 image-et hasznalsz.

A friss script ezt automatikusan kezeli, mert ebben a local/offline stackben az
SQL adat nullarol is indulhat:

- felismeri a downgrade hibauzenetet az MSSQL logban;
- torli csak az `mssql-data` volume-ot;
- ujraletrehozza jo jogosultsaggal;
- ujrainditja az MSSQL podot tiszta adatbazissal.

Ez SQL adatvesztessel jar, de Kafka/NiFi/log adatot nem torol.

Ha `run-offline.ps1`-t hasznalsz, az app podok ujraindulnak az infra utan. Ha
kezzel csak `deploy-infra-pods.ps1` futott, utana inditsd ujra az appokat is,
hogy az audit DB-k es tablak ujra letrejojjenek:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json `
  -SqlPassword "Alkalmassagi_2026!" `
  -SkipBuild
```

Ha nem akarod, hogy automatikusan torolje az SQL adatot, inditsd igy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost `
  -KeepMssqlDataOnVersionMismatch
```
