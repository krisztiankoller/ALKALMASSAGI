# Browser Pages

Ez a projekt helyi bongeszoben hasznos oldalainak rovid listaja.

## Fo oldalak

- [DbGate - SQL admin](http://localhost:40003)
  - Jelszo nelkul nyilik.
  - Bal oldali `Connections` listaban ezek a fontos kapcsolatok vannak:
    `Local MSSQL`, `app1_audit`, `app2_audit`, `app3_audit`, `app4_audit`, `app5_audit`, `app6_audit`.
  - Az app adatbazisokban az `audit_events` tabla mutatja, mit vett at es mit kuldott tovabb az adott app.
  - Windowsos SQL kliensbol ugyanezt az MSSQL szervert igy ered el: `localhost,40000`, user `sa`, password `Alkalmassagi_2026!`, `Trust server certificate` bekapcsolva.

- [Kafka UI - dashboard](http://localhost:40002)
  - Jelszo nelkul nyilik.
  - A `local` Kafka clustert mutatja.

- [Dozzle - log viewer](http://localhost:40004)
  - Jelszo nelkul nyilik.
  - Egy helyen mutatja az appok, SQL Server, Kafka es admin kontenerek logjait.
  - Java build loghoz keresd ezt: `java-build-log-viewer`.

- [Apache NiFi - file to Kafka](http://localhost:40011/nifi)
  - Jelszo nelkul nyilik.
  - Fajlokat tud Kafka topicokra kuldeni a `nifi-flows.yaml` alapjan.

## Kafka UI hasznos aloldalak

- [Kafka topics](http://localhost:40002/ui/clusters/local/all-topics)
  - Itt erdemes keresni ezeket:
    `app1.source`, `app2.source`, `app3.source`, `app4.source`, `app5.source`, `app6.source`, `app7.final`.

- [Kafka consumer groups](http://localhost:40002/ui/clusters/local/consumer-groups)
  - Itt latszanak az app consumer groupok:
    `app1-group`, `app2-group`, `app3-group`, `app4-group`, `app5-group`, `app6-group`.

- [Kafka brokers](http://localhost:40002/ui/clusters/local/brokers)
  - Broker allapot, Kafka verzio es alap cluster informaciok.

## Spring Boot app health oldalak

- [app1 health](http://localhost:40005/actuator/health)
- [app2 health](http://localhost:40006/actuator/health)
- [app3 health](http://localhost:40007/actuator/health)
- [app4 health](http://localhost:40008/actuator/health)
- [app5 health](http://localhost:40009/actuator/health)
- [app6 health](http://localhost:40010/actuator/health)

Mindegyiknel az a jo, ha ezt latod: `"status":"UP"`.

## Uzenet utvonala

Az alkalmazasok Kafka lancban dolgoznak:

`app1.source -> app2.source -> app3.source -> app4.source -> app5.source -> app6.source -> app7.final`

Az `app7.final` a vegso topic, ebbol mar nem olvas tovabb alkalmazas.

## Helyi bongeszos nyitolap

Nyisd meg ezt a fajlt bongeszoben, ha kattinthato linkgyujtemenyt szeretnel:

`.\browser-start.html`

## Kapcsolodo dokumentaciok

- `start.md` - reszletes inditas, offline masolas, masik Windows gep.
- `README.local-podman.md` - rovid helyi stack osszefoglalo.
- `PROXY-CONFIG.md` - egyetlen `proxy.config.json` fajlos proxy beallitas.
- `PORT-CONFIG.md` - portok atallitasa.
- `SQL-SERVER-CONNECTION.md` - MSSQL csatlakozas Windowsrol, kontenerbol es DbGate-bol.
- `SCRIPT-STRUCTURE.md` - `scripts` es `scripts/private` konyvtarak szerepe.
- `MODULE-SOURCE-SYNC.md` - Maven modulok Git forrasanak frissitese branch szerint.
- `MAVEN-LIBRARY-FIRST-BUILD.md` - library/BOM modulok installja app build elott.
- `LOG-VIEWER.md` - webes kontener log nezegeto Dozzle alapon.
- `LOG-PERSISTENCE.md` - logok megorzese ujrainditas es pod ujraletrehozas elott.
- `NIFI-FILE-TO-KAFKA.md` - fajlbol Kafka topicra kuldes Apache NiFi-vel.
- `APPLICATION-YAML-CONFIG.md` - app YAML, Kafka, DB, topic es JKS konfiguracio.
- `REST-SOAP-SECURITY-EXAMPLES.md` - REST/SOAP/JKS/security mintak.
- `ADD-NEW-APP.md` - uj `appN` vagy meglevo repo bekotese.

Minden PowerShell script reszletes helpet ad a `--help` kapcsoloval.

Log viewer reszletek: `LOG-VIEWER.md`.
