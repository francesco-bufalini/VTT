# Azioni di attacco — modello strutturato

Una **azione di attacco** è una sequenza ordinata di attacchi o capacità concessi, distinta
dai singoli attacchi che generano tiri per colpire. I singoli tiri restano sempre
nella scheda **Attacchi** e continuano ad applicare i bonus ordinari.

## Schema

Una voce nel catalogo `feature_timing_recovery_rules.json`, alla chiave
`attack_actions`, è collegata al tratto che la concede tramite
`class_name`, `class_source`, `feature`, `min_level` e
`rules_version` (se specificato). L'azione dichiara:

- `id`, `name`, `time`: identità e costo di economia dell'azione
  (`action`, `bonus`, `reaction`, ecc.).
- `tracker_name`, `tracker_cost`: risorsa consumata facoltativamente.
  Il motore trova il tracker attivo della classe e ne detrae atomicamente il costo.
- `steps`: componenti ordinati, ciascuno con `selector` e `count`
  (ripetizioni, intero da 1 a 99).

### Selettori

- `{"id":"unarmed"}`: attacco concreto, con ID stabile.
- `{"category":"melee"}`: scelta fra gli attacchi della categoria.
- `{"category":"attack"}`: un attacco qualsiasi.
- `{"category":"crossbow"}`: attacchi con balestra.
- `{"category":"grapple"}`: prova di lotta quando esposta tra le azioni.
- `{"kind":"attack","name":"claw"}`: attacco nominato nel bestiario.
- `{"kind":"ability","name":"Frightful Presence"}`: capacità non rappresentata
  da un tiro per colpire; rimane componente della sequenza ma non aumenta
  `attacks_per_action`.

Le categorie vengono derivate dagli stessi metadati che descrivono il tiro:
`melee`, `weapon_type`, proprietà dell'arma, attacco senz'armi, ecc.
Le categorie sono un vocabolario di scelta, **non** nuovi modificatori per
i tiri: le prove e gli attacchi conservano i bonus del motore esistente.

### Esempio: Raffica di colpi (2014)

```json
{
  "id": "flurry-of-blows-2014",
  "class_name": "Monk",
  "class_source": "PHB",
  "rules_version": "2014",
  "min_level": 2,
  "feature": "Flurry of Blows",
  "time": "bonus",
  "tracker_name": "Ki Points",
  "tracker_cost": 1,
  "steps": [{ "selector": { "id": "unarmed" }, "count": 2 }]
}
```

### Esempio: Multiattacco generico

```json
{
  "time": "action",
  "steps": [{ "selector": { "category": "attack" }, "count": 2 }]
}
```

### Esempio: drago 2014

```json
{
  "time": "action",
  "steps": [
    { "selector": { "kind": "ability", "name": "Frightful Presence" }, "count": 1 },
    { "selector": { "kind": "attack", "name": "bite" }, "count": 1 },
    { "selector": { "kind": "attack", "name": "claw" }, "count": 2 }
  ]
}
```

I Multiattacchi importati da 5eTools conservano `entries` testuali. Alla
normalizzazione vengono aggiunti `attack_action` e i conteggi separati
`vtt_attack_sequence_count` e `vtt_special_sequence_count`. Gli ID dei
singoli attacchi rimangono invariati. Nel caso del drago ci sono **3 attacchi**
e **1 capacità speciale**, senza creare un quarto tiro per colpire.

Un homebrew che dichiara una `attack_action.steps` esplicita la rende
autorevole: non bisogna dedurre le operazioni dal testo. L'eventuale requisito
situazionale di una capacità rimane descritto dal tratto, senza assumere che
il motore possa determinarlo automaticamente.

## Interfaccia

Le Azioni di attacco non hanno gittata propria, pulsanti sulla mappa o tiri
per colpire autonomi: mostrano costo, tracker e sequenza. Sono raggruppate nella
sezione **Azioni di attacco** di Battaglia, mentre i singoli tiri rimangono
nella tabella **Attacchi**. L'uso della capacità detrae il tracker, ma
non presume che i singoli attacchi abbiano automaticamente colpito.


## Operazioni generiche e alternative OR

Il campo `steps` non è limitato agli attacchi. Ogni `selector` può essere di tipo `attack` (id/nome/categoria), `action` (id del catalogo, ad esempio `dash` e `disengage`), `check` (target `skill:perception` o `ability_check:str`) oppure `ability` (id di una capacità esistente).

Un passo `{ "one_of": [...] }` concede **esattamente una** delle alternative. Ogni alternativa ha un `id` stabile, un `selector`, un'etichetta `label` opzionale e un `tracker_cost` o `tracker_id` opzionale che **sostituisce**, senza sommare, il costo del privilegio.

### Azione Scaltra 2014

```json
{
  "id": "cunning-action-phb",
  "class_name": "Rogue",
  "class_source": "PHB",
  "rules_version": "2014",
  "feature": "Cunning Action",
  "min_level": 2,
  "time": "bonus",
  "steps": [
    {
      "one_of": [
        {
          "id": "dash",
          "label": "Scattare",
          "selector": {
            "kind": "action",
            "id": "dash"
          }
        },
        {
          "id": "disengage",
          "label": "Disimpegnarsi",
          "selector": {
            "kind": "action",
            "id": "disengage"
          }
        },
        {
          "id": "hide",
          "label": "Nascondersi",
          "selector": {
            "kind": "action",
            "id": "hide"
          }
        }
      ]
    }
  ]
}
```

### Azioni leggendarie

Il gruppo viene proiettato dalle voci `stat_block.legendary` senza elencare i nomi dei mostri nel motore. Il costo effettivo dipende dalla scelta, ad esempio:

```json
{
  "time": "legendary",
  "tracker_id": "legendary_actions",
  "steps": [
    {
      "one_of": [
        {
          "id": "detect",
          "selector": {
            "kind": "check",
            "target": "skill:perception"
          },
          "tracker_cost": 1
        },
        {
          "id": "tail",
          "selector": {
            "kind": "attack",
            "name": "Tail"
          },
          "tracker_cost": 1
        },
        {
          "id": "wing",
          "selector": {
            "kind": "ability",
            "name": "Wing Attack"
          },
          "tracker_cost": 2
        }
      ]
    }
  ]
}
```

Il motore valida la scelta prima di consumare la risorsa. Le prove usano il popup d20, i singoli attacchi la tabella Attacchi e le azioni generali i rispettivi handler. `repeat: "per_target"` indica che i tiri si ripetono per ogni bersaglio lecito, senza fissare il numero o tirare automaticamente. I requisiti situazionali rimangono documentati nel tratto fino alla disponibilità di predicati verificabili.
