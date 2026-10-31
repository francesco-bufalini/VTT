# Generic item variants 5eTools — audit dei benefici strutturati

Fonte: `pwa/catalog/generic_item_variants.json`, generata da `data/magicvariants.json` con `scripts/generate_generic_item_variants.py`.

## Copertura

Sono state esaminate **230 varianti**. La generazione aggiunge **93 valori** di bonus numerici per oggetti (CA, arma, attacco e danno d'arma), **44 voci** di difesa (resistenza/immunità/vulnerabilità), **2 bonus** ai TS, **17 concessioni di incantesimi** e **33 tracker di cariche**. Inoltre si applicano campi oggetto già esistenti per furtività, requisito Forza, proprietà, rarità e sintonia.

I benefici primitivi introdotti nei dati sono solo `bonus`, `defenses`, `spells`: tipi già disponibili nel sistema. I benefici delle copie già salvate vengono riletti dal catalogo senza riscrivere i salvataggi. `attachedSpells` è proiettato solo se è noto un contatore deterministico; il recupero all'alba e il dado di ricarica rimangono note, non un recupero automatico inventato.

## Campi non completamente eseguibili

Le voci possono comparire in più categorie: i conteggi *non* si sommano a 230.

### Bonus ai danni degli incantesimi non generalizzabile (8)

Le otto Imbued Wood applicano il bonus soltanto a specifici tipi di danno; la fonte strutturata non dichiara un target di formula condizionale, quindi non è stato creato un bonus globale scorretto.

`Imbued Wood (Fernian Ash)` (ERLW), `Imbued Wood (Irian Rosewood)` (ERLW), `Imbued Wood (Kythrian Manchineel)` (ERLW), `Imbued Wood (Lamannian Oak)` (ERLW), `Imbued Wood (Mabaran Ebony)` (ERLW), `Imbued Wood (Risian Pine)` (ERLW), `Imbued Wood (Shavarran Birch)` (ERLW), `Imbued Wood (Xorian Wenge)` (ERLW).

### Velocità di nuoto/volo che sostituiscono il valore base (5)

Le modalità `static` ed `equal` assegnano una velocità o la rendono uguale alla camminata. I bonus aritmetici disponibili non equivalgono a impostare una velocità base, né funzionano correttamente sommati.

`Aquatic Wave-Swept Weapon` (AU), `Ascendant Wave-Swept Weapon` (AU), `Mariner's Armor` (DMG), `Ruidium Armor` (CRCotN), `Ruidium Weapon` (CRCotN).

### Emissioni di luce e relativi toggle (13)

Bright/dim sono dati strutturati, ma l'attuale sistema di benefici non applica luci persistenti/attivabili con raggio alla creatura o al token.

`Aquatic Wave-Swept Weapon` (AU), `Ascendant Wave-Swept Weapon` (AU), `Crystal Blade` (FTD), `Dazzling Weapon` (EFA), `Energy Bow` (XDMG), `Flame Tongue` (DMG), `Flame Tongue` (XDMG), `Frost Brand` (DMG), `Frost Brand` (XDMG), `Hellfire Weapon` (BGDIA), `Moon-Touched Sword` (XGE), `Moon-Touched Sword` (XDMG), `Sword of Sharpness` (DMG).

### Competenze o lingue senza valore esplicito (2)

`grantsProficiency: true` non specifica la competenza; non è corretto inventare un'arma, uno strumento o un'armatura.

`Elven Chain` (XDMG), `Weapon of Throne's Command` (BMT).

### Lingue senza valore esplicito (2)

`grantsLanguage: true` non identifica la lingua da concedere e il modello `proficiency` richiede una chiave concreta.

`Demon Armor` (XDMG), `Efreeti Chain` (XDMG).

### Incantesimi selezionabili ma non identificati (18)

Il dato specifica solo il livello della magia dell'Enspelled Item, non l'incantesimo da inserire. Per un beneficio `spells` serve un ID concreto.

`Enspelled Armor (Cantrip)` (XDMG), `Enspelled Armor (Level 1)` (XDMG), `Enspelled Armor (Level 2)` (XDMG), `Enspelled Armor (Level 3)` (XDMG), `Enspelled Armor (Level 4)` (XDMG), `Enspelled Armor (Level 5)` (XDMG), `Enspelled Armor (Level 6)` (XDMG), `Enspelled Armor (Level 7)` (XDMG), `Enspelled Armor (Level 8)` (XDMG), `Enspelled Weapon (Cantrip)` (XDMG), `Enspelled Weapon (Level 1)` (XDMG), `Enspelled Weapon (Level 2)` (XDMG), `Enspelled Weapon (Level 3)` (XDMG), `Enspelled Weapon (Level 4)` (XDMG), `Enspelled Weapon (Level 5)` (XDMG), `Enspelled Weapon (Level 6)` (XDMG), `Enspelled Weapon (Level 7)` (XDMG), `Enspelled Weapon (Level 8)` (XDMG).

### Bonus alle caratteristiche con prerequisiti contestuali (1)

`ability:{str:4}` dell'Hammer of Thunderbolts è soggetto a requisiti di equipaggiamento; assegnare sempre +4 Forza sarebbe errato.

`Hammer of Thunderbolts` (XDMG).

### Vincoli di sintonia basati su specie, classe o lancio di incantesimi (4)

La richiesta di sintonia viene rappresentata; la limitazione dell'idoneità del personaggio non è verificata dal normale controllo di sintonia.

`Armblade` (ERLW), `Holy Avenger` (DMG), `Holy Avenger` (XDMG), `Spell-Fueling Armor` (AUD).

### Maledizioni non descritte come effetti tipizzati (14)

`curse:true` segnala una maledizione, ma i suoi effetti specifici e i trigger sono nella descrizione, non in un campo eseguibile.

`Armor of Vulnerability (Bludgeoning)` (XDMG), `Armor of Vulnerability (Piercing)` (XDMG), `Armor of Vulnerability (Slashing)` (XDMG), `Berserker Axe` (DMG), `Berserker Axe` (XDMG), `Blade of the Medusa` (LLK), `Demon Armor` (XDMG), `Demonbone Polearm` (CoA), `Gambler's Blade` (LLK), `Polymorph Blade` (LLK), `Stygian Spear` (CoA), `Sword of Retribution` (CoA), `Sword of Vengeance` (DMG), `Sword of Vengeance` (XDMG).

### Formule di prezzo/peso (3)

Sono formule di valore commerciale, non bonus di gioco. Gli attuali item instance fields non valutano le espressioni 5eTools sui campi del compendio.

`Adamantine Weapon` (XGE), `Barding` (PHB), `Silvered Weapon` (PHB).

### Oggetto senziente (1)

Informazione narrativa/intelligenza dell'oggetto senza beneficio automatico tipizzato.

`Moonblade` (XDMG).

### Numero iniziale di cariche espresso come tiro (4)

L'attuale tracker richiede un massimo numerico già determinato. Il dado di creazione resta nei dati originali, senza costruire un tracker con un massimo inventato.

`Luck Blade` (DMG), `Luck Blade` (XDMG), `Nine Lives Stealer` (DMG), `Nine Lives Stealer` (XDMG).

### Incantesimi con cariche variabili (2)

Le due versioni della `Luck Blade` dichiarano `wish` e un numero di cariche estratto con un dado. Senza un massimo reale non viene concessa automaticamente un'opzione che consumerebbe risorse inesistenti.

`Luck Blade` (DMG), `Luck Blade` (XDMG).

### Recupero automatico delle cariche (28)

La PWA dispone di tracker con recupero manuale, riposo breve/lungo o su turno, ma non di un trigger universale `dawn` e del lancio della quantità di recupero 5eTools. Le **28 varianti** con `rechargeAmount` mantengono formula e momento di recupero nella nota del tracker; il ripristino deve essere registrato dal giocatore.

`Armor of Weightlessness` (BMT), `Clockwork Armor` (BMT), `Crystal Blade` (FTD), `Dazzling Weapon` (EFA), `Enspelled Armor (Cantrip)` (XDMG), `Enspelled Armor (Level 1)` (XDMG), `Enspelled Armor (Level 2)` (XDMG), `Enspelled Armor (Level 3)` (XDMG), `Enspelled Armor (Level 4)` (XDMG), `Enspelled Armor (Level 5)` (XDMG), `Enspelled Armor (Level 6)` (XDMG), `Enspelled Armor (Level 7)` (XDMG), `Enspelled Armor (Level 8)` (XDMG), `Enspelled Weapon (Cantrip)` (XDMG), `Enspelled Weapon (Level 1)` (XDMG), `Enspelled Weapon (Level 2)` (XDMG), `Enspelled Weapon (Level 3)` (XDMG), `Enspelled Weapon (Level 4)` (XDMG), `Enspelled Weapon (Level 5)` (XDMG), `Enspelled Weapon (Level 6)` (XDMG), `Enspelled Weapon (Level 7)` (XDMG), `Enspelled Weapon (Level 8)` (XDMG), `Feywrought Armor` (BMT), `Gloomwrought Armor` (BMT), `Hammer of Thunderbolts` (XDMG), `Starshot Crossbow` (BMT), `Thayan Sword` (AUD), `Weapon of Throne's Command` (BMT).

### Peso e valore in percentuale

`Barding` (PHB) contiene anche `weightExpression`, `weightMult` e `valueMult`: sono preservati nel documento sorgente, ma non sono un bonus di scheda e non vengono applicati a peso/prezzo dell'istanza.

### Ambiti che richiedono ulteriori condizioni

Le due `Luck Blade` concedono un bonus ai TS **mentre sono sulla persona**: il bonus è dichiarato con il tipo `bonus` esistente, ma le estensioni d'arma si attivano normalmente solo sull'arma equipaggiata. La regola di attivazione esatta resta quindi parziale.

Per effetti come danni aggiuntivi dopo l'attivazione (ad es. `Flame Tongue`), un bersaglio selezionato, una maledizione con trigger o un utilizzo con condizione, il campo `entries` fornisce prosa e non un payload di beneficio. Il catalogo preserva il testo: **non** lo trasforma automaticamente in un effetto permanente. L'audit tratta tutti i campi meccanici espliciti di `inherits`, non pretende di aver interpretato le descrizioni narrative.

## Metadati e identità

`source`, `page`, `srd`, `rarity`, `tier`, `namePrefix`, `nameSuffix`, `reprintedAs`, `lootTables`, `classFeatures` e `wondrous` rimangono metadati del catalogo: non sono automaticamente poteri del personaggio. Il titolo nell'inventario continua a concatenare oggetto base e varianti, come per le infusioni.
