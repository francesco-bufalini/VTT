# Migrazione background ai benefici per tipo — fase iniziale

## Scopo

Migrare **solo gli arricchimenti meccanici assenti dai dati strutturati di
5eTools** verso `vtt/enrichment/benefits/<tipo>.json`. Non creare un file
per background, non ripetere la sua prosa e non spostare le modifiche manuali
dalla scheda del personaggio ai dati condivisi.

## Verifica iniziale (1 novembre 2026)

| Fonte | Background / voci |
| --- | ---: |
| `5etools-mirror-3/5etools-src/data/backgrounds.json` | 175 |
| `vtt/data/compendium_backgrounds_5etools.json` | 168 |
| `vtt/data/proficiency_grants_5etools.json`, sezione background | 76 |
| `vtt/data/structured_ability_grants_5etools.json`, sezione background | 0 |
| `pwa/catalog/ability_grants.json`, sezione background | 0 |

Il divario tra gli indici locali e il mirror **non prova che il beneficio
manchi in 5eTools**. Per esempio Acolyte XPHB ha già nei dati 5eTools
`ability`, `feats`, `skillProficiencies` e `toolProficiencies`.
Il generatore o l'adattatore deve usare tali campi; non bisogna trasferirli
in `ability_score.json`, `feat_grant.json` o `proficiency.json` come
supplementi manuali.

Sette identità fonte+nome sono presenti nello snapshot upstream esaminato
ma non nel compendio locale:
`Discredited Neural Tuner|PL`, `Fabricated Mind|PL`,
`Initiate (Dissenter)|PSA`, `Mutated Commuter|PL`,
`Reconstructed Runaway|PL`, `Variant Noble (Retainers)|PHB`,
`Vizier (Dissenter)|PSA`. L'audit riporta le differenze senza
inventare contenuti o forzare importazioni incompatibili.

## Procedura riproducibile

```sh
python scripts/audit_background_benefits.py \
  --upstream /path/to/5etools-src/data/backgrounds.json \
  --output /tmp/background-benefits-audit.json
python -m unittest discover -s scripts -p test_background_benefit_migration.py
python scripts/validate_enrichment_authoring_schemas.py
```

L'audit identifica separatamente:
- campi strutturati già in 5eTools che mancano nei **nostri indici**;
- background non riconciliati per nome e fonte;
- supplementi nei file v2 potenzialmente sovrapposti a campi upstream.

I record `_copy` e `fromFeature` vanno risolti usando l'ereditarietà
5eTools: non vanno interpretati come benefici mancanti solo perché non hanno
i campi espliciti sulla singola voce.

## Stato

Questa fase introduce **classificazione, vincoli e test per l'importazione**.
Non ha ancora trasferito meccaniche non strutturate, aggiornato i lettori
runtime PWA o sostituito i cataloghi legacy. Le integrazioni verificate
saranno aggiunte ai file per tipo e testate con personaggi reali; prima
dell'attivazione, gli indici 5eTools locali devono essere rigenerati
dal generatore di origine, non modificati a mano.
