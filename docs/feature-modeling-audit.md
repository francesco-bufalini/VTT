# Revisione dei privilegi 5etools

Questa lista avanza per identità **nome + fonte + classe/specie + livello**.
Una descrizione leggibile non equivale a un effetto automatico. Le progressioni
consumabili si aggiungono ai dati solo quando limiti e recupero sono verificati;
scelte, condizioni e bersagli restano espliciti finché il modello non li supporta.

## Lotto 2026-10-23: Fighter e Dwarf

Fonti confrontate: `vtt/data/player_5etools_catalog.json` (identità),
`vtt/data/creature_references_5etools.json` e
`vtt/data/compendium_features_5etools.json` (testo 5etools),
`vtt/data/class_mechanics_5etools.json` (colonne numeriche),
`vtt/data/proficiency_grants_5etools.json` (competenze) e FightClub5eXML
`class-fighter-phb.xml` (`feff31ac772456b42f4b55103718f7de5d98ca1e`)
e `races-phb.xml` (`3b311d741bca2af58eadbc8068431ef28eb5b05b`).
Le fonti PHB e XPHB non sono intercambiabili.

### Classe Fighter: 50 voci di catalogo controllate

| Fonte | Privilegio e livelli controllati | Esito dei dati |
| --- | --- | --- |
| PHB | Ability Score Improvement 4, 6, 8, 12, 14, 16, 19 | Scelta del personaggio; nessun incremento inventato. |
| PHB | Action Surge 2, 17 | Contatore Fight Club, recupero breve; identità del privilegio conservata. |
| PHB | Extra Attack 5, 11, 20 | Progressione distinta dalla risorsa consumabile. |
| PHB | Fighting Style 1 | Richiede l'opzione effettivamente scelta. |
| PHB | Indomitable 9, 13, 17 | Contatore Fight Club con recupero lungo corretto. |
| PHB | Martial Archetype 3; Martial Archetype feature 7, 10, 15, 18 | Segnaposto di selezione; gli effetti appartengono ai privilegi della sottoclasse. |
| PHB/TCE | Martial Versatility 4 | Sostituzione di una scelta, non bonus permanente. |
| PHB | Second Wind 1 | Contatore e attivazione già presenti. |
| XPHB | Ability Score Improvement 4, 6, 8, 12, 14, 16 | Scelta del personaggio. |
| XPHB | Action Surge 2, 17 | **Ora in `class_resource_overrides.json`**: 1/2 usi, recupero breve, stesso ID salvato. |
| XPHB | Indomitable 9, 13, 17 | **Ora in `class_resource_overrides.json`**: 1/2/3 usi, recupero lungo, stesso ID salvato. |
| XPHB | Second Wind 1 | Massimo dalla colonna 5etools; recupero di un uso al breve e di tutti al lungo nel dato `feature_timing_recovery_rules.json`. |
| XPHB | Extra Attack 5; Two Extra Attacks 11; Three Extra Attacks 20 | Progressione degli attacchi, non contatore. |
| XPHB | Fighting Style 1; Weapon Mastery 1 | Capacità/possibilità di scelta; solo le opzioni selezionate possono produrre effetti. |
| XPHB | Fighter Subclass 3; Subclass Feature 7, 10, 15, 18 | Segnaposto di selezione. |
| XPHB | Tactical Mind 2; Tactical Shift 5; Tactical Master 9; Studied Attacks 13 | Effetti condizionati al tiro, uso di Second Wind, movimento o proprietà dell'arma; vedere lista sotto. |
| XPHB | Epic Boon 19 | Scelta del talento, non bonus di classe generico. |

### Specie Dwarf: 11 voci di catalogo controllate

| Fonte | Tratto | Esito dei dati |
| --- | --- | --- |
| PHB | Darkvision | Descrizione presente; manca un modello sensoriale utilizzabile. |
| PHB | Dwarven Armor Training (Mountain) | Competenze light/medium nel dato strutturato della sottorazza. |
| PHB | Dwarven Combat Training | Quattro armi nel dato strutturato della razza. |
| PHB | Dwarven Resilience | Resistenza al veleno nel dato della razza; vantaggio contestuale separato sotto. |
| PHB | Dwarven Toughness (Hill) | Incremento PF per livello separato sotto. |
| PHB | Stonecunning | Competenza ed expertise solo per specifiche prove sulla pietra; separato sotto. |
| PHB | Tool Proficiency | Scelta fra tre strumenti nel dato strutturato della razza. |
| XPHB | Darkvision | Portata 120 piedi descritta; manca un modello sensoriale utilizzabile. |
| XPHB | Dwarven Resilience | Resistenza al veleno nel dato della specie; vantaggio condizionato separato sotto. |
| XPHB | Dwarven Toughness | Incremento PF per livello separato sotto. |
| XPHB | Stonecunning | Usi pari alla competenza e Tremorsense temporaneo condizionato; separato sotto. |

### Privilegi ancora fuori dal modello automatico

- **Tactical Mind, Tactical Shift, Tactical Master, Studied Attacks XPHB:**
  dipendono da esiti di tiri, consumo contestuale, movimento o proprietà di
  arma. Nessun bonus o pagamento automatico viene dedotto dal testo.
- **Dwarven Toughness PHB/XPHB:** +1 PF per livello richiede un valore che
  segua il livello *del personaggio* e l'origine esatta del tratto. Il
  proiettore dei bonus automatici dei tratti accetta solo numeri letterali.
- **Dwarven Resilience PHB/XPHB:** il vantaggio è limitato a precise salvezze
  contro veleno/Poisoned; la resistenza fissa già presente non implica
  vantaggio universale. La resistenza top-level è oggi associata all'origine
  razza/specie: va ricondotta all'identità del tratto Dwarven Resilience
  prima di considerare completa la modellazione dell'origine.
- **Stonecunning PHB/XPHB:** la versione 2014 richiede il contesto della prova
  History; quella 2024 richiede superficie di pietra, durata, senso temporaneo
  e usi. Non è un'expertise generale né un senso sempre attivo.
- **Darkvision PHB/XPHB:** la scheda mostra il testo, ma la VTT non applica
  ancora la visibilità secondo portata e illuminazione del tratto.

## Lotto 2026-10-23: contatori Paladin, Sorcerer e Wizard XPHB

Fonti: `creature_references_5etools.json` (voci `class_features` con identità
classe, fonte e livello), `class_mechanics_5etools.json` per i limiti tabellari,
e il supplemento FightClub5eXML PHB come confronto della vecchia edizione.
I tre privilegi qui sotto hanno testo 5etools che fissa limite e recupero;
il contatore non tenta di applicare la loro azione o scegliere bersagli.

| Classe e privilegio | Esito dei dati |
| --- | --- |
| Paladin XPHB, Lay on Hands 1 | Pool di 5 punti per **livello di Paladino**, riposo lungo. Venti passi numerici nel dato condiviso conservano l'ID `class:paladin:xphb:lay_on_hands` anche nel multiclasse. La versione PHB resta separata. |
| Sorcerer XPHB, Innate Sorcery 1 | Due usi, riposo lungo, con origine nel privilegio stesso. Il bonus alla CD e il vantaggio valgono soltanto durante l'attivazione, quindi non sono bonus permanenti. |
| Wizard XPHB, Arcane Recovery 1 | Un uso dopo un riposo breve, nuovamente disponibile dopo il lungo. Il contatore traccia l'uso, non decide quali slot recuperare. La versione PHB resta separata. |

Il recupero opzionale di Sorcerous Restoration XPHB (metà del livello di
Sorcerer, una volta per riposo lungo) è già nel dato separato
`feature_timing_recovery_rules.json`; non è un reset completo del contatore.

### Privilegi collegati ancora fuori dal modello automatico

- **Lay on Hands / Restoring Touch XPHB:** spendere un numero scelto di punti
  per curare o rimuovere Poisoned o altre condizioni richiede un bersaglio e
  una spesa contestuale. Il pool è tracciato, ma non viene scalato da una
  generica guarigione né da una condizione rimossa manualmente.
- **Innate Sorcery / Sorcery Incarnate / Arcane Apotheosis XPHB:** durata,
  attivazione, incantesimi del Sorcerer, Metamagia e pagamento alternativo in
  Sorcery Points sono condizioni d'uso, non bonus sempre attivi.
- **Arcane Recovery / Memorize Spell / Signature Spells XPHB:** recuperare slot
  scelti con un tetto cumulativo, cambiare un preparato o scegliere due
  incantesimi distinti richiede selezioni non rappresentate da un singolo
  contatore di classe.
- **Divine Sense / Abjure Foes XPHB:** sensi contestuali, bersagli, salvezze e
  condizioni non derivano in automatico dal contatore Channel Divinity.

## Lotto 2026-10-23: contatori Artificer TCE

Fonti: `creature_references_5etools.json` per Flash of Genius e
`subclass_features_5etools.json` per i tratti delle quattro specializzazioni.
Le nove definizioni erano duplicate in Godot e in due proiezioni PWA. Ora i
limiti provengono da `class_resource_overrides.json`, senza nuove eccezioni
per nomi di privilegio nel codice. Ogni voce conserva ID, sottoclasse e
recupero preesistenti; i valori `int_mod` usano il minimo di un uso.

| Privilegio e livello | Numero strutturato | Parte ancora esplicita |
| --- | --- | --- |
| Flash of Genius 7 | Modificatore INT, minimo 1; riposo lungo. | Reazione a prova/TS di creatura visibile entro 30 piedi. |
| Armorer: Defensive Field 3 | Competenza; riposo lungo. | Armatura Guardian, PF temporanei e rimozione quando si toglie l'armatura. |
| Alchemist: Experimental Elixir 3, 6, 15 | 1/2/3 elisir gratuiti per riposo lungo. | Elisir distinti, effetto casuale, durata e creazione extra con slot. |
| Alchemist: Restorative Reagents 9 | Usi gratuiti di Lesser Restoration pari a INT, minimo 1; riposo lungo. | PF temporanei quando si beve un elisir. |
| Alchemist: Chemical Mastery 15 | Un Heal e un Greater Restoration, ciascuno con il proprio contatore; riposo lungo. | Lancio concreto e bersaglio; resistenze/immunità sono effetti separati. |
| Artillerist: Eldritch Cannon 3 | Una creazione gratuita per riposo lungo. | Oggetto cannone, tipi, durata, comandi e creazione ulteriore con slot. |
| Battle Smith: Arcane Jolt 9 | Modificatore INT, minimo 1; riposo lungo. | Attacco idoneo, scelta danno/cura e massimo una volta per turno. |
| Armorer: Perfected Armor → Guardian 15 | Competenza; riposo lungo. | Tiro salvezza, movimento del bersaglio e attacco contestuale. Il modello Infiltrator è distinto. |

La tabella rappresenta solo **limiti numerici verificati**. Gli oggetti,
effetti, bersagli e pagamenti alternativi nella terza colonna restano nella
lista dei lavori fuori dal modello automatico; non vengono ricavati dal
contatore. In particolare Experimental Elixir non equivale a un inventario
di fiasche già create.

Per i lotti successivi, partire dalle altre classi e specie PHB/XPHB. Prima
di marcare una voce come automatica, verificare fonte/edizione, identità del
tratto, scelta attiva, progressione, recupero e compatibilità Android/PWA.
