param(
    [string]$ServicesFile,

    [string]$SqlPassword = "",

    [string]$NetworkName = "devnet",
    [string]$Containerfile = "",
    [string]$BuildRoot = "",
    [string]$LogArchiveDir = "",
    [string]$ProxyConfigFile = "",
    [string]$HttpProxy = "",
    [string]$HttpsProxy = "",
    [string]$NoProxy = "localhost,127.0.0.1,mssql,kafka,kafka-ui,sql-admin,app1,app2,app3,app4,app5,app6",
    [string]$ProxyUsername = "",
    [string]$ProxyPassword = "",
    [switch]$SkipBuild,
    [switch]$SkipLogArchive,
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$script:InvocationBoundParameters = $PSBoundParameters
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Show-Help {
    @'
deploy-springboot-pods.ps1

Cel:
  A services.json alapjan elinditja az app1-app6 Spring Boot alkalmazasokat
  kulon Podman podokban. Opcionalisan elotte kontener image-et is buildel a
  kesz JAR-okbol.

Hasznalat:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 -ServicesFile .\services.json [opciok]

Image build + inditas:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
    -ServicesFile .\services.json `
    -SqlPassword "Alkalmassagi_2026!"

Csak ujrainditas mar meglevo image-ekbol:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
    -ServicesFile .\services.json `
    -SqlPassword "Alkalmassagi_2026!" `
    -SkipBuild

Mit csinal:
  1. Beolvassa a services.json fajlt.
  2. Minden service-hez ellenorzi az application.yaml fajlt.
  3. Ha nincs -SkipBuild, megkeresi a target alatti runnable JAR-t es image-et buildel.
  4. Letrehozza vagy ujra letrehozza az appN-pod podot.
  5. Mountolja az app application.yaml fajljat /app/config/application.yaml ala.
  6. Beallitja a health checket: /actuator/health.
  7. Elinditja az app kontenert a devnet networkon.

Parameterek:
  -ServicesFile
      Kotelezo normal futasnal. A services.json utvonala.

  -SqlPassword
      Ha meg van adva, az app env-be is bekerulhet a services.json env mellett.

  -NetworkName
      Podman network neve. Alapertelmezett: devnet

  -Containerfile
      Spring Boot JAR image build Containerfile. Uresen: .\Containerfile.spring-boot-jar

  -BuildRoot
      Ideiglenes build context konyvtar. Uresen: .\work\podman-build

  -LogArchiveDir
      Kontener log archive konyvtar. Uresen: .\data\logs
      Pod ujraletrehozas elott ide menti a regi app kontenerlogokat.

  -ProxyConfigFile
      Proxy config JSON. Uresen: .\proxy.config.json

  -HttpProxy, -HttpsProxy, -NoProxy, -ProxyUsername, -ProxyPassword
      Ideiglenes proxy feluliras podman buildhez. Normal esetben proxy.config.json.

  -SkipBuild
      Nem buildel image-et, csak mar letezo image-ekbol inditja a podokat.
      Offline target gepen a run-offline.ps1 ezt hasznalja.

  -SkipLogArchive
      Nem menti ki a regi app podok logjait torles elott.

  --help
      Ezt a reszletes leirast irja ki es nem indit appokat.

services.json fontos mezok:
  name, projectDir, imageTag, hostPort, containerPort, env, jarPath

Eredmeny:
  app1-pod ... app6-pod, mindegyik kulon podban, egymast DNS nevvel latjak:
  app1, app2, app3, app4, app5, app6, kafka, mssql
'@
}

if ($Help) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ServicesFile)) {
    throw "Missing required parameter: -ServicesFile. Use --help for detailed usage."
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

if ([string]::IsNullOrWhiteSpace($LogArchiveDir)) {
    $LogArchiveDir = Join-Path $ProjectRoot "data\logs"
} elseif (-not [System.IO.Path]::IsPathRooted($LogArchiveDir)) {
    $LogArchiveDir = Join-Path $ProjectRoot $LogArchiveDir
}

if ([string]::IsNullOrWhiteSpace($ProxyConfigFile)) {
    $ProxyConfigFile = Join-Path $ProjectRoot "proxy.config.json"
} elseif (-not [System.IO.Path]::IsPathRooted($ProxyConfigFile)) {
    $ProxyConfigFile = Join-Path $ProjectRoot $ProxyConfigFile
}

function Ensure-Network {
    param([string]$Name)

    podman network exists $Name 2>$null
    if ($LASTEXITCODE -ne 0) {
        podman network create $Name | Out-Null
    }
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

function Add-ProxyBuildArgs {
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
            $Args.Add("--build-arg")
            $Args.Add("$($item[0])=$($item[1])")
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
    $distro = Get-PodmanWslDistro
    $wslOutput = @(wsl.exe -d $distro -- wslpath -a $resolvedPath 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not convert path to WSL path using distro '$distro': $resolvedPath. Output: $($wslOutput -join ' ')"
    }

    $firstLine = $wslOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    if (-not $firstLine) {
        throw "Could not convert path to WSL path using distro '$distro': $resolvedPath. The wslpath command returned no output."
    }

    return ([string]$firstLine).Trim()
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
        [string]$NetworkName,
        [string]$Alias,
        [int]$HostPort,
        [int]$ContainerPort
    )

    podman pod exists $Name 2>$null
    if ($LASTEXITCODE -eq 0) {
        Save-PodLogs -Name $Name
        podman pod rm -f $Name | Out-Null
    }

    podman pod create `
        --name $Name `
        --network $NetworkName `
        --network-alias $Alias `
        --publish "0.0.0.0:${HostPort}:${ContainerPort}" | Out-Null
}

function Add-EnvArgs {
    param(
        [System.Collections.Generic.List[string]]$Args,
        [object]$EnvObject
    )

    if ($null -eq $EnvObject) {
        return
    }

    foreach ($property in $EnvObject.PSObject.Properties) {
        $Args.Add("-e")
        $Args.Add("$($property.Name)=$($property.Value)")
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

$effectiveHttpProxy = Resolve-ProxyUrl -Url $HttpProxy -Username $ProxyUsername -Password $ProxyPassword
$effectiveHttpsProxy = Resolve-ProxyUrl -Url $(if ([string]::IsNullOrWhiteSpace($HttpsProxy)) { $HttpProxy } else { $HttpsProxy }) -Username $ProxyUsername -Password $ProxyPassword
Set-ProxyEnvironment -HttpProxy $effectiveHttpProxy -HttpsProxy $effectiveHttpsProxy -NoProxy $NoProxy

Ensure-Network $NetworkName

$services = Get-Content -LiteralPath $ServicesFile -Raw -Encoding UTF8 | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null

foreach ($service in $services) {
    $name = [string]$service.name
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "Every service must have a name."
    }

    $projectDir = [string]$service.projectDir
    if ([string]::IsNullOrWhiteSpace($projectDir)) {
        throw "Service '$name' must have projectDir."
    }

    if (-not [System.IO.Path]::IsPathRooted($projectDir)) {
        $projectDir = Join-Path $ProjectRoot $projectDir
    }

    $hostPort = if ($service.hostPort) { [int]$service.hostPort } else { 0 }
    $containerPort = if ($service.containerPort) { [int]$service.containerPort } else { 8080 }
    if ($hostPort -le 0) {
        throw "Service '$name' must have a positive hostPort."
    }

    $imageTag = if ($service.imageTag) { [string]$service.imageTag } else { "local/${name}:dev" }
    $podName = "${name}-pod"
    $buildDir = Join-Path $BuildRoot $name
    $applicationYaml = Join-Path $projectDir "src\main\resources\application.yaml"

    if (-not (Test-Path -LiteralPath $applicationYaml)) {
        throw "Missing application YAML for service '$name': $applicationYaml"
    }

    if (-not $SkipBuild) {
        $jarPath = if ($service.jarPath) { [string]$service.jarPath } else { Find-ServiceJar $projectDir }

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
        Add-ProxyBuildArgs -Args $buildArgs -HttpProxy $effectiveHttpProxy -HttpsProxy $effectiveHttpsProxy -NoProxy $NoProxy
        $buildArgs.Add($buildDir)
        & podman @($buildArgs.ToArray())
        if ($LASTEXITCODE -ne 0) {
            throw "podman $($buildArgs -join ' ') failed with exit code $LASTEXITCODE"
        }
    }

    Recreate-Pod `
        -Name $podName `
        -NetworkName $NetworkName `
        -Alias $name `
        -HostPort $hostPort `
        -ContainerPort $containerPort

    $runArgs = [System.Collections.Generic.List[string]]::new()
    $baseRunArgs = @(
        "run", "-d",
        "--pod", $podName,
        "--name", $name,
        "--health-cmd", "curl -fsS http://127.0.0.1:${containerPort}/actuator/health || exit 1",
        "--health-interval", "10s",
        "--health-timeout", "5s",
        "--health-retries", "12",
        "--health-start-period", "60s",
        "-v", "$(ConvertTo-WslPath $applicationYaml):/app/config/application.yaml:ro"
    )

    foreach ($arg in $baseRunArgs) {
        $runArgs.Add([string]$arg)
    }

    Add-EnvArgs -Args $runArgs -EnvObject $service.env
    $runArgs.Add($imageTag)

    & podman @runArgs
}

podman ps --pod
