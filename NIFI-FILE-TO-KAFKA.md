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

Ez mindig ahhoz a projekt/bundle konyvtarhoz kepest ertendo, ahonnan a stacket
inditottad. Ha a fejlesztoi repo gyokerebol futott a `deploy-infra-pods.ps1`,
akkor a drop mappa:

```text
.\data\nifi\drop
```

Ha az offline bundle-bol futott a `run-offline.ps1`, akkor a drop mappa:

```text
.\offline-bundle\data\nifi\drop
```

Ha mar eleve az `offline-bundle` konyvtarban allsz, akkor ugyanez roviden:

```text
.\data\nifi\drop
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
- NiFi indulashoz szukseges alap conf fajlok, peldaul:
  `data\nifi\conf\bootstrap.conf`
- NiFi state adatok
- content/flowfile/provenance repository adatok
- NiFi sajat alkalmazas logjai
- drop mappak

Indulaskor a `deploy-infra-pods.ps1` ellenorzi, hogy a NiFi conf mappaban
megvan-e a minimalisan szukseges fajlkeszlet:

```text
bootstrap.conf
nifi.properties
logback.xml
state-management.xml
authorizers.xml
login-identity-providers.xml
```

Ha valamelyik hianyzik, a script a NiFi image-bol csak a hianyzo fajlt potolja.
A mar meglovo `flow.json.gz`, `flow.xml.gz`, `nifi.properties` es repository
adatok nem torlodnek.

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

## Hiba: `FileNotFoundException bootstrap.conf`

Hiba pelda a NiFi logban:

```text
FileNotFoundException /opt/nifi/nifi-current/conf/bootstrap.conf
```

Ok: a host oldali `data\nifi\conf` mappa bind mountkent bemountolodik a
kontener `/opt/nifi/nifi-current/conf` mappajara. Ha ez a host mappa hianyos,
akkor eltakarja az image-ben levo teljes gyari conf mappat, es a NiFi nem talalja
a `bootstrap.conf` fajlt.

Megoldas friss develop/offline bundle eseten:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

Offline bundle alol:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```

Ne torold elsore a teljes `data\nifi` konyvtarat, mert abban vannak a NiFi
flow/state/repository adatok. A friss script adatvesztes nelkul potolja a
hianyzo alap conf fajlokat.

## Fajl bekuldese

Pelda app1 pipeline inditasahoz:

```powershell
New-Item -ItemType Directory -Force -Path .\data\nifi\drop\app1.source
Set-Content -Encoding UTF8 -Path .\data\nifi\drop\app1.source\message-001.json -Value '{"id":"nifi-001","text":"hello from file"}'
```

Offline inditas utan, ha a repo gyokereben allsz es onnan masolsz fajlt, az
offline bundle sajat drop mappajat hasznald:

```powershell
New-Item -ItemType Directory -Force -Path .\offline-bundle\data\nifi\drop\app1.source
Set-Content -Encoding UTF8 -Path .\offline-bundle\data\nifi\drop\app1.source\message-001.json -Value '{"id":"nifi-001","text":"hello from offline file"}'
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
