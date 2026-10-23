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
| XPHB | Second Wind 1 | Massimo dalla colonna 5etools; recupero parziale ancora in lista sotto. |
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

- **Second Wind XPHB:** recupera un solo uso al riposo breve e tutti al lungo.
  Il tracker attuale ha un solo tipo di recupero; attribuirgli `short_rest`
  restituirebbe erroneamente tutti gli usi. La progressione massima resta
  quella della tabella 5etools.
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

Per i lotti successivi, partire dalle altre classi e specie PHB/XPHB. Prima
di marcare una voce come automatica, verificare fonte/edizione, identità del
tratto, scelta attiva, progressione, recupero e compatibilità Android/PWA.
