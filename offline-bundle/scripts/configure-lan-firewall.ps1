param(
    [string]$ServicesFile = "",
    [int[]]$InfraPorts = @(40000, 40001, 40002, 40003, 40004, 40011),
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Show-Help {
    @'
configure-lan-firewall.ps1

Cel:
  Opcionalis LAN elereshez Windows firewall szabalyokat es netsh portproxy
  beallitasokat hoz letre az infra es app portokra.

FIGYELEM:
  Ehhez Windows admin jog kell. Normal localhost-only hasznalathoz nem kell
  es nem is ajanlott futtatni.

Hasznalat admin PowerShellbol:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-lan-firewall.ps1

Egyedi services.json:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-lan-firewall.ps1 `
    -ServicesFile .\services.json

Egyedi infra portok:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-lan-firewall.ps1 `
    -InfraPorts 40000,40001,40002,40003,40004,40011

Mit csinal:
  1. Ellenorzi, hogy emelt jogosultsagu PowerShellbol fut-e.
  2. Beolvassa a services.json hostPort ertekeit.
  3. Hozzaadja az infra portokat.
  4. Letrehoz vagy frissit Windows inbound firewall rule-okat.
  5. Letrehoz netsh interface portproxy v4tov4 bejegyzeseket.
  6. Kiirja az aktualis portproxy tablat.

Parameterek:
  -ServicesFile
      services.json utvonala. Uresen: .\services.json

  -InfraPorts
      Az appokon kivuli portok listaja.
      Alapertelmezett: 40000, 40001, 40002, 40003, 40004, 40011

  --help
      Ezt a reszletes leirast irja ki es nem modosit firewall/portproxy beallitast.

Mikor kell:
  Csak akkor, ha masik gep vagy LAN kliens is el akarja erni a szolgaltatasokat.

Mikor nem kell:
  Ha minden csak localhostrol megy ugyanazon a Windows gepen.
'@
}

if ($Help) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ServicesFile)) {
    $ServicesFile = Join-Path $ProjectRoot "services.json"
} elseif (-not [System.IO.Path]::IsPathRooted($ServicesFile)) {
    $ServicesFile = Join-Path $ProjectRoot $ServicesFile
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated PowerShell window."
    }
}

function Ensure-FirewallRule {
    param(
        [string]$Name,
        [int]$Port
    )

    $existing = Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Set-NetFirewallRule -DisplayName $Name -Enabled True -Profile Any -Action Allow | Out-Null
        return
    }

    New-NetFirewallRule `
        -DisplayName $Name `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort $Port `
        -Profile Any | Out-Null
}

function Ensure-PortProxy {
    param([int]$Port)

    netsh interface portproxy delete v4tov4 `
        listenaddress=0.0.0.0 `
        listenport=$Port | Out-Null

    netsh interface portproxy add v4tov4 `
        listenaddress=0.0.0.0 `
        listenport=$Port `
        connectaddress=127.0.0.1 `
        connectport=$Port | Out-Null
}

Assert-Administrator

$ports = [System.Collections.Generic.List[int]]::new()
$InfraPorts | ForEach-Object { $ports.Add($_) }

if (Test-Path -Path $ServicesFile) {
    $servicesJson = Get-Content -Path $ServicesFile -Raw | ConvertFrom-Json
    $services = if ($servicesJson.PSObject.Properties["services"]) { $servicesJson.services } else { $servicesJson }
    foreach ($service in $services) {
        if ($service.hostPort) {
            $ports.Add([int]$service.hostPort)
        }
    }
}

foreach ($port in ($ports | Sort-Object -Unique)) {
    Ensure-FirewallRule -Name "ALKALMASSAGI Podman TCP $port" -Port $port
    Ensure-PortProxy -Port $port
}

Write-Output "Firewall and portproxy rules are ready for TCP ports: $(($ports | Sort-Object -Unique) -join ', ')"
netsh interface portproxy show v4tov4
