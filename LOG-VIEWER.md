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
