# Tempi di attivazione e recuperi dei privilegi

I dati verificati (5etools, integrati da Fight Club 5e per i tracker)
sono conservati in `vtt/data/feature_timing_recovery_rules.json`.
Questi dati sono **curati offline**: né Godot né la PWA interpretano
le descrizioni testuali delle capacità per decidere il costo in azioni
o il trigger di un recupero.

## Schema

- `actions[]`: `class_name`, `class_source`, `min_level`,
  `subclass` opzionale, `feature`, `action_id`, `activation`,
  `tracker_name`, `priority`. Le alternative con `action_id` identico
  competono per priorità: per esempio Moon 2014 sostituisce l'indicazione
  di attivazione della forma selvatica base senza creare un nuovo tracker.
- `recoveries[]`: stessi requisiti di classe e origine, più `resource_name`,
  `event`, `mode` (`full`, `partial`, `optional_partial`),
  `amount` o `formula`, e `limit_per_long_rest` dove applicabile.
- Identità del tracker e massimo **rimangono** quelli provenienti
  dai dati strutturati delle classi; questo supplemento modifica solo
  l'attivazione o il recupero.

## Casi supportati

| Caso | Edizione | Semantica |
| --- | --- | --- |
| Wild Shape, Circle of the Moon | 2014 | bonus al livello 2; base azione |
| Wild Shape | 2024 | bonus dal livello 2 per ogni druido |
| Cunning Action (Dash, Disengage, Hide) | 2014 e 2024 | alternative bonus |
| Fast Hands, Thief | 2014 e 2024 | uso degli oggetti con bonus, soggetto alle opzioni dell'edizione |
| Vanish, Ranger | 2014 | Hide con bonus dal livello 14 |
| Font of Inspiration | 2014 e 2024 | Bardic Inspiration: recupero pieno al riposo breve dal livello 5 |
| Wild Shape, Druid | 2014 | recupero pieno al riposo breve |
| Rage, Channel Divinity, Wild Shape, Second Wind | 2024 | **un solo uso** al riposo breve, tutti al riposo lungo |
| Channel Divinity, Paladin | 2024 | **un solo uso** al riposo breve |
| Focus Points, Monk | 2024 | recupero pieno al riposo breve |
| Sorcerous Restoration | 2014 | +4 Sorcery Points al riposo breve, solo livello 20 |
| Sorcerous Restoration | 2024 | fino a metà livello punti, solo dopo riposo breve, scelta esplicita una volta per riposo lungo |

`optional_partial` non viene eseguito automaticamente:
un riposo breve imposta `resource_recovery_ready[id]` e la scelta
consuma `resource_recovery_used[id]`. Un riposo lungo cancella i due
indicatori. I campi sono salvati nella scheda e sopravvivono agli
export/import. La PWA espone il pulsante per scegliere il recupero;
Godot espone `StructuredResourceTrackers.optional_recovery_patch`
per le interfacce native.

I costi in azioni sono mostrati nella scheda **Cosa posso fare?**;
la presenza di una voce non implica l'applicazione automatica di una
trasformazione o il consumo implicito di una carica.

## Limiti deliberati

Non assegnare genericamente il costo di un incantesimo a bonus
per `Quickened Spell`: è una **scelta su uno specifico lancio** che
richiede un'opzione di metamagia selezionata, una spesa di punti e
regole sull'interazione fra incantesimi. Allo stesso modo `War Magic`
e vari attacchi aggiuntivi dipendono da eventi precedenti nel turno,
non da una sostituzione incondizionata del costo dell'attacco.
Non vanno abilitati dalle sole descrizioni.

Per estendere il catalogo:
1. verificare livello, edizione, origine, subclass e limitazioni
   nella fonte di riferimento;
2. aggiungere una riga strutturata con match esatto e test
   Godot/Node per casi positivi, negativi e riposi;
3. non mutare a runtime il massimo o l'identità dei tracker e
   non eseguire reset completi per recuperi descritti come «one use».

Fonti upstream:
- https://github.com/5etools-mirror-3/5etools-src/tree/main/data/class
- https://github.com/vidalvanbergen/fightclub5exml
