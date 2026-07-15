# ALKALMASSAGI local Podman stack

## Current infra pods

- `java-build-pod`: Maven/JDK build pod for the Spring Boot JARs and build logs
- `mssql-pod`: SQL Server internal `mssql:1433`, Windows host `40000`
- `kafka-pod`: Kafka internal `kafka:9092`, external `40001`
- `kafka-ui-pod`: Kafbat UI on `40002`
- `sql-admin-pod`: DbGate on `40003`
- `log-viewer-pod`: Dozzle log viewer on `40004`
- `nifi-pod`: Apache NiFi file-to-Kafka UI on `40011`

## Local URLs

- Kafka UI: http://localhost:40002
- SQL admin UI: http://localhost:40003
- Log viewer UI: http://localhost:40004
- Apache NiFi UI: http://localhost:40011/nifi
- Browser page index: `.\browser-start.html`
- Detailed browser page documentation: `BROWSER-PAGES.md`
- SQL Server connection guide: `SQL-SERVER-CONNECTION.md`
- Spring app YAML configuration guide: `APPLICATION-YAML-CONFIG.md`
- Authenticated proxy guide: `PROXY-CONFIG.md`
- Port configuration guide: `PORT-CONFIG.md`
- Add a new app guide: `ADD-NEW-APP.md`
- Module source sync guide: `MODULE-SOURCE-SYNC.md`
- Maven library-first build guide: `MAVEN-LIBRARY-FIRST-BUILD.md`
- Script structure guide: `SCRIPT-STRUCTURE.md`
- Log viewer guide: `LOG-VIEWER.md`
- Log persistence guide: `LOG-PERSISTENCE.md`

## First run on a new machine from develop

Use this when the `develop` branch is checked out and the offline image archive
does not exist yet. Run from a normal non-admin PowerShell window:

```powershell
cd "<project-folder>"

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
```

If the machine is behind an authenticated proxy, fill `proxy.config.json` first.
If Podman image pulls fail with `tls: failed to verify certificate: x509`, set
`"podmanTlsVerify": false` in `proxy.config.json`. If Maven dependency downloads
fail with `certificate signed by unknown authority` or `PKIX path building failed`,
set `"mavenTlsVerify": false` too. Details: `PROXY-CONFIG.md`.
Explicit `podman pull` operations in the build/export scripts are retried 5
times by default before the script stops; no extra parameter is needed for this.
Use `-PodmanPullRetries` only if you want more than 5 attempts, and
`-PodmanPullRetryDelaySeconds` only if you want a different delay.
The Maven build itself is also retried 5 times by default, so transient Maven
repository/proxy failures do not stop the build immediately. Unlike Podman
pull retries, Maven build retries can be lowered to 1 with `-MavenBuildRetries 1`.
For corporate Nexus or Artifactory settings, put your complete local Maven
settings in `maven-settings.local.xml` and reference it from `proxy.config.json`
with `mavenSettingsFile`. The app build uses it with `mvn -s`; the file is
ignored by Git because it can contain credentials.

## Full rebuild and start order

Use this when you want to rebuild everything from the checked-out source and
start the complete local stack:

```powershell
cd "<project-folder>"
Get-ChildItem -Recurse -File | Unblock-File

podman machine list
podman machine start
podman info

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -SkipTests

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json
```

`sync-module-sources.ps1` uses the root `pom.xml` modules and the optional
`branch` field in `services.json`. If no branch is configured, it uses
`develop`. For one module: `.\scripts\sync-module-sources.ps1 -ModuleName app3`.

Then verify:

```powershell
podman pod ps
podman ps --pod

foreach ($port in 40005..40010) {
  Invoke-RestMethod "http://localhost:$port/actuator/health"
}

Invoke-WebRequest http://localhost:40002 -UseBasicParsing
Invoke-WebRequest http://localhost:40003 -UseBasicParsing
Invoke-WebRequest http://localhost:40004 -UseBasicParsing
Invoke-WebRequest http://localhost:40011/nifi/ -UseBasicParsing

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\send-test-message.ps1
```

## Rebuild and redeploy one app

Use this during development when only one Spring Boot app changed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -MavenProjects app3 `
  -AlsoMake `
  -SkipTests

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json `
  -ServiceName app3 `
  -SqlPassword "Alkalmassagi_2026!"
```

`-MavenProjects app3 -AlsoMake` runs Maven as `mvn -pl app3 -am clean package`.
`-ServiceName app3` rebuilds only that app image and recreates only `app3-pod`.
Multiple values are accepted as comma-separated names, for example
`-MavenProjects app3,app4` and `-ServiceName app3,app4`.

For the full repeatable test pass, including NiFi file-to-Kafka, MSSQL audit
row checks, log export, offline bundle export, and offline startup, read
`TESTING-CHECKLIST.md`.

If only app source changed, run only the build and Spring Boot deploy commands.
If only infra, NiFi, port, or proxy config changed, run infra deploy and then
Spring Boot deploy with `-SkipBuild`.

To create a portable offline package after the rebuild:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests
```

On an offline target machine, copy `offline-bundle`, unblock files, and run:

```powershell
cd "<copied-folder>\offline-bundle"
Get-ChildItem -Recurse -File | Unblock-File
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

For the detailed step-by-step rebuild, install, offline export, and restart
guide, read `start.md`.

## SQL Server connection

- From containers: `mssql:1433`
- From Windows: `localhost,40000`
- User: `sa`
- Default local password used in examples: `Alkalmassagi_2026!`

Windows SQL clients such as SSMS or Azure Data Studio should use SQL Login:

```text
Server name: localhost,40000
Authentication: SQL Login
Login: sa
Password: Alkalmassagi_2026!
Trust server certificate: checked
Encrypt: optional / false
```

Connection string example:

```text
Server=localhost,40000;Database=master;User Id=sa;Password=Alkalmassagi_2026!;TrustServerCertificate=True;Encrypt=False;
```

Detailed SQL connection documentation: `SQL-SERVER-CONNECTION.md`.

DbGate opens without a login screen and has preconfigured SQL Server connections:
`Local MSSQL`, `app1_audit`, `app2_audit`, `app3_audit`, `app4_audit`, `app5_audit`, and `app6_audit`.
The SQL admin container is started with `NODE_TLS_REJECT_UNAUTHORIZED=0`, so its Node.js runtime accepts self-signed/internal TLS certificates.
The infra deploy script also repairs the `mssql-data` Podman volume permissions
for the non-root SQL Server container user. If a new machine shows
`The system directory [/.system] could not be created`, rerun
`scripts\deploy-infra-pods.ps1` or `offline-bundle\scripts\run-offline.ps1`;
the fix is applied automatically without deleting the SQL data volume.
If the SQL image is downgraded, for example from SQL Server 2022 to SQL Server
2019, the existing `mssql-data` volume can be too new for the older server. In
that case the deploy script detects `A downgrade path is not supported`, removes
only the `mssql-data` volume, recreates it, and starts SQL Server from zero.
Use `-KeepMssqlDataOnVersionMismatch` only when you want the script to stop
instead of resetting the local SQL data.

Dozzle opens without a login screen at http://localhost:40004 and shows the logs for the app, SQL Server, Kafka, Kafka UI, DB admin, Java build, and log viewer containers.
Old container logs are archived before pod recreation under `data\logs`.
Java build logs are also written under `data\build-logs`; open `java-build-log-viewer` in Dozzle to watch the latest build log.

Apache NiFi opens without a login screen at http://localhost:40011/nifi.
Its file-to-Kafka flow is generated from `nifi-flows.yaml`; drop folders are under `data\nifi\drop`.
NiFi configuration, including `nifi.properties`, flow state, repositories and NiFi application logs are persisted under `data\nifi`.
The repository also contains a base NiFi properties template at `config\nifi\nifi.properties`.
On startup the infra deploy script validates the required NiFi conf files such
as `bootstrap.conf`, `logback.xml`, and `state-management.xml`. If a copied
machine has a partial `data\nifi\conf` folder, the script restores only the
missing base files from the NiFi image without deleting existing flow/state data.

## Kafka connection

- From containers: `kafka:9092`
- From Windows: `localhost:40001`

For this project the documented default is localhost access. If later you want LAN access too, see `PORT-CONFIG.md` and rerun the infra script with `-ExternalHostName <lan-ip>`.

## Start infra

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 -SqlPassword 'Alkalmassagi_2026!'
```

## Build Java apps without host Java/Maven

The host only needs Podman. Maven and JDK run in the `java-build-pod` pod.
The Maven cache stays inside this project folder at `data\maven-repo`.
The current build log stays inside this project folder at `data\build-logs\current.log`.
The script also starts `java-build-log-viewer`, so the same build log is visible in Dozzle at http://localhost:40004.
The Maven builder image pull is retried 5 times by default.
The `mvn clean package` execution is retried 5 times by default too, but it can
be lowered to one attempt with `-MavenBuildRetries 1`.

If the root `pom.xml` contains library, parent POM, or BOM modules that are not
services, the build installs those modules into `data\maven-repo` before
packaging the apps. Details: `MAVEN-LIBRARY-FIRST-BUILD.md`.

If internet is available only through an authenticated proxy, fill `proxy.config.json` once and keep the same build command. Details: `PROXY-CONFIG.md`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 -SkipTests
podman pod ps --filter name=java-build-pod
```

## Enable LAN access

Run this from an elevated PowerShell window:

```powershell
cd "<project-folder>"
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-lan-firewall.ps1
```

This creates Windows firewall rules and `netsh interface portproxy` entries for the infra and service ports.

