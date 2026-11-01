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

## Fase 2 — importazione strutturata dei background

Gli indici sono stati rigenerati dallo snapshot 5eTools contenente 175
background. Il catalogo delle competenze contiene ora **150** origini
background strutturate, incluso materiale 2024 di fonti diverse da XPHB.
Gli indici di caratteristica nativo e PWA contengono **74** background
con scelte `choose.weighted`.

La PWA ora interpreta entrambe le modalità senza hard-code di classe,
edizione o nome del background: +2/+1 su due caratteristiche distinte
oppure +1/+1/+1 su tre caratteristiche distinte. Le scelte rimangono
nell'identificatore `background|<source>|<name>`, per evitare collisioni
tra Acolyte PHB e Acolyte XPHB. Niente bonus automatico finché il player
non completa la selezione.

Le nuove opzioni non vengono scritte come override in
`vtt/enrichment/benefits/<tipo>.json`: provengono direttamente da campi
strutturati di 5eTools. I vecchi salvataggi e i benefici manuali del
personaggio non vengono modificati.

Rigenerazione mirata, senza toccare classi e specie:

```sh
python scripts/generate_proficiency_grants.py /path/to/5etools-src --backgrounds-only
python scripts/generate_structured_ability_grants.py /path/to/5etools-src --backgrounds-only
node pwa/tools/sync_native_catalogs.mjs --backgrounds-only
node --test pwa/tests/background_5etools_migration.test.mjs
```

Restano separati l'assegnazione automatica dei talenti iniziali
strutturati, la risoluzione completa dei background `_copy`/`fromFeature`
e i benefici specifici non strutturati: non devono essere simulati
leggendo o copiando la descrizione.

## Fase 3 — talenti iniziali referenziati da 5eTools

Gli 84 background del compendio locale che hanno riferimenti `feats`
espliciti nello snapshot 5eTools ora li conservano come campi **sorgente**
nello stesso compendio di 5eTools, non come voci ridondanti in
`vtt/enrichment/benefits/feat_grant.json`.

Durante il calcolo della scheda PWA, i talenti sono proiettati come
possessi **virtuali** identificati dalla fonte
`background|<source>|<name>`. Non si scrive `feats_catalog` nel salvataggio:
cambiare background ricalcola i talenti e rimuove automaticamente quelli
concessi dal vecchio, senza toccare i talenti manuali.

Le varianti strutturate come `Magic Initiate; Cleric` usano il catalogo
incantesimi 5eTools per scegliere la variante corretta (`Cleric Spells`).
Le scelte `anyFromCategory` non vengono assegnate in automatico: senza una
scelta esplicita del giocatore non si può determinare il talento.

```sh
python scripts/refresh_background_feat_refs.py /path/to/5etools-src
node --test pwa/tests/background_starting_feats.test.mjs
```

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
