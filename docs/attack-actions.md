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
