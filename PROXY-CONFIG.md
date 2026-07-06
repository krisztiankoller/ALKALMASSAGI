# Proxy configuration

Ez a dokumentum azt irja le, mit kell csinalni akkor, ha van internet, de csak authentikalt HTTP/HTTPS proxy mogott.

## Mikor kell proxy?

Proxy akkor kell, amikor a gepnek internetrol kell letoltenie valamit:

- `podman pull`
- `podman build`, ha az alap image-et vagy build contextet el kell erni
- Maven dependency letoltes
- offline bundle keszitese a forras gepen

Proxy nem kell a mar elkeszult offline bundle futtatasahoz, mert ott az image-ek mar benne vannak ebben:

```text
.\offline-bundle\images\podman-images.tar
```

## Egyetlen proxy config fajl

A projekt gyokereben van egy darab proxy konfiguracios fajl:

```text
.\proxy.config.json
```

Ezt kell kitolteni. Pelda:

```json
{
  "enabled": true,
  "httpProxy": "http://proxy.ceg.local:8080",
  "httpsProxy": "http://proxy.ceg.local:8080",
  "username": "DOMAIN\\user",
  "password": "secret",
  "podmanTlsVerify": true,
  "mavenTlsVerify": true,
  "noProxy": [
    "localhost",
    "127.0.0.1",
    ".ceg.local",
    "mssql",
    "kafka",
    "kafka-ui",
    "sql-admin",
    "app1",
    "app2",
    "app3",
    "app4",
    "app5",
    "app6"
  ]
}
```

Ha `enabled` erteke `false`, akkor a scriptek nem hasznalnak proxyt.

Ha a ceges proxy/TLS inspection miatt a Podman image letoltes ilyen hibaval all meg:

```text
tls: failed to verify certificate: x509
certificate signed by unknown authority
```

akkor ideiglenesen allithato:

```json
{
  "podmanTlsVerify": false,
  "mavenTlsVerify": false
}
```

Ez a scriptekben a Podman `pull` es `build` parancsokhoz ezt adja hozza:

```text
--tls-verify=false
```

Az explicit `podman pull` parancsokat a build/export scriptek alapbol 5-szor
probaljak meg, mielott hibaval megallnak. Ez proxy vagy instabil halozat mogott
hasznos, mert egy rovid registry/proxy hiba nem allitja meg azonnal az exportot.
Ehhez normal esetben nem kell semmilyen extra parameter.

Pelda tobb mint 5 probalkozas beallitasara:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests `
  -PodmanPullRetries 8 `
  -PodmanPullRetryDelaySeconds 15
```

Az app image Containerfile nem telepit csomagot `apk add`-dal, ezert az app image
buildjehez nem kell kulon Alpine TLS workaround. A health check sem hasznal
`wget` vagy `curl` csomagot.

Maven dependency letoltesnel pedig ezekkel futtatja a Maven buildet:

```text
-Dmaven.resolver.transport=wagon
-Dmaven.wagon.http.ssl.insecure=true
-Dmaven.wagon.http.ssl.allowall=true
-Dmaven.wagon.http.ssl.ignore.validity.dates=true
```

Biztonsagosabb hosszu tavu megoldas a ceges CA importalasa a Podman machine-be, de zart ceges proxy mogott a fenti kapcsolo gyors workaround lehet.

A TLS kapcsolok JSON boolean es string formaban is mukodnek:

```json
{
  "podmanTlsVerify": false,
  "mavenTlsVerify": "false"
}
```

Parancssorbol is elfogadott:

```powershell
-PodmanTlsVerify false -MavenTlsVerify false
```

Ezek a scriptek automatikusan olvassak:

```text
.\scripts\build-apps-with-podman.ps1
.\scripts\export-offline-bundle.ps1
.\scripts\deploy-springboot-pods.ps1
```

Ez azt jelenti, hogy normal esetben nem kell parancssori proxy kapcsolokat megadni.

Fontos: a kitoltott `proxy.config.json` tartalmazhat jelszot, ezert az offline export nem masolja automatikusan az `offline-bundle` mappaba. A kesz offline bundle futtatasahoz nincs szukseg proxy konfiguraciora.

## Proxy URL formatum

Proxy authentikacioval ket javasolt forma van.

Kulon username/password parameterekkel:

```text
http://proxy.ceg.local:8080
```

Vagy URL-be irt credentiallel:

```text
http://username:password@proxy.ceg.local:8080
```

Ha a jelszo specialis karaktereket tartalmaz, a javasolt megoldas tovabbra is a kulon `username` es `password` mezok hasznalata a `proxy.config.json` fajlban. Igy nem kell URL-escape-elessel foglalkozni. Ezeket a script automatikusan URL-encode-olja, mielott a proxy URL-be teszi, ezert a `DOMAIN\user`, `@`, `:`, `#`, `%` jellegu karakterek nem torik el a Podman/Maven proxy beallitast.

Parancssori feluliras csak ideiglenes hibakereseshez van:

```powershell
-ProxyUsername "DOMAIN\user"
-ProxyPassword "secret"
```

## No proxy lista

A belso Podman neveket ne kuldje proxyra:

```text
localhost,127.0.0.1,mssql,kafka,kafka-ui,sql-admin,app1,app2,app3,app4,app5,app6
```

Ha van sajat belso domain:

```text
localhost,127.0.0.1,.ceg.local,mssql,kafka,kafka-ui,sql-admin,app1,app2,app3,app4,app5,app6
```

## Java/Maven build proxy mogott

Host Java/Maven tovabbra sem kell. A Maven kontenerben fut.

Ha a `proxy.config.json` ki van toltve es `enabled: true`, eleg ennyi:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -SkipTests
```

Mit csinal a script?

1. Beallitja a `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` valtozokat a Podman parancsokhoz.
2. Atadja ezeket a Maven kontenernek.
3. General egy Maven proxy beallitast ide:

```text
.\data\maven-repo\settings.xml
```

Ez azert kell, mert a Maven/Java nem mindig elegszik meg az operacios rendszer proxy env valtozoival.

## Fontos a jelszavakrol

Ha a `proxy.config.json` tartalmaz jelszot, a script a Maven miatt letrehozhatja ezt:

```text
.\data\maven-repo\settings.xml
```

Ez tartalmazhat proxy credentialt plain text formaban.

Javaslat:

- Ne add tovabb ezt a fajlt, ha ceges proxy jelszot tartalmaz.
- Ne add tovabb a kitoltott `proxy.config.json` fajlt, ha ceges proxy jelszot tartalmaz.
- Offline bundle futtatashoz nincs szukseg erre a proxy settings fajlra.
- Ha mar kesz az offline bundle, a masik gepre eleg az `offline-bundle` mappa.

Torles, ha mar nincs ra szukseg:

```powershell
Remove-Item .\data\maven-repo\settings.xml -Force
```

## Offline bundle keszitese proxy mogott

Ha van internet, de proxy mogott, toltsd ki a `proxy.config.json` fajlt, majd futtasd:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests
```

Ez proxyval vegzi:

- Maven dependency letoltest
- Podman image pullokat
- Podman build kozbeni csomagletoltest
- app image buildeket
- image tar exportot

Az eredmeny tovabbra is:

```text
.\offline-bundle\images\podman-images.tar
```

## App image build proxy mogott Maven build nelkul

Ha a JAR-ok mar keszek, es csak app image-et buildelsz:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json
```

Ez az image buildhez adja at a proxy beallitasokat.

Ha csak mar meglevo image-ekbol inditasz:

```powershell
.\scripts\deploy-springboot-pods.ps1 -ServicesFile .\services.json -SkipBuild
```

Ehhez mar nem kell proxy.

## PowerShell session proxy env valtozok

Normal esetben ezt nem kell hasznalni, mert a projekt scriptjei a `proxy.config.json` fajlbol dolgoznak.

Ha megis kezzel akarsz proxy env-et beallitani egy kulon `podman pull` vagy mas CLI teszthez:

```powershell
$env:HTTP_PROXY="http://username:password@proxy.ceg.local:8080"
$env:HTTPS_PROXY="http://username:password@proxy.ceg.local:8080"
$env:NO_PROXY="localhost,127.0.0.1,.ceg.local,mssql,kafka,kafka-ui,sql-admin,app1,app2,app3,app4,app5,app6"
```

Ez segithet `podman pull` es mas CLI parancsoknal, de Mavenhez a projekt scriptje altal general Maven `settings.xml` megbizhatobb.

## Corporate CA / TLS inspection

Ha a ceges proxy TLS inspectiont hasznal, elofordulhat, hogy a letoltesek certificate hibaval megallnak.

Podman machine host CA import:

```powershell
podman machine set --import-native-ca podman-machine-default
podman machine stop
podman machine start
```

Ez a host trusted CA-kat importalja a Podman machine-be, ha a Podman verzio tamogatja.

Fontos: a Maven kontener sajat Java truststore-t hasznalhat. Ha Maven certificate hibaval all meg, akkor a ceges CA-t vagy Maven/Java truststore-ba kell tenni, vagy olyan Maven repository/proxy megoldast kell hasznalni, amit a kontener Java runtime-ja is megbizhatonak lat.

Gyors Maven workaround, ha csak fejlesztoi/proxy mogotti build kell:

```json
{
  "mavenTlsVerify": false
}
```

Ez nem ajanlott vegleges biztonsagi megoldasnak, de segithet ceges TLS inspection mogott, amikor a Maven ilyen jellegu hibaval all meg:

```text
certificate signed by unknown authority
PKIX path building failed
unable to find valid certification path
```

## Offline target gep proxy mogott

Ha a target gepen csak futtatni akarod a mar elkeszult offline bundle-t:

```powershell
cd "<ahova-masoltad>\offline-bundle"
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

Ehhez nem kell proxy es nem kell internet.

## Gyors hibakereses

Podman image pull teszt:

```powershell
podman pull alpine:latest
```

Maven build teszt:

```powershell
.\scripts\build-apps-with-podman.ps1 -SkipTests
```

Ha authentikacios hiba van:

- ellenorizd a usernevet;
- domaines usernel probald: `DOMAIN\user`;
- a jelszot inkabb a `proxy.config.json` `password` mezojebe tedd, ne az URL-be;
- ha kell, a parancssori `-ProxyUsername` es `-ProxyPassword` kapcsolokkal ideiglenesen felul tudod irni a config fajlt hibakereseshez.

Ha certificate hiba van:

- ellenorizd, hogy van-e TLS inspection;
- importald a corporate CA-t a Windows trust store-ba;
- futtasd: `podman machine set --import-native-ca podman-machine-default`;
- Maven/Java certificate hibanal Java truststore szintu beallitas is kellhet.
