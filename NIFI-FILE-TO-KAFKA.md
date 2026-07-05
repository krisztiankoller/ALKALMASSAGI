# Apache NiFi file to Kafka

Ez a stack tartalmaz egy Apache NiFi podot is, amivel fajlbol lehet uzeneteket
kuldeni Kafka topicokba.

## URL

```text
http://localhost:40011/nifi
```

Nincs kulon NiFi jelszo. A stack helyi, `localhost` alapu fejlesztoi
hasznalatra van beallitva.

A NiFi explicit HTTP modban indul:

```text
NIFI_WEB_HTTP_HOST=0.0.0.0
NIFI_WEB_HTTP_PORT=8080
NIFI_SECURITY_USER_AUTHORIZER=
NIFI_SECURITY_USER_LOGIN_IDENTITY_PROVIDER=
```

Ezert a webes felulet nem ker felhasznalonevet vagy jelszot.

## Mire valo

NiFi minden beallitott topicra figyel egy projekt alatti drop mappat.
Ha bemasolsz egy fajlt a megfelelo mappaba, NiFi a fajl teljes tartalmat
Kafka uzenetkent elkuldi a beallitott topicra.

Alap utvonal:

```text
data\nifi\drop
```

Alap topic/mappa parok:

```text
data\nifi\drop\app1.source  ->  app1.source
data\nifi\drop\app2.source  ->  app2.source
data\nifi\drop\app3.source  ->  app3.source
data\nifi\drop\app4.source  ->  app4.source
data\nifi\drop\app5.source  ->  app5.source
data\nifi\drop\app6.source  ->  app6.source
data\nifi\drop\app7.final   ->  app7.final
```

Az `app7.final` topicbol jelenleg nem olvas alkalmazas, de Kafka UI-ban
ellenorizheto.

## YAML konfiguracio

A NiFi flow forrasa:

```text
nifi-flows.yaml
```

Pelda:

```yaml
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
```

Mezok:

- `kafkaBootstrapServers`: NiFi kontenerbol lathato Kafka cim. Podmanon belul ez `kafka:9092`.
- `flowGroupName`: NiFi process group neve.
- `defaultPollInterval`: alap gyakorisag, ha egy flow nem ad sajatot.
- `dropRoot`: NiFi konteneren beluli drop root. Normal esetben ne valtoztasd.
- `name`: NiFi flow logikai neve.
- `enabled`: `true` eseten letrejon a flow, `false` eseten kimarad.
- `topic`: cel Kafka topic.
- `folder`: drop almappa neve a `data\nifi\drop` alatt.
- `pollInterval`: milyen gyakran nezze NiFi a mappat.
- `keepSourceFile`: `false` eseten a fajl feldolgozas utan eltunik a drop mappabol.

Fontos: `keepSourceFile: true` eseten ugyanaz a fajl ujra es ujra bekuldodhet,
minden poll ciklusban. Tesztre lehet hasznos, de normal esetben maradjon
`false`.

## Adatmegorzes

A NiFi adatai a projekt alatt maradnak:

```text
data\nifi\conf
data\nifi\drop
data\nifi\logs
data\nifi\database_repository
data\nifi\flowfile_repository
data\nifi\content_repository
data\nifi\provenance_repository
data\nifi\state
```

Ez azt jelenti, hogy Windows/Podman ujrainditas utan megmaradnak:

- NiFi flow definiciok: `data\nifi\conf\flow.json.gz`
- NiFi beallitasok: `data\nifi\conf\nifi.properties`
- NiFi state adatok
- content/flowfile/provenance repository adatok
- NiFi sajat alkalmazas logjai
- drop mappak

Fontos: a `deploy-infra-pods.ps1` alapbol ujrageneralja a `file-to-kafka`
process groupot a `nifi-flows.yaml` alapjan. Ez szandekos, mert ebben a
projektben a YAML a source of truth. Ha a NiFi UI-ban kezzel modositasz flow-t,
es azt nem akarod feluliratni, inditasnal add meg:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost `
  -SkipNifiConfiguration
```

## Fajl bekuldese

Pelda app1 pipeline inditasahoz:

```powershell
New-Item -ItemType Directory -Force -Path .\data\nifi\drop\app1.source
Set-Content -Encoding UTF8 -Path .\data\nifi\drop\app1.source\message-001.json -Value '{"id":"nifi-001","text":"hello from file"}'
```

Mintafajlok is vannak, de ezek nem a drop mappaban vannak, hogy indulaskor ne
kuldessek be veletlenul:

```text
nifi-sample-files\app1.source\message-001.json
nifi-sample-files\app2.source\message-001.json
nifi-sample-files\app3.source\message-001.json
nifi-sample-files\app4.source\message-001.json
nifi-sample-files\app5.source\message-001.json
nifi-sample-files\app6.source\message-001.json
nifi-sample-files\app7.final\message-001.json
```

Pelda mintafajl bekuldese:

```powershell
Copy-Item .\nifi-sample-files\app1.source\message-001.json .\data\nifi\drop\app1.source\
```

Ezutan:

1. NiFi a kovetkezo poll ciklusban elkuldi a fajlt az `app1.source` topicra.
2. `app1` leveszi az uzenetet.
3. Az uzenet vegigmegy az appokon.
4. A vegeredmeny az `app7.final` topicban lathato.

Kafka UI:

```text
http://localhost:40002
```

## Flow ujrageneralasa

Ha modositod a `nifi-flows.yaml` fajlt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-nifi-file-to-kafka.ps1
```

A script alapbol torli es ujrageneralja a `flowGroupName` szerinti NiFi process
groupot. Ha csak azt akarod, hogy meglovo flow eseten ne nyuljon hozza:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-nifi-file-to-kafka.ps1 -KeepExistingFlow
```

## Uj topic hozzaadasa

1. Hozd letre vagy allitsd be a topicot a Kafka oldalon.
2. Add hozza a `nifi-flows.yaml` `flows` listajahoz:

```yaml
    - name: file-to-my-topic
      enabled: true
      topic: my.topic
      folder: my.topic
      pollInterval: 30 sec
      keepSourceFile: false
```

3. Futtasd ujra:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-nifi-file-to-kafka.ps1
```

4. Masolj fajlt ide:

```text
data\nifi\drop\my.topic
```

## Ujragepen/offline hasznalat

Az offline bundle tartalmazza:

- NiFi image-et
- `nifi-flows.yaml` fajlt
- NiFi konfiguracios scriptet
- ezt a dokumentaciot

Masik gepen az offline inditas utan ugyanigy mukodik:

```powershell
cd .\offline-bundle
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

Utana a drop mappak az offline bundle alatt jonnek letre:

```text
data\nifi\drop
```

## Port atallitasa

Alap NiFi host port:

```text
40011
```

Online/local deploy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost `
  -NifiHostPort 41011
```

Offline inditas:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost `
  -NifiHostPort 41011
```

Ekkor a NiFi UI:

```text
http://localhost:41011/nifi
```
