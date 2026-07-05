param(
    [string]$ArchivePath = "",
    [string]$OutputDir = "",
    [int]$PartSizeMiB = 1900,
    [switch]$Overwrite,
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Show-Help {
    @'
split-offline-image.ps1

Cel:
  Az offline Podman image tar darabolasa GitHub/Git LFS kompatibilis
  reszekre. A teljes podman-images.tar jelenleg tobb GB, ezert nem toltheto
  fel normal GitHub fajlkent, es egyben Git LFS alatt is tul nagy lehet.

Hasznalat:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\split-offline-image.ps1

Pelda egyedi merettel:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\split-offline-image.ps1 `
    -PartSizeMiB 1900 `
    -Overwrite

Mit csinal:
  1. Beolvassa az offline-bundle\images\podman-images.tar fajlt.
  2. Letrehozza az offline-bundle\images\split konyvtarat.
  3. Letrehoz ilyen darabokat:
     podman-images.tar.part001
     podman-images.tar.part002
     ...
  4. Letrehoz egy podman-images.tar.parts.sha256 manifest fajlt.

Parameterek:
  -ArchivePath
      A darabolando tar fajl. Uresen:
      .\offline-bundle\images\podman-images.tar

  -OutputDir
      A cel konyvtar. Uresen:
      .\offline-bundle\images\split

  -PartSizeMiB
      Egy darab merete MiB-ben. Alapertelmezett: 1900
      Ez GitHub Free/Pro LFS 2 GB per-file limit alatt marad.

  -Overwrite
      Torli a korabbi podman-images.tar.part* fajlokat a cel konyvtarban.

  --help
      Ezt a reszletes leirast irja ki es nem darabol.

Visszaallitas:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\join-offline-image.ps1
'@
}

if ($Help) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path $ProjectRoot "offline-bundle\images\podman-images.tar"
} elseif (-not [System.IO.Path]::IsPathRooted($ArchivePath)) {
    $ArchivePath = Join-Path $ProjectRoot $ArchivePath
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot "offline-bundle\images\split"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot $OutputDir
}

if (-not (Test-Path -LiteralPath $ArchivePath)) {
    throw "Archive does not exist: $ArchivePath"
}
if ($PartSizeMiB -le 0) {
    throw "PartSizeMiB must be greater than zero."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
if ($Overwrite) {
    Get-ChildItem -LiteralPath $OutputDir -Filter "podman-images.tar.part*" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force
    Remove-Item -LiteralPath (Join-Path $OutputDir "podman-images.tar.parts.sha256") -Force -ErrorAction SilentlyContinue
}

if ((Get-ChildItem -LiteralPath $OutputDir -Filter "podman-images.tar.part*" -File -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    throw "Output parts already exist. Use -Overwrite to replace them."
}

$partSize = [int64]$PartSizeMiB * 1MB
$bufferSize = 4MB
$buffer = New-Object byte[] $bufferSize
$partIndex = 1
$manifestLines = [System.Collections.Generic.List[string]]::new()

$input = [System.IO.File]::OpenRead($ArchivePath)
try {
    while ($input.Position -lt $input.Length) {
        $partName = "podman-images.tar.part{0:D3}" -f $partIndex
        $partPath = Join-Path $OutputDir $partName
        $remainingInPart = $partSize
        $output = [System.IO.File]::Create($partPath)
        try {
            while ($remainingInPart -gt 0 -and $input.Position -lt $input.Length) {
                $readSize = [int][Math]::Min($buffer.Length, $remainingInPart)
                $read = $input.Read($buffer, 0, $readSize)
                if ($read -le 0) {
                    break
                }
                $output.Write($buffer, 0, $read)
                $remainingInPart -= $read
            }
        }
        finally {
            $output.Dispose()
        }

        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $partPath).Hash.ToLowerInvariant()
        $length = (Get-Item -LiteralPath $partPath).Length
        $manifestLines.Add("$hash  $partName  $length")
        Write-Output "Created $partName ($length bytes)"
        $partIndex++
    }
}
finally {
    $input.Dispose()
}

$manifestPath = Join-Path $OutputDir "podman-images.tar.parts.sha256"
$manifestLines | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Output "Manifest: $manifestPath"

