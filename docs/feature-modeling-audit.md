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

Dopo la correzione e i lotti Rogue/Ranger, tutte le **57 definizioni di contatore** nel supplemento
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
