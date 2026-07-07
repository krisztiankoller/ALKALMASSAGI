# Testing checklist

Ez a lista azt mutatja, hogyan lehet vegigellenorizni a teljes lokalis/offline
Podman stack-et. A parancsokat a projekt gyokerkonyvtarabol futtasd, kiveve ahol
kulon szerepel az `offline-bundle` konyvtar.

Teljes regresszios korben ezeket futtasd vegig sorban:

1. Script syntax es `--help` ellenorzes.
2. Java/Maven build Podman alatt.
3. Infra deploy: MSSQL, Kafka, Kafka UI, DbGate, Dozzle, NiFi.
4. App image build es app pod inditas.
5. Health, web UI, Kafka topic, direkt Kafka pipeline, NiFi file-to-Kafka,
   MSSQL audit es log export tesztek.
6. `applicationYaml` alternativ fajlnev teszt.
7. Offline image split/join teszt.
8. Offline bundle export.
9. Offline bundle `run-offline.ps1` inditas es offline pipeline ellenorzes.

A `configure-lan-firewall.ps1` nem resze a localhost regresszios kornek, mert
Windows tuzfalat modosit es jellemzoen admin jog kell hozza. Akkor futtasd, ha
nem csak localhostrol, hanem mas geprol is el akarod erni a portokat.

## 1. Script syntax es help ellenorzes

```powershell
$scripts = Get-ChildItem -LiteralPath .\scripts -Filter *.ps1 -Recurse
foreach ($script in $scripts) {
  $errors = $null
  [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $script.FullName -Raw), [ref]$errors) | Out-Null
  if ($errors -and $errors.Count -gt 0) { throw "Syntax error in $($script.FullName)" }
}

Get-ChildItem -LiteralPath .\scripts -Filter *.ps1 |
  ForEach-Object {
    powershell -NoProfile -ExecutionPolicy Bypass -File $_.FullName --help | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "--help failed: $($_.Name)" }
  }
```

## 2. Teljes Java build Podman alatt

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -MavenBuildRetries 1
```

Ez host Java es Maven nelkul fut. Ha nincs Java tesztforras, a Maven `No tests to
run` uzenetet ir, de a Surefire fazis akkor is lefut.

## 3. Infra ujrainditas

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

Ellenorizd a kimenetben:

```text
Running MSSQL schema script for app1_audit: sql/app1-audit.sql
...
Running MSSQL schema script for app6_audit: sql/app6-audit.sql
Ensuring Kafka topic: app1.source
...
Ensuring Kafka topic: app7.final
NiFi file-to-Kafka flow is ready: file-to-kafka
```

## 4. App image build es app pod inditas

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json `
  -SqlPassword "Alkalmassagi_2026!"
```

## 5. Health es web UI ellenorzes

```powershell
podman ps --pod

foreach ($port in 40005..40010) {
  Invoke-RestMethod "http://localhost:$port/actuator/health"
}

Invoke-WebRequest http://localhost:40002 -UseBasicParsing
Invoke-WebRequest http://localhost:40003 -UseBasicParsing
Invoke-WebRequest http://localhost:40004 -UseBasicParsing
Invoke-WebRequest http://localhost:40011/nifi/ -UseBasicParsing
```

Elvart eredmeny:

```text
app1 ... app6: status UP
Kafka UI: HTTP 200
DbGate SQL admin: HTTP 200
Dozzle log viewer: HTTP 200
NiFi: HTTP 200
```

## 6. Alternativ applicationYaml fajlnev teszt

Ez azt ellenorzi, hogy a `services.json` service szintu `applicationYaml`
mezoje mukodik-e, peldaul `application-local.yaml` fajlnevvel. A teszt ideiglenes
fajlokat hoz letre, majd visszaallitja az eredeti allapotot.

```powershell
$localYaml = ".\app1\src\main\resources\application-local.yaml"
$tempServices = ".\work\test-services-application-local.json"

New-Item -ItemType Directory -Force -Path (Split-Path $tempServices) | Out-Null
Copy-Item -LiteralPath ".\app1\src\main\resources\application.yaml" -Destination $localYaml -Force
Add-Content -LiteralPath $localYaml -Encoding UTF8 -Value "`n# applicationYaml alternate file test marker"

$config = Get-Content -Raw -LiteralPath ".\services.json" | ConvertFrom-Json
foreach ($service in $config.services) {
  if ($service.name -eq "app1") {
    $service.applicationYaml = "application-local.yaml"
  }
}
$config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempServices -Encoding UTF8

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile $tempServices `
  -SqlPassword "Alkalmassagi_2026!" `
  -SkipBuild

podman exec app1 sh -c "grep -q 'applicationYaml alternate file test marker' /app/config/application.yaml"
if ($LASTEXITCODE -ne 0) {
  throw "applicationYaml alternate file was not mounted into app1"
}
```

Visszaallitas:

```powershell
Remove-Item -LiteralPath $localYaml -Force
Remove-Item -LiteralPath $tempServices -Force

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json `
  -SqlPassword "Alkalmassagi_2026!" `
  -SkipBuild
```

## 7. Kafka topic ellenorzes

```powershell
podman run --rm --network devnet apache/kafka:3.9.0 `
  /opt/kafka/bin/kafka-topics.sh `
  --bootstrap-server kafka:9092 `
  --list
```

Elvart topicok:

```text
app1.source
app2.source
app3.source
app4.source
app5.source
app6.source
app7.final
```

## 8. Direkt Kafka pipeline teszt

```powershell
$id = "direct-test-$(Get-Date -Format yyyyMMddHHmmss)"

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\send-test-message.ps1 `
  -Message "{`"id`":`"$id`",`"text`":`"direct pipeline test`"}"

Start-Sleep -Seconds 8

$messages = podman run --rm --network devnet apache/kafka:3.9.0 `
  /opt/kafka/bin/kafka-console-consumer.sh `
  --bootstrap-server kafka:9092 `
  --topic app7.final `
  --from-beginning `
  --timeout-ms 10000 `
  --max-messages 200 2>&1

if (($messages -join "`n") -notmatch [regex]::Escape($id)) {
  throw "Message did not reach app7.final: $id"
}
```

## 9. NiFi file-to-Kafka teszt

```powershell
$id = "nifi-test-$(Get-Date -Format yyyyMMddHHmmss)"
$drop = Join-Path $PWD "data\nifi\drop\app1.source"
New-Item -ItemType Directory -Force -Path $drop | Out-Null

$file = Join-Path $drop "$id.json"
Set-Content -LiteralPath $file -Encoding UTF8 `
  -Value "{`"id`":`"$id`",`"text`":`"nifi file pipeline test`"}"

Start-Sleep -Seconds 20

$messages = podman run --rm --network devnet apache/kafka:3.9.0 `
  /opt/kafka/bin/kafka-console-consumer.sh `
  --bootstrap-server kafka:9092 `
  --topic app7.final `
  --from-beginning `
  --timeout-ms 10000 `
  --max-messages 200 2>&1

if (($messages -join "`n") -notmatch [regex]::Escape($id)) {
  throw "NiFi message did not reach app7.final: $id"
}

if (Test-Path -LiteralPath $file) {
  throw "NiFi did not consume the source file: $file"
}
```

Ha kozvetlenul elotte az `offline-bundle\scripts\run-offline.ps1` inditotta a
stacket, akkor a NiFi aktiv drop mountja az offline bundle alatt van. Ilyenkor,
ha a repo gyokereben allsz, ezt hasznald:

```powershell
$drop = Join-Path $PWD "offline-bundle\data\nifi\drop\app1.source"
```

## 10. MSSQL audit ellenorzes

```powershell
$sql = "SET NOCOUNT ON;`nSELECT DB_NAME() AS database_name, COUNT(*) AS audit_rows, MAX(event_time) AS last_event_time FROM dbo.audit_events;`n"
$encodedSql = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sql))
$template = @'
set -e
if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then sqlcmd=/opt/mssql-tools18/bin/sqlcmd; elif [ -x /opt/mssql-tools/bin/sqlcmd ]; then sqlcmd=/opt/mssql-tools/bin/sqlcmd; else sqlcmd=$(command -v sqlcmd); fi
printf '%s' '__SQL__' | base64 -d > /tmp/audit-check.sql
"$sqlcmd" -S localhost -U sa -P "$SQLCMDPASSWORD" -C -b -d __DB__ -i /tmp/audit-check.sql
'@

foreach ($db in "app1_audit","app2_audit","app3_audit","app4_audit","app5_audit","app6_audit") {
  $bash = $template.Replace("__DB__", $db).Replace("__SQL__", $encodedSql)
  podman exec -e "SQLCMDPASSWORD=Alkalmassagi_2026!" mssql bash -lc $bash
}
```

Az `audit_rows` erteknek nonie kell a direkt es a NiFi teszt utan.

## 11. Log export teszt

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-container-logs.ps1

Get-ChildItem -LiteralPath .\data\logs -Directory |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
```

Az eredmeny egy `data\logs\manual-YYYYMMDD-HHMMSS` konyvtar, benne app, Kafka,
MSSQL, NiFi, DbGate, Dozzle es build log fajlokkal.

## 12. Offline image split/join teszt

Ez a nagy `podman-images.tar` darabolasat es visszaallitasat ellenorzi. Akkor
hasznos, ha a nagy tar fajlt kulon branchre vagy darabolva akarod atvinni.
Ket modon is mukodnie kell:

- a fejlesztoi repo gyokerebol, ahol a teljes offline bundle az
  `offline-bundle` alkonyvtarban van;
- az atmasolt `offline-bundle` konyvtarbol, ahol mar maga a bundle a gyoker.

Fejlesztoi repo gyokerbol:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\split-offline-image.ps1 -Overwrite

$parts = Get-ChildItem -LiteralPath .\offline-bundle\images\split `
  -Filter "podman-images.tar.part*" -File |
  Where-Object { $_.Name -match '^podman-images[.]tar[.]part\d+$' }

if ($parts.Count -eq 0) {
  throw "No split image parts were created"
}

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\join-offline-image.ps1 -Overwrite

if (-not (Test-Path -LiteralPath .\offline-bundle\images\podman-images.tar)) {
  throw "Joined podman-images.tar was not restored"
}
```

Mar atmasolt offline bundle konyvtarbol:

```powershell
cd .\offline-bundle

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\split-offline-image.ps1 -Overwrite

$parts = Get-ChildItem -LiteralPath .\images\split `
  -Filter "podman-images.tar.part*" -File |
  Where-Object { $_.Name -match '^podman-images[.]tar[.]part\d+$' }

if ($parts.Count -eq 0) {
  throw "No split image parts were created"
}

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\join-offline-image.ps1 -Overwrite

if (-not (Test-Path -LiteralPath .\images\podman-images.tar)) {
  throw "Joined podman-images.tar was not restored"
}

cd ..
```

A join script csak a valodi numerikus part fajlokat olvassa
(`podman-images.tar.part001`, `podman-images.tar.part002`, ...), a manifestet
nem keveri bele az osszefuzesbe.

## 13. Offline bundle export es offline inditas

Ezt a lepest akkor is erdemes lefuttatni, ha a lokalis stack mar mukodik, mert
ez bizonyitja, hogy a masik gepre masolhato csomag tenyleg tartalmazza az
image-eket, SQL scripteket, runtime YAML fajlokat, `services.sample.json`
peldat es a dokumentaciot.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-offline-bundle.ps1 `
  -ServicesFile .\services.json `
  -SkipTests

Test-Path .\offline-bundle\images\podman-images.tar
Test-Path .\offline-bundle\sql\app1-audit.sql
Test-Path .\offline-bundle\sql\app6-audit.sql
Test-Path .\offline-bundle\services.sample.json

cd .\offline-bundle

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

Offline inditas utan futtasd ujra az app health es web UI ellenorzest, majd:

```powershell
cd ..

$id = "offline-send-test-$(Get-Date -Format yyyyMMddHHmmss)"
powershell -NoProfile -ExecutionPolicy Bypass -File .\offline-bundle\scripts\send-test-message.ps1 `
  -Message "{`"id`":`"$id`",`"text`":`"offline bundle send test`"}"
```

Ezutan a `app7.final` topicban meg kell jelennie az uzenetnek.
