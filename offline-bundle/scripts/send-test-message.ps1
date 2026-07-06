param(
    [string]$Topic = "app1.source",
    [string]$Message = "hello-from-podman",
    [string]$KafkaCliImage = "apache/kafka:3.9.0",
    [string]$NetworkName = "devnet",
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
  1. Elindit egy rovid eletu Kafka CLI kontenert a devnet networkon.
  2. A kafka-console-producer.sh eszkozzel elkuldi az uzenetet.
  3. Kiirja, melyik topicra mit kuldott.

Parameterek:
  -Topic
      Cel Kafka topic. Alapertelmezett: app1.source

  -Message
      Elkuldo szoveges uzenet. Alapertelmezett: hello-from-podman

  -KafkaCliImage
      Kafka CLI eszkozoket tartalmazo image. Alapertelmezett: apache/kafka:3.9.0
      Erre azert van szukseg, mert az apache/kafka-native broker image-ben
      nincsenek benne a kafka-console-* parancsok.

  -NetworkName
      Podman network neve, amelyen a kafka broker elerheto. Alapertelmezett: devnet

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
$escapedBootstrap = "kafka:9092"

podman run --rm --network $NetworkName $KafkaCliImage /bin/sh -lc "printf '%s\n' '$escapedMessage' | /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server '$escapedBootstrap' --topic '$escapedTopic'"
if ($LASTEXITCODE -ne 0) {
    throw "Could not send Kafka test message with image '$KafkaCliImage'. Make sure the image is available offline or can be pulled."
}

Write-Output "Sent message to topic '$Topic': $Message"
