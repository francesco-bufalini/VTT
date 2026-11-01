# Arricchimenti strutturati per origine (schema v2)

Questo è il **contratto di authoring** dei futuri JSON per singola classe, sottoclasse, specie,
sottorazza, talento, oggetto, background, incantesimo, optional feature, mostro o condizione.
La suddivisione fisica dei file segue l'**origine**; i tipi dei benefici rimangono universali.

> **Stato:** schemi, esempi e controlli di compatibilità **introdotti, non ancora collegati
> al runtime**. I dati attuali e la geometria in `assets/spell_area_geometry.json`
> continuano a essere usati dall'app e da Godot. Questo commit non migra né elimina i
> cataloghi correnti, non cambia i salvataggi e non rende automaticamente eseguibile un
> beneficio soltanto perché passa la validazione.

## Struttura dei file

Ogni documento contiene `schema_version: 2`, `category` ed `entries`. L'unità
di authoring consigliata è un **file per origine canonica** (non necessariamente un file
per ogni oggetto generato): `classes/barbarian.phb.json`,
`species/aasimar.mpmm.json`, `feats/sharpshooter.phb.json`,
`spells/fireball.phb.json`, ecc. Le sottoclassi/sottorazze possono stare in file
separati o nelle sezioni annidate `subclasses`/`subraces` dell'origine.

- [`origin.schema.json`](origin.schema.json): struttura comune `entries → features/options → benefits`.
  Schemi per categoria: `classes`, `subclasses`, `species`, `subraces`, `feats`,
  `items`, `backgrounds`, `spells`, `optional_features`, `monsters`, `conditions`.
- [`benefit.schema.json`](benefit.schema.json): **38 tipi di beneficio** con primitive
  riutilizzabili, composizione e requisiti condizionali. Un privilegio può avere
  tanti benefici indipendenti quanti ne servono.
- [`spell_geometry.schema.json`](spell_geometry.schema.json): `range`, `targeting`,
  `effect.geometry`, `effect.persistence` e tag dei danni/TS/condizioni; copre tutte le
  forme presenti nel catalogo esistente, comprese le varianti `wall` `path/circle/globe/panels/dome`.
- [`examples/`](examples/): casi rappresentativi di risorse, stati, OR di azioni,
  attacchi con competenza, modificatori indipendenti, scelte, homebrew, geometrie.
- [validatore](../../../scripts/validate_enrichment_authoring_schemas.py): verifica
  gli schemi Draft 2020-12, gli esempi e **ogni geometria attualmente nel catalogo**
  con `jsonschema`; in CI si esegue automaticamente quando cambiano questi file.

### Identità e testi

Il campo `ref` associa il record alla fonte: preferire un **ID 5eTools stabile**
oppure `name + source` più il contesto necessario (classe, sottoclasse, specie,
edizione/livello). `PHB` e `XPHB` sono identità distinte. **Non individuare
il privilegio con la sua traduzione visualizzata.**

`name` e `description` sono ammessi a livello di origine, tratto, opzione,
beneficio e oggetto generato, ma sono pensati **principalmente per l'homebrew**.
Per materiale ufficiale, la PWA deve ricavare nomi e descrizioni dai dati 5eTools;
i file di arricchimento forniscono soltanto le proprietà meccaniche non presenti
nel compendio. Il solo inserimento di `name` o `description` non implica che
il runtime li debba preferire rispetto a 5eTools.

`namespace` e `homebrew: true` permettono origini senza alcuna controparte 5eTools.
Questo formato non sostituisce il `homebrew/package.schema.json` v1 esistente:
l'adattatore/compilatore tra i due formati è lavoro successivo.

### Benefici e meccanismi

I `benefits[]` descrivono il *cosa* tramite `type`, senza codificare il nome
di una classe nel motore. Ogni beneficio può essere limitato da `requirements`,
`rules_version`, `min_level`, costi e sorgenti. `benefits[]` annidati,
`options[]` e `sequence.logic = "any" | "all"` consentono composizioni e
liste OR/AND di azioni, attacchi, tiri ed effetti. Il tipo di azione (`activation`)
e il consumo di una risorsa (`resource`/`cost`) restano proprietà distinte.

| Famiglie di benefici v2 | Dati attuali da ricondurre a queste famiglie |
| --- | --- |
| `action`, `activation`, `action_sequence`, `targeting` | `action_feature_overrides`, `feature_timing_recovery_rules.actions/contextual_actions/attack_actions` |
| `resource`, `tracker`, `resource_recovery`, `progression`, `scaling_die` | `class_resource_overrides`, `feature_timing_recovery_rules.recoveries`, `scaling_dice` |
| `attack`, `damage_bonus`, `damage_modifier`, `roll_bonus`, `roll_mode` | `roll_bonus_rules`, `species_attacks`, `species_conditional_bonuses`, `species_roll_modes`, feat mechanics |
| `numeric_modifier`, `ability_score`, `proficiency`, `language`, `sense`, `movement` | `class_numeric_feature_grants`, `ability_grants`, `proficiency_grants`, `sense_grants`, speed/skills |
| `defense`, `condition`, `state`, `effect`, `effect_extension` | `species_defenses`, `trait_states`, `effect_extensions`, `generic_item_variants` |
| `choice`, `option_selection`, `spell_selection`, `spellcasting`, `spell_slot` | `power_selections`, `optional_feature_progressions`, `spellcasting_benefits`, `class_spell_slot_profiles` |
| `spell_grant`, `item_grant`, `feat_grant`, `feature_grant`, `companion_grant` | `spell_grant_rules`, `feature_slot_spells`, `feature_item_grants`, `feature_feat_grants`, companion data |
| `area_geometry` e `entry.spell_geometry` | `assets/spell_area_geometry.json` |
| `entry.spell_runtime` | `vtt/enrichment/spells.json`: movimento AoE, punti di selezione, effetti visivi e spostamenti forzati |

Le primitive `bonus`, `attack`, `effect`, `proficiency`, `defense`,
`sequence`, `selection`, `spellcasting`, `grant` hanno definizioni ricorsive
all'interno di `benefit.schema.json`. Per i meccanismi già presenti ma poco
comuni è disponibile un payload `parameters` esplicito: **non** implica
supporto runtime generico o un interprete di regole arbitrario. Durante una
migrazione, un caso non ancora interpretabile deve rimanere segnalato, non essere
silenziosamente dichiarato automatizzato.

### Geometria degli incantesimi

L'entry di un incantesimo può avere `spell_geometry` direttamente, senza crearne
una falsa "capacità" aggiuntiva; `spell_runtime` conserva le informazioni operative
che oggi vivono in `vtt/enrichment/spells.json`. Esempi:
[`Fireball`](examples/spells/fireball.phb.json),
[`Wall of Fire`](examples/spells/wall-of-fire.phb.json),
[`Thunderwave`](examples/spells/thunderwave.phb.json).

`spell_geometry` usa **le stesse unità in feet e la stessa struttura**
(`range`, `targeting`, `effect`) del file utilizzato da Godot. Il test verifica
la compatibilità dello schema con ogni voce di quel file; *non* ha ancora
spostato i dati né modificato `vtt/spells/spell_area_catalog.gd`.

## Regole generali separate

Indebolimento (`Exhaustion`), economia generale delle azioni, calcolo dei TS,
regole base di progresso, funzioni di risoluzione bersagli/aree e logica dei
tracker **non sono proprietà di una classe** e non devono essere travasate
come privilegi inventati. Il vantaggio strutturale si ottiene separando:
origine → benefici dichiarati → motori generici → regole di sistema.

## Validazione

```sh
python -m pip install 'jsonschema==4.23.0'
python scripts/validate_enrichment_authoring_schemas.py
```

Il controllo verifica la sintassi e i vincoli dichiarati, non il contenuto
semantico dei manuali né l'equivalenza delle formule con il motore. L'integrazione
runtime richiederà un compilatore/normalizzatore che generi indici consultabili
per tipo di beneficio e le rispettive proiezioni; solo a quel punto sarà sicuro
eliminare i cataloghi precedenti.
