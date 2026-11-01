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

---

## Classi e sottoclassi: primo lotto

**Cataloghi per tipo**, non per origine. I benefici sono concessi da un
`granted_by.ref` 5eTools con nome/fonte canonica e classe/sottoclasse;
il motore non associa privilegi tramite descrizioni localizzate.

### Benefici migrati

| Nuovo catalogo | Origine temporanea legacy | Regole |
| --- | --- | ---: |
| [`action.json`](action.json) | `vtt/data/action_feature_overrides.json` | 52 |
| [`roll_bonus.json`](roll_bonus.json) | `pwa/catalog/roll_bonus_rules.json` | 15 |

Sono incluse le varianti `PHB`/`XPHB`/`TCE`, i privilegi di sottoclasse
quali Rune Knight, Champion, Fey Wanderer, Samurai, Cavalier e Zealot,
e tutte le opzioni di attivazione precedentemente note. Ogni voce
contiene **una sola meccanica** e il riferimento al tratto 5eTools
che la concede. Le descrizioni originali rimangono nei dati di 5eTools.

`pwa/class_benefit_catalogs.js` proietta i nuovi cataloghi nella forma
dati già interpretata dalle azioni e dal sistema dei bonus ai tiri.
`sheet_rules.loadRuleCatalogs()` e `action_economy.loadFeatureActionOverrides()`
leggono ora i JSON tipizzati con fallback al file precedente **solo quando
il nuovo URL non è disponibile** su host vecchi. Un JSON v2 malformato
non viene sostituito silenziosamente con i dati legacy.

I vecchi file rimangono temporaneamente nel repository come sorgenti
di confronto per le regressioni e per i lettori non ancora migrati.
**Non aggiungere nuovi privilegi ai due cataloghi legacy**: usare i file
nuovi; una fase successiva rimuoverà le copie dopo aver verificato
tutti gli altri lettori e i generatori.

### Ancora da migrare nelle classi

- `feature_timing_recovery_rules.json`: attivazioni contestuali,
  recuperi, progressioni di attacchi e sequenze OR.
- `class_resource_overrides.json`: capienza delle risorse di classe.
- `trait_states.json`: stati e scelte di sottoclasse (le regole globali
  di Exhaustion devono rimanere fuori dai benefici).
- `spellcasting_benefits.json`, `optional_feature_progressions.json`,
  `power_selections.json`, `feature_item_grants.json` e altre
  meccaniche concesse dai privilegi.

Ogni lotto deve migrare la proiezione runtime e la validazione,
evitando di concedere nuove competenze, spell o altri benefici già
strutturati in 5eTools. Le modifiche manuali degli utenti rimangono
nella scheda e non vengono riscritte da questa migrazione.

---

## Razze: attacchi naturali e vincoli al volo

[attack.json](attack.json) contiene 20 attacchi naturali supplementari
ricavati esclusivamente in fase di build dai tratti 5eTools con meccanica
univoca. [movement.json](movement.json) aggiunge 10 vincoli all'uso della
velocità di volo quando si indossano armature medie o pesanti. Non si
duplicano le velocità o le competenze già strutturate in 5eTools.

Le voci identificano il privilegio `species_trait` e la fonte esatta.
`pwa/tools/species_mechanics.mjs` può rigenerare i file e la suite
verifica la parità con la precedente proiezione dei benefici.
La PWA utilizza `pwa/species_benefit_catalogs.js` come adattatore,
senza interpretare le descrizioni originali durante la partita.

Le capacità di `species_powers.json` restano da migrare; le
difese già strutturate in 5eTools non vanno semplicemente copiate
in un catalogo `defense.json`.
