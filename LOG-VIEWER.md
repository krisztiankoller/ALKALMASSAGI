# Log viewer

A stack tartalmaz egy webes log viewer podot Dozzle alapon.

## Mire valo?

Egy bongeszoben, egy helyen lehet nezni a kontenerek logjait:

- app1
- app2
- app3
- app4
- app5
- app6
- mssql
- kafka
- kafka-ui
- sql-admin
- java-build-log-viewer
- java-maven-builder
- log-viewer

## URL

```text
http://localhost:40004
```

Nincs jelszo beallitva. A projekt tovabbra is localhost-only fejlesztoi stackkent van dokumentalva.

## Hogyan mukodik?

A Dozzle a Podman Docker-kompatibilis socketjet hasznalja:

```text
/var/run/docker.sock
```

Podman Desktop / Podman machine alatt ez a socket a Podman machine-on belul a Podman API-ra mutat.

A log viewer pod ezt mountolja:

```text
/var/run/docker.sock:/var/run/docker.sock:ro
```

Ezert latja az osszes kontenert es azok logjait.

## Java build logok

A Java/Maven buildet a `scripts\build-apps-with-podman.ps1` script a
`java-build-pod` podban futtatja. A buildhez ket fontos kontener tartozik:

```text
java-build-log-viewer
java-maven-builder
```

`java-build-log-viewer` egy futo kontener, amely a build utan kiirja a projekt
alatti aktualis build log fajl teljes tartalmat a sajat kontenerlogjaba:

```text
.\data\build-logs\current.log
```

Dozzle-ban ezt a kontenert nyisd meg, ha a build logot webes feluleten akarod
nezni:

```text
http://localhost:40004 -> java-build-log-viewer
```

Igy a Dozzle-ban a teljes utolso build log latszik akkor is, ha maga a Maven
build kontener mar kilepett es torlodott.

`java-maven-builder` maga a Maven build kontener. A script alapbol torli a build
utan, hogy a `java-build-pod` statusza tiszta maradjon. Ha hibakereseshez meg
akarod tartani a nyers kontenerlogot is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -SkipTests `
  -KeepBuildContainer
```

Ilyenkor:

```powershell
podman logs java-maven-builder
```

A kovetkezo build elott a script torli az elozo `java-maven-builder` kontenert,
majd letrehozza az ujat. A regi `current.log` fajlt minden build elejen
timestampelt fajlba menti ugyanabban a konyvtarban.

Ha valamiert nem akarod a webes build log tailert:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -SkipTests `
  -DisableBuildLogViewer
```

## Inditas

Az infra deploy script automatikusan inditja:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

Offline bundle futtatasnal is automatikusan indul:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

## Port atallitasa

Infra inditasnal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost `
  -LogViewerHostPort 40004
```

Offline futtatasnal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost `
  -LogViewerHostPort 40004
```

## Offline bundle

Az offline export beteszi a Dozzle image-et az image archive-ba:

```text
amir20/dozzle:latest
```

Ezert a masik gepen internet nelkul is indul, ha az offline bundle frissen lett generalva:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests
```

## Biztonsagi megjegyzes

A log viewer a Podman socketen keresztul latja a kontenereket. Emiatt ezt tovabbra is csak helyi, fejlesztoi, `localhost` hasznalatra javasolt futtatni.

LAN-ra vagy eles kornyezetbe csak kulon autentikacio, tuzfal es jogosultsagi atgondolas utan tedd ki.

## Regi logok megorzese

A Dozzle az elo kontenerek aktualis logjait mutatja.

Pod ujraletrehozas elott a deploy scriptek kimentik a regi logokat ide:

```text
.\data\logs
```

Reszletek: `LOG-PERSISTENCE.md`.

## Hibakereses

Ha nem indul:

```powershell
podman logs log-viewer
```

Ha nem lat kontenereket:

```powershell
podman machine ssh -- ls -la /var/run/docker.sock
podman machine ssh -- 'ls -la /run/user/$(id -u)/podman/podman.sock'
```

Ha a socket hianyzik, inditsd ujra a Podman machine-t:

```powershell
podman machine stop
podman machine start
```
