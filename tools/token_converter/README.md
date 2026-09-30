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

- assets/tokens/generated/<id>/<id>.obj
- assets/tokens/scenes/<id>_token.tscn
- assets/tokens/token_library.json

La scena *_token.tscn eredita da res://token.tscn. Quindi una miniatura
trascinata direttamente nella scena e' un vero token: CharacterBody3D, gruppo
dnd_token, collisione, selezione, drag, movimento su griglia, volo, indicatore
di direzione, visione, iniziativa, incantesimi, undo e sincronizzazione.

La miniatura scelta come default sostituisce automaticamente il corpo
procedurale dei nuovi token creati dal VTT. Se il manifest non esiste o l'asset
non e' disponibile, il token procedurale resta come fallback.
