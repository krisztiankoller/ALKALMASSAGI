param(
    [string]$ConfigFile = "",
    [string]$NifiBaseUrl = "http://localhost:40011",
    [int]$WaitTimeoutSeconds = 240,
    [switch]$KeepExistingFlow,
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Show-Help {
    @'
configure-nifi-file-to-kafka.ps1

Cel:
  Apache NiFi flow automatikus letrehozasa YAML fajlbol.
  A flow minden engedelyezett bejegyzeshez ezt epiti:

    GetFile -> PublishKafka

  Igy egy Windows/projekt alatti drop folderbe masolt fajl tartalma bekerul
  a megadott Kafka topicba.

Hasznalat:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-nifi-file-to-kafka.ps1

Egyedi YAML:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-nifi-file-to-kafka.ps1 `
    -ConfigFile .\nifi-flows.yaml

Egyedi NiFi URL:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-nifi-file-to-kafka.ps1 `
    -NifiBaseUrl http://localhost:40011

Mit csinal:
  1. Beolvassa a nifi-flows.yaml fajlt.
  2. Megvarja, amig NiFi REST API elerheto.
  3. Letrehozza a host oldali data\nifi\drop\<folder> konyvtarakat.
  4. Letrehozza vagy ujra letrehozza a megadott NiFi process groupot.
  5. Minden engedelyezett flow-hoz letrehoz egy GetFile es PublishKafka processort.
  6. Osszekoti a processorokat es elinditja oket.

YAML formatum:
  nifi:
    kafkaBootstrapServers: kafka:9092
    flowGroupName: file-to-kafka
    defaultPollInterval: 10 sec
    dropRoot: /data/nifi/drop
    flows:
      - name: file-to-app1-source
        enabled: true
        topic: app1.source
        folder: app1.source
        pollInterval: 10 sec
        keepSourceFile: false

Parameterek:
  -ConfigFile
      YAML config fajl. Uresen: .\nifi-flows.yaml

  -NifiBaseUrl
      NiFi web/API base URL. Alapertelmezett: http://localhost:40011
      Megadhato /nifi-api vegzodessel vagy anelkul.

  -WaitTimeoutSeconds
      Ennyi masodpercig var NiFi indulasa utan. Alapertelmezett: 240

  -KeepExistingFlow
      Ha mar van ugyanilyen nevu NiFi process group, nem torli es nem epiti ujra.
      Alapertelmezetten a script ujrageneralja a YAML-bol a flow-t.

  --help
      Ezt a reszletes leirast irja ki es nem modosit NiFi-t.

Fajl bekuldes:
  Masolj egy fajlt ide:

    .\data\nifi\drop\app1.source

  A fajl tartalma a kovetkezo poll ciklusban bekerul az app1.source topicba.
  keepSourceFile: false mellett NiFi feldolgozas utan eltavolitja a drop mappabol.

Megjegyzes:
  Ez a script egyszeru, szandekosan korlatozott YAML formatumot kezel.
  Ne hasznalj inline kommentet az ertekek utan, es a flows lista legyen a
  fenti szerkezetu.
'@
}

if ($Help) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    $ConfigFile = Join-Path $ProjectRoot "nifi-flows.yaml"
} elseif (-not [System.IO.Path]::IsPathRooted($ConfigFile)) {
    $ConfigFile = Join-Path $ProjectRoot $ConfigFile
}

if (-not (Test-Path -LiteralPath $ConfigFile)) {
    throw "NiFi YAML config does not exist: $ConfigFile"
}

$ClientId = [guid]::NewGuid().ToString()

function Convert-SimpleYamlValue {
    param([string]$Value)

    $text = $Value.Trim()
    if (($text.StartsWith("'") -and $text.EndsWith("'")) -or ($text.StartsWith('"') -and $text.EndsWith('"'))) {
        $text = $text.Substring(1, $text.Length - 2)
    }

    if ($text -ieq "true") {
        return $true
    }
    if ($text -ieq "false") {
        return $false
    }

    return $text
}

function Read-NifiFlowConfig {
    param([string]$Path)

    $config = [ordered]@{
        kafkaBootstrapServers = "kafka:9092"
        flowGroupName = "file-to-kafka"
        defaultPollInterval = "10 sec"
        dropRoot = "/data/nifi/drop"
        flows = [System.Collections.Generic.List[object]]::new()
    }

    $inFlows = $false
    $currentFlow = $null

    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
            continue
        }
        if ($trimmed -eq "nifi:") {
            continue
        }
        if ($trimmed -eq "flows:") {
            $inFlows = $true
            continue
        }

        if ($inFlows -and $trimmed.StartsWith("- ")) {
            $currentFlow = [ordered]@{}
            $config.flows.Add($currentFlow) | Out-Null
            $remainder = $trimmed.Substring(2).Trim()
            if ($remainder -match "^([A-Za-z0-9_-]+):\s*(.*)$") {
                $currentFlow[$Matches[1]] = Convert-SimpleYamlValue $Matches[2]
            }
            continue
        }

        if ($trimmed -match "^([A-Za-z0-9_-]+):\s*(.*)$") {
            $key = $Matches[1]
            $value = Convert-SimpleYamlValue $Matches[2]
            if ($inFlows -and $null -ne $currentFlow) {
                $currentFlow[$key] = $value
            } else {
                $config[$key] = $value
            }
        }
    }

    return [pscustomobject]$config
}

function Get-NifiApiBaseUrl {
    param([string]$BaseUrl)

    $clean = $BaseUrl.TrimEnd("/")
    if ($clean -match "/nifi-api$") {
        return $clean
    }
    return "$clean/nifi-api"
}

$ApiBaseUrl = Get-NifiApiBaseUrl $NifiBaseUrl

function Invoke-NifiApi {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null
    )

    $uri = "$ApiBaseUrl/$($Path.TrimStart('/'))"
    $parameters = @{
        Method = $Method
        Uri = $uri
        TimeoutSec = 60
    }
    if ($null -ne $Body) {
        $parameters.ContentType = "application/json"
        $parameters.Body = ($Body | ConvertTo-Json -Depth 40)
    }

    return Invoke-RestMethod @parameters
}

function Wait-Nifi {
    $deadline = (Get-Date).AddSeconds($WaitTimeoutSeconds)
    do {
        try {
            Invoke-NifiApi -Method Get -Path "flow/about" | Out-Null
            return
        }
        catch {
            Start-Sleep -Seconds 5
        }
    } while ((Get-Date) -lt $deadline)

    throw "NiFi API did not become ready within $WaitTimeoutSeconds seconds: $ApiBaseUrl"
}

function Get-DescriptorNames {
    param([object]$Descriptors)

    if ($null -eq $Descriptors) {
        return @()
    }
    if ($Descriptors -is [System.Collections.IDictionary]) {
        return @($Descriptors.Keys)
    }
    return @($Descriptors.PSObject.Properties.Name)
}

function Find-PropertyName {
    param(
        [object]$Descriptors,
        [string[]]$Candidates,
        [string]$Purpose
    )

    $names = @(Get-DescriptorNames $Descriptors)
    foreach ($candidate in $Candidates) {
        $match = $names | Where-Object { $_ -ieq $candidate } | Select-Object -First 1
        if ($match) {
            return $match
        }
    }

    throw "Could not find NiFi processor property for $Purpose. Tried: $($Candidates -join ', '). Available: $($names -join ', ')"
}

function Set-ProcessorProperties {
    param(
        [object]$Processor,
        [hashtable]$Properties,
        [string]$SchedulingPeriod,
        [string[]]$AutoTerminatedRelationships = @()
    )

    $mergedProperties = [ordered]@{}
    foreach ($property in $Processor.component.config.properties.PSObject.Properties) {
        $mergedProperties[$property.Name] = $property.Value
    }
    foreach ($key in $Properties.Keys) {
        $mergedProperties[$key] = $Properties[$key]
    }

    $config = [ordered]@{
        schedulingStrategy = "TIMER_DRIVEN"
        schedulingPeriod = $SchedulingPeriod
        executionNode = "ALL"
        penaltyDuration = "30 sec"
        yieldDuration = "1 sec"
        bulletinLevel = "WARN"
        properties = $mergedProperties
    }
    if ($AutoTerminatedRelationships.Count -gt 0) {
        $config.autoTerminatedRelationships = [string[]]$AutoTerminatedRelationships
    }

    $body = [ordered]@{
        revision = [ordered]@{
            clientId = $ClientId
            version = $Processor.revision.version
        }
        component = [ordered]@{
            id = $Processor.id
            config = $config
        }
    }

    return Invoke-NifiApi -Method Put -Path "processors/$($Processor.id)" -Body $body
}

function Set-ProcessorRunState {
    param(
        [object]$Processor,
        [string]$State
    )

    $body = [ordered]@{
        revision = [ordered]@{
            clientId = $ClientId
            version = $Processor.revision.version
        }
        state = $State
    }
    return Invoke-NifiApi -Method Put -Path "processors/$($Processor.id)/run-status" -Body $body
}

function Resolve-ProcessorType {
    param([string[]]$Candidates)

    $types = (Invoke-NifiApi -Method Get -Path "flow/processor-types").processorTypes
    foreach ($candidate in $Candidates) {
        $match = $types | Where-Object { $_.type -eq $candidate } | Select-Object -First 1
        if ($match) {
            return $match
        }
    }

    throw "None of the required NiFi processor types are available: $($Candidates -join ', ')"
}

function New-Processor {
    param(
        [string]$GroupId,
        [object]$ProcessorType,
        [string]$Name,
        [int]$X,
        [int]$Y
    )

    $component = [ordered]@{
        type = $ProcessorType.type
        name = $Name
        position = [ordered]@{
            x = $X
            y = $Y
        }
    }
    if ($ProcessorType.bundle) {
        $component.bundle = $ProcessorType.bundle
    }

    $body = [ordered]@{
        revision = [ordered]@{
            clientId = $ClientId
            version = 0
        }
        component = $component
    }

    return Invoke-NifiApi -Method Post -Path "process-groups/$GroupId/processors" -Body $body
}

function Remove-ProcessGroupIfExists {
    param(
        [string]$ParentGroupId,
        [string]$GroupName
    )

    $rootFlow = Invoke-NifiApi -Method Get -Path "flow/process-groups/$ParentGroupId"
    $existing = @($rootFlow.processGroupFlow.flow.processGroups) |
        Where-Object { $_.component.name -eq $GroupName } |
        Select-Object -First 1

    if (-not $existing) {
        return
    }

    if ($KeepExistingFlow) {
        Write-Output "NiFi process group already exists and KeepExistingFlow is set: $GroupName"
        exit 0
    }

    $groupFlow = Invoke-NifiApi -Method Get -Path "flow/process-groups/$($existing.id)"
    foreach ($processor in @($groupFlow.processGroupFlow.flow.processors)) {
        if ($processor.status.runStatus -eq "Running") {
            $stopped = Set-ProcessorRunState -Processor $processor -State "STOPPED"
            Start-Sleep -Seconds 1
            $processor.revision.version = $stopped.revision.version
        }
    }

    $entity = Invoke-NifiApi -Method Get -Path "process-groups/$($existing.id)"
    Invoke-NifiApi -Method Delete -Path "process-groups/$($existing.id)?version=$($entity.revision.version)&clientId=$ClientId" | Out-Null
}

function New-ProcessGroup {
    param(
        [string]$ParentGroupId,
        [string]$Name
    )

    $body = [ordered]@{
        revision = [ordered]@{
            clientId = $ClientId
            version = 0
        }
        component = [ordered]@{
            name = $Name
            position = [ordered]@{
                x = 120
                y = 120
            }
        }
    }

    return Invoke-NifiApi -Method Post -Path "process-groups/$ParentGroupId/process-groups" -Body $body
}

function New-Connection {
    param(
        [string]$GroupId,
        [object]$SourceProcessor,
        [object]$DestinationProcessor
    )

    $body = [ordered]@{
        revision = [ordered]@{
            clientId = $ClientId
            version = 0
        }
        component = [ordered]@{
            source = [ordered]@{
                id = $SourceProcessor.id
                groupId = $GroupId
                type = "PROCESSOR"
            }
            destination = [ordered]@{
                id = $DestinationProcessor.id
                groupId = $GroupId
                type = "PROCESSOR"
            }
            selectedRelationships = [string[]]@("success")
            flowFileExpiration = "0 sec"
            backPressureObjectThreshold = 10000
            backPressureDataSizeThreshold = "1 GB"
        }
    }

    return Invoke-NifiApi -Method Post -Path "process-groups/$GroupId/connections" -Body $body
}

function Ensure-HostDropFolder {
    param([string]$Folder)

    if ([string]::IsNullOrWhiteSpace($Folder)) {
        return
    }
    $safeFolder = $Folder.Trim().Trim("/", "\")
    $path = Join-Path (Join-Path $ProjectRoot "data\nifi\drop") $safeFolder
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

$config = Read-NifiFlowConfig -Path $ConfigFile
$enabledFlows = @($config.flows | Where-Object { $_.enabled -ne $false })
if ($enabledFlows.Count -eq 0) {
    throw "No enabled NiFi file-to-Kafka flows found in: $ConfigFile"
}

Wait-Nifi

$root = Invoke-NifiApi -Method Get -Path "flow/process-groups/root"
$rootGroupId = $root.processGroupFlow.id

Remove-ProcessGroupIfExists -ParentGroupId $rootGroupId -GroupName $config.flowGroupName
$group = New-ProcessGroup -ParentGroupId $rootGroupId -Name $config.flowGroupName
$groupId = $group.id

$getFileType = Resolve-ProcessorType -Candidates @(
    "org.apache.nifi.processors.standard.GetFile"
)
$publishKafkaType = Resolve-ProcessorType -Candidates @(
    "org.apache.nifi.processors.kafka.pubsub.PublishKafka_2_6",
    "org.apache.nifi.kafka.processors.PublishKafka",
    "org.apache.nifi.processors.kafka.pubsub.PublishKafka"
)

$index = 0
foreach ($flow in $enabledFlows) {
    $name = [string]$flow.name
    $topic = [string]$flow.topic
    $folder = [string]$flow.folder
    $pollInterval = if ($flow.pollInterval) { [string]$flow.pollInterval } else { [string]$config.defaultPollInterval }
    $keepSourceFile = if ($flow.keepSourceFile -eq $true) { "true" } else { "false" }

    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($topic) -or [string]::IsNullOrWhiteSpace($folder)) {
        throw "Every NiFi flow must have name, topic and folder. Invalid flow in: $ConfigFile"
    }

    Ensure-HostDropFolder -Folder $folder
    $inputDirectory = "$($config.dropRoot.TrimEnd('/'))/$($folder.Trim('/'))"
    $y = 120 + ($index * 260)

    $getFile = New-Processor -GroupId $groupId -ProcessorType $getFileType -Name "GetFile $topic" -X 120 -Y $y
    $publishKafka = New-Processor -GroupId $groupId -ProcessorType $publishKafkaType -Name "PublishKafka $topic" -X 560 -Y $y

    $getFileDescriptors = $getFile.component.config.descriptors
    $inputDirectoryProperty = Find-PropertyName -Descriptors $getFileDescriptors -Candidates @("Input Directory", "input-directory") -Purpose "GetFile input directory"
    $keepSourceFileProperty = Find-PropertyName -Descriptors $getFileDescriptors -Candidates @("Keep Source File", "keep-source-file") -Purpose "GetFile keep source file"
    $fileFilterProperty = Find-PropertyName -Descriptors $getFileDescriptors -Candidates @("File Filter", "file-filter") -Purpose "GetFile file filter"

    $getFileProps = @{
        $inputDirectoryProperty = $inputDirectory
        $keepSourceFileProperty = $keepSourceFile
        $fileFilterProperty = "[^\.].*"
    }
    $getFile = Set-ProcessorProperties -Processor $getFile -Properties $getFileProps -SchedulingPeriod $pollInterval

    $publishDescriptors = $publishKafka.component.config.descriptors
    $bootstrapProperty = Find-PropertyName -Descriptors $publishDescriptors -Candidates @("bootstrap.servers", "Kafka Brokers", "kafka-bootstrap-servers") -Purpose "Kafka bootstrap servers"
    $topicProperty = Find-PropertyName -Descriptors $publishDescriptors -Candidates @("topic", "Topic Name", "topic-name") -Purpose "Kafka topic"

    $publishProps = @{
        $bootstrapProperty = [string]$config.kafkaBootstrapServers
        $topicProperty = $topic
    }
    $acksProperty = $null
    try {
        $acksProperty = Find-PropertyName -Descriptors $publishDescriptors -Candidates @("acks", "Acknowledgment Wait Time") -Purpose "Kafka acknowledgments"
    }
    catch {
        $acksProperty = $null
    }
    if ($acksProperty -eq "acks") {
        $publishProps[$acksProperty] = "all"
    }

    $publishKafka = Set-ProcessorProperties -Processor $publishKafka -Properties $publishProps -SchedulingPeriod $pollInterval -AutoTerminatedRelationships @("success", "failure")

    New-Connection -GroupId $groupId -SourceProcessor $getFile -DestinationProcessor $publishKafka | Out-Null

    $publishKafka = Set-ProcessorRunState -Processor $publishKafka -State "RUNNING"
    $getFile = Set-ProcessorRunState -Processor $getFile -State "RUNNING"

    Write-Output "Configured NiFi flow: $name -> $topic from $inputDirectory every $pollInterval"
    $index++
}

Write-Output "NiFi file-to-Kafka flow is ready: $($config.flowGroupName)"
