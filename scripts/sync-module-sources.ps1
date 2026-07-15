param(
    [string]$PomFile = "",
    [string]$ServicesFile = "",
    [string[]]$ModuleName = @(),
    [string]$Branch = "",
    [string[]]$ModuleBranch = @(),
    [switch]$AllowDirty,
    [switch]$DryRun,
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Show-Help {
    @'
sync-module-sources.ps1

Cel:
  A root pom.xml <modules> listajaban szereplo Maven modulok forraskodjat
  frissiti Gitbol. A branch alapertelmezetten a services.json adott service
  bejegyzeseben megadott branch/gitBranch/sourceBranch ertek. Ha ott nincs
  branch megadva, a default: develop.

Hasznalat:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 [opciok]

Osszes root pom.xml modul frissitese:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1

Csak egy modul frissitese:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 `
    -ModuleName app3

Egy branch felulirasa minden kivalasztott modulra:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 `
    -ModuleName app3 `
    -Branch feature/my-branch

Branch feluliras modulonkent:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 `
    -ModuleBranch app3=feature/app3,app4=release/app4

Tobb modul:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 `
    -ModuleName app3,app4

Eloszor csak terv kiirasa, Git modositas nelkul:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 `
    -DryRun

Mit csinal:
  1. Beolvassa a root pom.xml <modules> listajat.
  2. Beolvassa a services.json services es moduleSources listajat.
  3. Modulonkent feloldja a branchet:
       -ModuleBranch module=branch
       -Branch branch
       services.json moduleSources vagy service branch/gitBranch/sourceBranch
       develop
  4. Ha a modul konyvtara Git repo, akkor:
       git fetch origin <branch> --prune
       git checkout <branch>
       git pull --ff-only origin <branch>
  5. Ha a modul konyvtara hianyzik, de a service tartalmaz gitUrl/repoUrl/
     repositoryUrl/sourceRepository mezot, akkor clone-olja a branchet.

Fontos:
  - Nem kell minden pom.xml modulnak szerepelnie a services.json services
    listajaban. Ha egy modul nincs benne sem a moduleSources, sem a services
    reszben, akkor a script a modul nevet hasznalja konyvtarkent, es a
    branchet develop-ra allitja.
  - Ha egy ilyen service.json nelkuli modul konyvtara hianyzik, akkor add meg
    a moduleSources reszben a gitUrl/repoUrl erteket, mert clone-ozni csak
    repository URL alapjan lehet.
  - Ha a modulok a root projekt sajat Git repo-jaban vannak, akkor azok nem
    kulon nested Git repok. Ilyenkor modulonkent kulon branch nem lehetseges,
    mert a branch a teljes root repo-ra vonatkozik.
  - A script koszos Git munkafanal alapbol megall. Ezzel vedi a helyi
    valtoztatasokat. Csak akkor hasznald az -AllowDirty kapcsolot, ha erted,
    hogy mit csinalsz.
  - A script nem commitol es nem pushol semmit.

Parameterek:
  -PomFile
      Root Maven pom.xml utvonala. Uresen: .\pom.xml

  -ServicesFile
      Services config JSON. Uresen: .\services.json

  -ModuleName
      Opcionalis modulnev szuro a root pom.xml <modules> nevei alapjan.
      Elfogad vesszovel elvalasztott ertekeket is: app3,app4

  -Branch
      Globalis branch feluliras minden kivalasztott modulra.

  -ModuleBranch
      Modulonkenti branch feluliras module=branch formaban.
      Pelda: -ModuleBranch app3=feature/app3,app4=release/app4

  -AllowDirty
      Nem all meg koszos Git munkafanal. Alapbol nem ajanlott.

  -DryRun
      Csak kiirja, mit csinalna, de nem futtat Git modosito parancsokat.

  --help
      Ezt a reszletes leirast irja ki. A PowerShell elfogadja a --help,
      -Help, -h es -? format is.
'@
}

if ($Help) {
    Show-Help
    exit 0
}

function Resolve-ProjectPath {
    param(
        [string]$Path,
        [string]$DefaultRelativePath
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $ProjectRoot $DefaultRelativePath
    } elseif (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path $ProjectRoot $Path
    }
    return $Path
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

function Get-JsonPropertyValue {
    param(
        [object]$Object,
        [string[]]$Names
    )
    if ($null -eq $Object) {
        return ""
    }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) {
            $value = $Object.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                return [string]$value
            }
        }
    }
    return ""
}

function Get-ServiceNestedValue {
    param(
        [object]$Service,
        [string[]]$Names
    )
    $value = Get-JsonPropertyValue -Object $Service -Names $Names
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value
    }
    if ($null -ne $Service -and $Service.PSObject.Properties.Name -contains "source" -and $null -ne $Service.source) {
        return Get-JsonPropertyValue -Object $Service.source -Names $Names
    }
    return ""
}

function Get-MavenModules {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "POM file does not exist: $Path"
    }
    [xml]$pom = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($pom.NameTable)
    $namespaceManager.AddNamespace("m", "http://maven.apache.org/POM/4.0.0")
    $nodes = @($pom.SelectNodes("/m:project/m:modules/m:module", $namespaceManager))
    return @($nodes | ForEach-Object { ([string]$_.InnerText).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-Services {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Services file does not exist: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ServicesList {
    param([object]$Config)
    if ($null -eq $Config -or $null -eq $Config.services) {
        return @()
    }
    return @($Config.services)
}

function Get-ModuleSources {
    param([object]$Config)
    if ($null -eq $Config -or $null -eq $Config.moduleSources) {
        return @()
    }

    $sources = $Config.moduleSources
    if ($sources -is [array]) {
        return @($sources)
    }

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($property in $sources.PSObject.Properties) {
        $value = $property.Value
        $entry = [ordered]@{
            name = $property.Name
        }
        if ($null -ne $value) {
            foreach ($valueProperty in $value.PSObject.Properties) {
                $entry[$valueProperty.Name] = $valueProperty.Value
            }
        }
        $result.Add([pscustomobject]$entry)
    }
    return $result.ToArray()
}

function Find-ConfigForModule {
    param(
        [string]$Module,
        [object[]]$Entries
    )
    $moduleNormalized = $Module.Replace("/", "\").Trim("\")
    foreach ($entry in $Entries) {
        $serviceName = [string](Get-JsonPropertyValue -Object $entry -Names @("name", "module"))
        $projectDir = [string](Get-JsonPropertyValue -Object $entry -Names @("projectDir", "path"))
        $projectDirNormalized = $projectDir.Replace("/", "\").Trim("\")
        if ($serviceName -eq $Module -or $projectDirNormalized -eq $moduleNormalized -or (Split-Path -Leaf $projectDirNormalized) -eq (Split-Path -Leaf $moduleNormalized)) {
            return $entry
        }
    }
    return $null
}

function Get-OverrideMap {
    param([string[]]$Values)
    $map = @{}
    foreach ($value in @(Normalize-ListValues -Values $Values)) {
        $parts = $value.Split("=", 2)
        if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
            throw "Invalid -ModuleBranch value '$value'. Use module=branch."
        }
        $map[$parts[0].Trim()] = $parts[1].Trim()
    }
    return $map
}

function Get-GitTopLevel {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }
    $output = @(& git -C $Path rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) {
        return ""
    }
    return (Resolve-Path -LiteralPath ([string]$output[0])).Path
}

function Invoke-Git {
    param(
        [string]$RepoPath,
        [string[]]$Arguments
    )
    Write-Output "git -C `"$RepoPath`" $($Arguments -join ' ')"
    if ($DryRun) {
        return
    }
    & git -C $RepoPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed with exit code ${LASTEXITCODE}: git -C `"$RepoPath`" $($Arguments -join ' ')"
    }
}

function Assert-CleanGitWorktree {
    param([string]$RepoPath)
    if ($AllowDirty -or $DryRun) {
        return
    }
    $status = @(& git -C $RepoPath status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read Git status: $RepoPath"
    }
    if ($status.Count -gt 0) {
        throw "Git worktree is dirty, refusing to switch/pull: $RepoPath. Commit/stash changes first, or use -AllowDirty."
    }
}

function Test-LocalBranchExists {
    param(
        [string]$RepoPath,
        [string]$BranchName
    )
    & git -C $RepoPath show-ref --verify --quiet "refs/heads/$BranchName"
    return ($LASTEXITCODE -eq 0)
}

function Test-RemoteBranchExists {
    param(
        [string]$RepoPath,
        [string]$BranchName
    )
    & git -C $RepoPath show-ref --verify --quiet "refs/remotes/origin/$BranchName"
    return ($LASTEXITCODE -eq 0)
}

function Sync-GitRepository {
    param(
        [string]$RepoPath,
        [string]$BranchName
    )
    Assert-CleanGitWorktree -RepoPath $RepoPath
    Invoke-Git -RepoPath $RepoPath -Arguments @("fetch", "origin", $BranchName, "--prune")
    if (-not $DryRun) {
        if (Test-LocalBranchExists -RepoPath $RepoPath -BranchName $BranchName) {
            Invoke-Git -RepoPath $RepoPath -Arguments @("checkout", $BranchName)
        } elseif (Test-RemoteBranchExists -RepoPath $RepoPath -BranchName $BranchName) {
            Invoke-Git -RepoPath $RepoPath -Arguments @("checkout", "-B", $BranchName, "origin/$BranchName")
        } else {
            throw "Branch '$BranchName' was not found locally or as origin/$BranchName in $RepoPath."
        }
    } else {
        Invoke-Git -RepoPath $RepoPath -Arguments @("checkout", $BranchName)
    }
    Invoke-Git -RepoPath $RepoPath -Arguments @("pull", "--ff-only", "origin", $BranchName)
}

function Clone-GitRepository {
    param(
        [string]$RepoUrl,
        [string]$TargetPath,
        [string]$BranchName
    )
    $parent = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $parent)) {
        if ($DryRun) {
            Write-Output "New-Item -ItemType Directory -Force -Path `"$parent`""
        } else {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
    }
    $args = @("clone", "--branch", $BranchName, "--single-branch", $RepoUrl, $TargetPath)
    Write-Output "git $($args -join ' ')"
    if ($DryRun) {
        return
    }
    & git @args
    if ($LASTEXITCODE -ne 0) {
        throw "Git clone failed with exit code ${LASTEXITCODE}: git $($args -join ' ')"
    }
}

$PomFile = Resolve-ProjectPath -Path $PomFile -DefaultRelativePath "pom.xml"
$ServicesFile = Resolve-ProjectPath -Path $ServicesFile -DefaultRelativePath "services.json"

$modules = @(Get-MavenModules -Path $PomFile)
if ($modules.Count -eq 0) {
    throw "No modules found in POM: $PomFile"
}

$requestedModules = @(Normalize-ListValues -Values $ModuleName)
if ($requestedModules.Count -gt 0) {
    $known = @{}
    foreach ($module in $modules) {
        $known[$module] = $true
    }
    foreach ($module in $requestedModules) {
        if (-not $known.ContainsKey($module)) {
            throw "ModuleName '$module' is not listed in root pom.xml."
        }
    }
    $modules = @($modules | Where-Object { $requestedModules -contains $_ })
}

$servicesConfig = Get-Services -Path $ServicesFile
$services = @(Get-ServicesList -Config $servicesConfig)
$moduleSources = @(Get-ModuleSources -Config $servicesConfig)
$moduleBranchOverrides = Get-OverrideMap -Values $ModuleBranch
$projectRootResolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
$repoOperations = [ordered]@{}

foreach ($module in $modules) {
    $moduleSource = Find-ConfigForModule -Module $module -Entries $moduleSources
    $service = Find-ConfigForModule -Module $module -Entries $services
    $branchName = ""
    if ($moduleBranchOverrides.ContainsKey($module)) {
        $branchName = $moduleBranchOverrides[$module]
    } elseif (-not [string]::IsNullOrWhiteSpace($Branch)) {
        $branchName = $Branch
    } else {
        $branchName = Get-ServiceNestedValue -Service $moduleSource -Names @("branch", "gitBranch", "sourceBranch")
        if ([string]::IsNullOrWhiteSpace($branchName)) {
            $branchName = Get-ServiceNestedValue -Service $service -Names @("branch", "gitBranch", "sourceBranch")
        }
    }
    if ([string]::IsNullOrWhiteSpace($branchName)) {
        $branchName = "develop"
    }

    $projectDir = Get-ServiceNestedValue -Service $moduleSource -Names @("projectDir", "path")
    if ([string]::IsNullOrWhiteSpace($projectDir)) {
        $projectDir = Get-ServiceNestedValue -Service $service -Names @("projectDir")
    }
    if ([string]::IsNullOrWhiteSpace($projectDir)) {
        $projectDir = $module
    }
    $modulePath = if ([System.IO.Path]::IsPathRooted($projectDir)) { $projectDir } else { Join-Path $ProjectRoot $projectDir }
    $repoUrl = Get-ServiceNestedValue -Service $moduleSource -Names @("gitUrl", "repoUrl", "repositoryUrl", "sourceRepository")
    if ([string]::IsNullOrWhiteSpace($repoUrl)) {
        $repoUrl = Get-ServiceNestedValue -Service $service -Names @("gitUrl", "repoUrl", "repositoryUrl", "sourceRepository")
    }

    if (-not (Test-Path -LiteralPath $modulePath)) {
        if ([string]::IsNullOrWhiteSpace($repoUrl)) {
            throw "Module path does not exist and no gitUrl/repoUrl/repositoryUrl/sourceRepository was configured for module '$module': $modulePath"
        }
        Write-Output "Module '$module': clone branch '$branchName' from $repoUrl into $modulePath"
        Clone-GitRepository -RepoUrl $repoUrl -TargetPath $modulePath -BranchName $branchName
        continue
    }

    $gitTopLevel = Get-GitTopLevel -Path $modulePath
    if ([string]::IsNullOrWhiteSpace($gitTopLevel)) {
        if ([string]::IsNullOrWhiteSpace($repoUrl)) {
            throw "Module '$module' exists but is not a Git repository and has no gitUrl/repoUrl configured: $modulePath"
        }
        $children = @(Get-ChildItem -LiteralPath $modulePath -Force -ErrorAction SilentlyContinue)
        if ($children.Count -gt 0) {
            throw "Module '$module' exists, is not a Git repository, and is not empty. Refusing to clone into it: $modulePath"
        }
        Write-Output "Module '$module': clone branch '$branchName' from $repoUrl into $modulePath"
        Clone-GitRepository -RepoUrl $repoUrl -TargetPath $modulePath -BranchName $branchName
        continue
    }

    $operationKey = $gitTopLevel.ToLowerInvariant()
    if (-not $repoOperations.Contains($operationKey)) {
        $repoOperations[$operationKey] = [ordered]@{
            repoPath = $gitTopLevel
            branch = $branchName
            modules = [System.Collections.Generic.List[string]]::new()
        }
    } elseif ($repoOperations[$operationKey].branch -ne $branchName) {
        throw "Modules in the same Git repository require different branches. Repo: $gitTopLevel. Existing branch: $($repoOperations[$operationKey].branch), requested branch for '$module': $branchName. This is only possible if modules are separate Git repositories."
    }
    $repoOperations[$operationKey].modules.Add($module)
}

foreach ($operation in $repoOperations.Values) {
    $repoPath = [string]$operation.repoPath
    $branchName = [string]$operation.branch
    $moduleList = ($operation.modules.ToArray() -join ", ")
    if ($repoPath -eq $projectRootResolved) {
        Write-Warning "Module(s) '$moduleList' are in the root Git repository. Updating branch '$branchName' affects the whole project, not only those modules."
    } else {
        Write-Output "Module(s) '$moduleList': sync nested Git repository $repoPath on branch '$branchName'"
    }
    Sync-GitRepository -RepoPath $repoPath -BranchName $branchName
}

Write-Output "Module source sync completed."
