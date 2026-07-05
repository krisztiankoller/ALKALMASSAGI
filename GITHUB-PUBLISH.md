# GitHub publish plan

Ez a dokumentum a projekt GitHubra feltoltesenek tervezett modjat irja le.

## Cel

- Normal fejlesztoi ag: `develop`
- Specialis offline image ag: `all`, a `develop` tartalmaval plusz a darabolt offline image fajlokkal
- A `develop` ag ne tartalmazzon runtime adatokat, Maven cache-t, target
  konyvtarakat, logokat vagy nagy image tar fajlt.
- Az `all` ag ugyanazt tartalmazza, mint a `develop`, plusz a nagy offline image bundle darabjait.

## Aktualis blokkolok ezen a gepen

Ezen a gepen jelenleg nem elerheto:

```text
git
gh
```

Ezert innen most nem lehet normal GitHub repot inicializalni, commitolni es
pusholni. A GitHub connector repo fajlokat tud kezelni, de uj repo letrehozasa
es tobb GB binaris feltoltese ehhez nem eleg.

## Fontos GitHub meretlimit

A `offline-bundle\images\podman-images.tar` jelenleg tobb mint 6 GiB.

GitHub normal Git objektumkent 100 MiB feletti fajlt blokkol.
Git LFS-ben is van per-file limit:

- GitHub Free/Pro: 2 GB
- GitHub Team: 4 GB
- GitHub Enterprise Cloud: 5 GB

Ezert a tar fajlt egyben nem szabad es nem is lehet megbizhatoan branchre
tenni. A megoldas: darabolt fajlok az `all` agon, Git LFS-sel.

## Elokeszites

Telepitendo:

```text
Git for Windows
GitHub CLI
Git LFS
```

Bejelentkezes:

```powershell
gh auth login
gh auth status
git lfs install
```

## Repo letrehozasa

Javasolt repo nev:

```text
ALKALMASSAGI
```

Ha privat repo kell:

```powershell
gh repo create krisztiankoller/ALKALMASSAGI --private --confirm
```

Ha publikus repo kell:

```powershell
gh repo create krisztiankoller/ALKALMASSAGI --public --confirm
```

## develop ag feltoltese

```powershell
cd <projekt-konyvtar>

git init -b develop
git remote add origin https://github.com/krisztiankoller/ALKALMASSAGI.git

git add .
git commit -m "Initial portable Podman stack"
git push -u origin develop

gh repo edit krisztiankoller/ALKALMASSAGI --default-branch develop
```

Ebben az agban a `.gitignore` miatt kimarad:

- `data`
- `work`
- `target`
- `offline-bundle/images/*.tar`
- `offline-bundle/images/*.tar.part*`
- `proxy.config.json`

A `proxy.config.sample.json` viszont bekerulhet, mert nem tartalmaz valodi
jelszot.

## all ag a nagy offline image-hez

Eloszor darabold fel a tar fajlt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\split-offline-image.ps1 -Overwrite
```

Ez letrehozza:

```text
offline-bundle\images\split\podman-images.tar.part001
offline-bundle\images\split\podman-images.tar.part002
...
offline-bundle\images\split\podman-images.tar.parts.sha256
```

Ezutan:

```powershell
git switch -c all develop
git lfs track "offline-bundle/images/split/podman-images.tar.part*"
git add .gitattributes GITHUB-PUBLISH.md
git add -f offline-bundle\images\split\podman-images.tar.part*
git add -f offline-bundle\images\split\podman-images.tar.parts.sha256

git commit -m "Add offline image bundle parts"
git push -u origin all
```

## Masik gepen visszaallitas

Kod, doksi es normal fejlesztoi anyag:

```powershell
git clone -b develop https://github.com/krisztiankoller/ALKALMASSAGI.git ALKALMASSAGI
```

Kod, doksi es offline image darabok egyutt:

```powershell
git clone -b all https://github.com/krisztiankoller/ALKALMASSAGI.git ALKALMASSAGI-all
```

Az `all` ag klonozasa utan:

```powershell
cd ALKALMASSAGI-all
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\join-offline-image.ps1
```

Ez visszaallitja:

```text
offline-bundle\images\podman-images.tar
```

Utana az offline inditas:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-offline.ps1 `
  -SqlPassword "Alkalmassagi_2026!" `
  -ExternalHostName localhost
```
