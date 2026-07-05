# Script structure

Minden PowerShell script a `scripts` konyvtar alatt van.

## Kozvetlenul hasznalhato scriptek

Ezeket lehet normal uzemelteteshez vagy fejleszteshez futtatni:

```text
.\scripts\build-apps-with-podman.ps1
.\scripts\deploy-infra-pods.ps1
.\scripts\deploy-springboot-pods.ps1
.\scripts\export-offline-bundle.ps1
.\scripts\run-offline.ps1
.\scripts\configure-lan-firewall.ps1
.\scripts\send-test-message.ps1
.\scripts\export-container-logs.ps1
.\scripts\configure-nifi-file-to-kafka.ps1
.\scripts\split-offline-image.ps1
.\scripts\join-offline-image.ps1
```

Minden script tud reszletes sajat helpet:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 --help
```

Ugyanez mukodik a private scriptekre is, peldaul:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\private\generate-spring-pipeline-apps.ps1 --help
```

Rovid szerepuk:

- `build-apps-with-podman.ps1` - Maven build Podman kontenerben, host Java/Maven nelkul.
- `deploy-infra-pods.ps1` - SQL Server, Kafka, Kafka UI, DB admin, log viewer es NiFi podok inditasa.
- `deploy-springboot-pods.ps1` - app1-app6 podok buildelese/inditasa.
- `export-offline-bundle.ps1` - offline csomag generalasa image tar-ral es doksikkal.
- `run-offline.ps1` - offline-bundle inditasa masik gepen.
- `configure-lan-firewall.ps1` - opcionalis LAN elereshez firewall/portproxy beallitas, admin jog kell.
- `send-test-message.ps1` - teszt Kafka uzenet kuldese az `app1.source` topicba.
- `export-container-logs.ps1` - aktualis kontenerlogok mentese a `data\logs` konyvtarba.
- `configure-nifi-file-to-kafka.ps1` - NiFi file-to-Kafka flow generalasa `nifi-flows.yaml` alapjan.
- `split-offline-image.ps1` - nagy offline image tar darabolasa GitHub/LFS kompatibilis reszekre.
- `join-offline-image.ps1` - darabolt offline image tar visszaallitasa.

## Private scriptek

Ezek nem napi hasznalatra valok:

```text
.\scripts\private\generate-spring-pipeline-apps.ps1
.\scripts\private\podman-dev-stack-template.ps1
```

Ezek generalo/template jellegu segedfajlok. Normal inditashoz, buildhez, offline exporthoz vagy masik gepen futtatashoz nem kellenek.
Ha megis hozza kell nyulni, elobb futtasd a `--help` kapcsoloval.

## Fontos utvonal szabaly

A scriptek bar a `scripts` konyvtarban vannak, a projekt gyokeret hasznaljak alapnak.

Ezert ezek tovabbra is a projekt gyokerben levo fajlokat hasznaljak:

```text
.\services.json
.\nifi-flows.yaml
.\proxy.config.json
.\Containerfile.spring-boot-jar
.\data
.\work
.\offline-bundle
```

Peldak:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 -SqlPassword "Alkalmassagi_2026!" -ExternalHostName localhost
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 -ServicesFile .\services.json -SkipTests
```

Offline bundle-ben is ugyanez a szabaly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 -SqlPassword "Alkalmassagi_2026!" -ExternalHostName localhost
```
