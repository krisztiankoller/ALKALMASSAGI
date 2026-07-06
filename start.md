# Start guide - offline Podman stack 

Ez a dokumentum azt irja le, hogyan kell a teljes rendszert atvinni es elinditani egy masik Windows gepen ugy, hogy azon csak Podman legyen telepitve, internet ne legyen, Java/Maven ne legyen, es Windows admin jog se kelljen.

## Uj gep develop branchbol, internet/proxy mellett

Ezt hasznald akkor, ha az uj gepen a GitHub `develop` branch van meg, nincs meg kesz
`offline-bundle\images\podman-images.tar`, es ezen a gepen kell mindent letolteni,
leforditani, image-et epiteni, offline bundle-t generalni, majd elinditani.

Feltetelek:

```text
Podman Desktop vagy Podman CLI telepitve van
Podman machine / WSL backend mukodik
internet elerheto, ha kell proxy mogott
Java es Maven NEM kell a host gepre
admin jog NEM kell localhost hasznalathoz
```

Ha a projekt ZIP-kent vagy bongeszobol letoltve kerult a gepre, a Windows
megjelolheti a `.ps1` fajlokat internetrol letoltottkent. Ez okozza a
`not digitally signed` PowerShell hibat. Ezert az elso lepes mindig az unblock.

Nyiss egy normal, nem admin PowerShell ablakot, menj a projekt gyokerebe, majd
futtasd ezt a teljes blokkot:

```powershell
cd "<ahova-klonoztad-vagy-kicsomagoltad>\ALKALMASSAGI"

# Ha a fajlok internetrol letoltottnek vannak jelolve, ez leveszi a blokkot.
Get-ChildItem -Recurse -File | Unblock-File

# Podman machine inditasa. Ha meg nincs letrehozva, elobb inicializalja.
podman machine start
if ($LASTEXITCODE -ne 0) {
  podman machine init
  podman machine start
}

podman info

# Build + image pull + app image build + offline bundle generalas.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests

# A frissen generalt offline bundle inditasa localhost-only modban.
powershell -NoProfile -ExecutionPolicy Bypass -File .\offline-bundle\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost

podman pod ps
podman ps --pod
```

Ha proxy mogott vagy, elotte toltsd ki a projekt gyokereben:

```text
.\proxy.config.json
```

Pelda:

```json
{
  "enabled": true,
  "httpProxy": "http://proxy.ceg.local:8080",
  "httpsProxy": "http://proxy.ceg.local:8080",
  "username": "DOMAIN\\user",
  "password": "secret",
  "podmanTlsVerify": false,
  "mavenTlsVerify": false,
  "noProxy": [
    "localhost",
    "127.0.0.1",
    ".ceg.local",
    "mssql",
    "kafka",
    "kafka-ui",
    "sql-admin",
    "nifi",
    "app1",
    "app2",
    "app3",
    "app4",
    "app5",
    "app6"
  ]
}
```

Fontos: a `podmanTlsVerify: false` csak akkor kell, ha ceges TLS inspection/proxy
miatt ilyen Podman hibat kapsz:

```text
tls: failed to verify certificate: x509
certificate signed by unknown authority
```

Ez a Podman `pull` es `build` parancsokhoz automatikusan hozzaadja:

```text
--tls-verify=false
```

Ha nincs ilyen cert hiba, hagyd `true` erteken.

Ha a hiba Maven dependency letoltes kozben jon, akkor a `mavenTlsVerify: false`
kapcsolo adja hozza a Maven TLS workaround parametereket. Ha nincs Maven cert
hiba, ezt is hagyd `true` erteken.

## Teljes ujraepites es inditas sorban

Ezt hasznald akkor, ha a `develop` branch megvan a gepen, van internet vagy
beallitott proxy, es mindent nullarol ujra akarsz epiteni, majd azonnal
elinditani Podman alatt.

### 1. Projekt mappa es PowerShell unblock

```powershell
cd "<ahova-klonoztad-vagy-kicsomagoltad>\ALKALMASSAGI"

Get-ChildItem -Recurse -File | Unblock-File
```

### 2. Podman machine ellenorzes

```powershell
podman machine list
podman machine start
podman info
```

Ha a `podman machine start` azt irja, hogy a machine mar fut, az nem gond.
Ha azt irja, hogy nincs machine, akkor egyszer kell inicializalni:

```powershell
podman machine init
podman machine start
podman info
```

### 3. Infrastrukturapodok inditasa

Ez inditja vagy ujrainditja az MSSQL, Kafka, Kafka UI, DbGate, Dozzle es NiFi
podokat. A hasznalt portok alapbol 40000-tol indulnak.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

### 4. Java appok forditasa host Java/Maven nelkul

Ez Podman kontenerben futtatja a Mavent, ezert a Windows host gepre nem kell
Java es nem kell Maven.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -SkipTests
```

### 5. App image-ek epitese es app podok inditasa

Ez ujraepiti a `local/app1:dev` - `local/app6:dev` image-eket, majd elinditja
az app podokat.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json
```

Ha a JAR-ok mar frissek, es csak ujra akarod inditani az app podokat:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json `
  -SkipBuild
```

### 6. Ellenorzes

```powershell
podman pod ps
podman ps --pod

Invoke-WebRequest http://localhost:40002 -UseBasicParsing
Invoke-WebRequest http://localhost:40003 -UseBasicParsing
Invoke-WebRequest http://localhost:40004 -UseBasicParsing
Invoke-WebRequest http://localhost:40011/nifi/ -UseBasicParsing

1..6 | ForEach-Object {
  $port = 40004 + $_
  Invoke-RestMethod "http://localhost:$port/actuator/health"
}
```

Kafka pipeline teszt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\send-test-message.ps1
```

Ezutan nezd meg:

```text
Kafka UI -> app7.final topic
DB admin UI -> app1_audit ... app6_audit -> audit_events tabla
Dozzle -> app1 ... app6, kafka, mssql, nifi logok
```

### 7. Offline bundle ujrageneralasa

Ha azt akarod, hogy a mostani allapot masik gepre is atviheto legyen internet
nelkul, generald ujra az offline bundle-t:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests
```

Ez a vegeredmeny:

```text
.\offline-bundle\images\podman-images.tar
```

Ha a JAR-ok es a `local/appN:dev` image-ek mar frissen megvannak, es csak a tar
bundle-t akarod ujracsomagolni:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipJavaBuild
```

## Mikor melyik parancs kell?

Teljes forrasbol ujraepites es inditas:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 -SqlPassword "Alkalmassagi_2026!" -ExternalHostName localhost
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 -SkipTests
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 -ServicesFile .\services.json
```

Csak app forraskod valtozott:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 -SkipTests
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 -ServicesFile .\services.json
```

Csak app YAML/JKS vagy `services.json` valtozott:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 -ServicesFile .\services.json
```

Csak infra/NiFi/port/proxy konfiguracio valtozott:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 -SqlPassword "Alkalmassagi_2026!" -ExternalHostName localhost
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 -ServicesFile .\services.json -SkipBuild
```

Masik gepen, offline bundle-bol inditas:

```powershell
cd "<ahova-masoltad>\offline-bundle"
Get-ChildItem -Recurse -File | Unblock-File
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

## Mit csinalnak a fo scriptek?

`scripts\deploy-infra-pods.ps1`:

- letrehozza a `devnet` Podman networkot, ha hianyzik;
- letrehozza vagy javitja az `mssql-data` volume jogosultsagait az SQL Server
  nem-root kontener felhasznalojahoz;
- felismeri az MSSQL adatbazisverzio inkompatibilitast, peldaul amikor egy
  SQL Server 2022-vel keszult `mssql-data` volume-ot SQL Server 2019-cel
  inditanal, es alapbol torli/ujraletrehozza az `mssql-data` volume-ot;
- elinditja az MSSQL, Kafka, Kafka UI, DbGate, Dozzle es NiFi podokat;
- beallitja a DbGate kapcsolatokat az app adatbazisokhoz;
- letrehozza vagy frissiti a NiFi fajlbol Kafka-ba kuldo flow konfiguraciot;
- nem fordit Java kodot.

`scripts\build-apps-with-podman.ps1`:

- elinditja a `java-build-pod` build podot;
- a Maven builder image explicit `podman pull` muveletet alapbol 5-szor probalja;
- a `mvn clean package` futast is alapbol 5-szor probalja, ha Maven/proxy
  letoltesi hiba miatt megallna, de `-MavenBuildRetries 1` kapcsoloval
  egy probalkozasra allithato;
- Maven/JDK kontenerrel forditja az `app1` - `app6` modulokat;
- a Maven cache-t a projekt alatt tartja: `data\maven-repo`;
- a build logot a projekt alatt tartja: `data\build-logs\current.log`;
- Dozzle-ban lathato build log tailert indit: `java-build-log-viewer`;
- a Maven build kontenert alapbol torli a build vegen, de `-KeepBuildContainer`
  kapcsoloval megtarthato `java-maven-builder` neven;
- nem inditja el az app podokat.

`scripts\deploy-springboot-pods.ps1`:

- a kesz JAR-okbol Podman image-et epit: `local/app1:dev` - `local/app6:dev`;
- elinditja az app podokat;
- a `services.json` alapjan oszt portot, app nevet es kornyezeti beallitast.

`scripts\export-offline-bundle.ps1`:

- letolti vagy ellenorzi a szukseges infra image-eket;
- minden explicit `podman pull` muveletet alapbol 5-szor probal, mielott
  hibaval megall;
- buildeli a Java appokat es app image-eket;
- elmenti az osszes image-et az `offline-bundle\images\podman-images.tar` fajlba;
- bemasolja az inditashoz szukseges scripteket, configokat es dokumentaciot.

`offline-bundle\scripts\run-offline.ps1`:

- betolti az image-eket a `podman-images.tar` fajlbol;
- elinditja az infrat;
- elinditja az app podokat;
- internetet, Java-t es Maven-t nem igenyel a host gepen.

## Mit kell atmasolni?

A teljes projektmappat masold at, vagy legalabb az `offline-bundle` mappat.

A legfontosabb fajl:

```text
.\offline-bundle\images\podman-images.tar
```

Ez tartalmazza az osszes kontener image-et. Internet nelkul ezert tud mukodni a rendszer: a masik gep nem letolti az image-eket, hanem ebbol a tar fajlbol tolti be oket a helyi Podman image store-ba.

## Mi van az image tar-ban?

Az `.\offline-bundle\images\podman-images.tar` jelenleg ezeket tartalmazza:

```text
mcr.microsoft.com/mssql/server:2019-latest
apache/kafka-native:3.9.0
apache/kafka:3.9.0
ghcr.io/kafbat/kafka-ui:latest
dbgate/dbgate:latest
amir20/dozzle:latest
eclipse-temurin:21-jre-alpine
maven:3.9.9-eclipse-temurin-21
local/app1:dev
local/app2:dev
local/app3:dev
local/app4:dev
local/app5:dev
local/app6:dev
```

Ezert nem kell internet a masik gepen.

## Ha a forras gep internetes, de proxy mogott van

Offline bundle kesziteshez ilyenkor egyetlen fajlt kell kitolteni:

```text
.\proxy.config.json
```

Allitsd:

```json
{
  "enabled": true,
  "httpProxy": "http://proxy.ceg.local:8080",
  "httpsProxy": "http://proxy.ceg.local:8080",
  "username": "DOMAIN\\user",
  "password": "secret"
}
```

Ezutan ugyanazokat a build/export parancsokat hasznald. A scriptek automatikusan olvassak a `proxy.config.json` fajlt.

Reszletek:

```text
.\PROXY-CONFIG.md
```

A kitoltott `proxy.config.json` jelszot tartalmazhat, ezert nem kerul automatikusan az `offline-bundle` mappaba. A kesz offline bundle futtatasahoz nincs szukseg proxyra.

## Mi kell a masik Windows gepen?

Kell:

```text
Podman Desktop vagy Podman CLI
mukodo Podman machine / WSL backend
eleg szabad lemezhely
szabad localhost portok
```

Nem kell:

```text
Java
Maven
internet
Windows admin jog
Docker
```

Admin jog csak akkor kellene, ha LAN-rol is el akarod erni a szolgaltatasokat es Windows firewall / portproxy beallitast akarsz csinalni. `localhost` hasznalathoz nem kell.

## Szukseges portok

Ezeknek szabadnak kell lenniuk a masik gepen:

```text
40000  SQL Server
40005  app1
40006  app2
40007  app3
40008  app4
40009  app5
40010  app6
40002  Kafka UI
40003  DB admin UI
40004  Log viewer UI
40011  Apache NiFi UI
40001  Kafka kulso localhost listener
```

Ellenorzes PowerShellbol:

```powershell
netstat -ano | findstr ":40000 :40001 :40002 :40003 :40004 :40005 :40006 :40007 :40008 :40009 :40010 :40011"
```

Ha valamelyik port foglalt, akkor az adott szolgaltatas nem fog elindulni, vagy mas portot kell beallitani.

Windowsos SQL kliensbol az alap MSSQL cim:

```text
localhost,40000
```

SSMS / Azure Data Studio alap beallitas:

```text
Server name: localhost,40000
Authentication: SQL Login
Login: sa
Password: Alkalmassagi_2026!
Trust server certificate: checked
Encrypt: optional / false
```

Kontenerekbol nem ezt kell hasznalni, hanem:

```text
mssql:1433
```

Reszletes MSSQL csatlakozasi leiras: `SQL-SERVER-CONNECTION.md`.

## Masolasi javaslat

Masold at a teljes projektet barmilyen konyvtarba. Pelda:

```text
<akarmilyen-konyvtar>\ALKALMASSAGI
```

Nincs beegetett, gephez vagy felhasznalohoz kotott abszolut Windows utvonal. A scriptek a `scripts` konyvtar szulojat tekintik projektgyokernek, ezert a mappa fajlmasolassal hordozhato.

## Inditas internet nelkul

Nyiss egy normal, nem admin PowerShell ablakot.

Lepj be az offline bundle mappaba:

```powershell
cd "<ahova-masoltad>\offline-bundle"
```

Inditas:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

Mit csinal ez?

1. Elinditja a Podman machine-t, ha lehet.
2. Betolti az image-eket innen: `.\images\podman-images.tar`.
3. Letrehozza a `devnet` Podman networkot.
4. Elinditja az SQL Server podot.
5. Elinditja a Kafka podot.
6. Elinditja a Kafka UI podot.
7. Elinditja a DB admin UI podot.
8. Elinditja az `app1` - `app6` Spring Boot podokat.

Fontos: az `-ExternalHostName localhost` azert kell, mert admin jog nelkuli, csak helyi gepes hasznalatot akarunk. Igy a Kafka kulso listener is `localhost:40001` cimen hirdeti magat.

## Mit ne futtass admin jog nelkul?

Ezt ne futtasd normal userkent:

```powershell
.\scripts\configure-lan-firewall.ps1
```

Ez Windows firewall es portproxy beallitast csinalna. Ahhoz admin jog kell. `localhost` hasznalathoz nincs ra szukseg.

## Elso ellenorzes inditas utan

Podok listazasa:

```powershell
podman pod ps
```

Kontenerek listazasa podokkal:

```powershell
podman ps --pod
```

Image-ek ellenorzese:

```powershell
podman images
```

Elvart fontos podok:

```text
mssql-pod
kafka-pod
kafka-ui-pod
sql-admin-pod
app1-pod
app2-pod
app3-pod
app4-pod
app5-pod
app6-pod
```

## Bongeszoben megnyitando oldalak

DB admin UI:

```text
http://localhost:40003
```

Kafka admin UI:

```text
http://localhost:40002
```

Log viewer:

```text
http://localhost:40004
```

Apache NiFi file-to-Kafka:

```text
http://localhost:40011/nifi
```

A NiFi jelszo nelkul nyilik. A flow-ok, repository adatok, state es NiFi logok
a projekt `data\nifi` konyvtara alatt maradnak meg.

Spring Boot health oldalak:

```text
http://localhost:40005/actuator/health
http://localhost:40006/actuator/health
http://localhost:40007/actuator/health
http://localhost:40008/actuator/health
http://localhost:40009/actuator/health
http://localhost:40010/actuator/health
```

Mindegyiknel az a jo, ha ezt latod:

```json
{"status":"UP"}
```

Helyi linkgyujtemeny:

```text
.\browser-start.html
```

Ha csak az `offline-bundle` mappat masoltad at, akkor ott is van ilyen fajl:

```text
.\offline-bundle\browser-start.html
```

## Tovabbi dokumentaciok

Portok atallitasa:

```text
.\PORT-CONFIG.md
```

Internet authentikalt proxy mogott:

```text
.\PROXY-CONFIG.md
```

REST/SOAP/JKS/security konfiguracios peldak:

```text
.\REST-SOAP-SECURITY-EXAMPLES.md
```

Uj `appN` hozzaadasa:

```text
.\ADD-NEW-APP.md
```

## DB admin UI

Nyisd meg:

```text
http://localhost:40003
```

Jelszo nelkul nyilik.

Fontos kapcsolatok:

```text
Local MSSQL
app1_audit
app2_audit
app3_audit
app4_audit
app5_audit
app6_audit
```

Az app adatbazisokban az `audit_events` tabla mutatja, hogy az adott app milyen uzenetet vett at es mit kuldott tovabb.

A DbGate a kontenerhalozaton beluli `mssql:1433` cimen kapcsolodik az SQL
szerverhez. Ha kulon Windowsos SQL kliensbol akarsz csatlakozni, akkor ezt
hasznald:

```text
localhost,40000
sa / Alkalmassagi_2026!
Trust server certificate: yes
```

Reszletek: `SQL-SERVER-CONNECTION.md`.

## Kafka UI

Nyisd meg:

```text
http://localhost:40002
```

Fontos topicok:

```text
app1.source
app2.source
app3.source
app4.source
app5.source
app6.source
app7.final
```

Consumer groupok:

```text
app1-group
app2-group
app3-group
app4-group
app5-group
app6-group
```

Az uzenet utvonala:

```text
app1.source -> app2.source -> app3.source -> app4.source -> app5.source -> app6.source -> app7.final
```

Az `app7.final` vegso topic, abbol mar nem olvas tovabb alkalmazas.

## Uzenet kuldese teszthez

Ha a teljes projektmappat masoltad at, hasznalhatod ezt:

```powershell
cd "<projekt-mappa>"
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\send-test-message.ps1
```

Ha csak az `offline-bundle` mappa van atmasolva, akkor ugyanez a script az offline bundle alol is hasznalhato, mert az export a Kafka CLI helper image-et is tartalmazza.

Utana nezd meg:

```text
Kafka UI -> app7.final topic
DB admin UI -> app1_audit ... app6_audit -> audit_events tabla
```

## Ujrakezdes / ujrainditas

Ha ugyanazt a csomagot ujra akarod inditani:

```powershell
cd "<ahova-masoltad>\offline-bundle"
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

A deploy scriptek ujraletrehozzak a podokat. Az SQL Server adatok Podman volume-ban vannak (`mssql-data`), tehat alapbol nem torlodnek pusztan attol, hogy a pod ujraindul.

## Leallitas

Osszes sajat pod leallitasa/torlese:

```powershell
podman pod rm -f app1-pod app2-pod app3-pod app4-pod app5-pod app6-pod
podman pod rm -f kafka-ui-pod sql-admin-pod kafka-pod mssql-pod
```

Ez a podokat torli. Az SQL Server volume adatai kulon maradnak, amig a `mssql-data` volume-ot nem torlod.

Volume torles csak akkor, ha tenyleg nullarol akarod:

```powershell
podman volume rm mssql-data
```

## Ha hibat kapsz

### PowerShell: not digitally signed

Hiba pelda:

```text
... cannot be loaded. The file ... is not digitally signed.
```

Ok: a Windows ugy latja, hogy a `.ps1` fajlok internetrol letoltott fajlok.

Megoldas a projekt gyokereben:

```powershell
Get-ChildItem -Recurse -File | Unblock-File
```

Ezutan a scripteket mindig igy futtasd:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\<script-nev>.ps1
```

Pelda:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests
```

### Podman: tls failed to verify certificate x509

Hiba pelda:

```text
tls: failed to verify certificate: x509
```

Gyors workaround ceges proxy/TLS inspection mogott: a projekt gyokerben a
`proxy.config.json` fajlban allitsd:

```json
{
  "podmanTlsVerify": false,
  "mavenTlsVerify": false
}
```

Ezutan futtasd ujra az exportot:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests
```

Hosszu tavon jobb megoldas a ceges CA importalasa a Podman machine-be. Reszletek:

```text
.\PROXY-CONFIG.md
```

### Missing image archive

Hiba pelda:

```text
Missing image archive: .\images\podman-images.tar
```

Ok: nem masoltad at az `images` mappat vagy a `podman-images.tar` fajlt.

Megoldas: masold at a teljes `offline-bundle` mappat, benne ezzel:

```text
.\offline-bundle\images\podman-images.tar
```

### Port already allocated

Ok: valamelyik portot mas program hasznalja.

Ellenorzes:

```powershell
netstat -ano | findstr ":40000 :40001 :40002 :40003 :40004 :40005 :40006 :40007 :40008 :40009 :40010 :40011"
```

Megoldas: allitsd le a masik programot, vagy modositsd a portokat a konfiguracioban.

### MSSQL: `The system directory [/.system] could not be created`

Hiba pelda:

```text
Error The system directory [/.system] could not be created
File LinuxDirectory.cpp 420 Access Denied
```

Ok: az SQL Server kontener nem rootkent fut, es az uj gepen az `mssql-data`
Podman volume jogosultsaga rossz lehet.

Megoldas: friss develop/offline bundle eseten egyszeruen futtasd ujra az indito
scriptet. A script automatikusan javitja a volume tulajdonjogat es jogait.

Develop branchbol:

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

Ez adatvesztes nelkuli jogosultsag-javitas. A script az `mssql-data` volume-on
`10001:0` tulajdonost es csoportirasi jogot allit be.

Csak akkor torold a volume-ot, ha biztosan nem kell semmilyen korabbi SQL adat:

```powershell
podman pod rm -f mssql-pod
podman volume rm mssql-data
```

### MSSQL: `A downgrade path is not supported`

Hiba pelda:

```text
The database 'master' cannot be opened because it is version 957.
This server supports version 904 and earlier.
A downgrade path is not supported.
```

Ok: az `mssql-data` volume egy ujabb SQL Server verzioval keszult, mint amit
most inditasz. Pelda: a volume SQL Server 2022-vel jott letre, de kesobb a
scriptet SQL Server 2019 image-dzsel futtatod.

Ebben a projektben ez local/offline fejlesztoi adat, ezert alapbol nem kell
megorizni. A friss `deploy-infra-pods.ps1` es `run-offline.ps1` ezt automatikusan
kezeli:

1. Elinditja az MSSQL kontenert.
2. Rovid ideig figyeli a logot.
3. Ha downgrade/verzio inkompatibilitast lat, torli az `mssql-data` volume-ot.
4. Ujraletrehozza a volume-ot jo jogosultsagokkal.
5. Ujrainditja az MSSQL podot tiszta adatbazissal.

Ez adatvesztessel jar az SQL Server volume-ra nezve, de csak az `mssql-data`
volume-ot erinti. A Kafka/NiFi/log/adat konyvtarak nem torlodnek emiatt.

Ha `run-offline.ps1`-t futtatsz, az app podok ujrainditasa automatikusan jon az
infra utan. Ha csak `deploy-infra-pods.ps1`-t futtattal kezzel, utana inditsd
ujra az app podokat is, hogy ujra letrehozzak az audit adatbazisokat:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json `
  -SqlPassword "Alkalmassagi_2026!" `
  -SkipBuild
```

Ha megis meg akarod allitani a scriptet adatvesztes elott, add meg:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost `
  -KeepMssqlDataOnVersionMismatch
```

Offline bundle alol ugyanez:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost `
  -KeepMssqlDataOnVersionMismatch
```

### NiFi: `FileNotFoundException bootstrap.conf`

Hiba pelda:

```text
FileNotFoundException /opt/nifi/nifi-current/conf/bootstrap.conf
```

Ok: a projekt `data\nifi\conf` mappaja bind mountkent eltakarja a kontener
gyari `/opt/nifi/nifi-current/conf` mappajat. Ha a host oldali conf mappa
hianyos, peldaul csak `nifi.properties` van benne, akkor a NiFi nem talalja a
`bootstrap.conf` fajlt.

Megoldas: friss develop/offline bundle eseten futtasd ujra az indito scriptet.
A script most ellenorzi es az image-bol potolja a hianyzo NiFi alap conf
fajlokat, adatvesztes nelkul.

Develop branchbol:

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

Ne torold elsore a teljes `data\nifi` konyvtarat, mert abban vannak a NiFi
flow/state/repository adatok. Csak akkor torold, ha biztosan teljesen nullarol
akarod kezdeni a NiFi-t.

### Podman machine nem indul

Ellenorzes:

```powershell
podman machine list
podman machine start
podman info
```

Ha ezek nem mukodnek, akkor a masik gepen a Podman/WSL telepites nincs rendben. Ezt admin jog nelkul nem mindig lehet javitani, mert maga a WSL/virtualizacio telepites rendszerszintu lehet.

### App health nem UP

Nezd meg az adott app logjat:

```powershell
podman logs app1
podman logs app2
podman logs app3
podman logs app4
podman logs app5
podman logs app6
```

Infra logok:

```powershell
podman logs mssql
podman logs kafka
podman logs kafka-ui
podman logs sql-admin
```

### Kafka UI megy, de az appok nem dolgoznak

Ellenorizd:

```text
http://localhost:40002
```

Topicok:

```text
app1.source
app2.source
app3.source
app4.source
app5.source
app6.source
app7.final
```

Consumer groupok:

```text
app1-group
app2-group
app3-group
app4-group
app5-group
app6-group
```

App log:

```powershell
podman logs app1
```

## Uj offline bundle keszitese a forras gepen

Ha modositod az appokat vagy a konfiguraciot, a forras gepen uj bundle-t kell generalni:

Ha a forras gep proxy mogott van, elobb toltsd ki a `proxy.config.json` fajlt. A parancs ettol nem valtozik.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests
```

Ez:

1. Podman alatt buildeli a Java appokat a `java-build-pod` podban.
2. Ujraepiti a `local/app1:dev` - `local/app6:dev` image-eket.
3. Elmenti az osszes szukseges image-et ide: `.\offline-bundle\images\podman-images.tar`.
4. Bemasolja a runtime YAML konfiguraciokat es dokumentaciot az `offline-bundle` mappaba.

Ha a build gepen sincs internet, de a Maven cache es az image-ek mar megvannak:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests `
  -OfflineJavaBuild
```

## Fontos hordozhatosagi szabalyok

- Ne irj be fix, gephez vagy felhasznalohoz kotott abszolut Windows utvonalakat a konfiguracioba.
- A projekt sajat fajljaira relativan hivatkozz.
- A scriptek a `scripts` konyvtar szulojat tekintik projektgyokernek.
- Az `application.yaml` fajlok az appok alatt vannak: `app1\src\main\resources\application.yaml` stb.
- A JKS fajlok helye apponkent: `appN\src\main\resources\security`.
- A masik gepen csak az `offline-bundle` mappabol inditsd a `scripts\run-offline.ps1` scriptet.

## Rovid parancslista

Uj gepen, `develop` branchbol, internet/proxy mellett, builddel egyutt:

```powershell
cd "<ahova-klonoztad-vagy-kicsomagoltad>\ALKALMASSAGI"

Get-ChildItem -Recurse -File | Unblock-File

podman machine start
if ($LASTEXITCODE -ne 0) {
  podman machine init
  podman machine start
}

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests

powershell -NoProfile -ExecutionPolicy Bypass -File .\offline-bundle\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost

podman pod ps
podman ps --pod
```

Masik gepen, offline, admin jog nelkul:

```powershell
cd "<ahova-masoltad>\offline-bundle"

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost

podman pod ps
podman ps --pod
```

Reszletes script help barmelyik scripthez:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 --help
```

Bongeszoben:

```text
http://localhost:40003
http://localhost:40002
http://localhost:40004
http://localhost:40011/nifi
http://localhost:40005/actuator/health
http://localhost:40006/actuator/health
http://localhost:40007/actuator/health
http://localhost:40008/actuator/health
http://localhost:40009/actuator/health
http://localhost:40010/actuator/health
```
