param(
    [string]$SqlPassword,

    [string]$BundleDir = "",
    [string]$NetworkName = "devnet",
    [string]$KafkaImage = "apache/kafka-native:3.9.0",
    [string]$KafkaUiImage = "ghcr.io/kafbat/kafka-ui:latest",
    [string]$SqlImage = "mcr.microsoft.com/mssql/server:2019-latest",
    [string]$SqlAdminImage = "dbgate/dbgate:latest",
    [string]$LogViewerImage = "amir20/dozzle:latest",
    [string]$NifiImage = "apache/nifi:1.28.1",
    [string]$ExternalHostName = "",
    [int]$MssqlHostPort = 40000,
    [int]$MssqlVersionCheckSeconds = 30,
    [int]$KafkaExternalHostPort = 40001,
    [int]$KafkaUiHostPort = 40002,
    [int]$SqlAdminHostPort = 40003,
    [int]$LogViewerHostPort = 40004,
    [int]$NifiHostPort = 40011,
    [int]$NifiWaitTimeoutSeconds = 240,
    [switch]$SkipNifiConfiguration,
    [switch]$KeepMssqlDataOnVersionMismatch,
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    @'
run-offline.ps1

Cel:
  Egy mar elkeszult offline-bundle inditasa masik Windows gepen internet,
  Java, Maven es admin jog nelkul. Csak Podman/WSL backend kell.

Hasznalat:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 -SqlPassword "<jelszo>" [opciok]

Javasolt localhost-only inditas:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
    -SqlPassword "Alkalmassagi_2026!" `
    -ExternalHostName localhost

Mit csinal:
  1. A scripts konyvtar szulojat offline bundle gyokernek veszi.
  2. Ellenorzi: .\images\podman-images.tar
  3. Ellenorzi: .\services.json
  4. Megprobalja elinditani a Podman machine-t.
  5. Betolti az image archive-ot: podman load --input ...
  6. Meghivja a scripts\deploy-infra-pods.ps1 scriptet, beleertve a log viewer
     es Apache NiFi podot.
  7. Meghivja a scripts\deploy-springboot-pods.ps1 scriptet -SkipBuild kapcsoloval.
  8. Kiirja a podman ps --pod eredmenyet.

Parameterek:
  -SqlPassword
      Kotelezo normal futasnal. Az SQL Server sa jelszava.

  -BundleDir
      Bundle gyoker. Uresen: a scripts konyvtar szuloja.
      Normal esetben nem kell megadni.

  -NetworkName
      Podman network neve. Alapertelmezett: devnet

  -KafkaImage, -KafkaUiImage, -SqlImage, -SqlAdminImage, -LogViewerImage, -NifiImage
      Infra image nevek. Normal esetben ne valtoztasd, mert a bundle manifest
      es image archive ezekhez keszult.

  -ExternalHostName
      Kafka external advertised listener hostneve.
      Admin jog nelkuli, csak helyi hasznalathoz: localhost
      LAN elereshez: IP vagy DNS nev, de akkor firewall/portproxy is kellhet.

  -MssqlHostPort
      SQL Server host port. Alapertelmezett: 40000

  -MssqlVersionCheckSeconds
      Ennyi masodpercig figyeli az MSSQL indulasi logot downgrade/verzio
      inkompatibilitas miatt. Alapertelmezett: 30

  -KeepMssqlDataOnVersionMismatch
      Ha az mssql-data volume ujabb SQL Serverrel keszult, mint amit most
      inditasz, ne torolje automatikusan a volume-ot, hanem alljon meg hibaval.
      Alapertelmezetten offline/local inditasnal a script torli es nullarol
      ujraletrehozza az SQL adatokat.

  -KafkaExternalHostPort
      Kafka kulso host port. Alapertelmezett: 40001

  -KafkaUiHostPort
      Kafka UI host port. Alapertelmezett: 40002

  -SqlAdminHostPort
      DbGate host port. Alapertelmezett: 40003

  -LogViewerHostPort
      Dozzle log viewer host port. Alapertelmezett: 40004

  -NifiHostPort
      Apache NiFi host port. Alapertelmezett: 40011

  -NifiWaitTimeoutSeconds
      NiFi REST API varakozasi ido flow generalas elott. Alapertelmezett: 240

  -SkipNifiConfiguration
      Elinditja NiFi-t, de nem generalja ujra a file-to-Kafka flow-t.

  --help
      Ezt a reszletes leirast irja ki es nem indit semmit.

Ellenorzes inditas utan:
  podman pod ps
  podman ps --pod

Bongeszos oldalak:
  Kafka UI: http://localhost:40002
  SQL admin: http://localhost:40003
  Logs: http://localhost:40004
  NiFi: http://localhost:40011/nifi
  App health: http://localhost:40005/actuator/health ... http://localhost:40010/actuator/health

Fontos:
  Offline futtatashoz nem kell proxy.config.json es nem kell internet.
'@
}

if ($Help) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrWhiteSpace($SqlPassword)) {
    throw "Missing required parameter: -SqlPassword. Use --help for detailed usage."
}

if ([string]::IsNullOrWhiteSpace($BundleDir)) {
    $BundleDir = Split-Path -Parent $PSScriptRoot
} elseif (-not [System.IO.Path]::IsPathRooted($BundleDir)) {
    $BundleDir = Join-Path (Split-Path -Parent $PSScriptRoot) $BundleDir
}

$archivePath = Join-Path $BundleDir "images\podman-images.tar"
$servicesFile = Join-Path $BundleDir "services.json"
$scriptsDir = Join-Path $BundleDir "scripts"
$infraScript = Join-Path $scriptsDir "deploy-infra-pods.ps1"
$appsScript = Join-Path $scriptsDir "deploy-springboot-pods.ps1"

if (-not (Test-Path -LiteralPath $archivePath)) {
    throw "Missing image archive: $archivePath"
}

if (-not (Test-Path -LiteralPath $servicesFile)) {
    throw "Missing services file: $servicesFile"
}

$previousErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = "Continue"
    $machineStartOutput = @(& podman machine start 2>&1)
    $machineStartExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($machineStartExitCode -ne 0 -and (($machineStartOutput -join " ") -notmatch "already running")) {
    throw "Could not start Podman machine. Output: $($machineStartOutput -join ' ')"
}

podman load --input $archivePath

& $infraScript `
    -SqlPassword $SqlPassword `
    -NetworkName $NetworkName `
    -KafkaImage $KafkaImage `
    -KafkaUiImage $KafkaUiImage `
    -SqlImage $SqlImage `
    -SqlAdminImage $SqlAdminImage `
    -LogViewerImage $LogViewerImage `
    -NifiImage $NifiImage `
    -ServicesFile $servicesFile `
    -NifiConfigFile (Join-Path $BundleDir "nifi-flows.yaml") `
    -ExternalHostName $ExternalHostName `
    -MssqlHostPort $MssqlHostPort `
    -MssqlVersionCheckSeconds $MssqlVersionCheckSeconds `
    -KafkaExternalHostPort $KafkaExternalHostPort `
    -KafkaUiHostPort $KafkaUiHostPort `
    -SqlAdminHostPort $SqlAdminHostPort `
    -LogViewerHostPort $LogViewerHostPort `
    -NifiHostPort $NifiHostPort `
    -NifiWaitTimeoutSeconds $NifiWaitTimeoutSeconds `
    -SkipNifiConfiguration:$SkipNifiConfiguration `
    -KeepMssqlDataOnVersionMismatch:$KeepMssqlDataOnVersionMismatch

& $appsScript `
    -ServicesFile $servicesFile `
    -SqlPassword $SqlPassword `
    -NetworkName $NetworkName `
    -SkipBuild

podman ps --pod
