# Token PCK Builder

Questa cartella contiene gli script Godot usati da `tools/build_token_packs.ps1` per trasformare le miniature convertite in **PCK indipendenti e lazy-loadable**.

L'obiettivo è evitare di distribuire tutte le miniature nel repository o nell'eseguibile principale del VTT.

## Pipeline

```text
assets/tokens/generated/<id>/<id>.obj|glb
assets/tokens/token_library.json
        |
        v
tools/build_token_packs.ps1
        |
        +--> tools/token_packs/build_one_token_pack.gd
        |
        +--> tools/token_packs/verify_token_pack.gd
        |
        v
dist/token_packs/<id>.pck
dist/token_packs/token_catalog.json
```

Ogni PCK contiene soltanto la parte specifica di quella miniatura.

Il comportamento comune dei token rimane nel progetto principale:

```text
res://token.tscn
res://token.gd
```

La scena contenuta nel PCK eredita da `res://token.tscn`, quindi non duplichiamo la logica VTT in ogni pacchetto.

## Requisiti

- Godot 4.7.2.
- Miniature già convertite tramite `tools/import_tokens.ps1`.
- `assets/tokens/token_library.json` aggiornato.
- Per controllare le Release di un repository privato: GitHub CLI (`gh`) autenticata.

Verifica GitHub CLI con:

```powershell
gh auth status
```

## Build di un singolo token

Esempio:

```powershell
.\tools\build_token_packs.ps1 `
    -TokenId ape `
    -Godot "C:\percorso\Godot_v4.7.2-stable_win64.exe"
```

Il wrapper preferisce automaticamente la variante `_console.exe` quando si trova accanto all'eseguibile Godot selezionato.

L'output è:

```text
dist/token_packs/ape.pck
```

e il catalogo viene aggiornato in:

```text
dist/token_packs/token_catalog.json
```

Una build esplicita con `-TokenId` ricostruisce il token richiesto.

## Build di tutti i token disponibili

```powershell
.\tools\build_token_packs.ps1 `
    -All `
    -Godot "C:\percorso\Godot_v4.7.2-stable_win64.exe"
```

`-All` prende gli ID dalle **sottodirectory immediate** di:

```text
assets/tokens/generated/
```

Per esempio:

```text
assets/tokens/generated/
├── ape/
├── goat/
├── giant_weasel/
└── hunter_shark/
```

produce i candidati:

```text
ape
goat
giant_weasel
hunter_shark
```

La presenza della directory decide cosa tentare di buildare. Il profilo corrispondente deve però esistere anche in `assets/tokens/token_library.json`, perché il builder usa il manifest per nome, taglia, footprint, altezza e visual asset.

Se una directory non ha un profilo nel manifest, viene segnalata e il batch continua.

## Modalità incrementale / additiva

`-All` è pensato per collezioni molto grandi.

Non è necessario creare tutti i PCK in una singola esecuzione.

Per ogni token lo script controlla:

1. se `<id>.pck` è già pubblicato in una GitHub Release;
2. altrimenti se `dist/token_packs/<id>.pck` esiste già localmente;
3. solo se manca in entrambi i posti viene costruito.

Quindi puoi:

1. buildare una tranche;
2. pubblicarla su GitHub Releases;
3. cancellare quei PCK dal disco locale;
4. convertire altre miniature;
5. rilanciare `-All`.

I PCK già pubblicati non verranno ricreati.

Se interrompi manualmente un batch, i pack già completati restano validi. Alla run successiva verranno saltati.

## Controllo di tutte le GitHub Releases

Il controllo remoto riguarda **tutte le Release del repository**, non soltanto l'ultima.

Lo script usa prima:

```powershell
gh api
```

in modo da sfruttare direttamente l'autenticazione salvata da:

```powershell
gh auth login
```

Questo è particolarmente importante perché il repository VTT è privato.

Le release vengono lette a pagine da 100 elementi.

Un token è considerato già pubblicato se in una qualsiasi Release esiste un asset chiamato esattamente:

```text
<id>.pck
```

Per esempio:

```text
ape.pck
giant_weasel.pck
hunter_shark.pck
```

Se lo stesso nome compare in più Release, i metadati della copia più recente vengono usati per il catalogo.

### Fallback con token GitHub

Per CI o macchine senza `gh`, è ancora possibile fornire:

```powershell
-GitHubToken "..."
```

oppure impostare:

```text
GITHUB_TOKEN
```

Il token non è necessario nell'uso locale normale se `gh api` funziona.

Lo script non usa intenzionalmente una richiesta anonima come fallback quando sa di dover accedere al repository privato.

## Forzare una rebuild completa

Per ignorare lo stato locale/remoto:

```powershell
.\tools\build_token_packs.ps1 -All -Force -Godot "C:\...\Godot.exe"
```

Con `-Force`, i PCK candidati vengono ricostruiti anche se già presenti.

Usarlo solo quando serve realmente, perché può essere molto costoso su librerie grandi.

## Opzioni principali

| Opzione | Significato |
| --- | --- |
| `-TokenId <id>` | Build esplicita di un singolo token. Default: `ape`. |
| `-All` | Scansiona tutte le sottodirectory immediate di `assets/tokens/generated`. |
| `-Force` | Ricostruisce anche i PCK già presenti. |
| `-Godot <path>` | Specifica l'eseguibile Godot. |
| `-SkipImport` | Salta il passaggio iniziale `Godot --import`. |
| `-SkipVerify` | Non esegue il test mount/load/instantiate del PCK. |
| `-SkipReleaseCheck` | Non controlla GitHub Releases. |
| `-GitHubToken <token>` | Fallback per API GitHub autenticata senza `gh`. |

## Import Godot

Durante `-All`, il comando:

```text
Godot --headless --import
```

viene eseguito **una sola volta per batch**, non una volta per miniatura.

Questo evita di moltiplicare inutilmente il costo di scansione/import del progetto.

Con `-SkipImport` il passaggio viene saltato.

OBJ e GLB supportati dal builder hanno comunque loader runtime dedicati; l'import iniziale resta utile per il resto delle risorse del progetto e per compatibilità con altri formati.

## OBJ statici

Gli OBJ non dipendono dal file Godot `.obj.import`.

`build_one_token_pack.gd` contiene un loader OBJ runtime che legge direttamente il file e supporta:

- vertici `v`;
- coordinate UV `vt`;
- normali `vn`;
- facce `f`;
- indici OBJ positivi e negativi;
- triangolazione fan dei poligoni;
- generazione delle normali quando non sono fornite.

Il risultato viene serializzato come `ArrayMesh` dentro lo staging del PCK.

Questo evita di dipendere dalla cache `.godot/imported/` per i token OBJ.

## GLB / GLTF riggati

I GLB/GLTF vengono importati a runtime con:

```text
GLTFDocument
GLTFState
generate_scene()
```

Il risultato viene salvato come `PackedScene`.

Questo è intenzionale: trasformare un token riggato in una semplice `ArrayMesh` eliminerebbe informazioni importanti.

La pipeline GLB preserva quindi, quando presenti:

- gerarchia;
- Skeleton3D;
- skin;
- pesi;
- animazioni;
- AnimationPlayer.

Nel log vengono riportati a scopo diagnostico il numero di Skeleton3D e AnimationPlayer trovati.

## Contenuto interno di un PCK

Per un token `ape`, il pack espone risorse sotto:

```text
res://remote_tokens/ape/
├── ape_visual.res
└── ape_token.tscn
```

La scena `ape_token.tscn` eredita da:

```text
res://token.tscn
```

e contiene i metadati specifici del token:

- visual asset;
- native footprint;
- display name;
- size;
- default footprint;
- altezza.

Il PCK non deve contenere una copia completa di `token.gd` o del resto del VTT.

## Verifica automatica

Salvo `-SkipVerify`, ogni PCK appena costruito viene verificato con:

```text
tools/token_packs/verify_token_pack.gd
```

Il test:

1. monta il PCK con `ProjectSettings.load_resource_pack()`;
2. carica la scena `res://remote_tokens/<id>/<id>_token.tscn`;
3. la istanzia;
4. verifica che sia un `Node3D`;
5. verifica il gruppo `dnd_token`;
6. controlla la presenza dei metodi base del token;
7. verifica che il visual asset provenga da `res://remote_tokens/`.

Tra i metodi controllati:

```text
configure
set_visual_asset
set_selected
set_conditions
get_visual_asset_path
```

Una build non viene considerata riuscita se questa verifica fallisce.

## Catalogo

Il file:

```text
dist/token_packs/token_catalog.json
```

è l'indice della libreria distribuibile.

Le entry locali includono almeno:

```text
id
name
size_name
footprint
version
bytes
pck
scene
sha256
source_collection
```

Quando un PCK viene trovato in una Release, il catalogo può includere anche:

```text
release_asset_id
release_download_url
release_tag
release_published_at
```

e il digest SHA-256 quando GitHub lo fornisce.

### Catalogo additivo

Il catalogo esistente viene letto prima del batch.

Le nuove entry vengono aggiunte/aggiornate senza cancellare automaticamente quelle generate in run precedenti.

Dopo ogni PCK costruito con successo il catalogo viene salvato immediatamente. Questo riduce la perdita di lavoro se un batch viene interrotto.

Al termine viene scritto nuovamente il catalogo consolidato.

## Pubblicazione su GitHub Releases

I PCK sono file binari pesanti e non devono essere committati normalmente nel repository.

La destinazione iniziale prevista è GitHub Releases.

Esempio:

```text
Release token-packs-001
├── ape.pck
├── goat.pck
└── lion.pck

Release token-packs-002
├── giant_weasel.pck
└── hunter_shark.pck
```

I pack possono essere distribuiti su più Release: `-All` le controlla tutte.

### token_catalog.json

Il catalogo deve essere considerato **globale**, non un catalogo separato per ogni tranche.

Una soluzione consigliata è pubblicarlo in una Release dedicata/stabile, per esempio:

```text
Release token-catalog
└── token_catalog.json
```

Il futuro runtime del VTT potrà scaricare questo singolo indice, mostrare tutte le miniature disponibili e poi scaricare soltanto il PCK scelto.

## Cache runtime prevista

La pipeline è progettata per il successivo lazy loading nel VTT:

```text
token_catalog.json remoto
        |
        v
utente sceglie una miniatura
        |
        v
download del solo <id>.pck
        |
        v
user://token_cache/
        |
        v
verifica SHA-256
        |
        v
ProjectSettings.load_resource_pack()
        |
        v
res://remote_tokens/<id>/<id>_token.tscn
```

Il download/runtime cache è una fase successiva rispetto agli script documentati qui.

## File temporanei e Git

Gli output pesanti e lo staging sono intenzionalmente ignorati da Git:

```text
assets/tokens/generated/
assets/tokens/scenes/
dist/token_packs/
.token_pack_build/
```

Non aggiungere i PCK al normale history Git.

## Diagnostica

Il wrapper crea log Godot sotto:

```text
.token_pack_build/logs/
```

Quando Godot termina con un codice diverso da zero, lo script stampa automaticamente la coda del log della fase fallita.

Esempi di stage del builder:

```text
TOKEN_PACK_STAGE profile
TOKEN_PACK_STAGE load
TOKEN_PACK_STAGE obj_runtime_loader
TOKEN_PACK_STAGE glb_runtime_loader
TOKEN_PACK_STAGE serialize
TOKEN_PACK_STAGE pck_start
TOKEN_PACK_STAGE add visual
TOKEN_PACK_STAGE add scene
TOKEN_PACK_STAGE flush
TOKEN_PACK_OK
```

Il batch `-All` non si ferma al primo token problematico: accumula i fallimenti, continua con gli altri e stampa un riepilogo finale.

Esempio:

```text
===== TOKEN PACK SUMMARY =====
Costruiti: 18
Gia presenti (locale/release): 42
Falliti: 3
Catalogo totale: 60
```

## Workflow consigliato

Per una libreria grande:

```text
1. converti una parte delle miniature
2. build_token_packs.ps1 -All
3. controlla i fallimenti
4. pubblica i PCK riusciti in una Release
5. eventualmente elimina i PCK locali già pubblicati
6. converti un'altra tranche
7. rilancia -All
8. ripeti
9. aggiorna/pubblica il catalogo globale
```

Non è necessario mantenere sul disco locale tutti i PCK già pubblicati.
