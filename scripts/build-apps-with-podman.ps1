param(
    [string]$MavenImage = "maven:3.9.9-eclipse-temurin-21",
    [string]$BuildPodName = "java-build-pod",
    [string]$BuildContainerName = "java-maven-builder",
    [string]$MavenRepoDir = "",
    [string]$ProxyConfigFile = "",
    [string]$HttpProxy = "",
    [string]$HttpsProxy = "",
    [string]$NoProxy = "localhost,127.0.0.1,mssql,kafka,kafka-ui,sql-admin,app1,app2,app3,app4,app5,app6",
    [string]$ProxyUsername = "",
    [string]$ProxyPassword = "",
    [switch]$SkipTests,
    [switch]$Offline,
    [switch]$KeepBuildContainer,
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$script:InvocationBoundParameters = $PSBoundParameters

function Show-Help {
    @'
build-apps-with-podman.ps1

Cel:
  Maven alapu Java/Spring Boot alkalmazasokat buildel Podman kontenerben.
  A host gepen nem kell Java vagy Maven. A Maven kontener a teljes projektet
  /workspace ala mountolja, es ott futtatja: mvn clean package.

Hasznalat:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 [opciok]

Gyakori pelda:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 -SkipTests

Offline Maven cache hasznalata:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 -SkipTests -Offline

Mit csinal:
  1. A scripts konyvtar szulojat projektgyokernek veszi.
  2. Letrehozza a projekt alatti Maven cache konyvtarat: .\data\maven-repo.
  3. Ha proxy.config.json enabled=true, atadja a proxy beallitasokat Podmannak es Mavennek.
  4. Letrehozza vagy ujrahasznalja a java-build-pod Podman podot.
  5. Elindit egy maven kontenert, amely a projektben mvn clean package parancsot futtat.
  6. A kesz JAR-ok az appN\target konyvtarakba kerulnek.

Fontos parameterek:
  -MavenImage
      A builder image. Alapertelmezett: maven:3.9.9-eclipse-temurin-21

  -BuildPodName
      A build pod neve. Alapertelmezett: java-build-pod

  -BuildContainerName
      Az ideiglenes Maven kontener neve. Alapertelmezett: java-maven-builder

  -MavenRepoDir
      Maven cache konyvtar a projekt alatt vagy abszolut utvonallal.
      Uresen: .\data\maven-repo

  -ProxyConfigFile
      Proxy config JSON. Uresen: .\proxy.config.json

  -HttpProxy, -HttpsProxy, -NoProxy, -ProxyUsername, -ProxyPassword
      Ideiglenes parancssori proxy feluliras. Normal esetben a proxy.config.json hasznalando.

  -SkipTests
      Maven tesztek kihagyasa: -DskipTests.

  -Offline
      Maven offline mod: -o. Csak akkor mukodik, ha a Maven cache mar tartalmazza a dependency-ket.

  -KeepBuildContainer
      Nem torli a build kontenert a vegen. Hibakereseshez hasznos.

  --help
      Ezt a reszletes leirast irja ki es nem futtat buildet.

Eredmeny:
  app1\target\*.jar ... app6\target\*.jar

Megjegyzes:
  Ez csak JAR-t buildel. Kontener image-et a deploy-springboot-pods.ps1 vagy
  az export-offline-bundle.ps1 keszit.
'@
}

if ($Help) {
    Show-Help
    exit 0
}

function Invoke-Podman {
    param([string[]]$Arguments)

    & podman @Arguments | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "podman $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function ConvertTo-WslPath {
    param([string]$Path)

    $resolvedPath = (Resolve-Path -Path $Path).Path
    $wslPath = wsl -d podman-machine-default -- wslpath -a $resolvedPath
    return ($wslPath | Select-Object -First 1).Trim()
}

function Format-ProjectRelativePath {
    param(
        [string]$Path,
        [string]$Root
    )

    $resolvedPath = (Resolve-Path -Path $Path).Path
    $resolvedRoot = (Resolve-Path -Path $Root).Path.TrimEnd("\")
    if ($resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $resolvedPath.Substring($resolvedRoot.Length).TrimStart("\")
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            return "."
        }
        return ".\$relativePath"
    }

    return $Path
}

function Apply-ProxyConfigFile {
    param(
        [string]$ConfigFile
    )

    if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
        return
    }
    if (-not (Test-Path -LiteralPath $ConfigFile)) {
        return
    }

    $config = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $config -or $config.enabled -ne $true) {
        return
    }

    if (-not $script:InvocationBoundParameters.ContainsKey("HttpProxy") -and $config.httpProxy) {
        $script:HttpProxy = [string]$config.httpProxy
    }
    if (-not $script:InvocationBoundParameters.ContainsKey("HttpsProxy") -and $config.httpsProxy) {
        $script:HttpsProxy = [string]$config.httpsProxy
    }
    if (-not $script:InvocationBoundParameters.ContainsKey("NoProxy") -and $config.noProxy) {
        if ($config.noProxy -is [array]) {
            $script:NoProxy = ($config.noProxy -join ",")
        } else {
            $script:NoProxy = [string]$config.noProxy
        }
    }
    if (-not $script:InvocationBoundParameters.ContainsKey("ProxyUsername") -and $config.username) {
        $script:ProxyUsername = [string]$config.username
    }
    if (-not $script:InvocationBoundParameters.ContainsKey("ProxyPassword") -and $config.password) {
        $script:ProxyPassword = [string]$config.password
    }
}

function Resolve-ProxyUrl {
    param(
        [string]$Url,
        [string]$Username,
        [string]$Password
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return ""
    }

    $builder = [System.UriBuilder]::new($Url)
    if (-not [string]::IsNullOrWhiteSpace($Username) -and [string]::IsNullOrWhiteSpace($builder.UserName)) {
        $builder.UserName = $Username
        $builder.Password = $Password
    }

    return $builder.Uri.AbsoluteUri
}

function Set-ProxyEnvironment {
    param(
        [string]$HttpProxy,
        [string]$HttpsProxy,
        [string]$NoProxy
    )

    if (-not [string]::IsNullOrWhiteSpace($HttpProxy)) {
        $env:HTTP_PROXY = $HttpProxy
        $env:http_proxy = $HttpProxy
    }
    if (-not [string]::IsNullOrWhiteSpace($HttpsProxy)) {
        $env:HTTPS_PROXY = $HttpsProxy
        $env:https_proxy = $HttpsProxy
    }
    if (-not [string]::IsNullOrWhiteSpace($NoProxy)) {
        $env:NO_PROXY = $NoProxy
        $env:no_proxy = $NoProxy
    }
}

function Add-ProxyEnvArgs {
    param(
        [System.Collections.Generic.List[string]]$Args,
        [string]$HttpProxy,
        [string]$HttpsProxy,
        [string]$NoProxy
    )

    foreach ($item in @(
        @("HTTP_PROXY", $HttpProxy),
        @("http_proxy", $HttpProxy),
        @("HTTPS_PROXY", $HttpsProxy),
        @("https_proxy", $HttpsProxy),
        @("NO_PROXY", $NoProxy),
        @("no_proxy", $NoProxy)
    )) {
        if (-not [string]::IsNullOrWhiteSpace($item[1])) {
            $Args.Add("-e")
            $Args.Add("$($item[0])=$($item[1])")
        }
    }
}

function ConvertTo-MavenNonProxyHosts {
    param([string]$NoProxy)

    if ([string]::IsNullOrWhiteSpace($NoProxy)) {
        return ""
    }

    return (($NoProxy -split ",") |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "|"
}

function Get-ProxyCredentialParts {
    param([System.Uri]$Uri)

    $result = [ordered]@{
        username = ""
        password = ""
    }

    if (-not [string]::IsNullOrWhiteSpace($Uri.UserInfo)) {
        $parts = $Uri.UserInfo.Split(":", 2)
        $result.username = [System.Uri]::UnescapeDataString($parts[0])
        if ($parts.Count -gt 1) {
            $result.password = [System.Uri]::UnescapeDataString($parts[1])
        }
    }

    return $result
}

function New-MavenProxyXml {
    param(
        [string]$Id,
        [string]$Protocol,
        [string]$ProxyUrl,
        [string]$NonProxyHosts
    )

    if ([string]::IsNullOrWhiteSpace($ProxyUrl)) {
        return ""
    }

    $uri = [System.Uri]$ProxyUrl
    $port = if ($uri.Port -gt 0) { $uri.Port } elseif ($uri.Scheme -eq "https") { 443 } else { 80 }
    $credentials = Get-ProxyCredentialParts -Uri $uri
    $usernameXml = if (-not [string]::IsNullOrWhiteSpace($credentials.username)) { "`n      <username>$([System.Security.SecurityElement]::Escape($credentials.username))</username>" } else { "" }
    $passwordXml = if (-not [string]::IsNullOrWhiteSpace($credentials.password)) { "`n      <password>$([System.Security.SecurityElement]::Escape($credentials.password))</password>" } else { "" }
    $nonProxyXml = if (-not [string]::IsNullOrWhiteSpace($NonProxyHosts)) { "`n      <nonProxyHosts>$([System.Security.SecurityElement]::Escape($NonProxyHosts))</nonProxyHosts>" } else { "" }

    return @"
    <proxy>
      <id>$([System.Security.SecurityElement]::Escape($Id))</id>
      <active>true</active>
      <protocol>$([System.Security.SecurityElement]::Escape($Protocol))</protocol>
      <host>$([System.Security.SecurityElement]::Escape($uri.Host))</host>
      <port>$port</port>$usernameXml$passwordXml$nonProxyXml
    </proxy>
"@
}

function Write-MavenSettingsWithProxy {
    param(
        [string]$MavenRepo,
        [string]$HttpProxy,
        [string]$HttpsProxy,
        [string]$NoProxy
    )

    if ([string]::IsNullOrWhiteSpace($HttpProxy) -and [string]::IsNullOrWhiteSpace($HttpsProxy)) {
        return
    }

    $nonProxyHosts = ConvertTo-MavenNonProxyHosts -NoProxy $NoProxy
    $httpXml = New-MavenProxyXml -Id "project-http-proxy" -Protocol "http" -ProxyUrl $HttpProxy -NonProxyHosts $nonProxyHosts
    $httpsXml = New-MavenProxyXml -Id "project-https-proxy" -Protocol "https" -ProxyUrl $HttpsProxy -NonProxyHosts $nonProxyHosts
    $settingsPath = Join-Path $MavenRepo "settings.xml"
    $settingsXml = @"
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <proxies>
$httpXml
$httpsXml
  </proxies>
</settings>
"@

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($settingsPath, $settingsXml, $utf8NoBom)
}

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProxyConfigFile)) {
    $ProxyConfigFile = Join-Path $projectRoot "proxy.config.json"
} elseif (-not [System.IO.Path]::IsPathRooted($ProxyConfigFile)) {
    $ProxyConfigFile = Join-Path $projectRoot $ProxyConfigFile
}
Apply-ProxyConfigFile -ConfigFile $ProxyConfigFile

if ([string]::IsNullOrWhiteSpace($MavenRepoDir)) {
    $mavenRepo = Join-Path $projectRoot "data\maven-repo"
} else {
    $mavenRepo = $MavenRepoDir
    if (-not [System.IO.Path]::IsPathRooted($mavenRepo)) {
        $mavenRepo = Join-Path $projectRoot $mavenRepo
    }
}
New-Item -ItemType Directory -Force -Path $mavenRepo | Out-Null

$effectiveHttpProxy = Resolve-ProxyUrl -Url $HttpProxy -Username $ProxyUsername -Password $ProxyPassword
$effectiveHttpsProxy = Resolve-ProxyUrl -Url $(if ([string]::IsNullOrWhiteSpace($HttpsProxy)) { $HttpProxy } else { $HttpsProxy }) -Username $ProxyUsername -Password $ProxyPassword
Set-ProxyEnvironment -HttpProxy $effectiveHttpProxy -HttpsProxy $effectiveHttpsProxy -NoProxy $NoProxy
Write-MavenSettingsWithProxy -MavenRepo $mavenRepo -HttpProxy $effectiveHttpProxy -HttpsProxy $effectiveHttpsProxy -NoProxy $NoProxy

$projectRootWsl = ConvertTo-WslPath $projectRoot
$mavenRepoWsl = ConvertTo-WslPath $mavenRepo

if (-not $Offline) {
    Invoke-Podman -Arguments @("pull", "--platform", "linux/amd64", $MavenImage)
}

& podman pod exists $BuildPodName *> $null
if ($LASTEXITCODE -ne 0) {
    Invoke-Podman -Arguments @("pod", "create", "--name", $BuildPodName)
}

& podman container exists $BuildContainerName *> $null
if ($LASTEXITCODE -eq 0) {
    Invoke-Podman -Arguments @("rm", "-f", $BuildContainerName)
}

$mavenArgs = @("mvn", "clean", "package")
if ($SkipTests) {
    $mavenArgs += "-DskipTests"
}
if ($Offline) {
    $mavenArgs += "-o"
}

$runArgs = [System.Collections.Generic.List[string]]::new()
foreach ($arg in @(
    "run",
    "--name", $BuildContainerName,
    "--pod", $BuildPodName,
    "-v", "${projectRootWsl}:/workspace",
    "-v", "${mavenRepoWsl}:/root/.m2",
    "-w", "/workspace"
)) {
    $runArgs.Add($arg)
}
Add-ProxyEnvArgs -Args $runArgs -HttpProxy $effectiveHttpProxy -HttpsProxy $effectiveHttpsProxy -NoProxy $NoProxy
$runArgs.Add($MavenImage)
foreach ($arg in $mavenArgs) {
    $runArgs.Add($arg)
}

Invoke-Podman -Arguments $runArgs.ToArray()

if (-not $KeepBuildContainer) {
    Invoke-Podman -Arguments @("rm", $BuildContainerName)
}

Write-Output "Build completed in Podman pod: $BuildPodName"
Write-Output "Maven cache folder: $(Format-ProjectRelativePath -Path $mavenRepo -Root $projectRoot)"
Write-Output "Show it with: podman pod ps --filter name=$BuildPodName"
