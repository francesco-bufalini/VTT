# Revisione dei privilegi 5etools

Questa lista avanza per identità **nome + fonte + classe/specie + livello**.
Una descrizione leggibile non equivale a un effetto automatico. Le progressioni
consumabili si aggiungono ai dati solo quando limiti e recupero sono verificati;
scelte, condizioni e bersagli restano espliciti finché il modello non li supporta.
I casi aperti dei lotti controllati sono raccolti anche nella
[lista separata](feature-modeling-backlog.md), senza introdurre dati surrogati.

## Lotto 2026-10-25: sottorazze SCAG del 2014 senza ristampa

Verificate una per una le **9** voci `subrace` SCAG di Half-Elf (4),
Halfling (1) e Tiefling (4) in
[5etools `data/races.json`](https://github.com/5etools-mirror-3/5etools-src/blob/master/data/races.json)
(snapshot `cefd817691d5ace9adebb5521811943efc378bf0`): nessuna ha
`reprintedAs`. Confronto con [FightClub5eXML `races-scag.xml`](https://github.com/vidalvanbergen/FightClub5eXML/blob/master/Sources/DND_5e/WizardsOfTheCoast/03_Campaign_Settings/Sword_Coast_Adventurers_Guide/races-scag.xml)
(`3b44ff074706efa6e6f912e4cc1d1b2f17a8baa4`). L'XML espone i tratti
alternativi nello stesso blocco razza; il campo `_versions` di 5etools
specifica invece le scelte **mutuamente esclusive**. Nessun tratto SCAG va
trasferito automaticamente a una specie XPHB.

| Sottorazza SCAG e tratti | Esito |
| --- | --- |
| Half-Elf, Aquatic Elf Descent: Skill Versatility **oppure** Swim Speed | Due scelte esclusive; la velocità di nuoto non è una concessione a tutti gli Half-Elf. |
| Half-Elf, Drow Descent: Drow Magic **oppure** Skill Versatility | La magia (Dancing Lights; Faerie Fire dal 3; Darkness dal 5) e due abilità sono alternative. Il blocco di incantesimi e le abilità della sottorazza non vengono più esportati come concessioni incondizionate. |
| Half-Elf, Moon Elf or Sun Elf Descent: Cantrip **oppure** Elf Weapon Training **oppure** Skill Versatility | Trucchetto Wizard scelto, quattro competenze nelle armi o due abilità: esattamente una opzione. Rimossi i blocchi incondizionati di magia, armi e abilità. |
| Half-Elf, Wood Elf Descent: Elf Weapon Training **oppure** Fleet of Foot **oppure** Mask of the Wild **oppure** Skill Versatility | Quattro alternative; rimosse le competenze incondizionate nelle armi e nelle abilità. Velocità e Hide contestuale richiedono la scelta registrata. |
| Halfling, Ghostwise: Silent Speech | Telepatia a una creatura entro 30 piedi che condivide una lingua; nessuna competenza o magia automatica aggiunta. |
| Tiefling, Devil's Tongue: Appearance, Devil's Tongue | Sostituisce Infernal Legacy; il blocco magico specifico (Vicious Mockery, Charm Person di 2° livello, Enthrall) resta distinto e strutturato. Appearance è descrittivo. |
| Tiefling, Hellfire: Appearance, Hellfire | Sostituisce Hellish Rebuke con Burning Hands di 2° livello; mantiene Thaumaturgy e Darkness. Blocco magico SCAG distinto. |
| Tiefling, Infernal Legacy: Appearance | Conserva il pacchetto Infernal Legacy del Tiefling PHB; non è un nuovo potere da sommare. |
| Tiefling, Winged: Appearance, Winged | Volo 30 piedi solo senza armatura pesante, in sostituzione di Infernal Legacy. La velocità grezza presente nel catalogo non rappresenta ancora il vincolo contestuale. |

Il generatore delle competenze omette i tre pacchetti Half-Elf che una
versione alternativa annulla; quello degli incantesimi omette Drow Descent e
Moon/Sun Descent. Le identità delle sottorazze rimangono selezionabili nel
catalogo. Le opzioni effettivamente scelte, l'origine del singolo tratto e il
vincolo dell'armatura pesante rimangono nella lista separata; nessuna scelta è
stata simulata con dati fittizi.

**Copertura XPHB 2024 verificata:** tutte le 283 voci `class_features` delle
12 classi (210 coppie classe/tratto distinte) e tutti i 38 tratti delle 10
specie presenti nello snapshot locale 5etools. Questa è una revisione dei
dati, non una dichiarazione di automazione completa. I tratti PHB 2014
confrontati nei lotti sotto sono una selezione e proseguono separatamente.

## Lotto 2026-10-24: domini PHB 2014 senza ristampa

Il campo `reprintedAs` del 5etools sorgente (`data/class/class-cleric.json`,
`subclass` con `source=PHB` e `classSource=PHB`) manca per **Nature** e
**Tempest**; gli altri cinque domini PHB hanno una ristampa dichiarata.
Le voci duplicate con `classSource=XPHB` sono riferimenti di compatibilità,
non una nuova edizione di questi tratti. Sono state confrontate tutte le
**14 voci** `subclassFeature` PHB dei due domini con
`vtt/data/subclass_features_5etools.json` e FightClub5eXML
`class-cleric-phb.xml` (`0c1118e94e7ae1fb0b608b65b3513fdaf0c65d13`).
La nuova modellazione usa solo `feature_timing_recovery_rules.json`, con
classe, edizione, sottoclasse e **nome del tratto concedente** esatti.

| Dominio | Privilegio (livello) | Esito |
| --- | --- | --- |
| Nature | Nature Domain (1) | Intestazione e incantesimi di dominio nel sorgente; le concessioni magiche richiedono ancora l'origine del tratto e la selezione della sottoclasse. |
| Nature | Acolyte of Nature (1) | Cantrip da Druido e abilità scelti; nessuna scelta inventata. |
| Nature | Bonus Proficiency (1) | Armature pesanti; da attribuire al tratto, non a tutti i Chierici. |
| Nature | Channel Divinity: Charm Animals and Plants (2) | **Ora strutturati:** azione e consumo del pool Channel Divinity PHB. Bersagli, TS e durata restano manuali. |
| Nature | Dampen Elements (6) | **Ora strutturata:** reazione senza contatore. Resistenza valida solo per quell'istanza di danno. |
| Nature | Divine Strike (8; migliora al 14) | Danno una volta nel turno, tipo scelto e dado progressivo; non un bonus permanente. |
| Nature | Master of Nature (17) | **Ora strutturata:** azione bonus. Richiede creature ancora affascinate dal privilegio del dominio. |
| Tempest | Tempest Domain (1) | Intestazione e incantesimi di dominio nel sorgente; stessa cautela sulle concessioni. |
| Tempest | Bonus Proficiencies (1) | Armi marziali e armature pesanti; da attribuire al tratto della sottoclasse. |
| Tempest | Wrath of the Storm (1) | **Ora strutturata:** reazione collegata al contatore già presente (modificatore Saggezza, minimo uno, riposo lungo). Colpo scatenante, TS e danno restano manuali. |
| Tempest | Channel Divinity: Destructive Wrath (2) | **Ora strutturati:** intervento contestuale senza azione e consumo del pool Channel Divinity PHB; non un secondo contatore. |
| Tempest | Thunderbolt Strike (6) | Spinta facoltativa solo dopo danno da fulmine a creatura idonea; resta contestuale. |
| Tempest | Divine Strike (8; migliora al 14) | Danno da tuono una volta nel turno e dado progressivo; non un bonus permanente. |
| Tempest | Stormborn (17) | Volo pari alla velocità attuale solo fuori da interni e sotterranei; resta contestuale. |

La verifica PWA copre presenza del tratto e della sottoclasse, soglia di
livello, assenza nelle schede XPHB e collegamento al contatore condiviso.
Le parti che richiedono scelta, bersaglio o stato sono nella lista separata.

## Lotto 2026-10-24: Warlock SCAG The Undying, regole 2014

La sottoclasse `The Undying|Warlock|PHB|SCAG` non ha `reprintedAs` nel
5etools sorgente (`data/class/class-warlock.json`). SCAG è stato pubblicato
dopo il PHB, ma questa è la sua versione per le **regole 2014**. Confrontati
tutti i **5 privilegi** con `vtt/data/subclass_features_5etools.json` e
FightClub5eXML `class-warlock-scag.xml`
(`90df7e27adcb2a62fe4da065989c9c02bde2a36b`).

| Privilegio (livello) | Esito |
| --- | --- |
| The Undying (1) | Intestazione e lista di incantesimi ampliata; non equivale a incantesimi conosciuti automaticamente. |
| Among the Dead (1) | Concede *spare the dying*; il vantaggio contro malattie e la protezione dal bersagliamento dei non morti sono contestuali. |
| Defy Death (6) | **Ora strutturato:** un uso, riposo lungo, esattamente nel tratto SCAG. Il recupero PF richiede il successo al TS morte o la stabilizzazione di una creatura. |
| Undying Nature (10) | Respiro, sostentamento, riposo e invecchiamento particolari; nessun bonus numerico generico. |
| Indestructible Life (14) | **Ora strutturati:** un uso, riposo breve e azione bonus dal tratto SCAG. Guarigione e riattacco di parti del corpo restano contestuali. |

La proiezione PWA di una vecchia scheda con sottoclasse nel campo principale
ora conserva quella scelta nella classe locale, così i due contatori restano
legati a `The Undying` anziché sparire. L'ID dei contatori conserva il formato
esistente `class:warlock:phb:<privilegio>`; non c'è un gestore speciale per
questa sottoclasse.

## Lotto 2026-10-24: Battlerager, Long Death e Crown SCAG

Nessuna delle tre sottoclassi SCAG ha `reprintedAs` nel 5etools sorgente.
Controllate una per una le **20 voci** `subclassFeature` con classe PHB e
fonte SCAG contro FightClub5eXML: `class-barbarian-scag.xml`
(`074dce2361317ef74358e895bb9264aeeb0f5664`),
`class-monk-scag.xml` (`69f052b85b3b378e0fa455def347f55d701367eb`) e
`class-paladin-scag.xml` (`092b4a8d0bf78a198b597dca6ea1cff7dffffe0d`).

| Sottoclasse e privilegio (livello) | Esito |
| --- | --- |
| Battlerager: Path of the Battlerager (3) | Intestazione della sottoclasse. |
| Battlerager: Battlerager Armor (3) | Attacco bonus solo con armatura chiodata indossata e Ira attiva; danno da presa condizionato. Nessuna azione sempre disponibile. |
| Battlerager: Restriction—Dwarves Only (3) | Restrizione di ambientazione revocabile dal DM; nessun blocco automatico per tutte le campagne. |
| Battlerager: Reckless Abandon (6) | PF temporanei solo quando usa Reckless Attack durante Ira; terminano con Ira. |
| Battlerager: Battlerager Charge (10) | Dash come azione bonus solo durante Ira; non un'alternativa sempre attiva. |
| Battlerager: Spiked Retribution (14) | Danno al colpitore solo con armatura, Ira e capacità di agire. |
| Long Death: Way of the Long Death (3) | Intestazione della sottoclasse. |
| Long Death: Touch of Death (3) | PF temporanei al trigger 0 PF di una creatura entro 5 piedi. |
| Long Death: Hour of Reaping (6) | **Ora strutturata:** azione senza contatore, con origine nel tratto SCAG. Bersagli, TS e Frightened restano manuali. |
| Long Death: Mastery of Death (11) | Spende 1 Ki solo al trigger 0 PF; nessun nuovo pool. |
| Long Death: Touch of the Long Death (17) | Azione e spesa **scelta** da 1 a 10 Ki; un costo fisso sarebbe scorretto, quindi resta aperta. |
| Crown: Oath of the Crown (3) | Intestazione della sottoclasse. |
| Crown: Champion Challenge (3) | **Ora strutturati:** azione bonus e pool Channel Divinity PHB; scelta bersagli, TS e movimento restano manuali. |
| Crown: Channel Divinity (3) | Introduce due opzioni, non un pool aggiuntivo. |
| Crown: Oath Spells (3) | Incantesimi sempre preparati subordinati alla scelta di questo giuramento. |
| Crown: Tenets of the Crown (3) | Testo narrativo, nessun bonus numerico. |
| Crown: Turn the Tide (3) | **Ora strutturati:** azione bonus e stesso pool Channel Divinity; cura richiede ascolto, distanza e PF non oltre metà. |
| Crown: Divine Allegiance (7) | **Ora strutturata:** reazione; bersaglio vicino e trasferimento del danno senza riduzione restano contestuali. |
| Crown: Unyielding Spirit (15) | Vantaggio solo ai TS per evitare Paralyzed o Stunned. |
| Crown: Exalted Champion (20) | **Ora strutturati:** un uso per riposo lungo e azione dal tratto SCAG. Aura, vantaggi, resistenze e durata restano contestuali. |

Per `Oath of the Crown` è stata corretta la normalizzazione generica dei nomi
di sottoclasse in Godot: rimuove in ordine `Oath of` e `the`, così il dato
`Crown` corrisponde al nome completo già salvato senza eccezioni dedicate.

## Lotto 2026-10-24: Fighter XGE Samurai e Cavalier

Le due sottoclassi XGE, usate con Fighter PHB, non hanno `reprintedAs` nel
5etools sorgente. Controllate le **15 voci** `subclassFeature` (7 Samurai,
8 Cavalier) contro FightClub5eXML `class-fighter-xge.xml`
(`2f6c94111ea863648ecea2ece01b3df07685f579`). Il suo contatore esplicito
per Fighting Spirit conferma tre usi; per gli altri tre limiti si sono
confrontati il testo XML e la voce strutturata 5etools, senza inferire usi da
un titolo o da un'altra edizione.

| Sottoclasse e privilegio (livello) | Esito |
| --- | --- |
| Samurai (3) | Intestazione della sottoclasse. |
| Bonus Proficiency (3) | Abilità oppure lingua scelta; nessuna scelta precompilata. |
| Fighting Spirit (3) | **Ora strutturati:** 3 usi/riposo lungo e azione bonus del tratto XGE. Vantaggio e PF temporanei 5/10/15 richiedono stato e livello della classe. |
| Elegant Courtier (7) | Modificatore Saggezza sulla sola Persuasion e competenza in TS Saggezza, con sostituzione a scelta se già posseduta. |
| Tireless Spirit (10) | Recupera un uso di Fighting Spirit all'iniziativa **solo a zero**; non un reset completo. |
| Rapid Strike (15) | Un attacco aggiuntivo una volta nel turno solo rinunciando al vantaggio su un tiro idoneo. |
| Strength before Death (18) | **Ora strutturati:** 1 uso/riposo lungo e reazione del tratto XGE. Il turno extra al trigger 0 PF e i TS morte restano contestuali. |
| Cavalier (3) | Intestazione della sottoclasse. |
| Bonus Proficiency (3) | Abilità oppure lingua scelta. |
| Born to the Saddle (3) | Vantaggio e movimento solo nel contesto di cavalcare/cadere. |
| Unwavering Mark (3) | **Ora strutturato:** solo il limite dell'**attacco speciale** (modificatore Forza, minimo uno, riposo lungo), con origine nel tratto. Il marchio iniziale non consuma usi. |
| Warding Maneuver (7) | **Ora strutturati:** usi pari al modificatore Costituzione, minimo uno, riposo lungo, e reazione. Bersaglio vicino, arma/scudo, d8 alla CA e resistenza condizionale restano manuali. |
| Hold the Line (10) | Attacco di opportunità e velocità zero richiedono posizione, movimento e colpo reale. |
| Ferocious Charger (15) | Movimento in linea, colpo e TS per Prone, una volta nel turno. |
| Vigilant Defender (18) | Reazione speciale per opportunità su turni altrui; non è un contatore ordinario. |

`Unwavering Mark (Special Attack)` è il nome del contatore, mentre
`origin_feature` punta esattamente al tratto `Unwavering Mark`. Il testo del
marchio resta utilizzabile senza spendere quel contatore.

## Lotto 2026-10-24: Druid XGE Dreams e Shepherd

Entrambe le sottoclassi per Druid PHB sono senza `reprintedAs` nel 5etools
sorgente. Controllate le **11 voci** `subclassFeature` (5 Dreams, 6 Shepherd)
contro FightClub5eXML `class-druid-xge.xml`
(`f73f8113290da33348f2ab2a90e0a28b9d065e18`). L'XML contiene 19 passi
espliciti per il pool di Balm, dal livello da Druido 2 al 20: sono riportati
nei dati senza usare il livello totale del personaggio in multiclasse.

| Sottoclasse e privilegio (livello) | Esito |
| --- | --- |
| Dreams: Circle of Dreams (2) | Intestazione della sottoclasse. |
| Dreams: Balm of the Summer Court (2) | **Ora strutturato:** pool di d6 pari al livello da Druido, riposo lungo. Ogni uso spende un numero *scelto* di dadi fino a metà livello: nessuna falsa azione a costo fisso. |
| Dreams: Hearth of Moonlight and Shadow (6) | Sfera scelta all'inizio di un riposo, con bonus solo all'interno e limiti di copertura; non un +5 permanente. |
| Dreams: Hidden Paths (10) | **Ora strutturati:** usi pari a Saggezza (minimo uno), riposo lungo, due attivazioni sullo stesso pool: bonus per sé, azione per creatura consenziente toccata. Posizione e spazio libero restano manuali. |
| Dreams: Walker in Dreams (14) | **Ora strutturato:** un uso/riposo lungo. Incantesimo scelto dopo un riposo breve, destinazione speciale e fallimento non consumante restano aperti. |
| Shepherd: Circle of the Shepherd (2) | Intestazione della sottoclasse. |
| Shepherd: Speech of the Woods (2) | Lingua Silvano e comunicazione con bestie; attribuire la lingua al tratto esatto. |
| Shepherd: Spirit Totem (2) | **Ora strutturati:** un uso/riposo breve e azione bonus per evocare. Tipo di spirito scelto, aura, durata e spostamento del totem restano contestuali. |
| Shepherd: Mighty Summoner (6) | PF e attacchi delle creature evocate da propri incantesimi; non un bonus al Druido. |
| Shepherd: Guardian Spirit (10) | Cura a fine turno delle creature evocate dentro l'aura del totem. |
| Shepherd: Faithful Summons (14) | **Ora strutturato:** un uso/riposo lungo, ma attivazione solo al trigger 0 PF o Incapacitated involontario; creature e durata restano aperte. |

L'XML porta inoltre contatori espliciti per Spirit Totem e Faithful Summons;
per Hidden Paths e Walker in Dreams il limite è verificato sul testo di XML e
5etools. Il modello mantiene gli ID dei tratti e non trasforma la magia di
Shepherd in una capacità generica della classe.

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

## Lotto 2026-10-23: Elf PHB e XPHB

Diciannove identità di tratto controllate nel catalogo
`player_5etools_catalog.json`, con testo da
`creature_references_5etools.json`. L'Elf PHB e le tre sottorazze sono stati
confrontati con FightClub5eXML `races-phb.xml`
(`3b311d741bca2af58eadbc8068431ef28eb5b05b`). Il dato
`additional_spells_5etools.json` contiene le opzioni magiche delle stirpi
XPHB; la sua presenza non dimostra da sola che una scelta del personaggio
sia stata effettuata.

| Fonte e tratto | Esito dei dati |
| --- | --- |
| Elf PHB: Darkvision | Testo e portata di 60 piedi presenti; applicazione visiva alla mappa ancora fuori modello. |
| Elf PHB: Keen Senses | Perception fissa nel dato `proficiency_grants_5etools.json`; attribuzione al tratto da perfezionare. |
| Elf PHB: Fey Ancestry | Vantaggio limitato ai TS contro Charmed e immunità al sonno magico; non sono effetti generali contro tutti gli incantesimi. |
| Elf PHB: Trance | Riposo lungo in quattro ore nel testo; il tempo di riposo non è una competenza né un bonus passivo. |
| Drow PHB: Superior Darkvision | Portata 120 piedi; non va sommata ai 60 piedi del tratto base. |
| Drow PHB: Sunlight Sensitivity | Svantaggio dipendente da luce solare, bersaglio e percezione visiva; non permanente. |
| Drow PHB: Drow Magic | Dancing Lights; Faerie Fire dal livello 3 e Darkness dal 5, una volta al giorno. Blocchi per la sottorazza presenti in `additional_spells_5etools.json`. |
| Drow PHB: Drow Weapon Training | Rapier, shortsword, hand crossbow nel testo; competenze non presenti come concessione della sottorazza nell'indice strutturato. |
| High Elf PHB: Elf Weapon Training | Longsword, shortsword, shortbow, longbow nel testo; manca la concessione strutturata con origine nel tratto. |
| High Elf PHB: Cantrip | Scelta dalla lista Wizard con INT; blocco di scelta in `additional_spells_5etools.json`. |
| High Elf PHB: Extra Language | Scelta di una lingua nel testo; non va fissata automaticamente senza conoscere la lingua scelta. |
| Wood Elf PHB: Elf Weapon Training | Stesse quattro armi di High Elf, ma tratto della propria sottorazza; origine distinta. |
| Wood Elf PHB: Fleet of Foot | Velocità 35 piedi già nel dato della sottorazza 5etools. |
| Wood Elf PHB: Mask of the Wild | Nascondersi solo con specifico oscuramento naturale; non vantaggio universale a Stealth. |
| Elf XPHB: Darkvision | Portata base 60 piedi; la stirpe Drow la porta a 120 solo se scelta. |
| Elf XPHB: Elven Lineage | Scelta Drow/High/Wood, benefici ai livelli del **personaggio** 1/3/5 e capacità magica INT/WIS/CHA scelta. Blocchi di incantesimi presenti; selezione, velocità e sostituzione del cantrip richiedono stato esplicito. |
| Elf XPHB: Fey Ancestry | Vantaggio solo ai TS per evitare o terminare Charmed; diversa dalla versione PHB. |
| Elf XPHB: Keen Senses | Scelta di **una** fra Insight, Perception e Survival. Il generatore 5etools non trova un campo strutturato e l'indice delle competenze non ha una voce Elf XPHB. |
| Elf XPHB: Trance | Riposo lungo in quattro ore, coscienza mantenuta e impossibilità di dormire per magia. |

### Tratti Elf ancora fuori dal modello automatico

- **Keen Senses XPHB e addestramenti PHB:** esistono scelta e armi certe nel
  testo, ma l'indice delle competenze usa attualmente un'origine di razza o
  sottorazza. Occorre collegare una concessione strutturata al *tratto esatto*
  prima di automatizzarla; una nuova voce generica `Elf` perderebbe tale
  provenienza e potrebbe applicare tutte e tre le abilità della scelta.
- **Elven Lineage XPHB:** la scelta attiva, la capacità magica e le sostituzioni
  dopo riposo non possono essere dedotte dai soli blocchi di incantesimi.
  Darkvision migliorata e velocità Wood dipendono dalla stirpe scelta.
- **Sensi, Trance, Fey Ancestry, Sunlight Sensitivity e Mask of the Wild:**
  richiedono durata del riposo, condizioni, illuminazione o geometria della
  scena. Il testo visibile resta disponibile senza assegnare bonus universali.

## Lotto 2026-10-23: identità di tre contatori PHB

Confronto puntuale fra `class_resource_overrides.json`, i tratti
`subclass_features_5etools.json` e gli XML FightClub5eXML
`class-warlock-phb.xml` (`4c75c5ad0582229926886c3be5d50607427d1ce5`)
e `class-wizard-phb.xml` (`c25716183abd3b40ea089c297a9ad4a9584108b6`).
I limiti e il recupero breve coincidono; tre etichette di contatore XML non
sono i nomi dei tratti 5etools. Il dato ora esplicita alias XML, nome del
tratto e vecchia chiave persistita, senza migrare o perdere gli usi spesi.

| Classe/sottoclasse | XML FightClub | Tratto 5etools mostrato | ID conservato |
| --- | --- | --- | --- |
| Warlock PHB, The Fiend 6 | Dark One's Luck | Dark One's Own Luck | `class:warlock:phb:dark_one's_luck` |
| Wizard PHB, School of Illusion 10 | Illusory Step | Illusory Self | `class:wizard:phb:illusory_step` |
| Wizard PHB, School of Divination 10 | Third Eye | The Third Eye | `class:wizard:phb:third_eye` |

Restano fuori dal contatore: il dado da scegliere dopo il tiro di Dark One's
Own Luck, l'attacco specifico annullato da Illusory Self e la scelta fra le
quattro modalità temporanee di The Third Eye. I nomi corretti non trasformano
questi effetti contestuali in bonus passivi.

Dopo la correzione e i lotti Rogue/Ranger/Barbarian/Monk/Warlock, tutte le **60 definizioni di contatore** nel supplemento
si collegano per classe, fonte, sottoclasse e nome d'origine a un `classFeature`
o `subclassFeature` del catalogo 5etools locale. Questa verifica riguarda
l'identità del tratto; non prova da sola ogni limite numerico o l'effetto
dell'attivazione.

### Altri privilegi Artificer TCE da trattare separatamente

- **Magic Item Adept / Savant / Master (10/14/18):** il limite di sintonia
  sale a 4/5/6. L'app ha ancora tre eccezioni di codice che selezionano il
  beneficio più alto; tre bonus numerici indipendenti sommati nei dati
  darebbero un valore sbagliato. Serve una progressione strutturata che
  sostituisca il limite precedente e conservi l'origine del tratto attivo.
- **Soul of Artifice (20):** il bonus ai salvataggi dipende dal numero di
  oggetti *attualmente* in sintonia. Un numero fisso nel catalogo sarebbe
  scorretto; l'effetto dinamico resta da modellare in modo generico.
- **Spell-Storing Item (11) e Magical Tinkering (1):** oggetto concreto,
  effetto scelto, portatore e capacità non sono un contatore di classe
  consumabile; richiedono identità e stato dei singoli oggetti.

## Lotto 2026-10-23: Rogue XPHB

Controllate tutte le **32 voci** del catalogo `class_features` Rogue XPHB
(25 nomi distinti, inclusi i livelli ripetuti). La versione PHB di Stroke of
Luck è nel supplemento FightClub5eXML
`class-rogue-phb.xml` (`0b8a42809ecfc061182437856d8c3e42eae80078`);
il testo XPHB in `creature_references_5etools.json` conferma un uso dal
livello 20 e recupero breve/lungo. Il nuovo passo XPHB è separato dal PHB,
con ID `class:rogue:xphb:stroke_of_luck`.

| Privilegio XPHB | Esito della verifica |
| --- | --- |
| Expertise 1, 6 | Due scelte di competenza per ciascun livello; non assegnare abilità consigliate come scelte effettive. |
| Sneak Attack 1 | Progressione dei dadi e condizioni di attacco; non è un pool da recuperare. |
| Thieves' Cant 1 | Linguaggio speciale e un'altra lingua scelta; scelta da conservare. |
| Weapon Mastery 1 | Due tipi d'arma scelti; capacità, non usi. |
| Cunning Action 2 | Dash, Disengage o Hide come azione bonus; nessun contatore. |
| Rogue Subclass 3 | Segnaposto della sottoclasse scelta. |
| Steady Aim 3 | Vantaggio sul successivo attacco solo se non si è mossi; velocità a zero dopo l'uso. |
| Ability Score Improvement 4, 8, 10, 12, 16 | Scelta di talento/incremento, non bonus automatico uguale per tutti. |
| Cunning Strike 5 | Opzioni pagate rinunciando a dadi di Sneak Attack nello stesso colpo. |
| Poison (Cost: 1d6) 5 | Salvezza CON, Poisoned, ripetizione del TS; costo contestuale. |
| Trip (Cost: 1d6) 5 | Taglia e salvezza DES prima di Prone. |
| Uncanny Dodge 5 | Reazione dopo essere colpiti da attaccante visibile; danno dimezzato contestualmente. |
| Withdraw (Cost: 1d6) 5 | Movimento immediato senza attacchi di opportunità; costo contestuale. |
| Evasion 7 | Esito del TS DES e condizioni d'uso; non bonus numerico universale. |
| Reliable Talent 7 | Soglia del d20 soltanto alle prove con competenza. |
| Subclass Feature 9, 13, 17 | Segnaposto: gli effetti appartengono ai tratti della sottoclasse reale. |
| Improved Cunning Strike 11 | Fino a due effetti pagati separatamente sullo stesso Sneak Attack. |
| Daze (Cost: 2d6) 14 | Salvezza CON e limitazione delle opzioni del turno. |
| Devious Strikes 14 | Sblocca le tre opzioni successive, senza risorsa autonoma. |
| Knock Out (Cost: 6d6) 14 | Salvezza CON e Unconscious con ripetizione del TS. |
| Obscure (Cost: 3d6) 14 | Salvezza DES e Blinded temporaneo. |
| Slippery Mind 15 | Competenze ai TS Saggezza e Carisma nel testo; origine del tratto da conservare. |
| Elusive 18 | Nega vantaggio agli attacchi contro il Rogue salvo Incapacitated. |
| Epic Boon 19 | Scelta del talento. |
| Stroke of Luck 20 | **Ora nei dati condivisi:** un uso, recupero breve, fonte XPHB distinta. La sostituzione del risultato del D20 Test resta contestuale. |

I costi di Cunning Strike sono dadi di danno rinunciati durante un singolo
attacco, non una risorsa accumulata. Le opzioni con salvezza, condizione,
durata o bersaglio restano nella lista dei privilegi non automatizzati; non
vengono trasformate in contatori generici.

## Lotto 2026-10-23: Ranger XPHB

Controllate le **23 voci** del catalogo `class_features` Ranger XPHB
(18 nomi distinti). Il testo 5etools distingue gli usi limitati di
**Tireless: Temporary Hit Points** dal suo secondo effetto, la riduzione
di Exhaustion al riposo breve. Il dato aggiunge soltanto il primo contatore,
con origine `Tireless`; Nature's Veil ha il proprio contatore. Entrambi
usano il modificatore WIS con minimo un uso e recupero lungo.

| Privilegio XPHB | Esito della verifica |
| --- | --- |
| Favored Enemy 1 | Lanci gratuiti di Hunter's Mark con capacità nella tabella 5etools; scelta/lancio di incantesimo, non un nuovo contatore generico. |
| Spellcasting 1 | Slot e preparazione restano nel modello degli incantesimi. |
| Weapon Mastery 1 | Due tipi di arma scelti e sostituibili al riposo lungo. |
| Deft Explorer 2 | Scelta di Expertise e di due lingue. |
| Fighting Style 2 | Scelta di talento. |
| Ranger Subclass 3 | Segnaposto della sottoclasse scelta. |
| Ability Score Improvement 4, 8, 12, 16 | Scelta del talento/incremento. |
| Extra Attack 5 | Capacità di attaccare due volte, non usi consumabili. |
| Roving 6 | Velocità condizionata all'armatura e modi di movimento. |
| Subclass Feature 7, 11, 15 | Segnaposto: gli effetti sono dei tratti della sottoclasse reale. |
| Expertise 9 | Due abilità scelte fra quelle già competenti. |
| Tireless 10 | **Ora nel dato:** usi dell'azione per PF temporanei pari a WIS, minimo 1; il decremento di Exhaustion al riposo breve è separato. |
| Relentless Hunter 13 | Concentrazione su Hunter's Mark non interrotta dal danno; effetto condizionato. |
| Nature's Veil 14 | **Ora nel dato:** usi pari a WIS, minimo 1; Invisible fino alla fine del turno successivo resta un effetto da applicare all'attivazione. |
| Precise Hunter 17 | Vantaggio contro il bersaglio attualmente marcato da Hunter's Mark. |
| Feral Senses 18 | Blindsight 30 piedi; modello sensoriale della mappa ancora distinto. |
| Epic Boon 19 | Scelta del talento. |
| Foe Slayer 20 | Dado di Hunter's Mark che passa a d10; non bonus generale ai danni. |

Restano fuori dal contatore: effetto e durata di Nature's Veil, tiro e
applicazione dei PF temporanei di Tireless, riduzione di Exhaustion al
riposo breve, scelte di competenza/arma e condizioni legate a Hunter's Mark.
Nessuna di queste viene dedotta dal numero di usi salvati.

Per i lotti successivi, partire dalle altre classi e specie PHB/XPHB. Prima
di marcare una voce come automatica, verificare fonte/edizione, identità del
tratto, scelta attiva, progressione, recupero e compatibilità Android/PWA.

## Lotto 2026-10-24: Barbarian, Monk e Warlock XPHB

Verificate una per una le **79 voci** `class_features` delle tre classi
(Barbarian 26, Monk 34, Warlock 19; rispettivamente 20, 29 e 11 nomi
distinti). La tabella di classe 5etools contiene già le capacità di **Rages**
e **Focus Points**, mentre Pact Magic resta nel modello degli incantesimi.
Nel supplemento sono stati aggiunti solo tre usi giornalieri con un tratto
concedente esatto: `Persistent Rage`, `Uncanny Metabolism` e `Magical Cunning`.
I tre contatori registrano l'attivazione; non applicano automaticamente
recupero di altre risorse, cura o effetti in combattimento.

| Barbarian XPHB (livello) | Esito |
| --- | --- |
| Rage (1) | Capacità Rages e Rage Damage già nella tabella XPHB; un uso rientra al riposo breve, tutti al lungo. Il recupero parziale e le condizioni di mantenimento restano da modellare. |
| Unarmored Defense (1) | CA 10 + DES + COS solo senza armatura; scudo consentito. Non è un bonus di CA incondizionato. |
| Weapon Mastery (1) | Due tipi d'arma scelti, capacità progressiva già in tabella; mantenere la scelta. |
| Danger Sense (2) | Vantaggio ai TS DES salvo Incapacitated; condizione da valutare al tiro. |
| Reckless Attack (2) | Scelta al primo attacco del turno e vantaggi reciproci temporanei. |
| Barbarian Subclass (3) | Segnaposto; gli effetti appartengono ai tratti della sottoclasse scelta. |
| Primal Knowledge (3) | Competenza in un'abilità scelta; sostituzione della caratteristica per prove specifiche mentre Rage è attiva. |
| Ability Score Improvement (4, 8, 12, 16) | Scelta di talento/incremento, nessun effetto comune da assegnare. |
| Extra Attack (5) | Due attacchi nell'azione Attack, non due usi. |
| Fast Movement (5) | Velocità condizionata all'assenza di armatura pesante. |
| Subclass Feature (6, 10, 14) | Segnaposto, nessun privilegio di classe generico da assegnare. |
| Feral Instinct (7) | Vantaggio all'iniziativa, non contatore. |
| Instinctive Pounce (7) | Movimento durante l'azione bonus che avvia Rage. |
| Brutal Strike (9) | Rinuncia contestuale al vantaggio di Reckless Attack, danno extra e opzione d'effetto sul colpo. |
| Relentless Rage (11) | TS COS quando si scende a 0 PF durante Rage; CD crescente dopo gli usi e azzerata al riposo breve/lungo, non usi fissi. |
| Improved Brutal Strike (13, 17) | Opzioni aggiuntive, poi dado di danno maggiore e due effetti distinti per colpo. |
| Persistent Rage (15) | **Dato aggiunto:** un'attivazione al tiro di iniziativa per recuperare gli usi Rage, recupero del privilegio al riposo lungo; recupero di Rage e durata restano da applicare. |
| Indomitable Might (18) | Soglia del totale di prova/TS Forza rispetto al punteggio di Forza. |
| Epic Boon (19) | Scelta del talento. |
| Primal Champion (20) | Aumento di Forza e Costituzione con tetto specifico; non una risorsa. |

| Monk XPHB (livello) | Esito |
| --- | --- |
| Bonus Unarmed Strike (1) | Colpo senz'armi come azione bonus; economia delle azioni. |
| Dexterous Attacks (1) | DES alternativa a FOR per attacchi/danni e CD di Grapple/Shove, solo nei casi descritti. |
| Martial Arts (1) | Definizione delle armi ammesse e relative regole, non pool. |
| Martial Arts Die (1) | Dado progressivo dalla tabella di classe; non effetto universale ai danni. |
| Unarmored Defense (1) | CA 10 + DES + SAG solo senza armatura né scudo. |
| Flurry of Blows (2) | Un Focus Point per due colpi; usare il pool comune `Monk's Focus`. |
| Monk's Focus (2) | Focus Points progressivi già in tabella XPHB, recupero breve/lungo; CD dei TS derivata da SAG e competenza. |
| Patient Defense (2) | Disengage gratuito come azione bonus oppure Focus Point per Disengage e Dodge; scelta contestuale. |
| Step of the Wind (2) | Dash gratuito come azione bonus oppure Focus Point per Dash, Disengage e salto; scelta contestuale. |
| Unarmored Movement (2) | Velocità progressiva condizionata a niente armatura/scudo. |
| Uncanny Metabolism (2) | **Dato aggiunto:** un uso per riposo lungo al tiro d'iniziativa; Focus Points e PF recuperati restano effetti separati. |
| Deflect Attacks (3) | Reazione a un colpo e riduzione del danno; eventuale reindirizzamento spende Focus solo se il danno scende a zero. |
| Monk Subclass (3) | Segnaposto della sottoclasse scelta. |
| Ability Score Improvement (4, 8, 12, 16) | Scelta di talento/incremento. |
| Slow Fall (4) | Reazione alla caduta e riduzione del danno in base al livello. |
| Extra Attack (5) | Due attacchi nell'azione Attack. |
| Stunning Strike (5) | Un Focus Point, massimo una volta per turno, TS ed esiti diversi su successo/fallimento. |
| Empowered Strikes (6) | Tipo di danno scelto per il colpo senz'armi. |
| Subclass Feature (6, 11, 17) | Segnaposto; origine nella sottoclasse effettiva. |
| Evasion (7) | Danno dipendente dall'esito del TS DES e dall'assenza di Incapacitated. |
| Acrobatic Movement (9) | Movimento su superfici/liquidi durante il turno, condizionato all'equipaggiamento. |
| Heightened Focus (10) | Modifica le tre opzioni che spendono Focus, senza creare un nuovo pool. |
| Self-Restoration (10) | Rimozione di una condizione ammessa a fine turno; esenzione specifica da Exhaustion. |
| Deflect Energy (13) | Allarga i tipi di danno di Deflect Attacks, senza duplicarne il tratto. |
| Disciplined Survivor (14) | Competenza a tutti i TS e ritentativo dopo fallimento pagando Focus. |
| Perfect Focus (15) | Recupero condizionato all'iniziativa soltanto se Uncanny Metabolism non è usato e Focus è a 3 o meno. |
| Superior Defense (18) | Tre Focus Points e resistenza temporanea con durata/interruzione. |
| Epic Boon (19) | Scelta del talento. |
| Body and Mind (20) | Aumento di DES e SAG con tetto specifico. |

| Warlock XPHB (livello) | Esito |
| --- | --- |
| Eldritch Invocation Options (1) | Elenco di opzioni, non concessione di tutte le invocazioni. |
| Eldritch Invocations (1) | Scelte progressive con prerequisiti, sostituzione e divieto di duplicati salvo eccezioni. |
| Pact Magic (1) | Slot e incantesimi nel modello magico, non nuovo contatore di privilegio. |
| Magical Cunning (2) | **Dato aggiunto:** un rito per riposo lungo; il recupero di slot Pact Magic fino a metà del massimo (arrotondato in alto) resta separato. |
| Warlock Subclass (3) | Segnaposto della sottoclasse effettiva. |
| Ability Score Improvement (4, 8, 12, 16) | Scelta di talento/incremento. |
| Subclass Feature (6, 10, 14) | Segnaposto, non effetto generico di classe. |
| Contact Patron (9) | `Contact Other Plane` sempre preparato e lancio gratuito specifico una volta per riposo lungo; appartiene al flusso incantesimi. |
| Mystic Arcanum (11, 13, 15, 17) | Quattro scelte di incantesimo di livelli diversi e lanci gratuiti distinti; non pool condiviso. |
| Epic Boon (19) | Scelta del talento. |
| Eldritch Master (20) | Cambia quanti slot recupera Magical Cunning, non aggiunge un uso. |

### Da modellare separatamente

- Recuperi **parziali** di Rage al riposo breve e recupero in iniziativa da
  Persistent Rage, con le condizioni e la durata di Rage.
- Incremento e azzeramento della CD di Relentless Rage fra i riposi; effetti
  temporanei e scelte sul colpo di Reckless Attack e Brutal Strike.
- Spesa contestuale di Focus Points e applicazione di colpi, TS, condizioni e
  riduzioni del danno; guarigione/ricarica di Uncanny Metabolism e soglia di
  Perfect Focus. Il contatore giornaliero da solo non li simula.
- Ripristino dei Pact Magic slot da Magical Cunning (inclusa la modifica di
  Eldritch Master), invocazioni scelte, Contact Patron e Mystic Arcanum nel
  modello degli incantesimi. Nessun lancio gratuito è stato trasformato in
  un privilegio generico o attribuito alla classe anziché al tratto.

## Lotto 2026-10-24: Cleric e Druid XPHB

Controllate tutte le **45 voci** `class_features` (Cleric 22, Druid 23).
`Channel Divinity` e `Wild Shape` hanno già capacità progressive nelle
rispettive tabelle XPHB. I due tratti recuperano **un** uso al riposo breve e
tutti al lungo: un contatore con il solo `reset: short_rest` perderebbe tale
distinzione, quindi non è stato aggiunto un duplicato nel supplemento.

| Cleric XPHB (livello) | Esito |
| --- | --- |
| Divine Order (1) | Una scelta fra Protector e Thaumaturge; mai concedere entrambe. |
| Protector (1) | Competenza con armi marziali e armatura pesante solo se l'opzione è scelta. |
| Spellcasting (1) | Trucchetti, incantesimi preparati e slot nella tabella/nel modello magico. |
| Thaumaturge (1) | Trucchetto extra scelto e bonus a prove Arcana/Religion, con minimo +1, solo se scelta. |
| Channel Divinity (2) | Pool progressivo già in tabella; scelta di effetto al consumo e recupero parziale breve. |
| Divine Spark (2) | Un'opzione di Channel Divinity: cura o danno con scelta di tipo, TS e dado; nessun pool proprio. |
| Turn Undead (2) | Un'opzione dello stesso pool: bersagli Undead, TS, condizioni e durata. |
| Cleric Subclass (3) | Segnaposto della sottoclasse scelta. |
| Ability Score Improvement (4, 8, 12, 16) | Scelta di talento/incremento. |
| Sear Undead (5) | Danno aggiuntivo ai bersagli che falliscono il TS contro Turn Undead; usa lo stesso evento. |
| Subclass Feature (6, 17) | Segnaposto dei tratti reali di sottoclasse. |
| Blessed Strikes (7) | Scelta esclusiva fra Divine Strike e Potent Spellcasting. |
| Divine Strike (7) | Danno una volta per turno solo su colpo con arma; scelta fra Necrotic e Radiant. |
| Potent Spellcasting (7) | SAG aggiunta al danno dei trucchetti Cleric, se questa opzione è scelta. |
| Divine Intervention (10) | Lancio di un incantesimo Cleric idoneo senza slot/materiali una volta per riposo lungo; deve restare legato al flusso incantesimi. |
| Improved Blessed Strikes (14) | Migliora solo l'opzione Blessed Strikes effettivamente scelta. |
| Epic Boon (19) | Scelta del talento. |
| Greater Divine Intervention (20) | Apre Wish tramite Divine Intervention e impone recupero dopo 2d4 riposi lunghi in quel caso; non è un uso separato fisso. |

| Druid XPHB (livello) | Esito |
| --- | --- |
| Druidic (1) | Linguaggio speciale, messaggi e `Speak with Animals` sempre preparato; il testo non concede un lancio gratuito generico. |
| Magician (1) | Trucchetto extra scelto e bonus Arcana/Nature, con minimo +1, solo se scelta. |
| Primal Order (1) | Una scelta fra Magician e Warden. |
| Spellcasting (1) | Trucchetti, preparazione e slot del modello magico. |
| Warden (1) | Competenza con armi marziali e armatura media solo se scelta. |
| Wild Companion (2) | `Find Familiar` tramite slot oppure un uso Wild Shape; entrambi i costi dipendono dalla scelta attiva. |
| Wild Shape (2) | Pool progressivo già in tabella, recupero parziale breve; forme conosciute, limiti CR/volo, PF temporanei e sostituzione delle statistiche richiedono modello della trasformazione. |
| Druid Subclass (3) | Segnaposto della sottoclasse scelta. |
| Ability Score Improvement (4, 8, 12, 16) | Scelta di talento/incremento. |
| Wild Resurgence (5) | Conversione slot→uso Wild Shape solo quando gli usi sono zero; conversione inversa per slot di livello 1 una volta per riposo lungo. Due operazioni diverse, non ricarica automatica. |
| Subclass Feature (6, 10, 14) | Segnaposto dei tratti della sottoclasse reale. |
| Elemental Fury (7) | Scelta esclusiva fra Potent Spellcasting e Primal Strike. |
| Potent Spellcasting (7) | SAG ai danni dei trucchetti Druid, se scelta. |
| Primal Strike (7) | Danno elementale una volta per turno su colpo con arma o attacco Beast durante Wild Shape. |
| Improved Elemental Fury (15) | Aumenta gittata dei trucchetti oppure dado di Primal Strike secondo la scelta precedente. |
| Beast Spells (18) | Permette incantesimi in Wild Shape con eccezioni per componenti materiali costosi/consumati. |
| Epic Boon (19) | Scelta del talento. |
| Archdruid (20) | Un uso Wild Shape all'iniziativa solo se a zero; conversione Wild Shape→slot una volta per riposo lungo con valore per uso; longevità. Non modifica indiscriminatamente il pool. |

Restano nella lista separata: recupero parziale dei due pool; scelta e
applicazione delle opzioni di Channel Divinity; scelte Divine Order, Blessed
Strikes, Primal Order ed Elemental Fury; trasformazioni Wild Shape; conversioni
di Wild Resurgence/Archdruid; Divine Intervention con selezione di incantesimo
e recupero variabile dopo Wish. La sola presenza del testo 5etools non
autorizza contatori o effetti fittizi.

## Lotto 2026-10-24: Gnome e Halfling PHB/XPHB

Controllate le **otto voci di specie** del catalogo 5etools: quattro basi
Gnome/Halfling PHB/XPHB e quattro sottorazze PHB (Forest/Rock,
Lightfoot/Stout). Velocità e identità restano qualificate dalla fonte:
25 piedi PHB, 30 piedi XPHB. Gli incrementi di caratteristiche PHB provengono
da `structured_ability_grants_5etools.json`; non vanno assegnati alle specie
XPHB. `Natural Illusionist` Forest PHB è già nel catalogo strutturato degli
incantesimi; `Tinker` Rock PHB fornisce la competenza con tinker's tools nel
catalogo delle competenze.

| Tratto 5etools | Esito |
| --- | --- |
| Gnome PHB: Age, Size, Languages | Dati descrittivi; taglia Small e lingue PHB conservate con fonte. |
| Gnome PHB: Darkvision | Vista al buio 60 piedi, senza inventare un bonus ai tiri. |
| Gnome PHB: Gnome Cunning | Vantaggio ai TS INT/SAG/CAR **contro magia**, non a tutti i TS di quelle caratteristiche. |
| Forest PHB: Natural Illusionist | `Minor Illusion` noto con INT; origine esatta della sottorazza, già in `additional_spells_5etools.json`. |
| Forest PHB: Speak with Small Beasts | Comunicazione di idee semplici con bestie Small o minori; non equivale all'incantesimo `Speak with Animals`. |
| Rock PHB: Artificer's Lore | Competenza raddoppiata soltanto nelle prove History pertinenti a oggetti magici/alchemici/tecnologici. |
| Rock PHB: Tinker | Competenza negli strumenti già strutturata; costruzione, costo, durata e limite di tre dispositivi restano inventario contestuale. |
| Gnome XPHB: Darkvision | Vista al buio 60 piedi con fonte XPHB. |
| Gnome XPHB: Gnomish Cunning | Vantaggio a tutti i TS INT/SAG/CAR, senza la condizione «contro magia» del PHB. |
| Gnome XPHB: Gnomish Lineage | Scelta Forest/Rock **e** INT/SAG/CAR come caratteristica degli incantesimi; nessuna scelta predefinita. Forest concede `Minor Illusion`, `Speak with Animals` preparato e lanci gratuiti pari a competenza per riposo lungo; Rock concede `Mending`, `Prestidigitation` e dispositivi. Il catalogo `additionalSpells` estratto non ha una voce XPHB Gnome: restano da modellare senza dedurli da una stringa descrittiva. |
| Halfling PHB: Age, Size, Languages | Dati descrittivi e lingue PHB; sottorazze Lightfoot/Stout distinte. |
| Halfling PHB: Lucky | Ripetizione del d20 soltanto su 1 per attacchi, prove e TS. |
| Halfling PHB: Brave | Vantaggio ai TS contro Frightened. |
| Halfling PHB: Halfling Nimbleness | Attraversa lo spazio di una creatura di taglia maggiore. |
| Lightfoot PHB: Naturally Stealthy | Può nascondersi quando oscurato soltanto da creatura più grande. |
| Stout PHB: Stout Resilience | Vantaggio contro veleno e resistenza al danno da veleno. |
| Halfling XPHB: Brave | Vantaggio ai TS per evitare **o terminare** Frightened. |
| Halfling XPHB: Halfling Nimbleness | Attraversa lo spazio di creatura più grande ma non può fermarvisi. |
| Halfling XPHB: Luck | Ripetizione del d20 su 1 per qualunque D20 Test; nome e ambito differiscono da Lucky PHB. |
| Halfling XPHB: Naturally Stealthy | Hide quando oscurato solo da creatura almeno una taglia più grande. |

Da modellare: attivazione contestuale dei vantaggi e reroll, movimento attraverso
creature, invisibilità/oscuramento per Hide, oggetti Tinker, e soprattutto la
scelta Gnomish Lineage con incantesimi e numero di lanci Forest dipendente da
competenza. Nessuno di questi effetti è stato inventato come bonus fisso di
specie o privilegio senza il suo tratto concedente.

## Lotto 2026-10-24: Bard XPHB

Verificate tutte le **18 voci** `class_features` (13 nomi distinti). Il
supplemento esistente attribuisce gli usi di `Bardic Inspiration` al tratto
omonimo con valore `cha_mod`: recupero lungo ai livelli 1–4 e breve dal
livello 5, coerente con `Font of Inspiration`. Nessun'altra voce di classe
richiede un contatore indipendente sicuro.

| Privilegio XPHB (livello) | Esito |
| --- | --- |
| Bardic Inspiration (1) | Pool già strutturato, dado progressivo e bersaglio che custodisce il dado; non un bonus permanente al destinatario. |
| Spellcasting (1) | Preparazione e slot nel modello incantesimi. |
| Expertise (2, 9) | Due abilità già competenti scelte a ciascuna soglia; le raccomandazioni non sono scelte automatiche. |
| Jack of All Trades (2) | Metà competenza, arrotondata in basso, solo alle prove con abilità prive di competenza e senza altro bonus di competenza. |
| Bard Subclass (3) | Segnaposto della sottoclasse scelta. |
| Ability Score Improvement (4, 8, 12, 16) | Scelta di talento/incremento. |
| Font of Inspiration (5) | Cambia recupero del pool Bardic Inspiration; conversione di uno slot in un uso solo quando esiste uno slot speso. |
| Subclass Feature (6, 14) | Segnaposto dei tratti di sottoclasse. |
| Countercharm (7) | Reazione a TS fallito contro Charmed/Frightened; nuovo tiro con vantaggio, nessun uso giornaliero. |
| Magical Secrets (10) | Allarga le liste ammesse per nuove preparazioni quando cresce la capacità; scelta dell'incantesimo reale. |
| Superior Inspiration (18) | All'iniziativa porta Bardic Inspiration a due usi disponibili se ne restano meno; non crea un pool aggiuntivo. |
| Epic Boon (19) | Scelta del talento. |
| Words of Creation (20) | `Power Word Heal` e `Power Word Kill` sempre preparati e secondo bersaglio a distanza vincolata; effetto del lancio. |

Restano separati: assegnazione e consumo del dado a un altro personaggio,
conversione slot→uso di Font of Inspiration, recupero parziale condizionato
di Superior Inspiration, scelte Expertise/Magical Secrets e secondo bersaglio
di Words of Creation.

## Lotto 2026-10-24: Human e Orc XPHB

Controllati i tre tratti Human XPHB e i tre tratti Orc XPHB; controllata
anche la base Human PHB (Age, Size, Languages). La base Human PHB non ha
una voce in `structured_ability_grants_5etools.json`: la progressione delle
caratteristiche 2014 va verificata e attribuita alla fonte PHB senza copiarla
su XPHB. Le due specie XPHB hanno identità e fonte distinte nel catalogo
5etools.

Verifica della lacuna Human PHB: `races-phb.xml` FightClub5eXML
(`3b311d741bca2af58eadbc8068431ef28eb5b05b`) dichiara il tratto
`Ability Score Increase` e +1 a tutte e sei le caratteristiche. Nel
`data/races.json` 5etools (`cefd817691d5ace9adebb5521811943efc378bf0`)
il pacchetto +1 è una **sottorazza PHB senza nome**, mentre `Variant` è un'altra
sottorazza con due caratteristiche scelte. Il generatore degli incrementi
salta le sottorazze senza `name`; forzare +1 sulla razza base Human
assegnerebbe erroneamente gli incrementi anche alla variante. La lacuna
resta nella lista separata finché la scelta Standard/Variant non ha identità
e origine del tratto persistite.

| Tratto 5etools | Esito |
| --- | --- |
| Human PHB: Age, Size, Languages | Medium, Common più una lingua scelta; provenienza PHB. |
| Human XPHB: Resourceful | Heroic Inspiration a ogni riposo lungo, da integrare con lo stato reale dell'ispirazione, non un tracker numerico senza semantica. |
| Human XPHB: Skillful | Una competenza in abilità scelta dal personaggio; mantenere tratto e scelta. |
| Human XPHB: Versatile | Un talento Origin scelto; non assegnare tutti i talenti del filtro. |
| Orc XPHB: Adrenaline Rush | Usi pari alla competenza, recupero al riposo breve o lungo; Dash come azione bonus e PF temporanei pari alla competenza **quando usato**. Richiede contatore con origine `Adrenaline Rush` e attivazione contestuale. |
| Orc XPHB: Darkvision | 120 piedi, fonte XPHB. |
| Orc XPHB: Relentless Endurance | Una volta per riposo lungo, da 0 a 1 PF solo se non si muore sul colpo; richiede il trigger effettivo del danno. |

`Adrenaline Rush` e `Relentless Endurance` non sono stati inseriti nel
supplemento dei **contatori di classe**: assegnarli a Orc come classe o a un
tracker generico perderebbe il tratto concedente e le condizioni di
attivazione. Restano esplicitamente in attesa di una rappresentazione dei
contatori di specie collegata al tratto, insieme alle scelte di Skillful e
Versatile e allo stato Heroic Inspiration di Resourceful.

## Lotto 2026-10-24: Paladin, Sorcerer e Wizard XPHB completi

Ricontrollate una per una le **59 voci** `class_features` di queste tre
classi (24/19/16; 19/12/11 nomi distinti). I contatori `Lay on Hands`,
`Innate Sorcery` e `Arcane Recovery` erano già stati aggiunti nel lotto
precedente. `Channel Divinity` e `Sorcery Points` hanno progressione nelle
tabelle di classe; aggiungere un secondo pool con nome diverso produrrebbe
risorse duplicate. Nessun effetto è stato spostato da un tratto alla classe.

| Paladin XPHB (livello) | Esito |
| --- | --- |
| Lay on Hands (1) | Pool di cinque PF per livello Paladin, già strutturato; bersaglio e quantità curata sono scelti all'uso. |
| Spellcasting (1) | Incantesimi preparati e slot nel modello magico. |
| Weapon Mastery (1) | Due tipi di arma scelti fra quelli competenti, sostituibili al riposo lungo. |
| Fighting Style (2) | Talento Fighting Style scelto, inclusa l'opzione Blessed Warrior. |
| Paladin's Smite (2) | `Divine Smite` sempre preparato e un lancio senza slot per riposo lungo; uso legato al lancio, non bonus danni passivo. |
| Channel Divinity (3) | Pool della tabella, condiviso fra gli effetti concessi dai tratti; scelta dell'effetto all'uso. |
| Divine Sense (3) | Usa Channel Divinity; tipi di creatura, posizione, raggio e durata contestuali. |
| Paladin Subclass (3) | Segnaposto della sottoclasse scelta. |
| Ability Score Improvement (4, 8, 12, 16) | Scelta di talento/incremento. |
| Extra Attack (5) | Due attacchi nell'azione Attack. |
| Faithful Steed (5) | `Find Steed` sempre preparato e un lancio senza slot per riposo lungo; creatura evocata distinta. |
| Aura of Protection (6) | Bonus ai TS pari a CAR, minimo +1, ad alleati **nell'aura** e solo quando il Paladin non è Incapacitated. |
| Subclass Feature (7, 15, 20) | Segnaposto dei tratti reali di sottoclasse. |
| Abjure Foes (9) | Spende Channel Divinity, seleziona fino a CAR bersagli visibili (minimo uno), TS e condizioni. |
| Aura of Courage (10) | Immunità a Frightened dentro Aura of Protection; effetto spaziale, non immunità globale. |
| Radiant Strikes (11) | Danno Radiante su colpo con arma da mischia o colpo senz'armi. |
| Restoring Touch (14) | Rimuove condizioni ammesse spendendo 5 punti dal pool Lay on Hands per condizione, insieme all'uso del tratto. |
| Aura Expansion (18) | Allarga Aura of Protection a 30 piedi, non aggiunge una seconda aura. |
| Epic Boon (19) | Scelta del talento. |

| Sorcerer XPHB (livello) | Esito |
| --- | --- |
| Innate Sorcery (1) | Due usi per riposo lungo già strutturati; vantaggi e CD +1 valgono solo durante il minuto di attivazione. |
| Spellcasting (1) | Trucchetti, preparazione e slot del modello magico. |
| Font of Magic (2) | Sorcery Points progressivi già nella tabella; conversione punti↔slot con costi specifici. |
| Metamagic (2, 10, 17) | Scelte progressive di opzioni e spesa di punti al lancio; non assegnare tutte le opzioni. |
| Metamagic Options (2) | Catalogo di possibilità, non concessione di ognuna. |
| Sorcerer Subclass (3) | Segnaposto della sottoclasse scelta. |
| Ability Score Improvement (4, 8, 12, 16) | Scelta di talento/incremento. |
| Sorcerous Restoration (5) | Recupera al riposo breve fino a metà livello Sorcerer, arrotondata in basso, una volta per riposo lungo; la regola di recupero è già nel dato dedicato. |
| Subclass Feature (6, 14, 18) | Segnaposto della sottoclasse reale. |
| Sorcery Incarnate (7) | Può pagare due Sorcery Points per attivare Innate Sorcery se gli usi sono esauriti; durante l'attivazione ammette fino a due Metamagie sullo stesso incantesimo. |
| Epic Boon (19) | Scelta del talento. |
| Arcane Apotheosis (20) | Una Metamagia gratuita per turno soltanto mentre Innate Sorcery è attiva. |

| Wizard XPHB (livello) | Esito |
| --- | --- |
| Arcane Recovery (1) | Un'attivazione per riposo lungo già strutturata; scelta degli slot dopo un riposo breve, somma dei livelli limitata e nessuno slot di livello 6+. |
| Ritual Adept (1) | Rituali presenti nel libro anche se non preparati; richiede libro e tag Ritual. |
| Spellcasting (1) | Libro, preparazione, trucchetti e slot del modello magico. |
| Scholar (2) | Expertise in **una** fra sei abilità in cui è già competente. |
| Wizard Subclass (3) | Segnaposto della sottoclasse scelta. |
| Ability Score Improvement (4, 8, 12, 16) | Scelta di talento/incremento. |
| Memorize Spell (5) | Sostituzione di un preparato di livello 1+ dal libro a fine riposo breve; scelta, non incremento della capacità. |
| Subclass Feature (6, 10, 14) | Segnaposto dei tratti della sottoclasse. |
| Spell Mastery (18) | Un incantesimo di livello 1 e uno di livello 2 scelti dal libro, sempre preparati e gratuiti solo al livello base; scelta sostituibile secondo il testo. |
| Epic Boon (19) | Scelta del talento. |
| Signature Spells (20) | Due incantesimi di livello 3 scelti dal libro, sempre preparati; un lancio gratuito **per ciascuno** per riposo breve/lungo. |

Restano fuori dall'automazione: selezione dei lanci gratuiti e del bersaglio
per Paladin's Smite/Faithful Steed; raggio, posizione e condizioni delle aure;
conversione fra Sorcery Points e slot e costi di Metamagia; libro,
preparazione e incantesimi scelti per Spell Mastery/Signature Spells. I
contatori già presenti non trasformano queste operazioni in effetti impliciti.

## Lotto 2026-10-24: Aasimar, Dragonborn, Goliath e Tiefling

Controllate le **16 voci di tratto** XPHB nel catalogo 5etools (5 Aasimar,
5 Dragonborn, 3 Goliath, 3 Tiefling) e i tratti base Dragonborn/Tiefling PHB.
I blocchi magici Aasimar e Tiefling PHB/XPHB già presenti in
`additional_spells_5etools.json` conservano la fonte, ma non provano che
una stirpe Tiefling sia stata scelta. Mancando un modello di contatore di
**specie** collegato al tratto concedente, i limiti di uso nel testo non sono
stati travasati nel supplemento dei contatori di classe.

| Specie e tratto | Esito |
| --- | --- |
| Aasimar XPHB: Celestial Resistance | Resistenza a Necrotic e Radiant; origine nel tratto, non protezione generica a ogni danno. |
| Aasimar XPHB: Darkvision | Portata 60 piedi; applicazione visuale alla mappa ancora separata. |
| Aasimar XPHB: Healing Hands | Un uso per riposo lungo, azione Magic e cura pari a tanti d4 quanti sono i punti di competenza, su creatura toccata. |
| Aasimar XPHB: Light Bearer | `Light` noto con CAR; blocco magico strutturato già presente. |
| Aasimar XPHB: Celestial Revelation | Dal livello **del personaggio** 3, una trasformazione per riposo lungo, con opzione scelta a ogni uso (Heavenly Wings, Inner Radiance, Necrotic Shroud), durata un minuto e danno/volo/luce/TS diversi. |
| Dragonborn PHB: Age, Size, Languages | Dati descrittivi della versione PHB e Common/Draconic. |
| Dragonborn PHB: Draconic Ancestry | Tipo di drago scelto determina danno, forma e tipo del TS del soffio. |
| Dragonborn PHB: Breath Weapon | Azione intera, un uso per riposo breve/lungo, danno 2d6→5d6 ai livelli 1/6/11/16; forma e TS dipendono dall'antenato. |
| Dragonborn PHB: Damage Resistance | Resistenza al tipo scelto con Draconic Ancestry. |
| Dragonborn XPHB: Draconic Ancestry | Scelta del drago determina **tipo** del danno e resistenza, non la forma dell'area. |
| Dragonborn XPHB: Breath Weapon | Sostituisce un attacco nell'azione Attack; cono 15 piedi o linea 30×5 scelti all'uso, TS DES, d10 progressivi ai livelli del personaggio 1/5/11/17, usi pari a competenza per riposo lungo. |
| Dragonborn XPHB: Damage Resistance | Resistenza al tipo dell'antenato selezionato. |
| Dragonborn XPHB: Darkvision | Portata 60 piedi, assente nella base Dragonborn PHB. |
| Dragonborn XPHB: Draconic Flight | Dal livello del personaggio 5, un uso per riposo lungo, volo pari alla velocità per 10 minuti finché la condizione lo permette. |
| Goliath XPHB: Giant Ancestry | Scelta di **uno** fra sei benefici; usi pari a competenza per riposo lungo. Teletrasporto, danno, rallentamento, Prone e reazioni dipendono dal beneficio effettivo. |
| Goliath XPHB: Large Form | Dal livello del personaggio 5, un uso per riposo lungo, taglia Large solo con spazio sufficiente, durata 10 minuti, vantaggio a prove FOR e +10 piedi di velocità temporanei. |
| Goliath XPHB: Powerful Build | Vantaggio alle prove per terminare Grappled e capacità di trasporto come taglia superiore; non taglia Large permanente. |
| Tiefling PHB: Age, Size, Languages, Darkvision | Dati descrittivi, Common/Infernal e vista al buio 60 piedi della versione PHB. |
| Tiefling PHB: Hellish Resistance | Resistenza Fire indipendente dalla scelta di stirpe della versione XPHB. |
| Tiefling PHB: Infernal Legacy | Thaumaturgy, Hellish Rebuke dal livello 3 e Darkness dal 5, usi gratuiti giornalieri e CAR; blocco magico PHB già strutturato. |
| Tiefling XPHB: Darkvision | Portata 60 piedi. |
| Tiefling XPHB: Fiendish Legacy | Scelta Abyssal/Chthonic/Infernal; resistenza e trucchetto diversi al livello 1, incantesimi dei livelli del personaggio 3/5 con un lancio gratuito ciascuno per riposo lungo; caratteristica magica INT/SAG/CAR scelta. Blocchi magici XPHB presenti. |
| Tiefling XPHB: Otherworldly Presence | Thaumaturgy con la caratteristica magica della stirpe scelta, senza scelta indipendente. |

Da modellare separatamente: contatori di specie con origine del tratto,
scelte Draconic/Giant Ancestry e Fiendish Legacy, l'attivazione reale dei
soffi e delle trasformazioni, geometria e TS del soffio, applicazione di
resistenze condizionate alla scelta e stato del volo/della taglia. Non si
aggiungono usi a una classe fittizia né si deduce una scelta dalle sole
descrizioni o dalla presenza dei blocchi `additionalSpells`.

## Lotto 2026-10-24: Ranger PHB e opzioni TCE

Controllate le **31 voci** `class_features` associate a Ranger PHB
(24 nomi distinti). La fonte del singolo tratto è essenziale: alcune voci
hanno `class_source: PHB` ma `source: TCE` perché sono **opzioni sostitutive**,
non privilegi ricevuti da tutti i Ranger PHB. Confronto con FightClub5eXML
`class-ranger-phb.xml` (`37ea050ea34a4501ec0aba847a3ba9effccecb4a`)
per la base 2014. Il test dei contatori controlla ora anche `source` del
tratto, oltre alla fonte della classe, così un eventuale contatore TCE non
può essere validato contro un tratto PHB omonimo.

| Privilegio (fonte, livello) | Esito |
| --- | --- |
| Favored Enemy (PHB, 1) | Tipo di nemico e lingua scelti; non bonus generalizzato contro ogni creatura. |
| Natural Explorer (PHB, 1) | Terreno preferito scelto, benefici nel relativo contesto di viaggio/prova. |
| Deft Explorer (TCE opz., 1) | Sostituisce Natural Explorer; Canny sceglie un'abilità già competente per expertise e due lingue. |
| Favored Foe (TCE opz., 1) | Sostituisce Favored Enemy; marchio sul colpo, concentrazione, danno una volta per turno e usi pari a competenza per riposo lungo. Non si concede senza la scelta sostitutiva. |
| Fighting Style (PHB, 2) | Uno stile scelto. |
| Spellcasting (PHB, 2) | Incantesimi conosciuti e slot nel modello magico. |
| Spellcasting Focus (TCE opz., 2) | Focus druidico ammesso solo se l'opzione è selezionata. |
| Primeval Awareness (PHB, 3) | Spende uno slot per individuare tipi di creature in un raggio dipendente dal terreno; non individua posizione o numero. |
| Primal Awareness (TCE opz., 3) | Sostituisce Primeval Awareness; cinque incantesimi a soglie diverse e un lancio gratuito **per ciascuno** al riposo lungo. |
| Ranger Archetype (PHB, 3) | Sottoclasse scelta. |
| Ability Score Improvement (PHB, 4, 8, 12, 16, 19) | Scelta di incremento/talento, non bonus identico per tutti. |
| Martial Versatility (TCE opz., 4) | Può sostituire lo stile a una soglia ASI; non conferisce uno stile aggiuntivo. |
| Extra Attack (PHB, 5) | Due attacchi nell'azione Attack. |
| Deft Explorer Improvement (TCE opz., 6, 10) | Roving a 6, Tireless a 10; quest'ultimo ha usi pari a competenza per PF temporanei e riduce Exhaustion al riposo breve. Solo se Deft Explorer è attivo. |
| Favored Enemy and Natural Explorer improvements (PHB, 6) | Nuovo terreno e nemico/lingua scelti, se i tratti originali non sono stati sostituiti. |
| Ranger Archetype feature (PHB, 7, 11, 15) | Segnaposto dei tratti della sottoclasse scelta. |
| Land's Stride (PHB, 8) | Movimento fra terreni/piante e TS specifici; dipende dal terreno reale. |
| Hide in Plain Sight (PHB, 10) | Mimetismo con materiali, tempo e posizione richiesti. |
| Natural Explorer improvement (PHB, 10) | Nuovo terreno scelto se Natural Explorer è ancora attivo. |
| Nature's Veil (TCE opz., 10) | Sostituisce Hide in Plain Sight; Invisible fino all'inizio del turno successivo, usi pari a competenza per riposo lungo. |
| Favored Enemy improvement (PHB, 14) | Nuovo nemico/lingua scelti se il tratto non è sostituito. |
| Vanish (PHB, 14) | Hide come azione bonus e tracciamento non magico limitato. |
| Feral Senses (PHB, 18) | Attacchi a creature non viste e localizzazione di Invisible entro 30 piedi con condizioni. |
| Foe Slayer (PHB, 20) | Aggiunge SAG a un tiro d'attacco **o** danno contro nemico favorito, una volta per turno; la sostituzione Favored Foe cambia quale bersaglio è valido. |

I sette nomi di tratti TCE opzionali, con Deft Explorer Improvement a due
livelli, richiedono una selezione persistita prima che
contatori o effetti possano essere assegnati. Non sono stati aggiunti
contatori automatici PHB per Favored Foe, Tireless o Nature's Veil TCE.

## Lotto 2026-10-24: Cleric e Paladin PHB

Controllate le **48 voci** `class_features` associate alle due classi PHB
(24 ciascuna; 15 nomi Cleric e 18 Paladin). La base 2014 è stata confrontata
con FightClub5eXML `class-cleric-phb.xml`
(`0c1118e94e7ae1fb0b608b65b3513fdaf0c65d13`) e
`class-paladin-phb.xml` (`249020fa50366d1c300fdc4e076bcddc469e408d`).
Le opzioni TCE che 5etools associa a una classe PHB hanno fonte del
**tratto** TCE e non sono automatiche. I contatori PHB già presenti per
Channel Divinity, Lay on Hands, Divine Sense e Cleansing Touch restano
distinti dai cambiamenti XPHB.

| Cleric (fonte, livello) | Esito |
| --- | --- |
| Divine Domain (PHB, 1) | Dominio scelto; incantesimi e privilegi della sottoclasse reale. |
| Spellcasting (PHB, 1) | Trucchetti, preparazione, slot e focus nel modello magico. |
| Channel Divinity (PHB, 2, 6, 18) | Pool di 1/2/3 usi per riposo breve, già strutturato; ogni effetto consuma lo stesso pool. |
| Channel Divinity: Turn Undead (PHB, 2) | Opzione con TS, bersagli Undead, movimento e durata; non un pool distinto. |
| Channel Divinity: Harness Divine Power (TCE opz., 2) | Spende Channel Divinity per recuperare uno slot con livello massimo e usi propri progressivi; non concedere senza l'opzione TCE. |
| Divine Domain feature (PHB, 2, 6, 8, 17) | Segnaposto dei tratti del dominio selezionato. |
| Ability Score Improvement (PHB, 4, 8, 12, 16, 19) | Scelta di incremento/talento. |
| Cantrip Versatility (TCE opz., 4) | Permette sostituire un trucchetto a una soglia ASI; non aggiunge un trucchetto. |
| Destroy Undead (CR 1/2, 1, 2, 3, 4; PHB, 5, 8, 11, 14, 17) | Soglia CR progressiva sul fallimento del TS di Turn Undead; evento contestuale. |
| Divine Intervention (PHB, 10) | Tiro percentile con soglia pari al livello, recupero lungo se fallisce e sette giorni se riesce; non contatore a recupero fisso. |
| Divine Intervention Improvement (PHB, 20) | Successo automatico del tratto esistente, nessun uso supplementare. |

| Paladin (fonte, livello) | Esito |
| --- | --- |
| Divine Sense (PHB, 1) | Usi 1+CAR per riposo lungo già strutturati; rilevamento e durata richiedono scena reale. |
| Lay on Hands (PHB, 1) | Pool di 5 PF per livello Paladin già strutturato; cura e rimozione di malattia/veleno richiedono spesa e bersaglio. |
| Divine Smite (PHB, 2) | Spesa di uno slot dopo colpo con arma da mischia, dadi e tetto per livello dello slot; non lancio gratuito della versione XPHB. |
| Fighting Style (PHB, 2) | Stile scelto. |
| Spellcasting (PHB, 2) | Preparazione e slot del modello magico. |
| Channel Divinity (PHB, 3) | Un uso per riposo breve/lungo; l'effetto dipende dal giuramento scelto. |
| Channel Divinity: Harness Divine Power (TCE opz., 3) | Opzione TCE che spende il pool condiviso per uno slot, con limite di uso progressivo. |
| Divine Health (PHB, 3) | Immunità alle malattie; origine del tratto, non una risorsa. |
| Sacred Oath (PHB, 3) | Giuramento scelto. |
| Ability Score Improvement (PHB, 4, 8, 12, 16, 19) | Scelta di incremento/talento. |
| Martial Versatility (TCE opz., 4) | Sostituisce lo stile a una soglia ASI solo se l'opzione è adottata. |
| Extra Attack (PHB, 5) | Due attacchi nell'azione Attack. |
| Aura of Protection (PHB, 6) | Bonus ai TS pari a CAR, minimo +1, entro 10 piedi e solo da Paladin cosciente; portata di 30 piedi al livello 18. |
| Sacred Oath feature (PHB, 7, 15, 20) | Segnaposto dei privilegi del giuramento scelto. |
| Aura of Courage (PHB, 10) | Protezione da Frightened entro 10 piedi, poi 30 al livello 18; richiede Paladin cosciente. |
| Improved Divine Smite (PHB, 11) | 1d8 Radiant aggiuntivo sui colpi con arma da mischia. |
| Cleansing Touch (PHB, 14) | Usi pari a CAR, minimo uno, recupero lungo già strutturato; azione per terminare un incantesimo su sé o creatura consenziente toccata. |
| Aura improvements (PHB, 18) | Espande l'aura, non aggiunge un bonus numerico sommabile. |

Restano da rappresentare in modo contestuale gli effetti su bersagli, slot
e area e le opzioni TCE selezionate.

## Lotto 2026-10-24: Half-Elf e Half-Orc PHB

Controllati i **13 tratti** delle due specie base PHB nel catalogo 5etools
(6 Half-Elf, 7 Half-Orc), confrontati con FightClub5eXML `races-phb.xml`
(`3b311d741bca2af58eadbc8068431ef28eb5b05b`) e con il campo `ability`
di 5etools `data/races.json` (`cefd817691d5ace9adebb5521811943efc378bf0`).
La fonte distingue la concessione fissa dalla scelta del personaggio.

| Tratto PHB | Esito |
| --- | --- |
| Half-Elf: Age, Size, Languages | Medium, Common/Elvish e una lingua scelta; l'indice delle lingue contiene la scelta. |
| Half-Elf: Darkvision | Portata 60 piedi, visibilità della scena ancora separata. |
| Half-Elf: Fey Ancestry | Vantaggio ai TS contro Charmed e impossibilità di dormire per magia, non vantaggio a ogni TS. |
| Half-Elf: Skill Versatility | Due abilità scelte; `proficiency_grants_5etools.json` conserva `any: 2`, ma l'origine proiettata è la razza e va attribuita al tratto. |
| Half-Elf: Ability Score Increase (XML/campo 5etools) | CAR +2 fisso già in `structured_ability_grants_5etools.json`; **due altre caratteristiche distinte** +1 scelte dall'insieme FOR/DES/COS/INT/SAG non sono ancora rappresentate. Il generatore attuale conserva solo i valori fissi per le razze. |
| Half-Orc: Age, Size, Languages | Medium e lingue Common/Orc. |
| Half-Orc: Darkvision | Portata 60 piedi. |
| Half-Orc: Menacing | Competenza Intimidation già nell'indice, da attribuire al tratto esatto. |
| Half-Orc: Relentless Endurance | Una volta per riposo lungo da 0 a 1 PF solo se il danno non uccide subito; richiede un contatore di specie e trigger di danno. |
| Half-Orc: Savage Attacks | Su critico con arma da mischia, un dado dell'arma aggiuntivo; dipende dal tiro e dall'arma effettiva. |
| Half-Orc: Ability Score Increase (XML/campo 5etools) | FOR +2 e COS +1 già nel dato strutturato; l'origine del tratto va resa esplicita. |

L'XML include `Ability Score Increase` come tratto per entrambe le specie,
mentre `creature_references_5etools.json` conserva solo i tratti descrittivi
non generici. La scelta Half-Elf non va simulata assegnando +1 a due
caratteristiche predefinite. Anche la competenza e il valore fisso numerico
già presenti vanno ricondotti al tratto, rispettando gli ID persistiti.

## Lotto 2026-10-24: Barbarian e Monk PHB

Controllate le **59 voci** `class_features` associate alle due classi PHB
(Barbarian 25, Monk 34; 20/28 nomi distinti). Confronto FightClub5eXML:
`class-barbarian-phb.xml` (`f5511fec11c9bb352e490942e1f35d9af7e5cced`)
e `class-monk-phb.xml` (`94c3f9c3490462d290421827648e4478ae5f046b`).
Le voci con `source: TCE` sono opzioni aggiunte a una classe con
`class_source: PHB`; richiedono scelta esplicita e non cambiano i tratti
PHB per tutti. Il contatore Rage PHB e la colonna Ki Points PHB restano
distinti dai corrispondenti XPHB.

| Barbarian (fonte, livello) | Esito |
| --- | --- |
| Rage (PHB, 1) | Usi progressivi nel dato, riposo lungo; al livello 20 la tabella è illimitata e il supplemento finito non deve prevalere. Durata e condizioni dipendono dall'attivazione. |
| Unarmored Defense (PHB, 1) | CA 10 + DES + COS solo senza armatura, scudo permesso. |
| Danger Sense (PHB, 2) | Vantaggio ai TS DES contro effetti **visibili** e senza condizioni che lo impediscono. |
| Reckless Attack (PHB, 2) | Scelta al primo attacco del turno; vantaggio in mischia con FOR e vantaggio per chi attacca il Barbarian fino al turno seguente. |
| Primal Knowledge (TCE opz., 3) | Scelta di abilità ai livelli 3 e 10 solo se l'opzione è adottata. |
| Primal Path (PHB, 3) | Sottoclasse scelta. |
| Ability Score Improvement (PHB, 4, 8, 12, 16, 19) | Scelta di incremento/talento. |
| Extra Attack (PHB, 5) | Due attacchi nell'azione Attack. |
| Fast Movement (PHB, 5) | +10 piedi senza armatura pesante. |
| Path Feature / Path feature (PHB, 6, 10, 14) | Segnaposto dei tratti della sottoclasse effettiva. |
| Feral Instinct (PHB, 7) | Vantaggio all'iniziativa; regola separata per sorpresa e stato Incapacitated. |
| Instinctive Pounce (TCE opz., 7) | Movimento durante l'azione bonus che avvia Rage, solo se scelta l'opzione. |
| Brutal Critical (1 die, 2 dice, 3 dice; PHB, 9, 13, 17) | Dadi aggiuntivi sul critico con attacco in mischia; progressione sostitutiva, non somma 1+2+3. |
| Relentless Rage (PHB, 11) | TS COS quando si scende a 0 PF durante Rage, CD crescente dopo gli usi e azzerata al riposo breve/lungo. |
| Persistent Rage (PHB, 15) | Modifica quando Rage finisce; non è il recupero giornaliero omonimo XPHB. |
| Indomitable Might (PHB, 18) | Soglia del totale delle **prove** FOR rispetto al punteggio FOR, non dei TS come XPHB. |
| Primal Champion (PHB, 20) | FOR e COS +4, massimo 24; XPHB ha un tetto diverso. |

| Monk (fonte, livello) | Esito |
| --- | --- |
| Martial Arts (PHB, 1) | Armi Monk ammesse, dado e regole del colpo senz'armi, con condizioni di armatura/scudo. |
| Unarmored Defense (PHB, 1) | CA 10 + DES + SAG solo senza armatura/scudo. |
| Dedicated Weapon (TCE opz., 2) | Arma scelta dopo riposo, con vincoli di competenza e proprietà. |
| Flurry of Blows (PHB, 2) | Un Ki Point dopo l'azione Attack, due colpi senz'armi. |
| Ki (PHB, 2) | Pool Ki progressivo già in tabella, recupero breve/lungo; non pool Focus XPHB. |
| Patient Defense (PHB, 2) | Un Ki Point per Dodge come azione bonus. |
| Step of the Wind (PHB, 2) | Un Ki Point per Dash **o** Disengage come azione bonus e salto raddoppiato. |
| Unarmored Movement (PHB, 2) | Velocità progressiva senza armatura/scudo; regola di superfici al livello 9. |
| Deflect Missiles (PHB, 3) | Reazione a colpo a distanza, riduzione del danno e possibile restituzione pagando Ki. |
| Ki-Fueled Attack (TCE opz., 3) | Attacco come azione bonus solo se si sono spesi Ki nell'azione di quel turno. |
| Monastic Tradition (PHB, 3) | Sottoclasse scelta. |
| Ability Score Improvement (PHB, 4, 8, 12, 16, 19) | Scelta di incremento/talento. |
| Quickened Healing (TCE opz., 4) | Due Ki Points per cura con dado Martial Arts e competenza, soltanto se scelta. |
| Slow Fall (PHB, 4) | Reazione e danno da caduta ridotto in base al livello. |
| Extra Attack (PHB, 5) | Due attacchi nell'azione Attack. |
| Focused Aim (TCE opz., 5) | Spesa contestuale da 1 a 3 Ki per correggere un attacco mancato. |
| Stunning Strike (PHB, 5) | Un Ki Point su colpo con arma da mischia, TS e condizione temporanea. |
| Ki-Empowered Strikes (PHB, 6) | Colpi senz'armi considerati magici per resistenze/immunità; non aggiunge un dado. |
| Monastic Tradition feature (PHB, 6, 11, 17) | Segnaposto dei tratti della sottoclasse effettiva. |
| Evasion (PHB, 7) | Danno dipendente dall'esito del TS DES. |
| Stillness of Mind (PHB, 7) | Azione per terminare su sé Charmed/Frightened quando l'azione è disponibile. |
| Unarmored Movement improvement (PHB, 9) | Movimento su superfici verticali/liquidi durante il turno. |
| Purity of Body (PHB, 10) | Immunità a malattie e veleno; origine del tratto. |
| Tongue of the Sun and Moon (PHB, 13) | Comprensione delle lingue parlate e farsi capire da creature che capiscono una lingua. |
| Diamond Soul (PHB, 14) | Competenza a tutti i TS e nuovo tiro dopo fallimento spendendo un Ki Point. |
| Timeless Body (PHB, 15) | Regole d'età, cibo e acqua; non risorsa consumabile. |
| Empty Body (PHB, 18) | Spese distinte di Ki per Invisible/resistenza temporanea e per Astral Projection; durata e bersagli. |
| Perfect Self (PHB, 20) | All'iniziativa, se Ki è a zero, recupera quattro punti; non un contatore giornaliero. |

Restano separati gli effetti contestuali, il pagamento Ki all'azione e le
scelte TCE. Un nome condiviso fra PHB e XPHB (come Persistent Rage) non
implica effetti o recuperi condivisi.

## Lotto 2026-10-24: Bard PHB

Controllate le **28 voci** `class_features` Bard PHB (20 nomi distinti),
confrontate con FightClub5eXML `class-bard-phb.xml`
(`32e201ceee460c825132bf84b42adf6126192617`). Il pool Bardic
Inspiration PHB già presente usa CAR (minimo un uso), recupero lungo ai
livelli 1–4 e breve dal livello 5; il dado crescente non è un aumento del
numero di usi. `Magical Inspiration` e `Bardic Versatility` hanno fonte
del tratto TCE e restano opzioni.

| Privilegio (fonte, livello) | Esito |
| --- | --- |
| Bardic Inspiration (PHB, 1; d8/d10/d12 ai livelli 5/10/15) | Il dado custodito dal bersaglio cresce, mentre il contatore usa CAR; bersaglio diverso dal Bard e uso contestuale. |
| Spellcasting (PHB, 1) | Incantesimi conosciuti, trucchetti e slot nel modello magico. |
| Jack of All Trades (PHB, 2) | Metà competenza alle prove che non la includono già; ambito diverso dalla formulazione XPHB legata alle abilità. |
| Magical Inspiration (TCE opz., 2) | Dado Bardic Inspiration usabile nel lancio di incantesimi per danno o cura, solo se l'opzione è scelta. |
| Song of Rest (d6/d8/d10/d12; PHB, 2/9/13/17) | Dado extra ai PF recuperati spendendo Hit Dice al riposo breve, progressione sostitutiva; non presente come tratto Bard XPHB. |
| Bard College (PHB, 3) | Sottoclasse scelta. |
| Expertise (PHB, 3/10) | Due abilità già competenti scelte a ciascuna soglia. |
| Ability Score Improvement (PHB, 4/8/12/16/19) | Scelta di incremento/talento. |
| Bardic Versatility (TCE opz., 4) | Sostituzione di una scelta a una soglia ASI; non concede una scelta ulteriore a tutti. |
| Font of Inspiration (PHB, 5) | Cambia il recupero del pool Bardic Inspiration a riposo breve/lungo; la conversione di slot in usi appartiene alla versione XPHB. |
| Bard College feature (PHB, 6/14) | Segnaposto della sottoclasse effettiva. |
| Countercharm (PHB, 6) | Performance avviata con azione che dura fino a fine turno successivo e aiuta TS contro Charmed/Frightened; XPHB è una reazione a TS fallito. |
| Magical Secrets (PHB, 10/14/18) | Due incantesimi da qualsiasi classe scelti a ciascuna soglia; non tutte le liste diventano automaticamente disponibili come nella progressione XPHB. |
| Superior Inspiration (PHB, 20) | All'iniziativa recupera **un** uso solo se Bardic Inspiration è a zero; XPHB porta fino a due se sotto due. |

Restano da modellare il dado e il suo destinatario, l'applicazione di Song
of Rest nel riposo, le scelte Expertise/Magical Secrets, la performance di
Countercharm e il recupero condizionato di Superior Inspiration. La fonte
del tratto impedisce di trasferire un effetto 2024 alla classe PHB.
