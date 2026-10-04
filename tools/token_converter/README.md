# Token Converter

Questa cartella contiene il convertitore Blender usato durante lo sviluppo per trasformare raccolte di miniature 3D in asset compatibili con il VTT Godot.

Il convertitore lavora sempre su una scena/copia temporanea in Blender: **non modifica mai i file sorgente originali**.

## Pipeline

```text
miniature originali
(.blend / .stl / .obj / .fbx / .glb / .gltf)
        |
        v
tools/import_tokens.ps1
        |
        v
Blender background
tools/token_converter/convert_tokens.py
        |
        +--> statico  -> assets/tokens/generated/<id>/<id>.obj
        |
        +--> riggato  -> assets/tokens/generated/<id>/<id>.glb
        |
        +--> assets/tokens/scenes/<id>_token.tscn
        |
        +--> assets/tokens/token_library.json
```

Gli asset in `assets/tokens/generated/` sono file locali di sviluppo e non devono essere usati come sistema di distribuzione finale. Per la distribuzione lazy-loaded usare la pipeline PCK documentata in `tools/token_packs/README.md`.

## Uso rapido

Da PowerShell, nella root del progetto:

```powershell
.\tools\import_tokens.ps1 -Source "C:\percorso\Miniature"
```

Per scegliere il token di default:

```powershell
.\tools\import_tokens.ps1 -Source "C:\percorso\Miniature" -Default "Solar Dragon"
```

Per ridurre la geometria dei modelli statici:

```powershell
.\tools\import_tokens.ps1 -Source "C:\percorso\Miniature" -DecimateRatio 0.65
```

Se Blender non è nel PATH:

```powershell
.\tools\import_tokens.ps1 `
    -Source "C:\percorso\Miniature" `
    -Blender "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe"
```

`import_tokens.ps1` individua Blender e avvia `convert_tokens.py` in background con il project root corretto.

## Formati sorgente supportati

Il convertitore considera:

- `.blend`
- `.stl`
- `.obj`
- `.fbx`
- `.glb`
- `.gltf`

Quando in una cartella esistono più file possibili, non vengono semplicemente importati tutti come una singola mesh. Il converter cerca il candidato che più probabilmente rappresenta la miniatura completa.

In generale vengono favoriti:

1. scene complete `.blend`;
2. GLB/GLTF;
3. FBX;
4. OBJ;
5. STL grezzi.

Nomi come `final`, `posed`, `complete`, `assembled`, `merged`, `whole` e `full` aumentano la priorità. File che sembrano singole parti di stampa, supporti, marker o basi vengono penalizzati.

Un file `.blend` non viene classificato come semplice "parte" solo perché contiene nel nome o nella scena oggetti come Body, Base o Marker: può contenere l'intera scena assemblata.

## Discovery delle miniature

`--source` può indicare:

- direttamente la cartella di una miniatura;
- una cartella con una sottocartella per miniatura;
- una collezione più profonda con cartelle alfabetiche o organizzative intermedie.

La ricerca è ricorsiva e non si ferma automaticamente alle cartelle di raggruppamento.

Le cartelle tecniche come `STL`, `Blend`, `Parts`, `Supported`, `Presupported`, `Models` ecc. vengono trattate come parti della stessa miniatura quando appropriato, invece di diventare token separati.

L'id del token viene normalizzato in forma slug, per esempio:

```text
Giant Weasel -> giant_weasel
Solar Dragon -> solar_dragon
```

## Importazioni additive

Le importazioni sono additive.

Puoi eseguire il convertitore più volte su raccolte o cartelle differenti:

```powershell
.\tools\import_tokens.ps1 -Source "D:\Miniatures\Appendix A"
.\tools\import_tokens.ps1 -Source "D:\Miniatures\Appendix B"
.\tools\import_tokens.ps1 -Source "D:\Miniatures\Characters"
```

I token già presenti in `assets/tokens/token_library.json` e in `assets/tokens/generated/` non vengono cancellati.

Se una run genera nuovamente lo stesso id, solo quel token viene aggiornato/sostituito. Gli altri restano invariati.

Il token di default precedente viene mantenuto, salvo uso esplicito di `-Default`.

## Come viene determinata la taglia

La scala **non viene ricavata dall'altezza del personaggio**.

Il riferimento principale è la base/size marker della miniatura.

Il converter cerca prima:

- marker già presenti nella scena;
- oppure file separati che rappresentano una base o un size marker.

Se il nome identifica direttamente una taglia D&D, quella taglia viene usata.

| Taglia | Footprint VTT |
| --- | ---: |
| Tiny | 0.5 celle |
| Small | 1 cella |
| Medium | 1 cella |
| Large | 2 celle |
| Huge | 3 celle |
| Gargantuan | 4 celle |

La base viene scalata affinché il suo diametro corrisponda al footprint.

Se non esiste una taglia esplicita nel nome, il diametro fisico della base viene confrontato con le dimensioni tabletop standard e viene scelta la taglia più vicina.

Il centro della base diventa `X/Z = 0` e il fondo viene portato a quota `0`.

Ali, code, armi e altre geometrie possono quindi uscire dal footprint senza alterare la taglia occupata sulla griglia.

### Marker e geometria

I marker esterni servono come riferimento di scala e non vengono esportati come parte della creatura.

Marker già presenti nella scena possono invece essere riconosciuti dalla struttura/nomenclatura del modello.

Casi speciali gestiti dal converter includono anche miniature i cui veri componenti si chiamano semplicemente `Body.stl` o `Tentacles.stl`: se sono l'unica geometria reale non vengono scartati come parti ausiliarie.

`Organic Base Sphere` può rappresentare geometria effettiva della creatura e non viene automaticamente eliminata come marker.

Se una cartella contiene soltanto un marker e nessuna geometria utilizzabile, la conversione fallisce invece di generare un token vuoto.

## Modelli statici: OBJ

Quando la miniatura non contiene un'armatura realmente collegata alle mesh visibili, il risultato è:

```text
assets/tokens/generated/<id>/<id>.obj
```

Il file viene normalizzato sulla base/marker e può essere semplificato con `-DecimateRatio`.

La decimazione viene applicata **solo alla copia temporanea importata in Blender**. Il file sorgente originale non viene mai riscritto.

`1.0` disabilita la decimazione. Ad esempio:

```powershell
-DecimateRatio 0.65
```

tenta di conservare circa il 65% delle facce.

## Modelli riggati: GLB

Una miniatura viene trattata come riggata solo quando esiste un'Armature che **controlla realmente una delle mesh visibili**, tramite:

- parentela nella gerarchia;
- oppure Armature Modifier.

La semplice presenza di un oggetto Armature inutilizzato non basta.

In questo caso l'output principale è:

```text
assets/tokens/generated/<id>/<id>.glb
```

La normalizzazione viene applicata alle radici della gerarchia anziché separatamente alle mesh, preservando:

- skeleton;
- bind pose;
- skin weights;
- gerarchia;
- animazioni embedded presenti nel sorgente.

La decimazione richiesta con `-DecimateRatio` viene ignorata sui modelli riggati per evitare di degradare skin e pesi.

## Rig type e animazioni

Il converter classifica in modo conservativo gli skeleton riconoscibili.

Un rig con sufficiente corrispondenza a ossa tipiche come hips/pelvis, spine, head, upper arm, hand, thigh e foot può essere marcato come:

```text
rig_type = humanoid
skeleton_profile = humanoid
```

Gli altri vengono mantenuti come rig generici.

Per umanoidi senza animazioni embedded il manifest può indicare:

```text
animation_set = humanoid_default
```

Questo è il punto di aggancio previsto per il retargeting Godot tramite `BoneMap` / `SkeletonProfileHumanoid`.

Se sono presenti animazioni embedded, il converter ne registra i nomi e sceglie preferibilmente un'animazione chiamata `idle`; in assenza di idle usa la prima disponibile come default.

Il VTT supporta anche una `animation_library` Godot condivisa (`.tres` / `.res`), evitando di duplicare le stesse clip in ogni modello.

## Wrapper Godot

Per ogni miniatura viene generata anche:

```text
assets/tokens/scenes/<id>_token.tscn
```

Questa scena eredita da:

```text
res://token.tscn
```

Quindi non è semplicemente una mesh: è un vero token del VTT e mantiene il comportamento comune definito dal progetto, tra cui collisione, selezione, drag, movimento su griglia, volo, direzione, visione, iniziativa, condizioni, incantesimi, undo e sincronizzazione.

## Manifest token_library.json

Il converter aggiorna:

```text
assets/tokens/token_library.json
```

Il manifest v3 usa `visual_asset` come path generico della risorsa visuale.

Per compatibilità mantiene anche il campo `obj`, ma il codice nuovo deve preferire `visual_asset`.

Tra i metadati utilizzati dal converter/pipeline possono comparire:

```text
id
name
source
visual_asset
obj
scene
asset_format
size_name
footprint
height_cells
width_cells
depth_cells
base_reference
base_diameter_source
scale_factor
rigged
rig_type
skeleton_profile
animation_set
animation_library
default_animation
embedded_animations
armatures
```

Il manifest è additivo come gli asset generati.

## Default token

Con `-Default` puoi indicare id, nome o una sottostringa del token da usare al posto del corpo procedurale predefinito.

Se il manifest o l'asset non sono disponibili, il token procedurale rimane il fallback.

## Errori e casi da controllare

Alla fine della conversione vengono riportati i token che non è stato possibile convertire. Una miniatura che fallisce non implica necessariamente che l'intera collezione sia inutilizzabile.

Controllare soprattutto:

- cartella con solo marker/base e nessuna creatura;
- file sorgente incompleto;
- scene con più varianti senza un candidato completo riconoscibile;
- geometria nascosta/visibilità Blender;
- armatura presente ma non collegata alle mesh visibili;
- scala/base anomala.

## Dal converter ai PCK lazy-loaded

Il converter produce gli asset locali di sviluppo. La pipeline successiva crea un PCK indipendente per token:

```text
assets/tokens/generated/<id>/
        |
        v
tools/build_token_packs.ps1
        |
        v
dist/token_packs/<id>.pck
```

Consulta:

```text
tools/token_packs/README.md
```

per build incrementali, verifica, catalogo e GitHub Releases.


## D&D size metadata from 5eTools

La taglia D&D è metadata e non ridimensiona automaticamente la miniatura.

Per default `tools/import_tokens.ps1` non richiede più un checkout 5eTools nel
repository. Alla prima esecuzione scarica online i dati bestiario dal mirror
pubblico `5etools-src`, costruisce un indice compatto e lo salva fuori dal
repository nella cache utente:

```text
%LOCALAPPDATA%\VTT\cache\5etools_creature_index.json
```

Le esecuzioni successive riutilizzano questa cache senza nuove richieste online.
Per aggiornarla esplicitamente:

```powershell
.\tools\import_tokens.ps1 -Source "C:\...\Monster Manual 2014" -Refresh5eTools
```

Resta possibile usare un checkout locale esterno al repository tramite
`-FiveEToolsRoot` o `VTT_5ETOOLS_ROOT`.

Lookup priority:

1. exact/controlled 5eTools creature-name match (MM 2014 preferred over XMM),
2. optional `assets/tokens/creature_size_overrides.json`,
3. explicit size word in package/model name,
4. base/marker fallback,
5. Medium.

Suffix controllati come `Updated`, `Final`, `posed` e `.001` vengono
rimossi senza fuzzy matching aggressivo. Un match ambiguo non viene inventato.

Se 5eTools e base/marker non concordano, il converter stampa un warning ma
mantiene la taglia 5eTools e la scala visuale authored.
