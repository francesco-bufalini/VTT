# Migrazione progressiva classi e sottoclassi: primo lotto

**Cataloghi per tipo**, non per origine. I benefici sono concessi da un
`granted_by.ref` 5eTools con nome/fonte canonica e classe/sottoclasse;
il motore non associa privilegi tramite descrizioni localizzate.

## Migrato in questa fase

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

## Ancora da migrare

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
