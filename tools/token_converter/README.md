# Import automatico miniature come token

La conversione viene eseguita da Blender in background e serve durante lo sviluppo.

## Uso

Da PowerShell, nella root del progetto:

    .\tools\import_tokens.ps1 -Source "C:\percorso\Miniature"

Se la cartella indicata contiene direttamente i file di una miniatura, viene
creato un solo token. Se invece contiene una sottocartella per miniatura, ogni
sottocartella viene convertita in un token.

Per scegliere il token di default:

    .\tools\import_tokens.ps1 -Source "C:\percorso\Miniature" -Default "Solar Dragon"

Se Blender non e' nel PATH:

    .\tools\import_tokens.ps1 -Source "C:\percorso\Miniature" -Blender "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe"


## Run multiple su cartelle diverse

Le importazioni sono additive. Puoi eseguire il convertitore piu' volte su
raccolte o cartelle diverse: i token gia' presenti in token_library.json e in
assets/tokens/generated non vengono cancellati.

Se una run genera un token con lo stesso id di uno gia' presente, quel token
viene aggiornato/sostituito; tutti gli altri restano invariati. Il token di
default precedente viene mantenuto tra le run, a meno che non venga passato
esplicitamente -Default.

## Come viene scelta la scala

La scala NON viene ricavata dall'altezza del personaggio.

Il convertitore cerca prima un oggetto della scena o un file separato che
rappresenti la base/size marker. Se nel nome compare Tiny, Small, Medium, Large,
Huge o Gargantuan, quella taglia e' usata direttamente. La base viene poi
scalata affinche' il suo diametro occupi il footprint del VTT:

- Tiny: 0.5 celle
- Small/Medium: 1 cella
- Large: 2 celle
- Huge: 3 celle
- Gargantuan: 4 celle

Se il nome non contiene la taglia, viene usato come fallback il diametro fisico
della base e il formato standard piu' vicino.

Il centro della base diventa X/Z = 0 del token e il fondo della base viene
portato a quota 0. Ali, code, armi e altre parti possono quindi uscire dal
footprint senza modificare la taglia del token.

### Verifica Solar Dragon

Nel pacchetto di test l'oggetto "Huge Creature Flying Marker" ha una base di
circa 68.40 x 68.40 unita' sorgente. Essendo Huge viene portata esattamente a
3 x 3 celle, con fattore di scala circa 0.0438584.

## Output

Per ogni miniatura vengono generati:

- modelli statici: assets/tokens/generated/<id>/<id>.obj
- modelli gia' riggati: assets/tokens/generated/<id>/<id>.glb
- assets/tokens/scenes/<id>_token.tscn
- assets/tokens/token_library.json

La pipeline sceglie GLB solo quando una Armature e' realmente collegata a una
delle mesh visibili tramite parentela o Armature modifier. In quel caso la
normalizzazione di scala/posizione viene applicata alle radici della gerarchia,
non separatamente alla mesh: skeleton, bind pose e skin weights restano quindi
coerenti. Le animazioni gia' presenti nel file sorgente vengono esportate nel
GLB. Se viene richiesto --decimate-ratio su un modello riggato, la
semplificazione viene ignorata per non rischiare di degradare skin/weights.

token_library.json v3 usa visual_asset come campo generico e mantiene obj come
alias di compatibilita'. Aggiunge inoltre asset_format, rigged, rig_type,
skeleton_profile, animation_set, animation_library, default_animation,
embedded_animations e armatures.

La scena *_token.tscn eredita da res://token.tscn. Quindi una miniatura
trascinata direttamente nella scena e' un vero token: CharacterBody3D, gruppo
dnd_token, collisione, selezione, drag, movimento su griglia, volo, indicatore
di direzione, visione, iniziativa, incantesimi, undo e sincronizzazione.

La miniatura scelta come default sostituisce automaticamente il corpo
procedurale dei nuovi token creati dal VTT. Se il manifest non esiste o l'asset
non e' disponibile, il token procedurale resta come fallback.

## Rig e animazioni condivise

Il convertitore non prova a inventare un rig per STL/OBJ statici: questi
continuano a funzionare esattamente come prima. Un FBX/GLB/BLEND con rig viene
invece conservato come GLB.

Per i rig riconosciuti come umanoidi il manifest imposta
skeleton_profile="humanoid" e, se non ci sono animazioni embedded,
animation_set="humanoid_default". Questo e' il punto di aggancio previsto per
retargeting Godot con BoneMap/SkeletonProfileHumanoid.

token.gd supporta anche animation_library: quando il campo contiene il path di
una AnimationLibrary Godot (.tres/.res), la libreria viene montata come
"shared" sull'AnimationPlayer del modello. default_animation viene avviata
automaticamente quando disponibile. In questo modo una sola libreria puo'
essere condivisa da molti token invece di duplicare le clip in ogni modello.

Gli asset di animazione esterni non sono inclusi automaticamente nel
repository. Per una libreria redistribuibile usare asset con licenza compatibile
(ad esempio CC0) e salvarne la versione Godot sotto assets/animations/.
