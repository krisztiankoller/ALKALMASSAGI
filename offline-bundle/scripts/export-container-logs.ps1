param(
    [string[]]$ContainerName = @(),
    [string[]]$PodName = @(),
    [string]$LogArchiveDir = "",
    [string]$Since = "",
    [string]$Tail = "",
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Show-Help {
    @'
export-container-logs.ps1

Cel:
  Kontenerlogok kezi exportalasa fajlokba. Akkor hasznos, ha ujrainditas
  elott vagy hibakereseshez egyben el akarod menteni a jelenlegi logokat.

Hasznalat:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-container-logs.ps1 [opciok]

Osszes kontener log mentese:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-container-logs.ps1

Csak egy pod logjai:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-container-logs.ps1 -PodName app1-pod

Csak konkret kontenerek:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-container-logs.ps1 -ContainerName app1,kafka,mssql

Csak az utolso 2 ora:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-container-logs.ps1 -Since 2h

Csak utolso 500 sor:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-container-logs.ps1 -Tail 500

Mit csinal:
  1. Kivalasztja a kontenereket.
  2. Letrehoz egy timestampelt konyvtarat a log archive alatt.
  3. Minden kontenerhez kulon .log fajlt ir.
  4. A logokat timestamp-pel menti: podman logs --timestamps.

Parameterek:
  -ContainerName
      Konkret kontenernevek listaja. Pelda: app1,kafka,mssql

  -PodName
      Konkret podnevek listaja. Pelda: app1-pod,kafka-pod

  -LogArchiveDir
      Cel konyvtar. Uresen: .\data\logs

  -Since
      Podman logs --since ertek. Pelda: 10m, 2h, 2026-07-05T10:00:00

  -Tail
      Podman logs --tail ertek. Pelda: 500

  --help
      Ezt a reszletes leirast irja ki es nem ment logot.

Eredmeny:
  .\data\logs\manual-YYYYMMDD-HHMMSS\<container>.log

Megjegyzes:
  A deploy-infra-pods.ps1 es deploy-springboot-pods.ps1 automatikusan is
  menti a regi podok logjait pod torles elott ugyanide.
'@
}

if ($Help) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrWhiteSpace($LogArchiveDir)) {
    $LogArchiveDir = Join-Path $ProjectRoot "data\logs"
} elseif (-not [System.IO.Path]::IsPathRooted($LogArchiveDir)) {
    $LogArchiveDir = Join-Path $ProjectRoot $LogArchiveDir
}

$selectedContainers = [System.Collections.Generic.List[string]]::new()

foreach ($rawName in $ContainerName) {
    foreach ($name in ($rawName -split ",")) {
        $trimmedName = $name.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmedName)) {
            $selectedContainers.Add($trimmedName)
        }
    }
}

foreach ($rawPod in $PodName) {
    foreach ($pod in ($rawPod -split ",")) {
        $trimmedPod = $pod.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedPod)) {
            continue
        }
        $podContainers = @(podman ps -a --filter "pod=$trimmedPod" --format "{{.Names}}" 2>$null |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        foreach ($container in $podContainers) {
            $selectedContainers.Add($container)
        }
    }
}

if ($selectedContainers.Count -eq 0) {
    $allContainers = @(podman ps -a --format "{{.Names}}" 2>$null |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($container in $allContainers) {
        $selectedContainers.Add($container)
    }
}

$uniqueContainers = @($selectedContainers | Sort-Object -Unique)
if ($uniqueContainers.Count -eq 0) {
    Write-Output "No containers found."
    exit 0
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$targetDir = Join-Path $LogArchiveDir "manual-$timestamp"
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

foreach ($container in $uniqueContainers) {
    $safeName = ($container -replace '[^A-Za-z0-9_.-]', '_')
    $logPath = Join-Path $targetDir "$safeName.log"

    $args = [System.Collections.Generic.List[string]]::new()
    $args.Add("logs")
    $args.Add("--timestamps")
    if (-not [string]::IsNullOrWhiteSpace($Since)) {
        $args.Add("--since")
        $args.Add($Since)
    }
    if (-not [string]::IsNullOrWhiteSpace($Tail)) {
        $args.Add("--tail")
        $args.Add($Tail)
    }
    $args.Add($container)

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & podman @($args.ToArray()) > $logPath 2>&1
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    Write-Output "Saved $container -> $logPath"
}

Write-Output "Log archive folder: $targetDir"
