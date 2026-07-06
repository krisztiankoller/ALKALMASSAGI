param(
    [string]$SqlPassword,

    [string]$NetworkName = "devnet",
    [string]$KafkaImage = "apache/kafka-native:3.9.0",
    [string]$SqlImage = "mcr.microsoft.com/mssql/server:2022-latest",
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    @'
podman-dev-stack-template.ps1

Cel:
  Belso/private template script egy egyszerubb Podman fejlesztoi stackhez.
  Ez nem a jelenlegi teljes ALKALMASSAGI stack fo indito scriptje, hanem
  korabbi/altalanos minta.

FIGYELEM:
  Normal hasznalathoz ne ezt futtasd. A jelenlegi projektben a fo scriptek:
    .\scripts\deploy-infra-pods.ps1
    .\scripts\deploy-springboot-pods.ps1
    .\scripts\run-offline.ps1

Hasznalat, ha tudatosan ezt a template-et akarod probalni:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\private\podman-dev-stack-template.ps1 `
    -SqlPassword "<jelszo>"

Mit csinal:
  1. Letrehoz egy Podman networkot.
  2. Letrehoz mssql-data es kafka-data volume-okat, es javitja az MSSQL volume
     jogosultsagait a nem-root SQL Server kontenerhez.
  3. Elindit egy SQL Server podot.
  4. Elindit egy Kafka podot.
  5. Minta app1 pod inditast mutat registry.example.local/app1:latest image-dzsel.

Parameterek:
  -SqlPassword
      Kotelezo normal futasnal. SQL Server sa jelszo.

  -NetworkName
      Podman network neve. Alapertelmezett: devnet

  -KafkaImage
      Kafka image. Alapertelmezett: apache/kafka-native:3.9.0

  -SqlImage
      SQL Server image. Alapertelmezett: mcr.microsoft.com/mssql/server:2022-latest

  --help
      Ezt a reszletes leirast irja ki es nem indit podokat.

Mikor hasznald:
  Csak mintanak vagy kiserletezeshez.

Mikor ne hasznald:
  A jelenlegi offline bundle, app1-app6 pipeline vagy dokumentalt stack
  inditasahoz.
'@
}

if ($Help) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrWhiteSpace($SqlPassword)) {
    throw "Missing required parameter: -SqlPassword. Use --help for detailed usage."
}

function Ensure-Network {
    param([string]$Name)

    podman network exists $Name 2>$null
    if ($LASTEXITCODE -ne 0) {
        podman network create $Name
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

function Recreate-Pod {
    param(
        [string]$Name,
        [string[]]$Args
    )

    podman pod exists $Name 2>$null
    if ($LASTEXITCODE -eq 0) {
        podman pod rm -f $Name | Out-Null
    }

    podman pod create --name $Name @Args | Out-Null
}

Ensure-Network $NetworkName
Ensure-Volume -Name "mssql-data" -Uid 10001 -Gid 0
Ensure-Volume "kafka-data"
Repair-MssqlVolumePermissions -VolumeName "mssql-data" -SqlImage $SqlImage

Recreate-Pod "mssql-pod" @(
    "--network", $NetworkName,
    "--network-alias", "mssql",
    "--publish", "40000:1433"
)

podman run -d `
    --pod mssql-pod `
    --name mssql `
    -e "ACCEPT_EULA=Y" `
    -e "MSSQL_SA_PASSWORD=$SqlPassword" `
    -e "MSSQL_PID=Developer" `
    -e "HOME=/var/opt/mssql" `
    -v "mssql-data:/var/opt/mssql" `
    $SqlImage

Recreate-Pod "kafka-pod" @(
    "--network", $NetworkName,
    "--network-alias", "kafka",
    "--publish", "40001:40001"
)

podman run -d `
    --pod kafka-pod `
    --name kafka `
    -e "KAFKA_NODE_ID=1" `
    -e "KAFKA_PROCESS_ROLES=broker,controller" `
    -e "KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka:9093" `
    -e "KAFKA_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093,EXTERNAL://:40001" `
    -e "KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092,EXTERNAL://localhost:40001" `
    -e "KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER" `
    -e "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,EXTERNAL:PLAINTEXT" `
    -e "KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT" `
    -e "CLUSTER_ID=abcdefghijklmnopqrstuv" `
    -v "kafka-data:/var/lib/kafka/data" `
    $KafkaImage

# Repeat this block for each Java app.
# Replace registry.example.local/app1:latest with your real image.
Recreate-Pod "app1-pod" @(
    "--network", $NetworkName,
    "--network-alias", "app1",
    "--publish", "40005:8080"
)

podman run -d `
    --pod app1-pod `
    --name app1 `
    -e "SPRING_DATASOURCE_URL=jdbc:sqlserver://mssql:1433;databaseName=appdb;encrypt=false;trustServerCertificate=true" `
    -e "SPRING_DATASOURCE_USERNAME=sa" `
    -e "SPRING_DATASOURCE_PASSWORD=$SqlPassword" `
    -e "SPRING_KAFKA_BOOTSTRAP_SERVERS=kafka:9092" `
    registry.example.local/app1:latest

podman ps --pod
