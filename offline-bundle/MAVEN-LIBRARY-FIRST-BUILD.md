# Maven library-first build

Ez a dokumentum azt irja le, hogyan kezeli a build azokat a root `pom.xml`
modulokat, amelyek nem indulnak Podman appkent, hanem library, parent POM vagy
BOM modulok.

## Alapelv

A root `pom.xml` tovabbra is Maven aggregator:

```xml
<modules>
    <module>safe-bom</module>
    <module>shared-library</module>
    <module>app1</module>
</modules>
```

A `services.json` `services` listaja mondja meg, mely modulokbol lesz futtathato
Spring Boot app/pod:

```json
{
  "services": [
    {
      "name": "app1",
      "projectDir": "app1",
      "imageTag": "local/app1:dev"
    }
  ]
}
```

A build script ez alapjan osztalyoz:

- root `pom.xml` modul + szerepel `services[*].projectDir` ertekkent: app modul;
- root `pom.xml` modul + nem szerepel service-kent: library/BOM/parent modul.

## Mit futtat a build?

Ha vannak library/BOM modulok, a build eloszor ezt futtatja:

```text
mvn -pl safe-bom,shared-library -am clean install
```

Ez beteszi a modulokat a projekt lokalis Maven cache-be:

```text
data\maven-repo
```

Utana jonnek az app modulok:

```text
mvn -pl app1 clean package
```

Igy az appok a parentet/BOM-ot/library-t mar a local Maven repositorybol tudjak
feloldani.

## SAFE-BOM parent az app pom.xml-ben

Ha az app eredeti `pom.xml` fajljaban a parent ilyen:

```xml
<parent>
    <groupId>com.company.platform</groupId>
    <artifactId>safe-bom</artifactId>
    <version>1.2.3</version>
    <relativePath/>
</parent>
```

akkor ez jo. A `<relativePath/>` azt jelenti, hogy Maven ne a fajlrendszeren
keresse a parentet, hanem Maven repositorybol oldja fel. Ha a `safe-bom` modul
eloszor `install`-al bekerult a `data\maven-repo` cache-be, az app build mar
megtalalja.

## Build parancs

Teljes build:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -SkipTests
```

Csak egy app:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -MavenProjects app1 `
  -SkipTests
```

Ilyenkor a script akkor is eloszor installalja a library/BOM modulokat, ha csak
egy appot kersz. Ez szandekos, mert az app parentje/fuggosege ezekbol johet.

Ha a Maven cache mar fel van toltve es nincs internet:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -Offline `
  -SkipTests
```

## Gitbol jovo library vagy BOM

Ha a `safe-bom` vagy `shared-library` kulon Git repo, akkor:

1. tedd be a root `pom.xml` modul listaba;
2. ne tedd be a `services` listaba, mert nem indul belole pod;
3. add meg a `services.json` `moduleSources` reszben, hogy honnan frissuljon:

```json
{
  "moduleSources": {
    "safe-bom": {
      "projectDir": "safe-bom",
      "branch": "develop",
      "gitUrl": "https://github.com/example/safe-bom.git"
    }
  }
}
```

Forrasfrissites:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-module-sources.ps1
```

Build:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-apps-with-podman.ps1 `
  -SkipTests
```

## Mikor kell Maven settings?

Ha a parent/BOM/library nem source modulbol jon, hanem ceges Nexus/Artifactory
repositorybol, akkor `maven-settings.local.xml` kell.

A `proxy.config.json`-ban:

```json
{
  "mavenSettingsFile": "maven-settings.local.xml"
}
```

Ebben legyenek a repositoryk, credentialok, proxyk es aktiv profilok.

## Fontos

Nem kell az app eredeti `pom.xml` fajljat modositani csak azert, hogy a parentet
lokalis fajlrendszerrol keresse. Ha az appban `<relativePath/>` van, es a
parent/BOM installalva van a local Maven cache-be, az eleg.
