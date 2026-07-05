param(
    [string]$PartsDir = "",
    [string]$ArchivePath = "",
    [switch]$Overwrite,
    [switch]$SkipHashCheck,
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Show-Help {
    @'
join-offline-image.ps1

Cel:
  A split-offline-image.ps1 altal keszitett podman-images.tar.partNNN
  fajlokbol visszaallitja az offline-bundle\images\podman-images.tar fajlt.

Hasznalat:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\join-offline-image.ps1

Feluliras:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\join-offline-image.ps1 -Overwrite

Mit csinal:
  1. Megkeresi az offline-bundle\images\split\podman-images.tar.part* fajlokat.
  2. Opcionalisan ellenorzi a sha256 manifestet.
  3. Osszefuzi a darabokat ide:
     offline-bundle\images\podman-images.tar

Parameterek:
  -PartsDir
      A darabokat tartalmazo konyvtar. Uresen:
      .\offline-bundle\images\split

  -ArchivePath
      A visszaallitando tar fajl celja. Uresen:
      .\offline-bundle\images\podman-images.tar

  -Overwrite
      Felulirja a mar letezo cel tar fajlt.

  -SkipHashCheck
      Nem ellenorzi a podman-images.tar.parts.sha256 manifestet.

  --help
      Ezt a reszletes leirast irja ki es nem allit vissza fajlt.
'@
}

if ($Help) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrWhiteSpace($PartsDir)) {
    $PartsDir = Join-Path $ProjectRoot "offline-bundle\images\split"
} elseif (-not [System.IO.Path]::IsPathRooted($PartsDir)) {
    $PartsDir = Join-Path $ProjectRoot $PartsDir
}

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path $ProjectRoot "offline-bundle\images\podman-images.tar"
} elseif (-not [System.IO.Path]::IsPathRooted($ArchivePath)) {
    $ArchivePath = Join-Path $ProjectRoot $ArchivePath
}

if (-not (Test-Path -LiteralPath $PartsDir)) {
    throw "Parts directory does not exist: $PartsDir"
}
if ((Test-Path -LiteralPath $ArchivePath) -and -not $Overwrite) {
    throw "Archive already exists: $ArchivePath. Use -Overwrite to replace it."
}

$parts = @(Get-ChildItem -LiteralPath $PartsDir -Filter "podman-images.tar.part*" -File | Sort-Object Name)
if ($parts.Count -eq 0) {
    throw "No parts found in: $PartsDir"
}

if (-not $SkipHashCheck) {
    $manifestPath = Join-Path $PartsDir "podman-images.tar.parts.sha256"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Missing manifest: $manifestPath. Use -SkipHashCheck to skip validation."
    }

    $expected = @{}
    foreach ($line in (Get-Content -LiteralPath $manifestPath -Encoding UTF8)) {
        if ($line -match "^([a-fA-F0-9]{64})\s+(\S+)\s+(\d+)$") {
            $expected[$Matches[2]] = [pscustomobject]@{
                Hash = $Matches[1].ToLowerInvariant()
                Length = [int64]$Matches[3]
            }
        }
    }

    foreach ($part in $parts) {
        if (-not $expected.ContainsKey($part.Name)) {
            throw "Part missing from manifest: $($part.Name)"
        }
        if ($part.Length -ne $expected[$part.Name].Length) {
            throw "Part size mismatch: $($part.Name)"
        }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $part.FullName).Hash.ToLowerInvariant()
        if ($hash -ne $expected[$part.Name].Hash) {
            throw "Part hash mismatch: $($part.Name)"
        }
    }
}

$targetDir = Split-Path -Parent $ArchivePath
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
Remove-Item -LiteralPath $ArchivePath -Force -ErrorAction SilentlyContinue

$bufferSize = 4MB
$buffer = New-Object byte[] $bufferSize
$output = [System.IO.File]::Create($ArchivePath)
try {
    foreach ($part in $parts) {
        $input = [System.IO.File]::OpenRead($part.FullName)
        try {
            while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $output.Write($buffer, 0, $read)
            }
        }
        finally {
            $input.Dispose()
        }
        Write-Output "Joined $($part.Name)"
    }
}
finally {
    $output.Dispose()
}

Write-Output "Archive restored: $ArchivePath"
