param(
    [string]$MavenImage = "maven:3.9.9-eclipse-temurin-21",
    [string]$BuildPodName = "java-build-pod",
    [string]$BuildContainerName = "java-maven-builder",
    [string]$BuildLogViewerContainerName = "java-build-log-viewer",
    [string]$MavenRepoDir = "",
    [string]$BuildLogDir = "",
    [string]$ServicesFile = "",
    [string]$ProxyConfigFile = "",
    [string]$MavenSettingsFile = "",
    [string]$HttpProxy = "",
    [string]$HttpsProxy = "",
    [string]$NoProxy = "localhost,127.0.0.1,mssql,kafka,kafka-ui,sql-admin,app1,app2,app3,app4,app5,app6",
    [string]$ProxyUsername = "",
    [string]$ProxyPassword = "",
    [string]$PodmanTlsVerify = "true",
    [string]$MavenTlsVerify = "true",
    [int]$PodmanPullRetries = 5,
    [int]$PodmanPullRetryDelaySeconds = 10,
    [int]$MavenBuildRetries = 5,
    [int]$MavenBuildRetryDelaySeconds = 10,
    [string[]]$MavenProjects = @(),
    [switch]$AlsoMake,
    [switch]$SkipTests,
    [switch]$Offline,
    [switch]$KeepBuildContainer,
    [switch]$DisableBuildLogViewer,
    [Alias("h", "?")]
    [switch]$Help
)
$ErrorActionPreference = "Stop"
$script:InvocationBoundParameters = $PSBoundParameters
$script:HttpProxy = $HttpProxy
$script:HttpsProxy = $HttpsProxy
$script:NoProxy = $NoProxy
$script:ProxyUsername = $ProxyUsername
$script:ProxyPassword = $ProxyPassword
$script:MavenSettingsFile = $MavenSettingsFile
$script:ConfiguredPodmanTlsVerify = $PodmanTlsVerify
$script:ConfiguredMavenTlsVerify = $MavenTlsVerify
function Show-Help {
    @'
build-apps-with-podman.ps1
Cel:
  Maven alapu Java/Spring Boot alkalmazasokat buildel Podman kontenerben.
  A host gepen nem kell Java vagy Maven. A Maven kontener a teljes projektet
  /workspace ala mountolja. Ha vannak nem-service Maven modulok, azokat eloszor
  installalja a lokalis Maven cache-be, utana package-eli az app modulokat.
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
  5. A root pom.xml es services.json alapjan kivalasztja a library/BOM es app modulokat.
  6. Ha van library/BOM modul, futtatja: mvn -pl <library-modulok> -am clean install.
  7. Utana futtatja az app package fazist: mvn -pl <app-modulok> clean package.
  8. A kesz JAR-ok az appN\target konyvtarakba kerulnek.
Fontos parameterek:
  -MavenImage
      A builder image. Alapertelmezett: maven:3.9.9-eclipse-temurin-21
  -BuildPodName
      A build pod neve. Alapertelmezett: java-build-pod
  -BuildContainerName
      A Maven build kontener neve. Alapertelmezett: java-maven-builder.
      A script alapbol torli a vegen, mert a webes build logot a
      java-build-log-viewer mutatja.
  -BuildLogViewerContainerName
      A Dozzle-ban futo, build log fajlt tail-elo kontener neve.
      Alapertelmezett: java-build-log-viewer
  -MavenRepoDir
      Maven cache konyvtar a projekt alatt vagy abszolut utvonallal.
      Uresen: .\data\maven-repo
  -BuildLogDir
      Build log konyvtar. Uresen: .\data\build-logs
  -ServicesFile
      Services config JSON. Uresen: .\services.json
      A script ebbol allapitja meg, mely root pom.xml modulok futtathato appok.
      Ami Maven modul, de nem szerepel service projectDir-kent, azt library/BOM
      modulnak tekinti es eloszor `mvn clean install` paranccsal telepiti a
      lokalis Maven cache-be.
  -ProxyConfigFile
      Proxy config JSON. Uresen: .\proxy.config.json
  -MavenSettingsFile
      Kulon Maven settings.xml fajl, amelyet csak ez az app build hasznal.
      Ha meg van adva, a Maven kontener read-only mounttal kapja meg, es a
      script `mvn -s /maven-settings/<fajlnev> clean package` parancsot futtat.
      Relativ ut eseten a projekt gyokerehez kepest ertendo.
      A script ezt a fajlt nem modositja es nem masolja a Maven cache-be.
  -HttpProxy, -HttpsProxy, -NoProxy, -ProxyUsername, -ProxyPassword
      Ideiglenes parancssori proxy feluliras. Normal esetben a proxy.config.json hasznalando.
  -PodmanTlsVerify
      Podman registry TLS certificate ellenorzes. Alapertelmezett: true.
      Ceges TLS inspection/x509 hiba eseten inkabb a proxy.config.json fajlban allitsd:
      "podmanTlsVerify": false
  -PodmanPullRetries
      Podman pull probalkozasok szama a Maven builder image-re. Alapertelmezett es minimum: 5
  -PodmanPullRetryDelaySeconds
      Varakozas ket sikertelen podman pull probalkozas kozott masodpercben.
      Alapertelmezett: 10
  -MavenTlsVerify
      Maven/Java HTTPS certificate ellenorzes dependency letoltes kozben. Alapertelmezett: true.
      Ceges TLS inspection vagy ismeretlen CA hiba eseten inkabb a proxy.config.json fajlban allitsd:
      "mavenTlsVerify": false
  -MavenBuildRetries
      Maven build probalkozasok szama. Alapertelmezett: 5
      Ha gyors hibaval megallast akarsz, allithato 1-re.
  -MavenBuildRetryDelaySeconds
      Varakozas ket sikertelen Maven build probalkozas kozott masodpercben.
      Alapertelmezett: 10
  -MavenProjects
      Opcionalis Maven project/module lista a -pl kapcsolohoz. Pelda:
        -MavenProjects app3
        -MavenProjects app3,app4
      Ilyenkor nem a teljes reactor build fut, hanem csak a megadott modul(ok).
  -AlsoMake
      Maven -am kapcsolo az app package fazishoz. A library/BOM install fazis
      ettol fuggetlenul mindig -am kapcsoloval fut.
      A -MavenProjects mellett akkor hasznald, ha a kivalasztott appok
      szukseges reactor fuggosegeit az app package fazisban is ujra akarod epiteni.
      Pelda eredmeny: mvn -pl app3 -am clean package.
  -SkipTests
      Maven tesztek kihagyasa: -DskipTests.
  -Offline
      Maven offline mod: -o. Csak akkor mukodik, ha a Maven cache mar tartalmazza a dependency-ket.
  -KeepBuildContainer
      Nem torli a Maven build kontenert a vegen. Hibakereseshez hasznos, ha a
      nyers `podman logs java-maven-builder` kimenetet is meg akarod tartani.
      Ilyenkor a java-build-pod statusza Degraded lehet, mert a Maven kontener
      sikeresen kilepett.
  -DisableBuildLogViewer
      Nem inditja el a java-build-log-viewer kontenert. Ilyenkor a build log
      csak a java-maven-builder kontener logjaban es a fajlban marad meg.
  --help
      Ezt a reszletes leirast irja ki es nem futtat buildet.
Eredmeny:
  app1\target\*.jar ... app6\target\*.jar
  .\data\build-logs\current.log
  Dozzle: http://localhost:40004 -> java-build-log-viewer
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
function Invoke-PodmanWithLog {
    param(
        [string[]]$Arguments,
        [string]$LogPath
    )
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $writer = [System.IO.StreamWriter]::new($LogPath, $true, $utf8NoBom)
    try {
        & podman @Arguments 2>&1 | ForEach-Object {
            $line = [string]$_
            Write-Host $line
            $writer.WriteLine($line)
            $writer.Flush()
        }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $writer.Dispose()
    }
    if ($exitCode -ne 0) {
        throw "podman $($Arguments -join ' ') failed with exit code $exitCode"
    }
}
function Start-BuildLogViewer {
    param(
        [string]$ContainerName,
        [string]$PodName,
        [string]$Image,
        [string]$BuildLogDirWsl
    )
    & podman container exists $ContainerName *> $null
    if ($LASTEXITCODE -eq 0) {
        Invoke-Podman -Arguments @("rm", "-f", $ContainerName)
    }
    $logViewerArgs = [System.Collections.Generic.List[string]]::new()
    foreach ($arg in @(
        "run", "-d",
        "--name", $ContainerName,
        "--pod", $PodName,
        "-v", "${BuildLogDirWsl}:/build-logs",
        $Image,
        "sh", "-lc", "cat /build-logs/current.log; tail -f /dev/null"
    )) {
        $logViewerArgs.Add($arg)
    }
    Invoke-Podman -Arguments $logViewerArgs.ToArray()
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
function ConvertTo-BooleanValue {
    param(
        [object]$Value,
        [string]$Name
    )
    if ($Value -is [bool]) {
        return $Value
    }
    $text = ([string]$Value).Trim()
    if ($text -match "^(?i:true|1|yes|y|on)$") {
        return $true
    }
    if ($text -match "^(?i:false|0|no|n|off)$") {
        return $false
    }
    throw "Invalid boolean value for ${Name}: '$Value'. Use true or false."
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
    if (-not $script:InvocationBoundParameters.ContainsKey("PodmanTlsVerify") -and
        $config.PSObject.Properties.Name -contains "podmanTlsVerify") {
        $script:ConfiguredPodmanTlsVerify = $config.podmanTlsVerify
    }
    if (-not $script:InvocationBoundParameters.ContainsKey("MavenTlsVerify") -and
        $config.PSObject.Properties.Name -contains "mavenTlsVerify") {
        $script:ConfiguredMavenTlsVerify = $config.mavenTlsVerify
    }
    if (-not $script:InvocationBoundParameters.ContainsKey("MavenSettingsFile") -and
        $config.PSObject.Properties.Name -contains "mavenSettingsFile" -and
        -not [string]::IsNullOrWhiteSpace([string]$config.mavenSettingsFile)) {
        $script:MavenSettingsFile = [string]$config.mavenSettingsFile
    }
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
        $authority = if ($builder.Port -gt 0) { "$($builder.Host):$($builder.Port)" } else { $builder.Host }
        $credentialPrefix = [System.Uri]::EscapeDataString($Username)
        if (-not [string]::IsNullOrWhiteSpace($Password)) {
            $credentialPrefix = "{0}:{1}" -f $credentialPrefix, [System.Uri]::EscapeDataString($Password)
        }
        $path = $builder.Path
        if ([string]::IsNullOrWhiteSpace($path)) {
            $path = "/"
        }
        return "{0}://{1}@{2}{3}{4}" -f $builder.Scheme, $credentialPrefix, $authority, $path, $builder.Query
    }
    return $builder.Uri.AbsoluteUri
}
function Add-PodmanTlsVerifyArg {
    param([System.Collections.Generic.List[string]]$ArgumentList)
    if ($script:ResolvedPodmanTlsVerify -eq $false) {
        $ArgumentList.Add("--tls-verify=false")
    }
}
function Invoke-PodmanPull {
    param([string]$Image)

    $pullArgs = [System.Collections.Generic.List[string]]::new()
    foreach ($arg in @("pull", "--platform", "linux/amd64")) {
        $pullArgs.Add($arg)
    }
    Add-PodmanTlsVerifyArg -ArgumentList $pullArgs
    $pullArgs.Add($Image)

    $attempts = [Math]::Max(5, $PodmanPullRetries)
    $delaySeconds = [Math]::Max(0, $PodmanPullRetryDelaySeconds)
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        try {
            Write-Host "Pulling image '$Image' (attempt $attempt/$attempts)..."
            Invoke-Podman -Arguments $pullArgs.ToArray()
            return
        }
        catch {
            if ($attempt -ge $attempts) {
                throw "Could not pull image '$Image' after $attempts attempt(s). Last error: $($_.Exception.Message)"
            }

            Write-Warning "Pull image '$Image' failed on attempt $attempt/$attempts. Retrying in $delaySeconds seconds. Error: $($_.Exception.Message)"
            if ($delaySeconds -gt 0) {
                Start-Sleep -Seconds $delaySeconds
            }
        }
    }
}
function Add-MavenTlsVerifyArgs {
    param([System.Collections.Generic.List[string]]$ArgumentList)
    if ($script:ResolvedMavenTlsVerify -eq $false) {
        $ArgumentList.Add("-Dmaven.resolver.transport=wagon")
        $ArgumentList.Add("-Dmaven.wagon.http.ssl.insecure=true")
        $ArgumentList.Add("-Dmaven.wagon.http.ssl.allowall=true")
        $ArgumentList.Add("-Dmaven.wagon.http.ssl.ignore.validity.dates=true")
    }
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
        [System.Collections.Generic.List[string]]$ArgumentList,
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
            $ArgumentList.Add("-e")
            $ArgumentList.Add("$($item[0])=$($item[1])")
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
function Normalize-ListValues {
    param([string[]]$Values)
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($value in @($Values)) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }
        foreach ($part in ([string]$value -split ",")) {
            $trimmed = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $result.Add($trimmed)
            }
        }
    }
    return $result.ToArray()
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
function Resolve-ProjectPathOrEmpty {
    param(
        [string]$Path,
        [string]$Root
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $Root $Path
}
function Get-MavenModulePaths {
    param([string]$PomPath)
    if (-not (Test-Path -LiteralPath $PomPath)) {
        throw "Root POM does not exist: $PomPath"
    }
    [xml]$pom = Get-Content -LiteralPath $PomPath -Raw -Encoding UTF8
    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($pom.NameTable)
    $namespaceManager.AddNamespace("m", "http://maven.apache.org/POM/4.0.0")
    $nodes = @($pom.SelectNodes("/m:project/m:modules/m:module", $namespaceManager))
    return @($nodes | ForEach-Object { ([string]$_.InnerText).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
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
function Normalize-ModulePath {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }
    return (([string]$Value).Replace("\", "/").Trim("/"))
}
function Get-ServiceModulePaths {
    param(
        [string]$Path,
        [string[]]$RootModules
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $serviceList = Get-JsonPropertyValue -Object $json -Name "services"
    if ($null -eq $serviceList) {
        return @()
    }

    $rootLookup = @{}
    foreach ($module in $RootModules) {
        $rootLookup[(Normalize-ModulePath -Value $module).ToLowerInvariant()] = $module
    }

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($service in @($serviceList)) {
        $projectDir = [string](Get-JsonPropertyValue -Object $service -Name "projectDir")
        if ([string]::IsNullOrWhiteSpace($projectDir)) {
            $projectDir = [string](Get-JsonPropertyValue -Object $service -Name "name")
        }
        $normalizedProjectDir = (Normalize-ModulePath -Value $projectDir).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($normalizedProjectDir)) {
            continue
        }
        if ($rootLookup.ContainsKey($normalizedProjectDir)) {
            $result.Add($rootLookup[$normalizedProjectDir])
        }
    }
    return @($result.ToArray() | Select-Object -Unique)
}
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ServicesFile)) {
    $ServicesFile = Join-Path $projectRoot "services.json"
} elseif (-not [System.IO.Path]::IsPathRooted($ServicesFile)) {
    $ServicesFile = Join-Path $projectRoot $ServicesFile
}
if ([string]::IsNullOrWhiteSpace($ProxyConfigFile)) {
    $ProxyConfigFile = Join-Path $projectRoot "proxy.config.json"
} elseif (-not [System.IO.Path]::IsPathRooted($ProxyConfigFile)) {
    $ProxyConfigFile = Join-Path $projectRoot $ProxyConfigFile
}
Apply-ProxyConfigFile -ConfigFile $ProxyConfigFile
$script:ResolvedPodmanTlsVerify = ConvertTo-BooleanValue -Value $script:ConfiguredPodmanTlsVerify -Name "PodmanTlsVerify"
$script:ResolvedMavenTlsVerify = ConvertTo-BooleanValue -Value $script:ConfiguredMavenTlsVerify -Name "MavenTlsVerify"
if ([string]::IsNullOrWhiteSpace($MavenRepoDir)) {
    $mavenRepo = Join-Path $projectRoot "data\maven-repo"
} else {
    $mavenRepo = $MavenRepoDir
    if (-not [System.IO.Path]::IsPathRooted($mavenRepo)) {
        $mavenRepo = Join-Path $projectRoot $mavenRepo
    }
}
New-Item -ItemType Directory -Force -Path $mavenRepo | Out-Null
if ([string]::IsNullOrWhiteSpace($BuildLogDir)) {
    $buildLogDirResolved = Join-Path $projectRoot "data\build-logs"
} else {
    $buildLogDirResolved = $BuildLogDir
    if (-not [System.IO.Path]::IsPathRooted($buildLogDirResolved)) {
        $buildLogDirResolved = Join-Path $projectRoot $buildLogDirResolved
    }
}
New-Item -ItemType Directory -Force -Path $buildLogDirResolved | Out-Null
$currentBuildLog = Join-Path $buildLogDirResolved "current.log"
if ((Test-Path -LiteralPath $currentBuildLog) -and (Get-Item -LiteralPath $currentBuildLog).Length -gt 0) {
    $previousBuildLog = Join-Path $buildLogDirResolved ("build-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Copy-Item -LiteralPath $currentBuildLog -Destination $previousBuildLog -Force
}
$buildLogHeader = @(
    "Build started: $(Get-Date -Format o)",
    "Build pod: $BuildPodName",
    "Build container: $BuildContainerName",
    "Maven image: $MavenImage",
    ""
)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllLines($currentBuildLog, $buildLogHeader, $utf8NoBom)
$effectiveHttpProxy = Resolve-ProxyUrl -Url $script:HttpProxy -Username $script:ProxyUsername -Password $script:ProxyPassword
$effectiveHttpsProxy = Resolve-ProxyUrl -Url $(if ([string]::IsNullOrWhiteSpace($script:HttpsProxy)) { $script:HttpProxy } else { $script:HttpsProxy }) -Username $script:ProxyUsername -Password $script:ProxyPassword
$effectiveNoProxy = $script:NoProxy
Set-ProxyEnvironment -HttpProxy $effectiveHttpProxy -HttpsProxy $effectiveHttpsProxy -NoProxy $effectiveNoProxy
$mavenSettingsFileResolved = Resolve-ProjectPathOrEmpty -Path $script:MavenSettingsFile -Root $projectRoot
if ([string]::IsNullOrWhiteSpace($mavenSettingsFileResolved)) {
    Write-MavenSettingsWithProxy -MavenRepo $mavenRepo -HttpProxy $effectiveHttpProxy -HttpsProxy $effectiveHttpsProxy -NoProxy $effectiveNoProxy
} else {
    if (-not (Test-Path -LiteralPath $mavenSettingsFileResolved)) {
        throw "Maven settings file was not found: $mavenSettingsFileResolved"
    }
    try {
        [xml]$null = Get-Content -LiteralPath $mavenSettingsFileResolved -Raw -Encoding UTF8
    }
    catch {
        throw "Maven settings file is not valid XML: $mavenSettingsFileResolved. Error: $($_.Exception.Message)"
    }
    Write-Host "Using app build Maven settings file: $(Format-ProjectRelativePath -Path $mavenSettingsFileResolved -Root $projectRoot)"
}
$projectRootWsl = ConvertTo-WslPath $projectRoot
$mavenRepoWsl = ConvertTo-WslPath $mavenRepo
$buildLogDirWsl = ConvertTo-WslPath $buildLogDirResolved
$mavenSettingsDirWsl = ""
$mavenSettingsFileName = ""
if (-not [string]::IsNullOrWhiteSpace($mavenSettingsFileResolved)) {
    $mavenSettingsDir = Split-Path -Parent $mavenSettingsFileResolved
    $mavenSettingsFileName = Split-Path -Leaf $mavenSettingsFileResolved
    $mavenSettingsDirWsl = ConvertTo-WslPath $mavenSettingsDir
}
if (-not $Offline) {
    Invoke-PodmanPull -Image $MavenImage
}
& podman pod exists $BuildPodName *> $null
if ($LASTEXITCODE -ne 0) {
    Invoke-Podman -Arguments @("pod", "create", "--name", $BuildPodName)
}
function Remove-BuildContainerIfExists {
    & podman container exists $BuildContainerName *> $null
    if ($LASTEXITCODE -eq 0) {
        Invoke-Podman -Arguments @("rm", "-f", $BuildContainerName)
    }
}
function New-MavenArgs {
    param(
        [string[]]$Projects,
        [string[]]$Goals,
        [bool]$UseAlsoMake
    )
    $args = [System.Collections.Generic.List[string]]::new()
    $args.Add("mvn")
    if (-not [string]::IsNullOrWhiteSpace($mavenSettingsFileName)) {
        $args.Add("-s")
        $args.Add("/maven-settings/$mavenSettingsFileName")
    }
    if ($Projects.Count -gt 0) {
        $args.Add("-pl")
        $args.Add(($Projects -join ","))
        if ($UseAlsoMake) {
            $args.Add("-am")
        }
    }
    foreach ($goal in $Goals) {
        $args.Add($goal)
    }
    if ($SkipTests) {
        $args.Add("-DskipTests")
    }
    if ($Offline) {
        $args.Add("-o")
    }
    Add-MavenTlsVerifyArgs -ArgumentList $args
    return $args.ToArray()
}
function New-PodmanMavenRunArgs {
    param([string[]]$MavenArguments)
    $args = [System.Collections.Generic.List[string]]::new()
    foreach ($arg in @(
        "run",
        "--name", $BuildContainerName,
        "--pod", $BuildPodName,
        "-v", "${projectRootWsl}:/workspace",
        "-v", "${mavenRepoWsl}:/root/.m2",
        "-w", "/workspace"
    )) {
        $args.Add($arg)
    }
    if (-not [string]::IsNullOrWhiteSpace($mavenSettingsDirWsl)) {
        $args.Add("-v")
        $args.Add("${mavenSettingsDirWsl}:/maven-settings:ro")
    }
    Add-ProxyEnvArgs -ArgumentList $args -HttpProxy $effectiveHttpProxy -HttpsProxy $effectiveHttpsProxy -NoProxy $effectiveNoProxy
    $args.Add($MavenImage)
    foreach ($arg in $MavenArguments) {
        $args.Add($arg)
    }
    return $args.ToArray()
}
function Invoke-MavenBuildPhase {
    param(
        [string]$PhaseName,
        [string[]]$MavenArguments,
        [bool]$KeepContainerAfterSuccess
    )
    $mavenAttempts = [Math]::Max(1, $MavenBuildRetries)
    $mavenRetryDelaySeconds = [Math]::Max(0, $MavenBuildRetryDelaySeconds)
    for ($attempt = 1; $attempt -le $mavenAttempts; $attempt++) {
        try {
            Remove-BuildContainerIfExists
            $runArgs = New-PodmanMavenRunArgs -MavenArguments $MavenArguments
            Write-Output "Running Maven $PhaseName (attempt $attempt/$mavenAttempts): $($MavenArguments -join ' ')"
            Invoke-PodmanWithLog -Arguments $runArgs -LogPath $currentBuildLog
            if (-not $KeepContainerAfterSuccess) {
                Remove-BuildContainerIfExists
            }
            return
        }
        catch {
            if ($attempt -ge $mavenAttempts) {
                if (-not $DisableBuildLogViewer) {
                    Start-BuildLogViewer -ContainerName $BuildLogViewerContainerName -PodName $BuildPodName -Image $MavenImage -BuildLogDirWsl $buildLogDirWsl
                }
                throw "Maven $PhaseName failed after $mavenAttempts attempt(s). Last error: $($_.Exception.Message)"
            }

            Write-Warning "Maven $PhaseName failed on attempt $attempt/$mavenAttempts. Retrying in $mavenRetryDelaySeconds seconds. Error: $($_.Exception.Message)"
            Remove-BuildContainerIfExists
            if ($mavenRetryDelaySeconds -gt 0) {
                Start-Sleep -Seconds $mavenRetryDelaySeconds
            }
        }
    }
}

$rootModules = @(Get-MavenModulePaths -PomPath (Join-Path $projectRoot "pom.xml"))
$serviceModules = @(Get-ServiceModulePaths -Path $ServicesFile -RootModules $rootModules)
$requestedModules = @(Normalize-ListValues -Values $MavenProjects)

$rootModuleLookup = @{}
foreach ($module in $rootModules) {
    $rootModuleLookup[(Normalize-ModulePath -Value $module).ToLowerInvariant()] = $module
}
foreach ($module in $requestedModules) {
    $normalized = (Normalize-ModulePath -Value $module).ToLowerInvariant()
    if (-not $rootModuleLookup.ContainsKey($normalized)) {
        throw "Maven project '$module' is not listed in root pom.xml modules."
    }
}

$serviceModuleLookup = @{}
foreach ($module in $serviceModules) {
    $serviceModuleLookup[(Normalize-ModulePath -Value $module).ToLowerInvariant()] = $true
}

$libraryModules = @()
if ($serviceModules.Count -gt 0) {
    $libraryModules = @($rootModules | Where-Object {
        -not $serviceModuleLookup.ContainsKey((Normalize-ModulePath -Value $_).ToLowerInvariant())
    })
}

$packageAllModules = $false
if ($requestedModules.Count -gt 0) {
    $requestedResolved = @($requestedModules | ForEach-Object { $rootModuleLookup[(Normalize-ModulePath -Value $_).ToLowerInvariant()] })
    $libraryLookup = @{}
    foreach ($module in $libraryModules) {
        $libraryLookup[(Normalize-ModulePath -Value $module).ToLowerInvariant()] = $true
    }
    $appModulesToPackage = @($requestedResolved | Where-Object {
        -not $libraryLookup.ContainsKey((Normalize-ModulePath -Value $_).ToLowerInvariant())
    })
    $explicitLibraryModules = @($requestedResolved | Where-Object {
        $libraryLookup.ContainsKey((Normalize-ModulePath -Value $_).ToLowerInvariant())
    })
    if ($appModulesToPackage.Count -gt 0) {
        $libraryModulesToInstall = $libraryModules
    } else {
        $libraryModulesToInstall = $explicitLibraryModules
    }
} elseif ($serviceModules.Count -gt 0) {
    $appModulesToPackage = $serviceModules
    $libraryModulesToInstall = $libraryModules
} else {
    $appModulesToPackage = @()
    $libraryModulesToInstall = @()
    $packageAllModules = $true
}

if ($libraryModulesToInstall.Count -gt 0) {
    Write-Output "Library/BOM modules to install first: $($libraryModulesToInstall -join ', ')"
    $libraryMavenArgs = New-MavenArgs -Projects $libraryModulesToInstall -Goals @("clean", "install") -UseAlsoMake $true
    Invoke-MavenBuildPhase -PhaseName "library install" -MavenArguments $libraryMavenArgs -KeepContainerAfterSuccess $false
} else {
    Write-Output "No separate library/BOM modules detected before app build."
}

if ($packageAllModules) {
    Write-Output "App modules to package: all root pom.xml modules"
    $appMavenArgs = New-MavenArgs -Projects @() -Goals @("clean", "package") -UseAlsoMake $false
    Invoke-MavenBuildPhase -PhaseName "app package" -MavenArguments $appMavenArgs -KeepContainerAfterSuccess $KeepBuildContainer
} elseif ($appModulesToPackage.Count -gt 0) {
    Write-Output "App modules to package: $($appModulesToPackage -join ', ')"
    $appMavenArgs = New-MavenArgs -Projects $appModulesToPackage -Goals @("clean", "package") -UseAlsoMake ([bool]$AlsoMake)
    Invoke-MavenBuildPhase -PhaseName "app package" -MavenArguments $appMavenArgs -KeepContainerAfterSuccess $KeepBuildContainer
} else {
    Write-Output "No app modules selected for package phase."
}
if (-not $DisableBuildLogViewer) {
    Start-BuildLogViewer -ContainerName $BuildLogViewerContainerName -PodName $BuildPodName -Image $MavenImage -BuildLogDirWsl $buildLogDirWsl
}
Write-Output "Build completed in Podman pod: $BuildPodName"
Write-Output "Maven cache folder: $(Format-ProjectRelativePath -Path $mavenRepo -Root $projectRoot)"
Write-Output "Build log file: $(Format-ProjectRelativePath -Path $currentBuildLog -Root $projectRoot)"
if (-not $DisableBuildLogViewer) {
    Write-Output "Dozzle log viewer: http://localhost:40004 -> $BuildLogViewerContainerName"
}
Write-Output "Raw Maven container logs kept only with: -KeepBuildContainer"
Write-Output "Show it with: podman pod ps --filter name=$BuildPodName"
