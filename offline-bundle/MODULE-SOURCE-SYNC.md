# Module source sync

Ez a dokumentum azt irja le, hogyan lehet a root `pom.xml` moduljaihoz tartozo
forraskodot Gitbol frissiteni a `services.json`-ban megadott branch alapjan.

## Mire valo?

A `scripts\sync-module-sources.ps1` script:

- beolvassa a root `pom.xml` `<modules>` listajat;
- a `services.json` `moduleSources` es `services` listajaban megkeresi az adott modul Git beallitasait;
- modulonkent feloldja, melyik branch-et kell hasznalni;
- Gitbol frissiti a modult vagy a hozza tartozo nested repot;
- ha a modul konyvtara hianyzik es van `gitUrl`, clone-olja.

## Branch sorrend

Egy modul branch-e ebben a sorrendben dol el:

1. `-ModuleBranch app3=feature/my-branch`
2. `-Branch feature/all-selected`
3. `services.json` `moduleSources` bejegyzesben: `branch`, `gitBranch` vagy `sourceBranch`
4. `services.json` service bejegyzesben: `branch`, `gitBranch` vagy `sourceBranch`
5. `develop`

Pelda `services.json` service bejegyzes:

```json
{
  "name": "app3",
  "projectDir": "app3",
  "branch": "develop",
  "gitUrl": "https://github.com/example/app3.git",
  "hostPort": 40007,
  "containerPort": 8080,
  "imageTag": "local/app3:dev",
  "applicationYaml": "application.yaml"
}
```

A `gitUrl` nem kotelezo, ha a modul konyvtara mar megvan. Akkor kell, ha a
scriptnek clone-oznia kell a hianyzo modul konyvtarat.

Ha a modul nem Spring Boot service, hanem peldaul library modul, ne tedd a
`services` listaba. Hasznald a top-level `moduleSources` reszt:

```json
{
  "moduleSources": {
    "shared-library": {
      "projectDir": "shared-library",
      "branch": "develop",
      "gitUrl": "https://github.com/example/shared-library.git"
    }
  }
}
```

A `moduleSources` csak a Git forrasszinkronhoz kell. Nem indit podot, nem epit
image-et, es nem hoz letre runtime resource-okat.

## Ha a modul nincs benne a services.json-ban

Ez teljesen tamogatott. A root `pom.xml` tartalmazhat olyan modult, amely nincs
benne a `services` listaban, peldaul egy kozos Spring Boot library:

```xml
<module>shared-library</module>
```

Ha nincs hozza `moduleSources` es nincs `services` bejegyzes, akkor a script:

- a modul nevet hasznalja konyvtarkent: `.\shared-library`;
- a branch-et `develop` ertekre allitja;
- ha ez a konyvtar Git repo vagy a root Git repo resze, dry-run/pull szerint kezeli.

Ha a konyvtar meg hianyzik, akkor kell `moduleSources` bejegyzes `gitUrl`-lel,
mert a script csak igy tudja honnan clone-ozza:

```json
{
  "moduleSources": {
    "shared-library": {
      "projectDir": "shared-library",
      "branch": "develop",
      "gitUrl": "https://github.com/example/shared-library.git"
    }
  }
}
```

## Minden modul frissitese

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1
```

## Csak egy modul

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 `
  -ModuleName app3
```

## Tobb modul

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 `
  -ModuleName app3,app4
```

## Branch feluliras minden kivalasztott modulra

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 `
  -ModuleName app3 `
  -Branch feature/new-flow
```

## Branch feluliras modulonkent

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 `
  -ModuleBranch app3=feature/app3,app4=feature/app4
```

## Dry run

Ezt hasznald eloszor, ha csak latni akarod, mit futtatna:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 `
  -DryRun
```

## Root repo kontra kulon app repo

Ha az app konyvtarak ugyanabban a root Git repoban vannak, mint a teljes
projekt, akkor a branch valtas a teljes projektre vonatkozik. Ilyenkor nem
lehet `app3` es `app4` ugyanabban a munkafaban kulon branch-en.

Modulonkent kulon branch akkor mukodik, ha az appok kulon Git repok:

```text
ALKALMASSAGI
  app1  -> kulon Git repo
  app2  -> kulon Git repo
```

Ha ugyanaz a Git repo tobb kivalasztott modulhoz mas-mas branch-et kapna, a
script megall es nem valt branchet.

## Dirty worktree vedelem

A script alapbol megall, ha a Git munkafa nem tiszta. Ez vedi a helyi
modositasokat branch valtas vagy pull elott.

Ha biztos vagy benne, hogy igy is folytatni akarod:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 `
  -AllowDirty
```

## Tipikus sorrend forrasfrissites utan

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -SkipTests

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json
```

Csak egy appnal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 `
  -ModuleName app3

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -MavenProjects app3 `
  -AlsoMake `
  -SkipTests

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-springboot-pods.ps1 `
  -ServicesFile .\services.json `
  -ServiceName app3 `
  -SqlPassword "Alkalmassagi_2026!"
```

## Reszletes help

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 --help
```

Ugyanez mukodik igy is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 -Help
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 -h
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1 -?
```
