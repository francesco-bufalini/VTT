# Supplementi meccanici per tipo di beneficio

Questa cartella raccoglie **solo i benefici non già disponibili come campi
strutturati di 5eTools**, in un singolo catalogo `<tipo>.json` per meccanica.

Un background non possiede un file separato: ogni integrazione sarà una voce
nel catalogo pertinente (per esempio `proficiency.json`, `roll_bonus.json`,
`resource.json`), con `granted_by.kind = "5etools"` e
`ref = { "category": "background", "name": "...", "source": "..." }`.

## Prima di aggiungere una voce

1. Verificare `data/backgrounds.json` nel mirror 5eTools usato per il
   compendio. Competenze, talenti iniziali, caratteristiche, incantesimi
   aggiuntivi ed equipaggiamento spesso sono già espressi strutturalmente.
2. Se il campo c'è in 5eTools ma manca negli indici VTT/PWA, **correggere
   importatore o generatore**. Non duplicarlo in un supplemento.
3. Solo se la meccanica manca realmente in 5eTools, aggiungerla sotto il
   suo tipo con origine canonica `name + source`, senza copiare la prosa.
4. Le aggiunte manuali appartengono esclusivamente alla scheda del
   personaggio, `scope: character`, mai ai file condivisi.

Per classificare le differenze tra i dati upstream e gli indici locali:

```sh
python scripts/audit_background_benefits.py \
  --upstream /path/to/5etools-src/data/backgrounds.json \
  --output /tmp/vtt-background-audit.json
```

L'assenza di un file `<tipo>.json` significa che non è ancora stato
individuato un supplemento verificato per quel tipo; non significa che il
background non conceda quel beneficio. Le concessioni 5eTools restano la
fonte primaria. La migrazione del runtime non è ancora completata.
