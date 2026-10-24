# Privilegi 5etools ancora fuori dal modello automatico

Questa lista riguarda soltanto i lotti già verificati nella
[revisione per tratto](feature-modeling-audit.md). Un contatore già presente
può rappresentare gli **usi** senza rappresentare l'effetto, il bersaglio o
la scelta. L'origine richiesta è il tratto `classFeature`, `subclassFeature`
o il tratto della specie con fonte/edizione esatta; una classe o specie da
sola non concede effetti generici.

Il catalogo `additional_spells_5etools.json` conserva oggi le concessioni
magiche al livello `race`/`subrace`; i risolutori Godot e PWA producono ID
di quell'origine. Per i tratti di specie qui sotto, la presenza di un blocco
di incantesimi è utile, ma **non certifica ancora l'identità del tratto
concedente**. Il passaggio a tale identità richiede continuità degli ID
persistiti e verifica con entrambe le interfacce; resta aperto.

| Fonte e tratti | Parte ancora da rappresentare fedelmente |
| --- | --- |
| Fighter XPHB: Tactical Mind, Tactical Shift, Tactical Master, Studied Attacks | Esito del tiro, consumo di Second Wind, movimento o proprietà dell'arma al momento dell'azione. |
| Barbarian XPHB: Rage, Persistent Rage | Recupero di **un** uso Rage al riposo breve, recupero completo condizionato all'iniziativa, durata e cessazione di Rage. Il contatore di Persistent Rage copre solo l'uso giornaliero. |
| Barbarian XPHB: Reckless Attack, Brutal Strike, Relentless Rage | Scelta sul colpo, vantaggio con conseguenze temporanee, opzioni d'effetto e CD che aumenta dopo i tentativi e si azzera al riposo. |
| Barbarian PHB: Rage, Relentless Rage, Brutal Critical, opzioni TCE | Durata di Rage e limite illimitato al livello 20, CD crescente dei tentativi, dado critico progressivo non cumulativo; Primal Knowledge/Instinctive Pounce TCE richiedono scelta. Persistent Rage PHB modifica la durata, mentre XPHB ha anche un recupero giornaliero. |
| Bard XPHB: Bardic Inspiration, Font of Inspiration, Superior Inspiration | Trasferimento e spesa del dado su altro personaggio, conversione slot→uso, ricarica fino a due usi all'iniziativa. Il pool numerico è già presente. |
| Bard XPHB: Expertise, Magical Secrets, Words of Creation | Abilità e incantesimi scelti, seconda creatura bersaglio nel lancio. |
| Cleric XPHB: Channel Divinity, Divine Spark, Turn Undead, Sear Undead | Recupero di **un** uso al riposo breve; scelta dell'opzione, bersagli, TS, cura, danno e condizioni d'effetto. |
| Cleric XPHB: Divine Order, Blessed Strikes | Opzione esclusiva e beneficio derivato dal solo tratto selezionato. |
| Cleric XPHB: Divine Intervention, Greater Divine Intervention | Incantesimo idoneo scelto al lancio e recupero di 2d4 riposi lunghi dopo Wish; non un secondo contatore statico. |
| Cleric PHB: Divine Intervention, Channel Divinity: Harness Divine Power (TCE opz.) | Recupero diverso dopo successo/fallimento del tiro percentile; l'opzione TCE richiede selezione e spende Channel Divinity per uno slot entro un tetto. |
| Druid XPHB: Wild Shape, Wild Companion | Recupero breve parziale, forme conosciute e statistiche della trasformazione, scelta fra slot e uso Wild Shape per Find Familiar. |
| Druid XPHB: Primal Order, Elemental Fury, Improved Elemental Fury | Opzione esclusiva e progressione dipendente dall'opzione scelta. |
| Druid XPHB: Wild Resurgence, Archdruid | Conversioni bidirezionali fra slot e usi Wild Shape, vincoli dei valori e ricarica condizionata all'iniziativa. |
| Monk XPHB: Flurry of Blows, Patient Defense, Step of the Wind, Stunning Strike, Deflect Attacks, Superior Defense | Consumo contestuale del pool Focus, azioni, TS, condizioni, danno e durata. |
| Monk XPHB: Uncanny Metabolism, Perfect Focus | Ripristino dei Focus Points all'iniziativa e guarigione; soglia di quattro punti e mutua esclusione. Il contatore giornaliero di Uncanny Metabolism è già presente. |
| Monk PHB: Ki, Deflect Missiles, Stunning Strike, Diamond Soul, Empty Body, Perfect Self e opzioni TCE | Spese Ki legate all'azione, bersaglio/TS/durata e recupero condizionato all'iniziativa; Dedicated Weapon, Ki-Fueled Attack, Quickened Healing e Focused Aim non si concedono senza selezione TCE. |
| Paladin XPHB: Lay on Hands, Restoring Touch, Divine Sense, Abjure Foes | Punti spesi, bersaglio, condizioni e sensi al momento dell'uso. |
| Paladin XPHB: Paladin's Smite, Faithful Steed, Aura of Protection/Courage/Expansion | Lanci gratuiti specifici di Divine Smite/Find Steed e stato della creatura evocata; bonus/immunità entro aura spaziale attiva, con raggio progressivo. |
| Paladin PHB: Divine Smite, Lay on Hands, aure e Harness Divine Power (TCE opz.) | Colpo concreto e slot speso, cura/rimozione su bersaglio e area delle aure; l'opzione TCE non è concessa automaticamente con la classe PHB. |
| Ranger XPHB: Tireless, Nature's Veil, Hunter's Mark features | PF temporanei e condizione Invisible attivati, riduzione di Exhaustion, concentrazione/bersaglio marcato. I limiti numerici di Tireless e Nature's Veil sono già presenti. |
| Ranger PHB con opzioni TCE: Favored Foe, Deft Explorer/Tireless, Primal Awareness, Nature's Veil | La fonte del tratto è TCE anche con `class_source: PHB`; occorre registrare le sostituzioni opzionali e i tratti effettivamente scelti prima di attribuire usi o incantesimi. Favored Foe, Tireless e Nature's Veil hanno limiti verificati ma non sono concessi a tutti i Ranger PHB. |
| Rogue XPHB: Cunning Strike, Devious Strikes, Improved Cunning Strike | Dadi Sneak Attack rinunciati sul singolo attacco, opzioni, TS, condizioni e durata; i dadi non sono una riserva persistente. |
| Sorcerer XPHB: Innate Sorcery, Sorcery Incarnate, Arcane Apotheosis | Durata/attivazione, incantesimo e Metamagia scelti, costi alternativi in Sorcery Points. |
| Sorcerer XPHB: Font of Magic, Metamagic | Conversione Sorcery Points↔slot con costi, opzioni scelte e spesa contestuale al lancio. |
| Warlock XPHB: Magical Cunning, Eldritch Master | Ripristino degli slot Pact Magic in quantità diversa prima e dopo il livello 20. Il contatore di Magical Cunning copre solo il rito giornaliero. |
| Warlock XPHB: Eldritch Invocations, Contact Patron, Mystic Arcanum | Scelte con prerequisiti, lancio gratuito specifico e quattro incantesimi distinti. |
| Wizard XPHB: Arcane Recovery, Memorize Spell, Signature Spells | Slot scelti entro tetto cumulativo, preparazione e due incantesimi scelti. Il contatore Arcane Recovery copre solo l'uso. |
| Wizard XPHB: Scholar, Ritual Adept, Spell Mastery | Abilità già competente scelta, libro di incantesimi effettivo, rituali ammissibili e due incantesimi scelti per lanci gratuiti al livello base. |
| Artificer TCE: Magic Item Adept/Savant/Master, Soul of Artifice | Le eccezioni esistenti nel codice vanno espresse con dati del tratto: limite di sintonia che **sostituisce** il precedente e bonus dinamico legato agli oggetti davvero in sintonia. |
| Artificer TCE: Experimental Elixir, Eldritch Cannon, Spell-Storing Item, Magical Tinkering | Stato di oggetti specifici, creazione, scelta, durata, bersaglio e pagamento alternativo con slot. |
| Dwarf PHB/XPHB: Darkvision, Dwarven Toughness, Dwarven Resilience, Stonecunning | Senso contestuale, PF per livello, TS contro veleno e origine esatta del tratto; in XPHB Stonecunning ha usi e Tremorsense temporaneo. |
| Elf PHB/XPHB: Elven Lineage, Keen Senses, weapon training, Fey Ancestry, Trance, Darkvision | Scelte di stirpe/abilità/armi, competenze attribuite al tratto esatto, TS contestuali, riposo e vista sulla mappa. |
| Gnome PHB/XPHB: Gnome Cunning, Gnomish Cunning, Gnomish Lineage, Artificer's Lore, Tinker | Ambito diverso dei TS PHB/XPHB; scelta Forest/Rock e capacità magica; lanci gratuiti Forest pari a competenza; prova History contestuale e dispositivi. `additionalSpells` estratto non contiene Gnome XPHB. |
| Half-Elf PHB: Ability Score Increase, Skill Versatility, Fey Ancestry | CAR +2 fisso è presente; mancano due incrementi +1 in caratteristiche distinte scelte fra cinque, con origine nel tratto XML. Due abilità scelte sono nell'indice competenze ma con origine razza. Il vantaggio e il sonno magico restano contestuali. |
| Half-Orc PHB: Menacing, Relentless Endurance, Savage Attacks | Competenza Intimidation e incrementi fissi sono presenti ma non attribuiti al tratto esatto; manca un contatore di specie per il trigger 0→1 PF, e il dado critico dipende dall'arma. |
| Halfling PHB/XPHB: Lucky/Luck, Brave, Nimbleness, Naturally Stealthy, Stout Resilience | Ripetizione condizionata del d20, TS contro Frightened/veleno, passaggio tra creature e Hide con oscuramento valido. |
| Human PHB: Ability Score Increase / Variant | FightClub5eXML concede +1 a tutte le caratteristiche per Standard; 5etools lo colloca in una sottorazza PHB **senza nome** che il generatore salta. La variante sceglie due caratteristiche. Serve distinguere e persistere Standard/Variant e il tratto d'origine prima di aggiungere incrementi; non applicare +1 a tutti gli Human. |
| Human XPHB: Resourceful, Skillful, Versatile | Stato Heroic Inspiration al riposo, una abilità scelta e un talento Origin scelto. L'indice delle competenze non contiene ancora una concessione `Skillful` con origine di tratto. |
| Orc XPHB: Adrenaline Rush, Relentless Endurance | Contatori di **specie** con origine di tratto, usi di Adrenaline Rush pari a competenza e recupero breve/lungo, PF temporanei all'uso e trigger 0→1 PF di Relentless Endurance. Non attribuirli a una classe. |
| Aasimar XPHB: Healing Hands, Celestial Revelation | Contatori di specie con origine di tratto, cura su bersaglio, opzione di trasformazione scelta a ogni uso, durata, danno/volo/luce/TS relativi. |
| Dragonborn PHB/XPHB: Draconic Ancestry, Breath Weapon, Damage Resistance, Draconic Flight | Scelta dell'antenato, area e TS diversi per edizione, usi e dado progressivi, resistenza al tipo scelto e volo temporaneo. Il soffio PHB non usa le regole XPHB. |
| Goliath XPHB: Giant Ancestry, Large Form, Powerful Build | Beneficio gigante scelto e usi pari a competenza, taglia/velocità temporanee con spazio sufficiente, capacità di trasporto senza taglia permanente. |
| Tiefling XPHB: Fiendish Legacy, Otherworldly Presence | Stirpe e caratteristica magica scelte; resistenza, trucchetti e lanci gratuiti dei livelli del personaggio 3/5 legati alla stirpe reale. I blocchi `additionalSpells` non sono una scelta già compiuta. |
| Aasimar/Tiefling/Elf e altri incantesimi di specie | Collegare ogni blocco `additionalSpells` al tratto preciso che lo concede, mantenendo gli ID dei lanci e dei contatori già salvati; oggi l'origine proiettata è `race`/`subrace`. |

Prima di chiudere una riga occorrono una fonte 5etools/FightClub5eXML
verificata, l'identità del tratto concedente, una scelta/stato persistito se
necessari e un controllo coerente su Godot e PWA. Se manca uno di questi,
il testo resta consultabile ma l'effetto non viene inventato.
