param(
    [string]$ServicesFile,
    [string]$BundleDir = "",
    [string]$NetworkName = "devnet",
    [string]$KafkaImage = "apache/kafka-native:3.9.0",
    [string]$KafkaCliImage = "apache/kafka:3.9.0",
    [string]$KafkaUiImage = "ghcr.io/kafbat/kafka-ui:latest",
    [string]$SqlImage = "mcr.microsoft.com/mssql/server:2022-latest",
    [string]$SqlAdminImage = "dbgate/dbgate:latest",
    [string]$LogViewerImage = "amir20/dozzle:latest",
    [string]$NifiImage = "apache/nifi:1.28.1",
    [string]$BaseJavaImage = "eclipse-temurin:21-jre-alpine",
    [string]$MavenImage = "maven:3.9.9-eclipse-temurin-21",
    [string]$BuildPodName = "java-build-pod",
    [string]$Containerfile = "",
    [string]$BuildRoot = "",
    [string]$ProxyConfigFile = "",
    [string]$HttpProxy = "",
    [string]$HttpsProxy = "",
    [string]$NoProxy = "localhost,127.0.0.1,mssql,kafka,kafka-ui,sql-admin,app1,app2,app3,app4,app5,app6",
    [string]$ProxyUsername = "",
    [string]$ProxyPassword = "",
    [string]$PodmanTlsVerify = "true",
    [string]$MavenTlsVerify = "true",
    [switch]$SkipJavaBuild,
    [switch]$SkipTests,
    [switch]$OfflineJavaBuild,
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
$script:PodmanTlsVerify = $PodmanTlsVerify
$script:MavenTlsVerify = $MavenTlsVerify
$ProjectRoot = Split-Path -Parent $PSScriptRoot
function Show-Help {
    @'
export-offline-bundle.ps1
Cel:
  Teljes offline Podman bundle keszitese masik Windows gepre.
  A bundle tartalmazza az image tar fajlt, services.json-t, runtime YAML
  konfiguraciokat, dokumentaciot es a scripts konyvtarat.
Hasznalat:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 -ServicesFile .\services.json [opciok]
Normal export internetes gepen:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
    -ServicesFile .\services.json `
    -SkipTests
Proxy mogotti gepen:
  1. Toltsd ki: .\proxy.config.json
  2. Allitsd: "enabled": true
  3. Ugyanazt a fenti export parancsot futtasd.
Ha a Java buildet mar kulon megcsinaltad:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
    -ServicesFile .\services.json `
    -SkipJavaBuild
Ha Maven cache mar megvan es nincs internet:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
    -ServicesFile .\services.json `
    -SkipTests `
    -OfflineJavaBuild
Mit csinal:
  1. Opcionalisan futtatja a build-apps-with-podman.ps1 scriptet.
  2. Minden service JAR-bol local/appN:dev image-et buildel.
  3. Lehuzza vagy ellenorzi az infra image-eket:
     SQL Server, Kafka broker, Kafka CLI helper, Kafka UI, DbGate, Dozzle,
     Apache NiFi, Java runtime, Maven builder.
  4. Osszegyujti az osszes image-et es elmenti ide:
     .\offline-bundle\images\podman-images.tar
  5. Bemasolja a services.json-t es a Containerfile-t.
  6. Bemasolja a scripts konyvtarat, beleertve a scripts/private segedfajlokat.
  7. Bemasolja az appok src/main/resources konyvtarait runtime YAML config miatt.
  8. Bemasolja a dokumentaciot es browser-start.html-t.
  9. Letrehozza a bundle-manifest.json fajlt.
Parameterek:
  -ServicesFile
      Kotelezo normal futasnal. A services.json utvonala.
  -BundleDir
      Cel bundle konyvtar. Uresen: .\offline-bundle
      A script ezt ujrageneralja.
      Ha a rendszermeghajton nincs eleg hely a podman-images.tar fajlhoz,
      adj meg masik meghajtot, peldaul: -BundleDir P:\offline-bundle
  -NetworkName
      A manifestbe es run scriptbe valo network nev. Alapertelmezett: devnet
  -KafkaImage, -KafkaCliImage, -KafkaUiImage, -SqlImage, -SqlAdminImage, -LogViewerImage, -BaseJavaImage, -MavenImage
      A bundle-be mentendo image-ek.
  -NifiImage
      Apache NiFi image a file-to-Kafka podhoz. Alapertelmezett: apache/nifi:1.28.1
  -BuildPodName
      Maven build pod neve. Alapertelmezett: java-build-pod
  -Containerfile
      Spring Boot app image Containerfile. Uresen: .\Containerfile.spring-boot-jar
  -BuildRoot
      Ideiglenes build context konyvtar. Uresen: .\work\podman-build
  -ProxyConfigFile
      Proxy config JSON. Uresen: .\proxy.config.json
  -HttpProxy, -HttpsProxy, -NoProxy, -ProxyUsername, -ProxyPassword
      Ideiglenes proxy feluliras. Normal esetben a proxy.config.json hasznalando.
  -PodmanTlsVerify
      Podman registry TLS certificate ellenorzes pull/build kozben. Alapertelmezett: true.
      Ceges TLS inspection/x509 hiba eseten inkabb a proxy.config.json fajlban allitsd:
      "podmanTlsVerify": false
  -MavenTlsVerify
      Maven/Java HTTPS certificate ellenorzes dependency letoltes kozben. Alapertelmezett: true.
      Ceges TLS inspection vagy ismeretlen CA hiba eseten inkabb a proxy.config.json fajlban allitsd:
      "mavenTlsVerify": false
  -SkipJavaBuild
      Nem futtat Maven buildet. Akkor hasznald, ha a JAR-ok mar keszek.
  -SkipTests
      Maven buildnel kihagyja a teszteket.
  -OfflineJavaBuild
      Maven build offline modban fut. Csak feltoltott Maven cache mellett mukodik.
  --help
      Ezt a reszletes leirast irja ki es nem general bundle-t.
Eredmeny:
  .\offline-bundle
  .\offline-bundle\images\podman-images.tar
  .\offline-bundle\scripts\run-offline.ps1
Masik gepen futtatas:
  cd "<ahova-masoltad>\offline-bundle"
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
    -SqlPassword "Alkalmassagi_2026!" `
    -ExternalHostName localhost
Biztonsag:
  A kitoltott proxy.config.json nincs automatikusan bemasolva az offline bundle-be,
  mert jelszot tartalmazhat. Az offline futtatashoz nem kell proxy config.
'@
}
if ($Help) {
    Show-Help
    exit 0
}
if ([string]::IsNullOrWhiteSpace($ServicesFile)) {
    throw "Missing required parameter: -ServicesFile. Use --help for detailed usage."
}
if ([string]::IsNullOrWhiteSpace($BundleDir)) {
    $BundleDir = Join-Path $ProjectRoot "offline-bundle"
} elseif (-not [System.IO.Path]::IsPathRooted($BundleDir)) {
    $BundleDir = Join-Path $ProjectRoot $BundleDir
}
if ([string]::IsNullOrWhiteSpace($Containerfile)) {
    $Containerfile = Join-Path $ProjectRoot "Containerfile.spring-boot-jar"
} elseif (-not [System.IO.Path]::IsPathRooted($Containerfile)) {
    $Containerfile = Join-Path $ProjectRoot $Containerfile
}
if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
    $BuildRoot = Join-Path $ProjectRoot "work\podman-build"
} elseif (-not [System.IO.Path]::IsPathRooted($BuildRoot)) {
    $BuildRoot = Join-Path $ProjectRoot $BuildRoot
}
if ([string]::IsNullOrWhiteSpace($ProxyConfigFile)) {
    $ProxyConfigFile = Join-Path $ProjectRoot "proxy.config.json"
} elseif (-not [System.IO.Path]::IsPathRooted($ProxyConfigFile)) {
    $ProxyConfigFile = Join-Path $ProjectRoot $ProxyConfigFile
}
function Invoke-Podman {
    param([string[]]$Arguments)
    & podman @Arguments | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "podman $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
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
        $script:PodmanTlsVerify = $config.podmanTlsVerify
    }
    if (-not $script:InvocationBoundParameters.ContainsKey("MavenTlsVerify") -and
        $config.PSObject.Properties.Name -contains "mavenTlsVerify") {
        $script:MavenTlsVerify = $config.mavenTlsVerify
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
    if ($script:PodmanTlsVerify -eq $false) {
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
    Invoke-Podman -Arguments $pullArgs.ToArray()
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
function Add-ProxyBuildArgs {
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
            $ArgumentList.Add("--build-arg")
            $ArgumentList.Add("$($item[0])=$($item[1])")
        }
    }
}
function Find-ServiceJar {
    param([string]$ProjectDir)
    $targetDir = Join-Path $ProjectDir "target"
    if (-not (Test-Path -LiteralPath $targetDir)) {
        throw "Missing target directory: $targetDir"
    }
    $jars = Get-ChildItem -LiteralPath $targetDir -Filter "*.jar" -File |
        Where-Object {
            $_.Name -notmatch "(-sources|-javadoc|\.original)\.jar$" -and
            $_.Name -notmatch "^original-"
        } |
        Sort-Object LastWriteTime -Descending
    if (-not $jars) {
        throw "No runnable JAR found in: $targetDir"
    }
    return $jars[0].FullName
}
function Build-ServiceImage {
    param(
        [object]$Service,
        [string]$BuildRoot,
        [string]$Containerfile
    )
    $name = [string]$Service.name
    $projectDir = [string]$Service.projectDir
    if (-not [System.IO.Path]::IsPathRooted($projectDir)) {
        $projectDir = Join-Path $ProjectRoot $projectDir
    }
    $imageTag = if ($Service.imageTag) { [string]$Service.imageTag } else { "local/${name}:dev" }
    $jarPath = if ($Service.jarPath) { [string]$Service.jarPath } else { Find-ServiceJar $projectDir }
    $buildDir = Join-Path $BuildRoot $name
    if (-not (Test-Path -LiteralPath $jarPath)) {
        throw "JAR does not exist for service '$name': $jarPath"
    }
    Remove-Item -LiteralPath $buildDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    Copy-Item -LiteralPath $Containerfile -Destination (Join-Path $buildDir "Containerfile") -Force
    Copy-Item -LiteralPath $jarPath -Destination (Join-Path $buildDir "app.jar") -Force
    $buildArgs = [System.Collections.Generic.List[string]]::new()
    foreach ($arg in @(
        "build",
        "--platform", "linux/amd64",
        "-t", $imageTag,
        "-f", (Join-Path $buildDir "Containerfile")
    )) {
        $buildArgs.Add($arg)
    }
    Add-PodmanTlsVerifyArg -ArgumentList $buildArgs
    Add-ProxyBuildArgs -ArgumentList $buildArgs -HttpProxy $script:EffectiveHttpProxy -HttpsProxy $script:EffectiveHttpsProxy -NoProxy $script:EffectiveNoProxy
    $buildArgs.Add($buildDir)
    Invoke-Podman -Arguments $buildArgs.ToArray()
    return $imageTag
}
function Copy-ServiceRuntimeConfig {
    param(
        [object]$Service,
        [string]$BundleDir
    )
    $name = [string]$Service.name
    $projectDir = [string]$Service.projectDir
    if (-not [System.IO.Path]::IsPathRooted($projectDir)) {
        $projectDir = Join-Path $ProjectRoot $projectDir
    }
    $resourcesDir = Join-Path $projectDir "src\main\resources"
    $applicationYaml = Join-Path $resourcesDir "application.yaml"
    if (-not (Test-Path -LiteralPath $applicationYaml)) {
        throw "Missing runtime application YAML for service '$name': $applicationYaml"
    }
    $targetResourcesDir = Join-Path $BundleDir "$name\src\main\resources"
    New-Item -ItemType Directory -Force -Path $targetResourcesDir | Out-Null
    Copy-Item -Path (Join-Path $resourcesDir "*") -Destination $targetResourcesDir -Recurse -Force
}
function Get-ArchiveDriveInfo {
    param([string]$Path)
    $root = [System.IO.Path]::GetPathRoot($Path)
    if ([string]::IsNullOrWhiteSpace($root)) {
        return $null
    }
    try {
        return [System.IO.DriveInfo]::new($root)
    }
    catch {
        return $null
    }
}
function Get-EstimatedArchiveSizeBytes {
    param([string[]]$Images)
    $totalBytes = [int64]0
    foreach ($image in ($Images | Select-Object -Unique)) {
        $sizeText = (& podman image inspect --format "{{.Size}}" $image 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sizeText)) {
            continue
        }
        $parsedSize = 0L
        if ([int64]::TryParse($sizeText.Trim(), [ref]$parsedSize)) {
            $totalBytes += $parsedSize
        }
    }
    if ($totalBytes -le 0) {
        return 0L
    }
    # Multi-image docker archives share some layers, but they still need substantial headroom.
    return [int64][Math]::Ceiling(($totalBytes * 0.75) + 512MB)
}
function Assert-SufficientArchiveSpace {
    param(
        [string]$ArchivePath,
        [string[]]$Images
    )
    $driveInfo = Get-ArchiveDriveInfo -Path $ArchivePath
    if ($null -eq $driveInfo) {
        return
    }
    $estimatedBytes = Get-EstimatedArchiveSizeBytes -Images $Images
    if ($estimatedBytes -le 0) {
        return
    }
    if ($driveInfo.AvailableFreeSpace -lt $estimatedBytes) {
        $availableGiB = [Math]::Round($driveInfo.AvailableFreeSpace / 1GB, 2)
        $estimatedGiB = [Math]::Round($estimatedBytes / 1GB, 2)
        throw "Not enough free space on drive '$($driveInfo.Name)' for podman save. Available: ${availableGiB} GiB. Estimated minimum required: ${estimatedGiB} GiB. Use -BundleDir on a drive with more free space, for example: -BundleDir P:\offline-bundle"
    }
}
if (-not (Test-Path -LiteralPath $ServicesFile)) {
    if (-not [System.IO.Path]::IsPathRooted($ServicesFile)) {
        $ServicesFile = Join-Path $ProjectRoot $ServicesFile
    }
}
if (-not (Test-Path -LiteralPath $ServicesFile)) {
    throw "Services file does not exist: $ServicesFile"
}
if (-not (Test-Path -LiteralPath $Containerfile)) {
    throw "Containerfile does not exist: $Containerfile"
}
Apply-ProxyConfigFile -ConfigFile $ProxyConfigFile
$script:PodmanTlsVerify = ConvertTo-BooleanValue -Value $script:PodmanTlsVerify -Name "PodmanTlsVerify"
$script:MavenTlsVerify = ConvertTo-BooleanValue -Value $script:MavenTlsVerify -Name "MavenTlsVerify"
$script:EffectiveHttpProxy = Resolve-ProxyUrl -Url $script:HttpProxy -Username $script:ProxyUsername -Password $script:ProxyPassword
$script:EffectiveHttpsProxy = Resolve-ProxyUrl -Url $(if ([string]::IsNullOrWhiteSpace($script:HttpsProxy)) { $script:HttpProxy } else { $script:HttpsProxy }) -Username $script:ProxyUsername -Password $script:ProxyPassword
$script:EffectiveNoProxy = $script:NoProxy
Set-ProxyEnvironment -HttpProxy $script:EffectiveHttpProxy -HttpsProxy $script:EffectiveHttpsProxy -NoProxy $script:EffectiveNoProxy
if (-not $SkipJavaBuild) {
    $javaBuildScript = Join-Path $PSScriptRoot "build-apps-with-podman.ps1"
    if (-not (Test-Path -LiteralPath $javaBuildScript)) {
        throw "Java build script does not exist: $javaBuildScript"
    }
    $javaBuildArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $javaBuildScript,
        "-MavenImage", $MavenImage,
        "-BuildPodName", $BuildPodName,
        "-ProxyConfigFile", $ProxyConfigFile
    )
    if ($SkipTests) {
        $javaBuildArgs += "-SkipTests"
    }
    if ($OfflineJavaBuild) {
        $javaBuildArgs += "-Offline"
    }
    if ($script:PodmanTlsVerify -eq $false) {
        $javaBuildArgs += "-PodmanTlsVerify"
        $javaBuildArgs += "false"
    }
    if ($script:MavenTlsVerify -eq $false) {
        $javaBuildArgs += "-MavenTlsVerify"
        $javaBuildArgs += "false"
    }
    & powershell @javaBuildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Java build failed with exit code $LASTEXITCODE"
    }
}
$services = Get-Content -LiteralPath $ServicesFile -Raw -Encoding UTF8 | ConvertFrom-Json
$images = [System.Collections.Generic.List[string]]::new()
$images.Add($SqlImage)
$images.Add($KafkaImage)
$images.Add($KafkaCliImage)
$images.Add($KafkaUiImage)
$images.Add($SqlAdminImage)
$images.Add($LogViewerImage)
$images.Add($NifiImage)
$images.Add($BaseJavaImage)
$images.Add($MavenImage)
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
foreach ($service in $services) {
    $imageTag = Build-ServiceImage -Service $service -BuildRoot $BuildRoot -Containerfile $Containerfile
    $images.Add($imageTag)
}
Invoke-PodmanPull -Image $SqlImage
Invoke-PodmanPull -Image $KafkaImage
Invoke-PodmanPull -Image $KafkaCliImage
Invoke-PodmanPull -Image $KafkaUiImage
Invoke-PodmanPull -Image $SqlAdminImage
Invoke-PodmanPull -Image $LogViewerImage
Invoke-PodmanPull -Image $NifiImage
Invoke-PodmanPull -Image $BaseJavaImage
if (-not $OfflineJavaBuild) {
    Invoke-PodmanPull -Image $MavenImage
}
Remove-Item -LiteralPath $BundleDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $BundleDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $BundleDir "images") | Out-Null
$archivePath = Join-Path $BundleDir "images\podman-images.tar"
$uniqueImages = $images | Select-Object -Unique
Assert-SufficientArchiveSpace -ArchivePath $archivePath -Images $uniqueImages
$saveArgs = @(
    "save",
    "-m",
    "--format", "docker-archive",
    "-o", $archivePath
) + @($uniqueImages)
Invoke-Podman -Arguments $saveArgs
Copy-Item -LiteralPath $ServicesFile -Destination (Join-Path $BundleDir "services.json") -Force
Copy-Item -LiteralPath $Containerfile -Destination (Join-Path $BundleDir "Containerfile.spring-boot-jar") -Force
$nifiConfigPath = Join-Path $ProjectRoot "nifi-flows.yaml"
if (Test-Path -LiteralPath $nifiConfigPath) {
    Copy-Item -LiteralPath $nifiConfigPath -Destination (Join-Path $BundleDir "nifi-flows.yaml") -Force
}
$nifiTemplateConfigPath = Join-Path $ProjectRoot "config\nifi"
if (Test-Path -LiteralPath $nifiTemplateConfigPath) {
    New-Item -ItemType Directory -Force -Path (Join-Path $BundleDir "config") | Out-Null
    Copy-Item -LiteralPath $nifiTemplateConfigPath -Destination (Join-Path $BundleDir "config\nifi") -Recurse -Force
}
$nifiSamplesPath = Join-Path $ProjectRoot "nifi-sample-files"
if (Test-Path -LiteralPath $nifiSamplesPath) {
    Copy-Item -LiteralPath $nifiSamplesPath -Destination (Join-Path $BundleDir "nifi-sample-files") -Recurse -Force
}
$bundleScriptsDir = Join-Path $BundleDir "scripts"
$bundlePrivateScriptsDir = Join-Path $bundleScriptsDir "private"
New-Item -ItemType Directory -Force -Path $bundleScriptsDir | Out-Null
New-Item -ItemType Directory -Force -Path $bundlePrivateScriptsDir | Out-Null
foreach ($scriptName in @(
    "deploy-springboot-pods.ps1",
    "deploy-infra-pods.ps1",
    "configure-lan-firewall.ps1",
    "run-offline.ps1",
    "build-apps-with-podman.ps1",
    "export-offline-bundle.ps1",
    "send-test-message.ps1",
    "export-container-logs.ps1",
    "configure-nifi-file-to-kafka.ps1",
    "split-offline-image.ps1",
    "join-offline-image.ps1"
)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $scriptName) -Destination (Join-Path $bundleScriptsDir $scriptName) -Force
}
Copy-Item -Path (Join-Path $PSScriptRoot "private\*.ps1") -Destination $bundlePrivateScriptsDir -Force
foreach ($service in $services) {
    Copy-ServiceRuntimeConfig -Service $service -BundleDir $BundleDir
}
foreach ($docName in @(
    ".gitignore",
    ".gitattributes",
    "proxy.config.sample.json",
    "GITHUB-PUBLISH.md",
    "offline-bundle.README.md",
    "README.local-podman.md",
    "BROWSER-PAGES.md",
    "APPLICATION-YAML-CONFIG.md",
    "PROXY-CONFIG.md",
    "PORT-CONFIG.md",
    "SCRIPT-STRUCTURE.md",
    "LOG-VIEWER.md",
    "LOG-PERSISTENCE.md",
    "NIFI-FILE-TO-KAFKA.md",
    "REST-SOAP-SECURITY-EXAMPLES.md",
    "ADD-NEW-APP.md",
    "start.md",
    "browser-start.html"
)) {
    $docPath = Join-Path $ProjectRoot $docName
    if (Test-Path -LiteralPath $docPath) {
        Copy-Item -LiteralPath $docPath -Destination (Join-Path $BundleDir $docName) -Force
    }
}
$manifest = [ordered]@{
    createdAt = (Get-Date).ToString("s")
    networkName = $NetworkName
    sqlImage = $SqlImage
    kafkaImage = $KafkaImage
    kafkaCliImage = $KafkaCliImage
    kafkaUiImage = $KafkaUiImage
    sqlAdminImage = $SqlAdminImage
    logViewerImage = $LogViewerImage
    nifiImage = $NifiImage
    baseJavaImage = $BaseJavaImage
    mavenImage = $MavenImage
    buildPodName = $BuildPodName
    images = @($uniqueImages)
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $BundleDir "bundle-manifest.json") -Encoding UTF8
$bundleDisplayPath = Format-ProjectRelativePath -Path $BundleDir -Root $ProjectRoot
Write-Output "Offline bundle created: $bundleDisplayPath"
Write-Output "Copy this whole folder to the target machine and run: .\scripts\run-offline.ps1 -SqlPassword '<password>'"
