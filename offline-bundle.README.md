# Offline Podman bundle

## Export on the build machine

The host only needs Podman. The export script builds every Spring Boot JAR in a visible Podman pod named `java-build-pod`.
If this build machine is behind an authenticated proxy, fill `proxy.config.json` once, then run the same export command. See `PROXY-CONFIG.md`.

1. Update `services.sample.json` or your own `services.json`.
2. Run:

```powershell
.\scripts\export-offline-bundle.ps1 -ServicesFile .\services.json -SkipTests
```

The script builds the service images and saves all required images into:

```text
offline-bundle\images\podman-images.tar
```

Copy the whole `offline-bundle` folder to the target machine.
The filled `proxy.config.json` is not copied automatically, because it can contain a password. The offline target does not need it.

## Run on the offline target machine

The target machine still needs Podman/WSL installed and a working Podman machine.
No Windows admin rights are needed for localhost-only use. Do not run `scripts\configure-lan-firewall.ps1` without admin rights.
No internet or proxy is needed for running an already exported offline bundle.

```powershell
.\scripts\run-offline.ps1 -SqlPassword 'YourStrongPassword123!' -ExternalHostName localhost
```

This loads the image archive, starts SQL Server and Kafka, then starts every Spring Boot service from `services.json`.
Use `-ExternalHostName <ip-or-dns-name>` only when you intentionally want Kafka to advertise a LAN-accessible address.

Useful local pages after start:

```text
http://localhost:40003  SQL admin
http://localhost:40002  Kafka UI
http://localhost:40004  Log viewer
http://localhost:40011/nifi  Apache NiFi
```

Every script supports detailed help:

```powershell
.\scripts\run-offline.ps1 --help
```

## Notes

- This bundle contains container images and scripts, not database backups.
- This bundle also contains each app's `src/main/resources` folder, including `application.yaml` and `security/` JKS locations, because the services mount YAML config at runtime.
- The Maven/JDK build image is included in the image archive, and the build helper script is copied as `scripts\build-apps-with-podman.ps1`.
- The Dozzle log viewer image is included in the image archive for browser-based container logs.
- The Apache NiFi image is included for file-to-Kafka upload flows generated from `nifi-flows.yaml`.
- For GitHub publishing and the special `all` branch layout, see `GITHUB-PUBLISH.md`.
- Start with `start.md`. For script layout use `SCRIPT-STRUCTURE.md`; for log viewer details use `LOG-VIEWER.md`; for NiFi file upload use `NIFI-FILE-TO-KAFKA.md`; for saved log behavior use `LOG-PERSISTENCE.md`; for authenticated proxy setup use `PROXY-CONFIG.md`; for port changes use `PORT-CONFIG.md`; for REST/SOAP/JKS examples use `REST-SOAP-SECURITY-EXAMPLES.md`; for adding a new app use `ADD-NEW-APP.md`.
- If you also need existing database data, export/import SQL backups separately.
- Keep the same service names in `services.json`; they become DNS names on the `devnet` network.
