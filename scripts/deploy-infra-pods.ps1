param(
    [string]$SqlPassword,

    [string]$NetworkName = "devnet",
    [string]$KafkaImage = "apache/kafka-native:3.9.0",
    [string]$KafkaCliImage = "apache/kafka:3.9.0",
    [string]$KafkaUiImage = "ghcr.io/kafbat/kafka-ui:latest",
    [string]$SqlImage = "mcr.microsoft.com/mssql/server:2019-latest",
    [string]$SqlAdminImage = "dbgate/dbgate:latest",
    [string]$LogViewerImage = "amir20/dozzle:latest",
    [string]$NifiImage = "apache/nifi:1.28.1",
    [string]$ServicesFile = "",
    [string]$NifiConfigFile = "",
    [string]$LogArchiveDir = "",
    [string]$ExternalHostName = "",
    [int]$MssqlHostPort = 40000,
    [int]$MssqlVersionCheckSeconds = 30,
    [int]$KafkaExternalHostPort = 40001,
    [int]$KafkaUiHostPort = 40002,
    [int]$SqlAdminHostPort = 40003,
    [int]$LogViewerHostPort = 40004,
    [int]$NifiHostPort = 40011,
    [int]$NifiWaitTimeoutSeconds = 240,
    [switch]$SkipLogArchive,
    [switch]$SkipNifiConfiguration,
    [switch]$KeepMssqlDataOnVersionMismatch,
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
  3. Letrehozza az SQL Server volume-ot es javitja a volume jogosultsagait.
     Ez fontos, mert az SQL Server kontener nem rootkent fut.
  4. Letrehozza a projekt alatti data konyvtarakat.
  5. Beolvassa a services.json kafkaTopics es databases katalogusait.
  6. Letrehozza a hianyzo kezelt MSSQL adatbazisokat/audit tablakat.
  7. Letrehozza a hianyzo kezelt Kafka topicokat.
  8. Torli azokat a korabban kezelt DB/topic resource-okat, amelyek mar
     nincsenek a services.json fajlban.
  9. DbGate kapcsolatokat general a services.json databases katalogusa alapjan.
  10. Ujra letrehozza az infra podokat, ha mar leteznek.
  11. Elinditja:
     - mssql-pod / mssql
     - kafka-pod / kafka
     - kafka-ui-pod / kafka-ui
     - sql-admin-pod / sql-admin
     - log-viewer-pod / log-viewer
     - nifi-pod / nifi
  12. Opcionalisan nifi-flows.yaml alapjan letrehozza a NiFi file-to-Kafka flow-t.

Fontos:
  Ez a script a podokat ujra letrehozhatja. Az SQL adat volume megmarad,
  de a kontenerek/podok ujraindulnak.

Parameterek:
  -SqlPassword
      Kotelezo normal futasnal. Az SQL Server sa jelszava, es az appok DB
      kapcsolatai is ezt hasznaljak.

  -NetworkName
      Podman network neve. Alapertelmezett: devnet

  -KafkaImage, -KafkaCliImage, -KafkaUiImage, -SqlImage, -SqlAdminImage, -LogViewerImage, -NifiImage
      Hasznalt kontener image-ek. A Kafka broker alapbol apache/kafka-native,
      a topic admin parancsokhoz kulon apache/kafka CLI helper image fut.

  -ServicesFile
      services.json utvonala. Uresen: .\services.json
      Ez alapjan jonnek letre a kezelt Kafka topicok, MSSQL audit DB-k,
      audit tablak es DbGate kapcsolatok. A torleshez a script ezt a state
      fajlt hasznalja: .\data\managed-resources.json

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

  -MssqlVersionCheckSeconds
      Ennyi masodpercig figyeli az MSSQL indulasi logot verzio inkompatibilitas
      miatt. Alapertelmezett: 30

  -KeepMssqlDataOnVersionMismatch
      Ha SQL Server downgrade/verzio inkompatibilitas latszik, ne torolje az
      mssql-data volume-ot, hanem alljon meg hibaval. Alapertelmezetten a script
      torli es ujraletrehozza az mssql-data volume-ot, mert ez a local/offline
      fejlesztoi stack nullarol is indulhat.

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
$ResourceStateFile = Join-Path $DataRoot "managed-resources.json"
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
    param(
        [string]$Name,
        [int]$Uid = -1,
        [int]$Gid = -1
    )

    podman volume exists $Name 2>$null
    if ($LASTEXITCODE -ne 0) {
        $volumeArgs = [System.Collections.Generic.List[string]]::new()
        $volumeArgs.Add("volume")
        $volumeArgs.Add("create")
        if ($Uid -ge 0) {
            $volumeArgs.Add("--uid")
            $volumeArgs.Add([string]$Uid)
        }
        if ($Gid -ge 0) {
            $volumeArgs.Add("--gid")
            $volumeArgs.Add([string]$Gid)
        }
        $volumeArgs.Add($Name)
        & podman @volumeArgs | Out-Null
    }
}

function Repair-MssqlVolumePermissions {
    param(
        [string]$VolumeName,
        [string]$SqlImage
    )

    Write-Output "Ensuring MSSQL volume permissions for volume '$VolumeName'..."
    $permissionCommand = "chown -R 10001:0 /var/opt/mssql && chmod -R g=u /var/opt/mssql && chmod -R u+rwX /var/opt/mssql"
    $podmanArgs = @(
        "run",
        "--rm",
        "--user",
        "0",
        "-v",
        "${VolumeName}:/var/opt/mssql",
        $SqlImage,
        "bash",
        "-lc",
        $permissionCommand
    )

    $output = @(& podman @podmanArgs 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not repair MSSQL volume permissions for '$VolumeName'. Output: $($output -join ' ')"
    }
}

function Test-MssqlVersionMismatch {
    param(
        [string]$ContainerName,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $logs = @(& podman logs $ContainerName 2>&1)
        $text = $logs -join "`n"

        if ($text -match "A downgrade path is not supported" -or
            ($text -match "cannot be opened because it is version" -and $text -match "This server supports version") -or
            $text -match "Error:\s*948") {
            return $true
        }

        if ($text -match "SQL Server is now ready for client connections" -or
            $text -match "Recovery is complete") {
            return $false
        }

        $state = @(& podman inspect $ContainerName --format "{{.State.Status}}" 2>$null)
        if ($LASTEXITCODE -eq 0 -and (($state -join " ") -match "^(exited|dead)$")) {
            return $false
        }

        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Reset-MssqlDataVolume {
    param(
        [string]$VolumeName,
        [string]$SqlImage
    )

    Write-Output "Resetting incompatible MSSQL data volume '$VolumeName'. SQL data will start from zero."

    podman pod exists "mssql-pod" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Save-PodLogs -Name "mssql-pod"
        podman pod rm -f "mssql-pod" | Out-Null
    }

    podman volume rm -f $VolumeName | Out-Null
    Ensure-Volume -Name $VolumeName -Uid 10001 -Gid 0
    Repair-MssqlVolumePermissions -VolumeName $VolumeName -SqlImage $SqlImage
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

function Start-MssqlPod {
    param(
        [string]$NetworkName,
        [int]$MssqlHostPort,
        [string]$SqlPassword,
        [string]$SqlImage,
        [string]$MssqlBackupDataWsl
    )

    Recreate-Pod "mssql-pod" @(
        "--network", $NetworkName,
        "--network-alias", "mssql",
        "--publish", "0.0.0.0:${MssqlHostPort}:1433"
    )

    $podmanArgs = @(
        "run",
        "-d",
        "--pod", "mssql-pod",
        "--name", "mssql",
        "-e", "ACCEPT_EULA=Y",
        "-e", "MSSQL_SA_PASSWORD=$SqlPassword",
        "-e", "MSSQL_PID=Developer",
        "-e", "HOME=/var/opt/mssql",
        "-v", "mssql-data:/var/opt/mssql",
        "-v", "${MssqlBackupDataWsl}:/var/opt/mssql/backup",
        $SqlImage
    )

    $output = @(& podman @podmanArgs 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not start MSSQL container. Output: $($output -join ' ')"
    }
    $output | ForEach-Object { Write-Output $_ }
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

function Get-JsonPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )
    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Get-ServicesConfig {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $ProjectRoot "services.json"
    } elseif (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path $ProjectRoot $Path
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        $defaultServices = @("app1", "app2", "app3", "app4", "app5", "app6") | ForEach-Object {
            [pscustomobject]@{
                name = $_
            }
        }
        return [ordered]@{
            services = @($defaultServices)
            kafkaTopics = $null
            databases = $null
        }
    }

    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $serviceList = Get-JsonPropertyValue -Object $json -Name "services"
    if ($null -eq $serviceList) {
        $serviceList = $json
    }
    return [ordered]@{
        services = @($serviceList)
        kafkaTopics = Get-JsonPropertyValue -Object $json -Name "kafkaTopics"
        databases = Get-JsonPropertyValue -Object $json -Name "databases"
    }
}

function Get-ConfigMapEntry {
    param(
        [object]$Map,
        [string]$Key,
        [string]$MapName
    )
    if ([string]::IsNullOrWhiteSpace($Key)) {
        return $null
    }
    $entry = Get-JsonPropertyValue -Object $Map -Name $Key
    if ($null -eq $entry) {
        throw "Unknown $MapName reference '$Key' in services.json."
    }
    return $entry
}

function Get-JsonBooleanValue {
    param(
        [object]$Object,
        [string]$Name,
        [bool]$DefaultValue
    )

    $value = Get-JsonPropertyValue -Object $Object -Name $Name
    if ($null -eq $value) {
        return $DefaultValue
    }
    if ($value -is [bool]) {
        return [bool]$value
    }
    return [System.Convert]::ToBoolean([string]$value)
}

function Assert-ResourceIdentifier {
    param(
        [string]$Value,
        [string]$Purpose
    )
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch "^[A-Za-z0-9_.-]+$") {
        throw "Invalid $Purpose '$Value'. Use only letters, numbers, underscore, dot or dash."
    }
    return $Value
}

function Assert-SqlResourceIdentifier {
    param(
        [string]$Value,
        [string]$Purpose
    )
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch "^[A-Za-z0-9_]+$") {
        throw "Invalid $Purpose '$Value'. Use only letters, numbers or underscore. This must match the Spring app SQL identifier validation."
    }
    return $Value
}

function Get-ResourceCatalog {
    param([string]$Path)

    $config = Get-ServicesConfig -Path $Path
    $databases = [System.Collections.Generic.List[object]]::new()
    $topics = [System.Collections.Generic.List[object]]::new()

    if ($null -ne $config.databases) {
        foreach ($property in $config.databases.PSObject.Properties) {
            $database = $property.Value
            $databaseName = Assert-SqlResourceIdentifier -Value ([string](Get-JsonPropertyValue -Object $database -Name "name")) -Purpose "database name"
            $schemaName = [string](Get-JsonPropertyValue -Object $database -Name "schema")
            $managed = Get-JsonBooleanValue -Object $database -Name "managed" -DefaultValue $true
            $connectionString = [string](Get-JsonPropertyValue -Object $database -Name "connectionString")
            $username = [string](Get-JsonPropertyValue -Object $database -Name "username")
            $password = [string](Get-JsonPropertyValue -Object $database -Name "password")
            if ([string]::IsNullOrWhiteSpace($schemaName)) {
                $schemaName = "dbo"
            }
            $schemaScript = [string](Get-JsonPropertyValue -Object $database -Name "schemaScript")
            if ($managed -and [string]::IsNullOrWhiteSpace($schemaScript)) {
                throw "Database resource '$($property.Name)' must have a schemaScript field in services.json."
            }
            Assert-SqlResourceIdentifier -Value $schemaName -Purpose "schema name" | Out-Null
            $databases.Add([pscustomobject]@{
                key = [string]$property.Name
                name = $databaseName
                schema = $schemaName
                managed = $managed
                connectionString = $connectionString
                username = $username
                password = $password
                schemaScript = $schemaScript
            })
        }
    }

    if ($null -ne $config.kafkaTopics) {
        foreach ($property in $config.kafkaTopics.PSObject.Properties) {
            $topic = $property.Value
            $topicName = Assert-ResourceIdentifier -Value ([string](Get-JsonPropertyValue -Object $topic -Name "name")) -Purpose "Kafka topic name"
            $partitions = Get-JsonPropertyValue -Object $topic -Name "partitions"
            $replicas = Get-JsonPropertyValue -Object $topic -Name "replicas"
            $topics.Add([pscustomobject]@{
                key = [string]$property.Name
                name = $topicName
                partitions = if ($null -ne $partitions) { [int]$partitions } else { 1 }
                replicas = if ($null -ne $replicas) { [int]$replicas } else { 1 }
            })
        }
    }

    return [ordered]@{
        databases = @($databases)
        kafkaTopics = @($topics)
    }
}

function Get-DatabaseConnections {
    param([object[]]$Databases)

    $connections = [System.Collections.Generic.List[object]]::new()
    foreach ($database in $Databases) {
        $connectionString = [string]$database.connectionString
        $server = "mssql"
        $port = "1433"
        $databaseName = [string]$database.name
        if ($connectionString -match "^jdbc:sqlserver://([^;:/]+)(?::([0-9]+))?") {
            $server = $Matches[1]
            if (-not [string]::IsNullOrWhiteSpace($Matches[2])) {
                $port = $Matches[2]
            }
        }
        if ($connectionString -match "(?i)(?:;|^)databaseName=([^;]+)") {
            $databaseName = $Matches[1]
        }
        $username = [string]$database.username
        if ([string]::IsNullOrWhiteSpace($username)) {
            $username = "sa"
        }
        $connections.Add([pscustomobject]@{
            key = [string]$database.key
            label = [string]$database.name
            server = $server
            port = $port
            database = $databaseName
            username = $username
            password = [string]$database.password
        })
    }
    return @($connections)
}

function Read-ManagedResourceState {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{
            databases = @()
            kafkaTopics = @()
        }
    }
    $state = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return [ordered]@{
        databases = @($state.databases | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        kafkaTopics = @($state.kafkaTopics | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
}

function Write-ManagedResourceState {
    param(
        [string]$Path,
        [object[]]$Databases,
        [object[]]$KafkaTopics
    )

    $state = [ordered]@{
        databases = @($Databases | Where-Object { $_.managed } | ForEach-Object { [string]$_.name } | Sort-Object -Unique)
        kafkaTopics = @($KafkaTopics | ForEach-Object { [string]$_.name } | Sort-Object -Unique)
    }
    Write-Utf8File -Path $Path -Content ($state | ConvertTo-Json -Depth 10)
}

function Invoke-KafkaTopicsCommand {
    param([string[]]$KafkaArgs)

    $output = @(& podman run --rm --network $NetworkName $KafkaCliImage /opt/kafka/bin/kafka-topics.sh @KafkaArgs 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Kafka topics command failed: kafka-topics.sh $($KafkaArgs -join ' '). Output: $($output -join ' ')"
    }
    return $output
}

function Wait-KafkaReady {
    param([int]$TimeoutSeconds = 120)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $output = @(& podman run --rm --network $NetworkName $KafkaCliImage /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list 2>&1)
        if ($LASTEXITCODE -eq 0) {
            return
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    throw "Kafka did not become ready within $TimeoutSeconds seconds. Last output: $($output -join ' ')"
}

function Sync-KafkaTopicResources {
    param(
        [object[]]$Topics,
        [string[]]$PreviouslyManagedTopics
    )

    $currentTopicNames = @($Topics | ForEach-Object { [string]$_.name })
    foreach ($oldTopic in $PreviouslyManagedTopics) {
        if ($currentTopicNames -notcontains $oldTopic) {
            Write-Output "Deleting managed Kafka topic not present in services.json anymore: $oldTopic"
            Invoke-KafkaTopicsCommand -KafkaArgs @("--bootstrap-server", "kafka:9092", "--delete", "--if-exists", "--topic", $oldTopic) | Out-Null
        }
    }

    foreach ($topic in $Topics) {
        Write-Output "Ensuring Kafka topic: $($topic.name)"
        Invoke-KafkaTopicsCommand -KafkaArgs @(
            "--bootstrap-server", "kafka:9092",
            "--create",
            "--if-not-exists",
            "--topic", [string]$topic.name,
            "--partitions", [string]$topic.partitions,
            "--replication-factor", [string]$topic.replicas
        ) | Out-Null
    }
}

function ConvertTo-SqlLiteral {
    param([string]$Value)
    return "N'$($Value.Replace("'", "''"))'"
}

function ConvertTo-SqlIdentifier {
    param([string]$Value)
    Assert-SqlResourceIdentifier -Value $Value -Purpose "SQL identifier" | Out-Null
    return "[$($Value.Replace("]", "]]"))]"
}

function Resolve-ProjectFilePath {
    param(
        [string]$Path,
        [string]$Purpose
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Missing $Purpose path."
    }
    $resolvedPath = $Path
    if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
        $resolvedPath = Join-Path $ProjectRoot $resolvedPath
    }
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "$Purpose file does not exist: $resolvedPath"
    }
    return (Resolve-Path -LiteralPath $resolvedPath).Path
}

function Get-DatabaseSchemaScriptSql {
    param([object]$Database)

    $scriptPath = Resolve-ProjectFilePath -Path ([string]$Database.schemaScript) -Purpose "Database schemaScript"
    return Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
}

function Invoke-MssqlSql {
    param(
        [string]$Sql,
        [string]$SqlPassword
    )

    $encodedSql = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Sql))
    $command = "set -e; if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then sqlcmd=/opt/mssql-tools18/bin/sqlcmd; elif [ -x /opt/mssql-tools/bin/sqlcmd ]; then sqlcmd=/opt/mssql-tools/bin/sqlcmd; elif command -v sqlcmd >/dev/null 2>&1; then sqlcmd=`$(command -v sqlcmd); else echo 'sqlcmd was not found in the mssql container.'; exit 45; fi; printf '%s' '$encodedSql' | base64 -d > /tmp/alkalmassagi-resource.sql; `"`$sqlcmd`" -S localhost -U sa -P `"`$SQLCMDPASSWORD`" -C -b -i /tmp/alkalmassagi-resource.sql"
    $output = @(& podman exec -e "SQLCMDPASSWORD=$SqlPassword" mssql bash -lc $command 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "SQL resource command failed. Output: $($output -join ' ')"
    }
    return $output
}

function Wait-MssqlReady {
    param(
        [string]$SqlPassword,
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            Invoke-MssqlSql -Sql "SELECT 1;" -SqlPassword $SqlPassword | Out-Null
            return
        }
        catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Seconds 2
        }
    } while ((Get-Date) -lt $deadline)

    throw "MSSQL did not become ready within $TimeoutSeconds seconds. Last error: $lastError"
}

function Sync-MssqlDatabaseResources {
    param(
        [object[]]$Databases,
        [string[]]$PreviouslyManagedDatabases,
        [string]$SqlPassword
    )

    $managedDatabases = @($Databases | Where-Object { $_.managed })
    $currentDatabaseNames = @($Databases | ForEach-Object { [string]$_.name })
    foreach ($oldDatabase in $PreviouslyManagedDatabases) {
        if ($currentDatabaseNames -notcontains $oldDatabase) {
            Write-Output "Dropping managed MSSQL database not present in services.json anymore: $oldDatabase"
            $dropSql = @"
IF DB_ID($(ConvertTo-SqlLiteral $oldDatabase)) IS NOT NULL
BEGIN
    ALTER DATABASE $(ConvertTo-SqlIdentifier $oldDatabase) SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE $(ConvertTo-SqlIdentifier $oldDatabase);
END
"@
            Invoke-MssqlSql -Sql $dropSql -SqlPassword $SqlPassword | Out-Null
        }
    }

    foreach ($database in $managedDatabases) {
        Write-Output "Ensuring MSSQL database: $($database.name)"
        $databaseName = [string]$database.name
        $createDatabaseSql = @"
IF DB_ID($(ConvertTo-SqlLiteral $databaseName)) IS NULL
BEGIN
    CREATE DATABASE $(ConvertTo-SqlIdentifier $databaseName);
END
"@
        Invoke-MssqlSql -Sql $createDatabaseSql -SqlPassword $SqlPassword | Out-Null

        if (-not [string]::IsNullOrWhiteSpace([string]$database.schemaScript)) {
            Write-Output "Running MSSQL schema script for $($database.name): $($database.schemaScript)"
            $schemaSql = @"
USE $(ConvertTo-SqlIdentifier $databaseName);
$(Get-DatabaseSchemaScriptSql -Database $database)
"@
            Invoke-MssqlSql -Sql $schemaSql -SqlPassword $SqlPassword | Out-Null
        }
    }
}

function Add-DbGateConnectionEnv {
    param(
        [System.Collections.Generic.List[string]]$PodmanArgs,
        [string]$Key,
        [string]$Label,
        [string]$Server,
        [string]$Port,
        [string]$Database,
        [string]$Username,
        [string]$Password
    )

    foreach ($item in @(
        @("LABEL_$Key", $Label),
        @("SERVER_$Key", $Server),
        @("USER_$Key", $Username),
        @("PASSWORD_$Key", $Password),
        @("PORT_$Key", $Port),
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

    $requiredConfigFiles = @(
        "bootstrap.conf",
        "nifi.properties",
        "logback.xml",
        "state-management.xml",
        "authorizers.xml",
        "login-identity-providers.xml"
    )

    function Get-MissingNifiConfigFiles {
        param(
            [string]$Path,
            [string[]]$RequiredFiles
        )

        return @($RequiredFiles | Where-Object {
                -not (Test-Path -LiteralPath (Join-Path $Path $_) -PathType Leaf)
            })
    }

    function Copy-MissingNifiConfigFilesFromImage {
        param(
            [string]$NifiImage,
            [string]$TargetPath,
            [string[]]$RequiredFiles
        )

        foreach ($file in $RequiredFiles) {
            $target = Join-Path $TargetPath $file
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                continue
            }

            $source = "/opt/nifi/nifi-current/conf/$file"
            $readCommand = "if [ -f '$source' ]; then base64 '$source' | tr -d '\n'; else exit 44; fi"
            $encodedOutput = @(& podman run --rm --entrypoint bash $NifiImage -lc $readCommand 2>&1)
            if ($LASTEXITCODE -eq 0) {
                $encoded = ($encodedOutput -join "").Trim()
                [System.IO.File]::WriteAllBytes($target, [System.Convert]::FromBase64String($encoded))
            } elseif ($file -eq "nifi.properties" -and (Test-Path -LiteralPath $TemplatePropertiesPath -PathType Leaf)) {
                Copy-Item -LiteralPath $TemplatePropertiesPath -Destination $target -Force
            } else {
                Write-Output "Could not copy NiFi config file '$file' from image '$NifiImage'. Output: $($encodedOutput -join ' ')"
            }
        }
    }

    New-Item -ItemType Directory -Force -Path $ConfPath | Out-Null

    $nifiPropertiesPath = Join-Path $ConfPath "nifi.properties"
    if ((-not (Test-Path -LiteralPath $nifiPropertiesPath -PathType Leaf)) -and
        (Test-Path -LiteralPath $TemplatePropertiesPath -PathType Leaf)) {
        Copy-Item -LiteralPath $TemplatePropertiesPath -Destination $nifiPropertiesPath -Force
    }

    $missingFiles = @(Get-MissingNifiConfigFiles -Path $ConfPath -RequiredFiles $requiredConfigFiles)
    if ($missingFiles.Count -eq 0) {
        return
    }

    Copy-MissingNifiConfigFilesFromImage -NifiImage $NifiImage -TargetPath $ConfPath -RequiredFiles $requiredConfigFiles

    $missingFiles = @(Get-MissingNifiConfigFiles -Path $ConfPath -RequiredFiles $requiredConfigFiles)
    if ($missingFiles.Count -gt 0) {
        throw "Could not create required NiFi config files in '$ConfPath': $($missingFiles -join ', '). Check that image '$NifiImage' contains /opt/nifi/nifi-current/conf."
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
Ensure-Volume -Name "mssql-data" -Uid 10001 -Gid 0
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

$ResourceCatalog = Get-ResourceCatalog -Path $ServicesFile
$ManagedResourceState = Read-ManagedResourceState -Path $ResourceStateFile
$ServiceDatabaseConnections = Get-DatabaseConnections -Databases $ResourceCatalog.databases

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

Repair-MssqlVolumePermissions -VolumeName "mssql-data" -SqlImage $SqlImage

Start-MssqlPod `
    -NetworkName $NetworkName `
    -MssqlHostPort $MssqlHostPort `
    -SqlPassword $SqlPassword `
    -SqlImage $SqlImage `
    -MssqlBackupDataWsl $MssqlBackupDataWsl

if (Test-MssqlVersionMismatch -ContainerName "mssql" -TimeoutSeconds $MssqlVersionCheckSeconds) {
    if ($KeepMssqlDataOnVersionMismatch) {
        throw "MSSQL data volume 'mssql-data' is incompatible with image '$SqlImage'. A downgrade path is not supported. Remove -KeepMssqlDataOnVersionMismatch or use a compatible newer SQL Server image."
    }

    Write-Output "Detected MSSQL data version mismatch with image '$SqlImage'. The local/offline stack will reset SQL data and start from zero."
    Reset-MssqlDataVolume -VolumeName "mssql-data" -SqlImage $SqlImage
    Start-MssqlPod `
        -NetworkName $NetworkName `
        -MssqlHostPort $MssqlHostPort `
        -SqlPassword $SqlPassword `
        -SqlImage $SqlImage `
        -MssqlBackupDataWsl $MssqlBackupDataWsl
}

Wait-MssqlReady -SqlPassword $SqlPassword
Sync-MssqlDatabaseResources `
    -Databases $ResourceCatalog.databases `
    -PreviouslyManagedDatabases $ManagedResourceState.databases `
    -SqlPassword $SqlPassword

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

Wait-KafkaReady
Sync-KafkaTopicResources `
    -Topics $ResourceCatalog.kafkaTopics `
    -PreviouslyManagedTopics $ManagedResourceState.kafkaTopics

Write-ManagedResourceState `
    -Path $ResourceStateFile `
    -Databases $ResourceCatalog.databases `
    -KafkaTopics $ResourceCatalog.kafkaTopics

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
$serviceConnectionKeys = @($ServiceDatabaseConnections | ForEach-Object { $_.key })
$connectionsEnvValue = if ($serviceConnectionKeys.Count -gt 0) { "mssql,$($serviceConnectionKeys -join ',')" } else { "mssql" }
foreach ($arg in @(
    "run", "-d",
    "--pod", "sql-admin-pod",
    "--name", "sql-admin",
    "-e", "SKIP_ALL_AUTH=1",
    "-e", "NODE_TLS_REJECT_UNAUTHORIZED=0",
    "-e", "NODE_TL_REJECT_UNAUTHORIZED=0",
    "-e", "CONNECTIONS=$connectionsEnvValue"
)) {
    $sqlAdminArgs.Add($arg)
}

Add-DbGateConnectionEnv -PodmanArgs $sqlAdminArgs -Key "mssql" -Label "Local MSSQL" -Server "mssql" -Port "1433" -Database "master" -Username "sa" -Password $SqlPassword
foreach ($connection in $ServiceDatabaseConnections) {
    $connectionPassword = [string]$connection.password
    if ([string]::IsNullOrWhiteSpace($connectionPassword)) {
        $connectionPassword = $SqlPassword
    }
    Add-DbGateConnectionEnv -PodmanArgs $sqlAdminArgs -Key $connection.key -Label $connection.label -Server $connection.server -Port $connection.port -Database $connection.database -Username $connection.username -Password $connectionPassword
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
