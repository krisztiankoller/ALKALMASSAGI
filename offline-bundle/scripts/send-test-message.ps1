param(
    [string]$Topic = "app1.source",
    [string]$Message = "hello-from-podman",
    [Alias("h", "?")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    @'
send-test-message.ps1

Cel:
  Egyszeru tesztuzenetet kuld a Kafka kontenerbe, alapbol az app1.source
  topicra. Ezzel elindithato az app1 -> app6 pipeline.

Hasznalat:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\send-test-message.ps1 [opciok]

Alap teszt:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\send-test-message.ps1

Egyedi uzenet:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\send-test-message.ps1 `
    -Message "teszt-001"

Egyedi topic:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\send-test-message.ps1 `
    -Topic "app1.source" `
    -Message "teszt-001"

Mit csinal:
  1. podman exec paranccsal belep a kafka kontenerbe.
  2. A kafka-console-producer.sh eszkozzel elkuldi az uzenetet.
  3. Kiirja, melyik topicra mit kuldott.

Parameterek:
  -Topic
      Cel Kafka topic. Alapertelmezett: app1.source

  -Message
      Elkuldo szoveges uzenet. Alapertelmezett: hello-from-podman

  --help
      Ezt a reszletes leirast irja ki es nem kuld uzenetet.

Ellenorzes:
  Kafka UI: http://localhost:40002
  Topic utvonal:
    app1.source -> app2.source -> app3.source -> app4.source -> app5.source -> app6.source -> app7.final

App log pelda:
  podman logs app1
  podman logs app6
'@
}

if ($Help) {
    Show-Help
    exit 0
}

$escapedMessage = $Message.Replace("'", "'\''")
$escapedTopic = $Topic.Replace("'", "'\''")

podman exec kafka /bin/sh -lc "printf '%s\n' '$escapedMessage' | /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic '$escapedTopic'"

Write-Output "Sent message to topic '$Topic': $Message"
