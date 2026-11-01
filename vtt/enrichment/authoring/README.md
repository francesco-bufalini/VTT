# Cataloghi dei benefici per tipo (schema v2)

## Scelta architetturale

**Un file JSON per tipo di beneficio**, con tutte le voci che lo concedono,
indipendentemente dalla classe, specie, talento, sottoclasse, oggetto,
background, incantesimo o mostro di provenienza. È una scelta intenzionale:
durante lo sviluppo bisogna poter scorrere e modificare tutti i benefici
di uno stesso tipo in **un solo punto**.

I file vivono sotto `vtt/enrichment/benefits/<tipo>.json` e sono convalidati
con `vtt/enrichment/authoring/<tipo>.schema.json`.
**Migrazione delle razze:** `roll_mode.json` (164 regole), `roll_bonus.json`
(23 bonus), `attack.json` (20 attacchi naturali) e `movement.json`
(10 limitazioni di volo con armatura) sono fonti attive della PWA.
Le velocità, le difese e le competenze già strutturate in 5eTools non
vengono duplicate nei supplementi.
I vecchi `pwa/catalog/species_roll_modes.json` e
`pwa/catalog/species_conditional_bonuses.json` e
`pwa/catalog/species_attacks.json` sono stati eliminati: il
modulo `pwa/species_benefit_catalogs.js` ricostruisce soltanto in memoria
l'interfaccia che i calcoli della scheda usano attualmente.
Gli altri cataloghi eterogenei rimangono da migrare; salvataggi e geometria
di Godot sono invariati.

### Un esempio: bonus ai tiri

```json
{
  "schema_version": 2,
  "benefit_type": "roll_bonus",
  "scope": "catalog",
  "entries": [{
    "id": "artificer:flash-of-genius:roll-bonus",
    "granted_by": {
      "kind": "5etools",
      "ref": {
        "category": "class_feature",
        "name": "Flash of Genius",
        "source": "TCE",
        "class_name": "Artificer",
        "class_source": "TCE"
      }
    },
    "benefit": {
      "type": "roll_bonus",
      "bonus": {
        "targets": ["ability_check", "saving_throw"],
        "ability_modifier": "int",
        "minimum": 1
      }
    }
  }]
}
```

Ogni `entries[]` indica **chi concede il beneficio** (`granted_by`) e
**cosa concede** (`benefit`), con ID stabili. L'identità canonica
può usare un ID 5eTools oppure `name + source` con il contesto appropriato,
come classe/sottoclasse e libro. Non usare traduzioni come chiavi. `PHB` e
`XPHB` sono origini diverse.

### Nessuna duplicazione dei dati già strutturati in 5eTools

La regola è **integrare, non ricopiare**:

- Se 5eTools **già specifica** una competenza, un linguaggio o altra
  informazione strutturata utilizzabile, non inserirla nuovamente nel catalogo.
- Se 5eTools **non la specifica**, si aggiunge nel file del tipo corrispondente
  (`proficiency.json`, `language.json`, `sense.json`, ecc.) con
  `granted_by.kind = "5etools"` e il riferimento al tratto che la concede.
- Un'origine homebrew usa `kind = "homebrew"`, un `namespace` e un
  identificatore stabile. `name` e `description` sono opzionali e
  pensati soprattutto per homebrew, non come copie della prosa dei manuali.
- In generale `merge = "augment"` (predefinito): integra i dati 5eTools
  anziché sovrascriverli. `merge = "replace"` è deliberato e richiede
  un'applicazione esplicita nel futuro normalizzatore.

### Benefici aggiunti manualmente dal giocatore

**La modifica manuale appartiene alla scheda del personaggio**, non a
un catalogo condiviso: il giocatore può aggiungere un bonus a un *singolo tratto*
di uno specifico personaggio. Viene usata la stessa forma dei benefici,
ma `scope = "character"`, `character_id` e
`granted_by.kind = "character_trait"`, con `trait_key` stabile.
È coerente con l'identità già utilizzata dall'editor PWA
(`feature:trait:<trait_key>`).

L'esempio [roll_bonus.character.json](examples/roll_bonus.character.json)
illustra come dichiarare **+2 a tutte le prove di caratteristica**
solo per quel tratto e quella scheda. L'esempio è un fixture, non una
regola ufficiale e **non viene inserito nei dati del compendio**.

Il formato v2 non implica cambiare ora la serializzazione o le funzioni
di salvataggio esistenti: una futura conversione userà le identità dei
record già salvati, senza duplicare né resettare i benefici manuali.

## Schemi e organizzazione

- [catalog.schema.json](catalog.schema.json): struttura dei file, riferimenti
  5eTools/homebrew/character, unicità dei grant e ambito dei dati.
- [benefit.schema.json](benefit.schema.json): campi condivisi dei benefici,
  tipi e primitive meccaniche riutilizzabili (azioni, sequenze OR/AND,
  modificatori, attacchi, stati, risorse, scelte e altro).
- **43 schemi di tipo** (`roll_bonus.schema.json`,
  `action_sequence.schema.json`, `proficiency.schema.json`, ecc.).
  Il nome del file deve coincidere con `benefit_type`, e ogni voce
  deve contenere `benefit.type` dello stesso tipo.
- [spell_geometry.schema.json](spell_geometry.schema.json): geometria
  di un incantesimo; memorizzabile come beneficio nel file comune
  `area_geometry.json`, **non in un file per incantesimo**.
- [legacy_sources.json](legacy_sources.json): inventario dei cataloghi
  correnti e relativi tipi di beneficio per guidare la migrazione;
  non è un duplicato dei loro contenuti.
- [examples](examples/): un esempio per ciascun tipo, oltre a quello
  `scope = "character"`; i fixture non sono regole attivate dall'app.

Le regole di sistema non attribuibili a un tratto, per esempio
`Exhaustion`, economia globale delle azioni e comportamento base dei
tracker, restano separate dai cataloghi dei benefici.

## Geometria e metadati degli incantesimi

Le voci `area_geometry.json` possono essere collegate al corrispondente
incantesimo 5eTools (`ref.category = "spell"` con nome e fonte canonici).
Il payload `benefit.spell_geometry` usa la struttura **già esistente**
`range`, `targeting`, `effect.geometry`. `benefit.spell_runtime`
può contenere i parametri di spostamento area, movimento forzato, scelta
del bersaglio ed effetti grafici attualmente in `vtt/enrichment/spells.json`.
Nel nuovo file si possono raccogliere, consultare e modificare insieme le
geometrie di tutti gli incantesimi. Non è stato spostato alcun dato,
né modificato `vtt/spells/spell_area_catalog.gd`.

## Validazione e limiti

```sh
python -m pip install 'jsonschema==4.23.0'
python scripts/validate_enrichment_authoring_schemas.py
```

La CI verifica i **43 schemi**, gli esempi per tipo, riferimenti e
differenziazione tra catalogo e modifica manuale, e la compatibilità dello
schema geometrico con tutte le **619 geometrie** correnti.
`legacy_sources.json` registra i cataloghi da migrare, ma **non è ancora
una migrazione**; le regole esistenti potrebbero contenere dettagli che
richiederanno una versione successiva dello schema. Perciò la validazione
dello schema non significa che ogni meccanica sia già automatizzata
o che i vecchi cataloghi possano essere cancellati.

L'importazione/normalizzazione v2 e la migrazione dei cataloghi (senza
duplicare concessioni esistenti di 5eTools né toccare benefici manuali)
sono un passaggio successivo.
