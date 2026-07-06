# Log persistence

## Mi volt a problema?

A Dozzle webes feluleten az aktualis kontenerlogokat mutatja.

Ha egy podot torlunk es ujra letrehozunk, akkor a regi kontener megszunik. A regi kontenerhez tartozo `podman logs` tartalom ilyenkor elveszhet, ha elotte nem mentjuk ki.

## Mi marad meg mostantol?

A deploy scriptek pod torles elott automatikusan kimentik a regi kontenerlogokat ide:

```text
.\data\logs
```

Pelda:

```text
.\data\logs\20260705-141500\app1-pod\app1.log
.\data\logs\20260705-141500\kafka-pod\kafka.log
.\data\logs\20260705-141500\mssql-pod\mssql.log
```

Offline bundle-bol futtatva ugyanez az offline bundle alatt lesz:

```text
.\offline-bundle\data\logs
```

## Melyik scriptek mentenek automatikusan?

Ezek pod ujraletrehozas elott mentenek:

```text
.\scripts\deploy-infra-pods.ps1
.\scripts\deploy-springboot-pods.ps1
```

Ez azt jelenti, hogy ezek logjai is megmaradnak ujrainditas elott:

- app1
- app2
- app3
- app4
- app5
- app6
- mssql
- kafka
- kafka-ui
- sql-admin
- log-viewer
- java-build-log-viewer
- java-maven-builder

## Java build logok

A Maven build logok kulon is megmaradnak itt:

```text
.\data\build-logs
```

Az aktualis build log:

```text
.\data\build-logs\current.log
```

Uj build inditasakor a regi `current.log` timestampelt fajlba kerul, peldaul:

```text
.\data\build-logs\build-20260706-142500.log
```

A `java-build-log-viewer` kontener a build utan a teljes `current.log` fajlt
kiirja a sajat kontenerlogjaba, ezert a build log Dozzle-ban is lathato:

```text
http://localhost:40004 -> java-build-log-viewer
```

## Kezi log export

Barmikor kimentheted az osszes aktualis kontenerlogot:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-container-logs.ps1
```

Csak egy pod logjai:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-container-logs.ps1 -PodName app1-pod
```

Csak konkret kontenerek:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-container-logs.ps1 -ContainerName app1,kafka,mssql
```

Csak az utolso 2 ora:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-container-logs.ps1 -Since 2h
```

Csak utolso 500 sor:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-container-logs.ps1 -Tail 500
```

## Automatikus mentest ki lehet kapcsolni?

Igen, ha valamiert nem akarod menteni a regi kontenerlogokat:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-infra-pods.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost `
  -SkipLogArchive
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json `
  -SkipBuild `
  -SkipLogArchive
```

## Mit nem old meg?

Ez nem teljes log management rendszer es nem indexelheto keresomotor.

A logok sima `.log` fajlok lesznek a projekt alatt. Ez fejleszteshez es offline hibakereseshez egyszeru es jol hordozhato.

Ha kesobb nagyobb mennyisegu, keresheto log kell, akkor erdemes lehet Loki/Grafana vagy OpenSearch/Fluent Bit iranyba tovabblepni.

## Dozzle es mentett logok

Dozzle:

```text
http://localhost:40004
```

A Dozzle az elo kontenerek aktualis logjait mutatja.

A regi, archive-olt logokat a fajlrendszerben talalod:

```text
.\data\logs
```
