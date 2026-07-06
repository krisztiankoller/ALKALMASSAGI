param(
    [string]$SqlPassword,

    [string]$NetworkName = "devnet",
    [string]$KafkaImage = "apache/kafka-native:3.9.0",
    [string]$KafkaUiImage = "ghcr.io/kafbat/kafka-ui:latest",
    [string]$SqlImage = "mcr.microsoft.com/mssql/server:2022-latest",
    [string]$SqlAdminImage = "dbgate/dbgate:latest",
    [string]$LogViewerImage = "amir20/dozzle:latest",
    [string]$NifiImage = "apache/nifi:1.28.1",
    [string]$ServicesFile = "",
    [string]$NifiConfigFile = "",
    [string]$LogArchiveDir = "",
    [string]$ExternalHostName = "",
    [int]$MssqlHostPort = 40000,
    [int]$KafkaExternalHostPort = 40001,
    [int]$KafkaUiHostPort = 40002,
    [int]$SqlAdminHostPort = 40003,
    [int]$LogViewerHostPort = 40004,
    [int]$NifiHostPort = 40011,
    [int]$NifiWaitTimeoutSeconds = 240,
    [switch]$SkipLogArchive,
    [switch]$SkipNifiConfiguration,
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    @'
deploy-infra-pods.ps1

Cel:
  Elinditja vagy ujrainditja a helyi infrastruktura podokat:
  SQL Server, Kafka, Kafka UI, DbGate SQL admin UI, Dozzle log viewer es
  Apache NiFi file-to-Kafka UI.

Hasznalat:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 -SqlPassword "<jelszo>" [opciok]

Localhost-only pelda:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
    -SqlPassword "Alkalmassagi_2026!" `
    -ExternalHostName localhost

Mit csinal:
  1. A scripts konyvtar szulojat projektgyokernek veszi.
  2. Letrehozza vagy ellenorzi a Podman networkot.
  3. Letrehozza az SQL Server volume-ot es a projekt alatti data konyvtarakat.
  4. DbGate kapcsolatokat general a services.json alapjan.
  5. Ujra letrehozza az infra podokat, ha mar leteznek.
  6. Elinditja:
     - mssql-pod / mssql
     - kafka-pod / kafka
     - kafka-ui-pod / kafka-ui
     - sql-admin-pod / sql-admin
     - log-viewer-pod / log-viewer
     - nifi-pod / nifi
  7. Opcionalisan nifi-flows.yaml alapjan letrehozza a NiFi file-to-Kafka flow-t.

Fontos:
  Ez a script a podokat ujra letrehozhatja. Az SQL adat volume megmarad,
  de a kontenerek/podok ujraindulnak.

Parameterek:
  -SqlPassword
      Kotelezo normal futasnal. Az SQL Server sa jelszava, es az appok DB
      kapcsolatai is ezt hasznaljak.

  -NetworkName
      Podman network neve. Alapertelmezett: devnet

  -KafkaImage, -KafkaUiImage, -SqlImage, -SqlAdminImage, -LogViewerImage, -NifiImage
      Hasznalt kontener image-ek.

  -ServicesFile
      services.json utvonala. Uresen: .\services.json
      Ez alapjan kerulnek be az app adatbazis kapcsolatok a DbGate UI-ba.

  -NifiConfigFile
      NiFi file-to-Kafka YAML config. Uresen: .\nifi-flows.yaml

  -LogArchiveDir
      Kontener log archive konyvtar. Uresen: .\data\logs
      Pod ujraletrehozas elott ide menti a regi kontenerlogokat.

  -SkipLogArchive
      Nem menti ki a regi podok logjait torles elott.

  -ExternalHostName
      Kafka external advertised listener hostneve.
      Localhost-only, admin jog nelkuli hasznalathoz: localhost
      LAN elereshez: gep IP vagy DNS nev, de ehhez firewall/portproxy is kellhet.

  -MssqlHostPort
      SQL Server host port. Alapertelmezett: 40000

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
      Ezt a reszletes leirast irja ki es nem indit podokat.

Bongeszos oldalak inditas utan:
  Kafka UI: http://localhost:40002
  SQL admin: http://localhost:40003
  Logs: http://localhost:40004
  NiFi: http://localhost:40011/nifi
'@
}

if ($Help) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrWhiteSpace($SqlPassword)) {
    throw "Missing required parameter: -SqlPassword. Use --help for detailed usage."
}

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DataRoot = Join-Path $ProjectRoot "data"
$MssqlBackupData = Join-Path $DataRoot "mssql-backups"
$KafkaData = Join-Path $DataRoot "kafka"
$CloudBeaverData = Join-Path $DataRoot "cloudbeaver"
$NifiData = Join-Path $DataRoot "nifi"
$NifiConf = Join-Path $NifiData "conf"
$NifiTemplateProperties = Join-Path $ProjectRoot "config\nifi\nifi.properties"
$NifiDropData = Join-Path $NifiData "drop"
$NifiLogs = Join-Path $NifiData "logs"
$NifiDatabaseRepository = Join-Path $NifiData "database_repository"
$NifiFlowFileRepository = Join-Path $NifiData "flowfile_repository"
$NifiContentRepository = Join-Path $NifiData "content_repository"
$NifiProvenanceRepository = Join-Path $NifiData "provenance_repository"
$NifiState = Join-Path $NifiData "state"
if ([string]::IsNullOrWhiteSpace($LogArchiveDir)) {
    $LogArchiveDir = Join-Path $DataRoot "logs"
} elseif (-not [System.IO.Path]::IsPathRooted($LogArchiveDir)) {
    $LogArchiveDir = Join-Path $ProjectRoot $LogArchiveDir
}
if ([string]::IsNullOrWhiteSpace($NifiConfigFile)) {
    $NifiConfigFile = Join-Path $ProjectRoot "nifi-flows.yaml"
} elseif (-not [System.IO.Path]::IsPathRooted($NifiConfigFile)) {
    $NifiConfigFile = Join-Path $ProjectRoot $NifiConfigFile
}

function Get-PrimaryIPv4Address {
    try {
        $address = Get-NetIPConfiguration |
            Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address } |
            Select-Object -ExpandProperty IPv4Address |
            Where-Object { $_.IPAddress -notlike "169.254.*" } |
            Select-Object -First 1 -ExpandProperty IPAddress

        if ($address) {
            return $address
        }
    }
    catch {
    }

    return $env:COMPUTERNAME
}

function Get-PodmanWslDistro {
    if ($script:PodmanWslDistro) {
        return $script:PodmanWslDistro
    }

    $distros = @(wsl.exe -l -q 2>$null |
        ForEach-Object { ($_ -replace "`0", "").Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $distro = $distros | Where-Object { $_ -eq "podman-machine-default" } | Select-Object -First 1
    if (-not $distro) {
        $distro = $distros | Where-Object { $_ -like "podman-machine-*" } | Select-Object -First 1
    }

    if (-not $distro) {
        throw "No Podman WSL distro was found. Run these first: podman machine init; podman machine start. Then check: podman machine list; wsl -l -v"
    }

    $script:PodmanWslDistro = $distro
    return $script:PodmanWslDistro
}

function ConvertTo-WslPath {
    param([string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $root = [System.IO.Path]::GetPathRoot($resolvedPath)
    if ([string]::IsNullOrWhiteSpace($root) -or $root.Length -lt 2 -or $root[1] -ne ":") {
        throw "Only local drive paths can be mounted into the Podman WSL machine. Path: $resolvedPath"
    }

    $drive = ([string]$root[0]).ToLowerInvariant()
    $relativePath = $resolvedPath.Substring($root.Length).Replace("\", "/")
    return "/mnt/$drive/$relativePath"
}

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Content
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Ensure-Network {
    param([string]$Name)

    podman network exists $Name 2>$null
    if ($LASTEXITCODE -ne 0) {
        podman network create $Name | Out-Null
    }
}

function Ensure-Volume {
    param([string]$Name)

    podman volume exists $Name 2>$null
    if ($LASTEXITCODE -ne 0) {
        podman volume create $Name | Out-Null
    }
}

function Save-PodLogs {
    param([string]$Name)

    if ($SkipLogArchive) {
        return
    }

    podman pod exists $Name 2>$null
    if ($LASTEXITCODE -ne 0) {
        return
    }

    $containers = @(podman ps -a --filter "pod=$Name" --format "{{.Names}}" 2>$null |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($containers.Count -eq 0) {
        return
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $targetDir = Join-Path $LogArchiveDir "$timestamp\$Name"
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    foreach ($container in $containers) {
        $safeName = ($container -replace '[^A-Za-z0-9_.-]', '_')
        $logPath = Join-Path $targetDir "$safeName.log"
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            & podman logs --timestamps $container > $logPath 2>&1
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    }
}

function Recreate-Pod {
    param(
        [string]$Name,
        [string[]]$PodArgs
    )

    podman pod exists $Name 2>$null
    if ($LASTEXITCODE -eq 0) {
        Save-PodLogs -Name $Name
        podman pod rm -f $Name | Out-Null
    }

    podman pod create --name $Name @PodArgs | Out-Null
}

function Ensure-CloudBeaverConfiguration {
    param(
        [string]$WorkspacePath,
        [string]$SqlPassword
    )

    $dbeaverConfigPath = Join-Path $WorkspacePath "GlobalConfiguration\.dbeaver"
    New-Item -ItemType Directory -Force -Path $dbeaverConfigPath | Out-Null

    $dataSources = [ordered]@{
        folders = [ordered]@{}
        connections = [ordered]@{
            "local-mssql" = [ordered]@{
                provider = "sqlserver"
                driver = "microsoft"
                name = "Local MSSQL"
                configuration = [ordered]@{
                    host = "mssql"
                    port = "1433"
                    database = "master"
                    url = "jdbc:sqlserver://mssql:1433;databaseName=master;encrypt=false;trustServerCertificate=true"
                    configurationType = "MANUAL"
                    type = "dev"
                    closeIdleConnection = $true
                    "auth-model" = "native"
                    "auth-properties" = [ordered]@{
                        userName = "sa"
                        userPassword = $SqlPassword
                    }
                    bootstrap = [ordered]@{
                        autocommit = $true
                    }
                    "provider-properties" = [ordered]@{
                        sslTrustServerCertificate = "true"
                    }
                }
            }
        }
    }

    $permissions = [ordered]@{
        "local-mssql" = @("user")
    }

    Write-Utf8File `
        -Path (Join-Path $dbeaverConfigPath "data-sources.json") `
        -Content ($dataSources | ConvertTo-Json -Depth 20)

    Write-Utf8File `
        -Path (Join-Path $dbeaverConfigPath "data-sources-permissions.json") `
        -Content ($permissions | ConvertTo-Json -Depth 10)
}

function Get-ServiceNames {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $ProjectRoot "services.json"
    } elseif (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path $ProjectRoot $Path
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return @("app1", "app2", "app3", "app4", "app5", "app6")
    }

    $services = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($services | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Add-DbGateConnectionEnv {
    param(
        [System.Collections.Generic.List[string]]$PodmanArgs,
        [string]$Key,
        [string]$Label,
        [string]$Database,
        [string]$SqlPassword
    )

    foreach ($item in @(
        @("LABEL_$Key", $Label),
        @("SERVER_$Key", "mssql"),
        @("USER_$Key", "sa"),
        @("PASSWORD_$Key", $SqlPassword),
        @("PORT_$Key", "1433"),
        @("DATABASE_$Key", $Database),
        @("ENGINE_$Key", "mssql@dbgate-plugin-mssql"),
        @("AUTH_TYPE_$Key", "tedious"),
        @("SSL_TRUST_CERTIFICATE_$Key", "1")
    )) {
        $PodmanArgs.Add("-e")
        $PodmanArgs.Add("$($item[0])=$($item[1])")
    }
}

function Sync-NifiConfigurationData {
    param(
        [string]$ConfPath,
        [string]$NifiImage,
        [string]$TemplatePropertiesPath
    )

    $nifiPropertiesPath = Join-Path $ConfPath "nifi.properties"
    podman container exists nifi 2>$null
    if ($LASTEXITCODE -eq 0) {
        podman cp "nifi:/opt/nifi/nifi-current/conf/." $ConfPath | Out-Null
        if (Test-Path -LiteralPath $nifiPropertiesPath) {
            return
        }
    }

    if (Test-Path -LiteralPath $nifiPropertiesPath) {
        return
    }

    $tempContainerName = "nifi-conf-template-$([guid]::NewGuid().ToString('N'))"
    try {
        podman create --name $tempContainerName $NifiImage | Out-Null
        podman cp "${tempContainerName}:/opt/nifi/nifi-current/conf/." $ConfPath | Out-Null
    }
    finally {
        podman rm -f $tempContainerName 2>$null | Out-Null
    }

    if (-not (Test-Path -LiteralPath $nifiPropertiesPath) -and (Test-Path -LiteralPath $TemplatePropertiesPath)) {
        Copy-Item -LiteralPath $TemplatePropertiesPath -Destination $nifiPropertiesPath -Force
    }

    if (-not (Test-Path -LiteralPath $nifiPropertiesPath)) {
        throw "Could not create NiFi properties file: $nifiPropertiesPath. Check that image '$NifiImage' contains /opt/nifi/nifi-current/conf/nifi.properties."
    }
}

function Set-NifiUnsecuredConfiguration {
    param(
        [string]$ConfPath,
        [string]$SensitivePropsKey
    )

    $propertiesPath = Join-Path $ConfPath "nifi.properties"
    if (-not (Test-Path -LiteralPath $propertiesPath)) {
        throw "Missing NiFi properties file: $propertiesPath"
    }

    Get-ChildItem -LiteralPath $ConfPath -File -Recurse | ForEach-Object {
        if ($_.IsReadOnly) {
            $_.IsReadOnly = $false
        }
    }

    $content = Get-Content -LiteralPath $propertiesPath -Raw -Encoding UTF8
    $replacements = [ordered]@{
        "nifi.web.http.host" = "0.0.0.0"
        "nifi.web.http.port" = "8080"
        "nifi.web.https.host" = ""
        "nifi.web.https.port" = ""
        "nifi.security.user.authorizer" = ""
        "nifi.security.user.login.identity.provider" = ""
        "nifi.sensitive.props.key" = $SensitivePropsKey
    }

    foreach ($key in $replacements.Keys) {
        $escapedKey = [regex]::Escape($key)
        $value = $replacements[$key]
        if ($content -match "(?m)^$escapedKey=.*$") {
            $content = [regex]::Replace($content, "(?m)^$escapedKey=.*$", "$key=$value")
        } else {
            $content = $content.TrimEnd() + "`n$key=$value`n"
        }
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($propertiesPath, $content, $utf8NoBom)
}

Ensure-Network $NetworkName
Ensure-Volume "mssql-data"
New-Item -ItemType Directory -Force -Path $MssqlBackupData | Out-Null
New-Item -ItemType Directory -Force -Path $KafkaData | Out-Null
New-Item -ItemType Directory -Force -Path $CloudBeaverData | Out-Null
foreach ($path in @(
    $NifiConf,
    $NifiDropData,
    $NifiLogs,
    $NifiDatabaseRepository,
    $NifiFlowFileRepository,
    $NifiContentRepository,
    $NifiProvenanceRepository,
    $NifiState
)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}
Sync-NifiConfigurationData -ConfPath $NifiConf -NifiImage $NifiImage -TemplatePropertiesPath $NifiTemplateProperties
Set-NifiUnsecuredConfiguration -ConfPath $NifiConf -SensitivePropsKey "AlkalmassagiLocalOnlyKey2026"
Ensure-CloudBeaverConfiguration -WorkspacePath $CloudBeaverData -SqlPassword $SqlPassword

if ([string]::IsNullOrWhiteSpace($ExternalHostName)) {
    $ExternalHostName = Get-PrimaryIPv4Address
}

$ServiceNames = Get-ServiceNames -Path $ServicesFile

$MssqlBackupDataWsl = ConvertTo-WslPath $MssqlBackupData
$KafkaDataWsl = ConvertTo-WslPath $KafkaData
$CloudBeaverDataWsl = ConvertTo-WslPath $CloudBeaverData
$NifiConfWsl = ConvertTo-WslPath $NifiConf
$NifiDropDataWsl = ConvertTo-WslPath $NifiDropData
$NifiLogsWsl = ConvertTo-WslPath $NifiLogs
$NifiDatabaseRepositoryWsl = ConvertTo-WslPath $NifiDatabaseRepository
$NifiFlowFileRepositoryWsl = ConvertTo-WslPath $NifiFlowFileRepository
$NifiContentRepositoryWsl = ConvertTo-WslPath $NifiContentRepository
$NifiProvenanceRepositoryWsl = ConvertTo-WslPath $NifiProvenanceRepository
$NifiStateWsl = ConvertTo-WslPath $NifiState
$podmanWslDistro = Get-PodmanWslDistro
$mkdirOutput = @(wsl.exe -d $podmanWslDistro -- mkdir -p $MssqlBackupDataWsl $KafkaDataWsl $CloudBeaverDataWsl $NifiConfWsl $NifiDropDataWsl $NifiLogsWsl $NifiDatabaseRepositoryWsl $NifiFlowFileRepositoryWsl $NifiContentRepositoryWsl $NifiProvenanceRepositoryWsl $NifiStateWsl 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Could not create data directories inside Podman WSL distro '$podmanWslDistro'. Output: $($mkdirOutput -join ' ')"
}

Recreate-Pod "mssql-pod" @(
    "--network", $NetworkName,
    "--network-alias", "mssql",
    "--publish", "0.0.0.0:${MssqlHostPort}:1433"
)

podman run -d `
    --pod mssql-pod `
    --name mssql `
    -e "ACCEPT_EULA=Y" `
    -e "MSSQL_SA_PASSWORD=$SqlPassword" `
    -e "MSSQL_PID=Developer" `
    -v "mssql-data:/var/opt/mssql" `
    -v "${MssqlBackupDataWsl}:/var/opt/mssql/backup" `
    $SqlImage

Recreate-Pod "kafka-pod" @(
    "--network", $NetworkName,
    "--network-alias", "kafka",
    "--publish", "0.0.0.0:${KafkaExternalHostPort}:${KafkaExternalHostPort}"
)

podman run -d `
    --pod kafka-pod `
    --name kafka `
    -e "KAFKA_NODE_ID=1" `
    -e "KAFKA_PROCESS_ROLES=broker,controller" `
    -e "KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka:9093" `
    -e "KAFKA_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093,EXTERNAL://:${KafkaExternalHostPort}" `
    -e "KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092,EXTERNAL://${ExternalHostName}:${KafkaExternalHostPort}" `
    -e "KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER" `
    -e "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,EXTERNAL:PLAINTEXT" `
    -e "KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT" `
    -e "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1" `
    -e "KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1" `
    -e "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1" `
    -e "KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0" `
    -e "CLUSTER_ID=abcdefghijklmnopqrstuv" `
    -v "${KafkaDataWsl}:/var/lib/kafka/data" `
    $KafkaImage

Recreate-Pod "kafka-ui-pod" @(
    "--network", $NetworkName,
    "--network-alias", "kafka-ui",
    "--publish", "0.0.0.0:${KafkaUiHostPort}:8080"
)

podman run -d `
    --pod kafka-ui-pod `
    --name kafka-ui `
    -e "DYNAMIC_CONFIG_ENABLED=true" `
    -e "KAFKA_CLUSTERS_0_NAME=local" `
    -e "KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS=kafka:9092" `
    $KafkaUiImage

Recreate-Pod "sql-admin-pod" @(
    "--network", $NetworkName,
    "--network-alias", "sql-admin",
    "--publish", "0.0.0.0:${SqlAdminHostPort}:3000"
)

$sqlAdminArgs = [System.Collections.Generic.List[string]]::new()
foreach ($arg in @(
    "run", "-d",
    "--pod", "sql-admin-pod",
    "--name", "sql-admin",
    "-e", "SKIP_ALL_AUTH=1",
    "-e", "NODE_TLS_REJECT_UNAUTHORIZED=0",
    "-e", "NODE_TL_REJECT_UNAUTHORIZED=0",
    "-e", "CONNECTIONS=mssql,$($ServiceNames -join ',')"
)) {
    $sqlAdminArgs.Add($arg)
}

Add-DbGateConnectionEnv -PodmanArgs $sqlAdminArgs -Key "mssql" -Label "Local MSSQL" -Database "master" -SqlPassword $SqlPassword
foreach ($serviceName in $ServiceNames) {
    Add-DbGateConnectionEnv -PodmanArgs $sqlAdminArgs -Key $serviceName -Label "${serviceName}_audit" -Database "${serviceName}_audit" -SqlPassword $SqlPassword
}

$sqlAdminArgs.Add("-v")
$sqlAdminArgs.Add("${CloudBeaverDataWsl}:/root/.dbgate")
$sqlAdminArgs.Add($SqlAdminImage)

& podman @sqlAdminArgs

Recreate-Pod "log-viewer-pod" @(
    "--network", $NetworkName,
    "--network-alias", "log-viewer",
    "--publish", "0.0.0.0:${LogViewerHostPort}:8080"
)

podman run -d `
    --pod log-viewer-pod `
    --name log-viewer `
    --security-opt "label=disable" `
    -v "/var/run/docker.sock:/var/run/docker.sock:ro" `
    $LogViewerImage

Recreate-Pod "nifi-pod" @(
    "--network", $NetworkName,
    "--network-alias", "nifi",
    "--publish", "0.0.0.0:${NifiHostPort}:8080"
)

podman run -d `
    --pod nifi-pod `
    --name nifi `
    -e "NIFI_WEB_HTTP_HOST=0.0.0.0" `
    -e "NIFI_WEB_HTTP_PORT=8080" `
    -e "NIFI_WEB_PROXY_HOST=localhost:${NifiHostPort}" `
    -e "NIFI_REMOTE_INPUT_SECURE=false" `
    -e "NIFI_SECURITY_USER_AUTHORIZER=" `
    -e "NIFI_SECURITY_USER_LOGIN_IDENTITY_PROVIDER=" `
    -e "NIFI_SENSITIVE_PROPS_KEY=AlkalmassagiLocalOnlyKey2026" `
    -v "${NifiConfWsl}:/opt/nifi/nifi-current/conf" `
    -v "${NifiDropDataWsl}:/data/nifi/drop" `
    -v "${NifiLogsWsl}:/opt/nifi/nifi-current/logs" `
    -v "${NifiDatabaseRepositoryWsl}:/opt/nifi/nifi-current/database_repository" `
    -v "${NifiFlowFileRepositoryWsl}:/opt/nifi/nifi-current/flowfile_repository" `
    -v "${NifiContentRepositoryWsl}:/opt/nifi/nifi-current/content_repository" `
    -v "${NifiProvenanceRepositoryWsl}:/opt/nifi/nifi-current/provenance_repository" `
    -v "${NifiStateWsl}:/opt/nifi/nifi-current/state" `
    $NifiImage

if (-not $SkipNifiConfiguration) {
    $nifiConfigScript = Join-Path $PSScriptRoot "configure-nifi-file-to-kafka.ps1"
    if (-not (Test-Path -LiteralPath $nifiConfigScript)) {
        throw "NiFi configuration script does not exist: $nifiConfigScript"
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $nifiConfigScript `
        -ConfigFile $NifiConfigFile `
        -NifiBaseUrl "http://localhost:${NifiHostPort}" `
        -WaitTimeoutSeconds $NifiWaitTimeoutSeconds
    if ($LASTEXITCODE -ne 0) {
        throw "NiFi file-to-Kafka configuration failed with exit code $LASTEXITCODE"
    }
}

podman ps --pod
