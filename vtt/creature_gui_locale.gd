extends RefCounted

# Creature-sheet-only display translations. Never mutate persisted records or the global locale.
const CONFIG_PATH := "user://creature_gui_locale.cfg"
const EN: Dictionary = {
	"ARCHIVIO DELLE CREATURE": "CREATURE ARCHIVE",
	"Opzioni ▾": "Options ▾",
	"Chiudi": "Close",
	"Le mie creature": "My creatures",
	"Cerca tra le mie creature…": "Search my creatures…",
	"Le mie creature · clic destro per le azioni": "My creatures · right-click for actions",
	"+ Personaggio": "+ Character",
	"Crea una nuova scheda di personaggio": "Create a new character sheet",
	"Bestiario · cerca per nome o fonte": "Bestiary · search by name or source",
	"+ Dal bestiario": "+ From bestiary",
	"Aggiungi una creatura dalla voce selezionata nel bestiario": "Add a creature from the selected bestiary entry",
	"Visualizza e modifica": "View and edit",
	"Scegli una sezione da visualizzare o modificare": "Choose a section to view or edit",
	"Niente": "None",
	"Competenze": "Proficiencies",
	"Talenti": "Feats",
	"Bonus": "Bonuses",
	"Tracker": "Trackers",
	"Info": "Info",
	"Statistiche": "Statistics",
	"Aspetto": "Appearance",
	"Tratti": "Traits",
	"Stati": "Conditions",
	"Incantesimi": "Spells",
	"Inventario": "Inventory",
	"Documenti": "Documents",
	"IDENTITÀ": "IDENTITY",
	"Nome": "Name",
	"Fazione": "Faction",
	"Regole": "Rules",
	"Edizione delle regole del personaggio": "Character rules edition",
	"Default": "Default",
	"PUNTI FERITA": "HIT POINTS",
	"Attuali": "Current",
	"TEMP": "TEMP",
	"Seconda forma": "Second form",
	"CA E INIZIATIVA": "AC AND INITIATIVE",
	"CA": "AC",
	"Bonus iniziativa": "Initiative bonus",
	"MOVIMENTO": "MOVEMENT",
	"Camminata (ft)": "Walking (ft)",
	"Scalata (ft)": "Climbing (ft)",
	"Nuoto (ft)": "Swimming (ft)",
	"Volo (ft)": "Flying (ft)",
	"Scavo (ft)": "Burrowing (ft)",
	"SALTI · DISTANZE MASSIME": "JUMPS · MAXIMUM DISTANCES",
	"CARATTERISTICHE": "ABILITY SCORES",
	"Car.": "Ability",
	"Punteggio": "Score",
	"Mod.": "Mod.",
	"TS": "Save",
	"ABILITÀ": "SKILLS",
	"🎓 Competenza  ·  🎓🎓 Maestria": "🎓 Proficiency  ·  🎓🎓 Expertise",
	"RIEPILOGO": "SUMMARY",
	"Bonus competenza": "Proficiency bonus",
	"Percezione passiva": "Passive Perception",
	"STRUMENTI E LINGUAGGI": "TOOLS AND LANGUAGES",
	"Strumenti: ": "Tools: ",
	"Linguaggi: ": "Languages: ",
	"ATTACCHI DISPONIBILI": "AVAILABLE ATTACKS",
	"Caratteristica attacchi": "Attack ability",
	"Forza": "Strength",
	"Destrezza": "Dexterity",
	"Arma attiva": "Active weapon",
	"Sottorazza": "Subrace",
	"Razza / Specie": "Race / Species",
	"Tipo": "Type",
	"GS": "CR",
	"Progressione": "Progression",
	"Background": "Background",
	"Classi aggiuntive (multiclasse)": "Additional classes (multiclass)",
	"Classi principali aggiuntive": "Additional primary classes",
	"Classi aggiuntive": "Additional classes",
	"+ Classe": "+ Class",
	"Classe base": "Primary class",
	"Sottoclasse": "Subclass",
	"Livello": "Level",
	"CLASSI E PROGRESSIONE": "CLASSES AND PROGRESSION",
	"XP": "XP",
	"RISORSE": "RESOURCES",
	"STORIA E PERSONALITÀ": "BACKGROUND AND PERSONALITY",
	"Note": "Notes",
	"Miniatura base": "Default miniature",
	"Forma attuale": "Current form",
	"Cerca e scegli…": "Search and choose…",
	"Scegli aspetto attuale…": "Choose current appearance…",
	"↺ Aspetto di base": "↺ Default appearance",
	"Taglia": "Size",
	"Fronte della miniatura": "Miniature facing",
	"Quantità": "Quantity",
	"Attacco": "Attack",
	"Arma": "Weapon",
	"Portata": "Reach",
	"Gittata": "Range",
	"Colpire": "To hit",
	"Danni": "Damage",
	"Tira per colpire": "Roll to hit",
	"Tira danni": "Roll damage",
	"IN USO": "IN USE",
	"✓ Competente": "✓ Proficient",
	"Competente": "Proficient",
	"Due mani (versatile)": "Two hands (versatile)",
	"Competenza inclusa (bestiario)": "Proficiency included (bestiary)",
	"▸ Descrizione del bestiario": "▸ Bestiary description",
	"▾ Nascondi descrizione": "▾ Hide description",
	"Azioni leggendarie": "Legendary actions",
	"Colpo senz'armi": "Unarmed strike",
	"Arma improvvisata": "Improvised weapon",
	"Calcola automaticamente": "Auto-calculate",
	"Applica": "Apply",
	"Annulla": "Cancel",
	"Cedi controllo…": "Transfer control…",
	"Ricevi creatura…": "Receive creature…",
	"Scarica creatura…": "Export creature…",
	"Elimina creatura selezionata…": "Delete selected creature…",
	"Copia il mio ID": "Copy my ID",
	"Cartella homebrew": "Homebrew folder",
	"Cartella integrazioni VTT": "VTT integrations folder",
	"Ricarica homebrew": "Reload homebrew",
	"Associa a token selezionato": "Link to selected token",
	"Calcola automaticamente…": "Auto-calculate…",
	"Elimina creatura…": "Delete creature…",
	"Crea o importa una creatura.": "Create or import a creature.",
	"Nessuna creatura corrispondente.": "No matching creatures.",
	"Danni: prima temporanei, poi PF della seconda forma, infine PF normali.": "Damage: temporary HP first, then second-form HP, then normal HP.",
	"Sottrai PF: inserisci un valore o tira un dado": "Subtract HP: enter a value or roll dice",
	"Punti ferita attuali": "Current hit points",
	"PF massimi effettivi": "Effective maximum HP",
	"PF massimi base, prima dei bonus": "Base maximum HP before bonuses",
	"Punti ferita temporanei: assorbono i danni prima delle altre forme.": "Temporary HP absorb damage before the other forms.",
	"Aggiungi PF: inserisci un valore o tira un dado": "Add HP: enter a value or roll dice",
	"Ripristina i PF al valore massimo": "Restore HP to maximum",
	"PF attuali della seconda forma; si consumano dopo quelli temporanei.": "Current second-form HP; consumed after temporary HP.",
	"PF massimi della seconda forma (polimorfia o forma selvatica)": "Maximum second-form HP (polymorph or wild shape)",
	"Classe Armatura base, prima dei bonus": "Base Armor Class, before bonuses",
	"Velocità base dalla specie o dal bestiario, modificabile": "Base speed from species or bestiary, editable",
	"Punteggio base": "Base score",
	"Modificatore calcolato dal punteggio e dal bonus": "Modifier calculated from the score and bonuses",
	"Tiro salvezza: modificatore caratteristica + competenza, se posseduta": "Saving throw: ability modifier + proficiency if trained",
	"Competenze negli strumenti delle origini attive": "Tool proficiencies from active origins",
	"Linguaggi delle origini attive": "Languages from active origins",
	"Arma / attacco precedente": "Previous weapon / attack",
	"Arma / attacco successivo": "Next weapon / attack",
	"Scegli un'arma dall'inventario o un attacco naturale; la portata visibile sulla mappa seguirà questa scelta.": "Choose an inventory weapon or natural attack; the range shown on the map follows this choice.",
	"Solo le sottorazze della razza selezionata, in base a raceName e raceSource.": "Only subraces of the selected race, based on raceName and raceSource.",
	"Grado sfida del bestiario, anche frazionario (es. 1/4). Non è un livello di classe.": "Bestiary challenge rating, including fractions (e.g. 1/4). Not a class level.",
	"XP calcolati unicamente dai livelli di classe effettivi; il GS è indipendente": "XP calculated from actual class levels only; CR is independent",
	"Storia, carattere, ideali, legami, difetti e annotazioni…": "Background, personality, ideals, bonds, flaws and notes…",
	"Scegli una miniatura dal catalogo": "Choose a miniature from the catalog",
	"Cerca la miniatura attuale; funziona anche senza token in scena.": "Find the current miniature, even without a token on the map.",
	"Reimposta l'aspetto attuale alla miniatura di base.": "Reset the current appearance to the default miniature.",
	"Dettagli effetto": "Effect details",
	"Elimina creatura": "Delete creature",
	"Modificabile nell'inventario; in assenza di scelta segue la taglia della creatura.": "Editable in inventory; defaults to creature size.",
	"Usa il dado versatile solo quando la mano secondaria è libera": "Use versatile damage only when the off hand is free",
	"Il bonus al tiro per colpire pubblicato da 5etools include già la competenza": "The 5etools attack bonus already includes proficiency",
	"Gestisci competenze e origini nella scheda Competenze, non sul singolo attacco.": "Manage proficiencies and origins in Proficiencies, not per attack.",
	"Mostra il testo originale di 5etools": "Show original 5etools text",
	"La CA base viene dall'armatura indossata nell'inventario": "Base AC comes from armor worn in inventory",
	"Portata o gittata di questo attacco, indipendente dalle altre armi": "This attack's reach or range, independent of other weapons",
	"Oltre la gittata normale si applica svantaggio (regole 2014)": "Disadvantage beyond normal range (2014 rules)",
	"Tira 1d20 e il bonus per colpire nel roller": "Roll 1d20 and the attack bonus in the dice roller",
	"Tira i danni dell'attacco nel roller": "Roll this attack's damage in the dice roller",
	"Modifica PF": "Edit HP",
	"Scegli una quantità o tira un dado con il roller.": "Choose an amount or roll dice.",
	"Usa una formula di dadi": "Use a dice formula",
	"Esempio: 2d6+3": "Example: 2d6+3",
	"PF della seconda forma": "Second-form HP",
	"Vuoi assegnare PF alla nuova forma?": "Assign HP to the new form?",
	"Sì · Inserisci manualmente": "Yes · Enter manually",
	"Sì · Prendi dal bestiario": "Yes · Use bestiary",
	"No · Senza PF di seconda forma": "No · No second-form HP",
	"Ripristino della forma base": "Restore default form",
	"Sì, rimuovi": "Yes, remove",
	"No, conserva": "No, keep",
	"Seconda forma esaurita": "Second form depleted",
	"Sì, ripristina": "Yes, restore",
	"No, mantieni": "No, keep",
	"Consuma un utilizzo": "Spend one use",
	"Recupera un utilizzo": "Recover one use",
	"Miniatura predefinita": "Default miniature",
	"Conferma": "Confirm",
	"Cerca miniatura per nome o ID...": "Search miniature by name or ID...",
	"ID catalogo: ": "Catalog ID: ",
	"Leggi effetti": "Read effects",
	"Nessuna risorsa con utilizzi espliciti nei dati strutturati.": "No resources with explicit uses in structured data.",
	"Scegli i valori da ricalcolare. Gli altri campi restano invariati.": "Choose values to recalculate. Other fields remain unchanged.",
	"PF massimi: media dei dadi vita + Costituzione": "Maximum HP: hit-die average + Constitution",
	"Bonus di competenza: somma livelli di classe": "Proficiency bonus: sum of class levels",
	"Limiti degli incantesimi conosciuti/preparabili": "Known/preparable spell limits",
	"Slot incantesimo e Magia del Patto dal livello di classe": "Spell slots and Pact Magic from class levels",
	"Aggiorna i massimi dei tracker strutturati e limita gli utilizzi": "Update structured tracker maxima and cap uses",
	"Dadi vita, XP minimo, iniziativa e velocità base": "Hit dice, minimum XP, initiative and base speed",
	"Difese, iniziativa, competenze e portata attiva da dati strutturati": "Defenses, initiative, proficiencies and active reach from structured data",
	"Cedi controllo della creatura": "Transfer creature control",
	"Seleziona un giocatore con il VTT aperto nella stessa partita Tailscale.": "Choose a player with the VTT open in the same Tailscale game.",
	"Aggiorna giocatori online": "Refresh online players",
	"Giocatore online": "Online player",
	"Nessun altro giocatore VTT online": "No other VTT player online",
	"Ricevi il controllo di una creatura": "Receive control of a creature",
	"Importa": "Import",
	"Incolla qui il codice JSON ricevuto dal precedente controllore.": "Paste the JSON code received from the previous controller.",
	"Scarica creatura": "Export creature",
	"Cerca incantesimo per nome, descrizione o fonte": "Search spells by name, description or source",
	"Mie classi": "My classes",
	"Limita la ricerca agli incantesimi delle mie classi": "Limit search to spells from my classes",
	"Catalogo · doppio clic per lanciare": "Catalog · double-click to cast",
	"Incantesimi di classe": "Class spells",
	"Incantesimi delle classi fino al livello attuale": "Class spells up to current level",
	"Libro degli incantesimi: vista e selezione delle magie trascritte": "Spellbook: view and select transcribed spells",
	"Modalità libro: clicca una magia per inserirla o rimuoverla.": "Spellbook mode: click a spell to add or remove it.",
	"Incantesimi disponibili": "Available spells",
	"Mostra ricerca incantesimi": "Show spell search",
	"Nascondi ricerca incantesimi": "Hide spell search",
	"Seleziona un incantesimo per consultare la descrizione.": "Select a spell to see its description.",
	"Aggiungi ai disponibili": "Add to available",
	"Aggiungi o rimuovi l’incantesimo selezionato dai disponibili": "Add or remove the selected spell from available spells",
	"✨ Lancia": "✨ Cast",
	"Lancia": "Cast",
	"Lancia l'incantesimo selezionato da una qualsiasi delle tre liste": "Cast the selected spell from any of the three lists",
	"Slot incantesimo": "Spell slots",
	"Ricarica": "Recover",
	"Liv.   −  +  Rimasti / max     (doppio clic sul massimo)": "Lvl.   −  +  Remaining / max     (double-click the maximum)",
	"Consuma uno slot di livello %d": "Spend a level %d slot",
	"Numero base di slot massimi": "Base number of maximum slots",
	"Ricarica uno slot di livello %d": "Recover a level %d slot",
	"Patto": "Pact",
	"Slot di Magia del Patto": "Pact Magic slots",
	"Liv.": "Lvl.",
	"Usa": "Use",
	"Ricarica uno slot della Magia del Patto": "Recover a Pact Magic slot",
	"Lancia incantesimo": "Cast spell",
	"Slot:": "Slots:",
	"Nascondi slot": "Hide slots",
	"Nascondi patto": "Hide pact",
	"Inventario · Catalogo e oggetti personalizzati": "Inventory · Catalog and custom items",
	"Nome, fonte, rarità, danno o proprietà…": "Name, source, rarity, damage or property…",
	"Azzera filtri": "Reset filters",
	"+ Aggiungi all'inventario": "+ Add to inventory",
	"Aggiungi l'oggetto selezionato; doppio clic sulla lista per aggiungere": "Add selected item; double-click the list to add",
	"Oggetti posseduti": "Owned items",
	"⚔ Mano principale": "⚔ Main hand",
	"🛡 Secondaria / Scudo": "🛡 Off hand / Shield",
	"Indossa armatura": "Wear armor",
	"Seleziona questa armatura per calcolare automaticamente la CA": "Select this armor to automatically calculate AC",
	"Rimuovi equipaggiamento": "Unequip",
	"Sintonia": "Attunement",
	"Gli oggetti che richiedono sintonia conferiscono bonus solo quando sintonizzati.": "Items requiring attunement grant bonuses only while attuned.",
	"Attivo": "Active",
	"Disattiva gli effetti di un oggetto senza rimuoverlo dall'inventario.": "Disable item effects without removing it from inventory.",
	"Taglia arma": "Weapon size",
	"Default: taglia della creatura. Le armi Grandi/Enormi/Mastodontiche usano dadi aggiuntivi.": "Default: creature size. Large/Huge/Gargantuan weapons use additional dice.",
	"Rimuovi": "Remove",
	"🔍 Cerca oggetti": "🔍 Search items",
	"Mostra ricerca oggetti": "Show item search",
	"Nascondi ricerca oggetti": "Hide item search",
	"Origine": "Origin",
	"Cerca un privilegio…": "Search a feature…",
	"Espandi tutti": "Expand all",
	"Comprimi": "Collapse",
	"Nessun privilegio da mostrare.": "No features to show.",
	"Mostra o nascondi la descrizione di questo tratto": "Show or hide the description of this trait",
	"LIVELLO %d": "LEVEL %d",
	"%d tratti e descrizioni": "%d traits and descriptions",
	"+ Competenza": "+ Proficiency",
	"Oppure scrivi una competenza": "Or enter a proficiency",
	"Scegli chi concede questa competenza (o senza origine)": "Choose the granting origin (or no origin)",
	"Aggiungi competenza": "Add proficiency",
	"Completa le competenze": "Complete proficiencies",
	"Elimina competenza": "Delete proficiency",
	"Da quale origine vuoi eliminare la competenza?": "From which origin should the proficiency be removed?",
	"✓ competenza attiva · ◇ scelte da completare · ⏻ disattivazione senza eliminare i dati": "✓ active proficiency · ◇ incomplete choices · ⏻ disable without deleting data",
	"Completa le scelte: ": "Complete choices: ",
	"Nessuna competenza disponibile.": "No proficiencies available.",
	"Origini:\n": "Origins:\n",
	"Mestria": "Expertise",
	"Maestria (doppia competenza)": "Expertise (double proficiency)",
	"Attiva o disattiva questa competenza, da tutte le origini, senza eliminarla.": "Enable or disable this proficiency across all origins without deleting it.",
	"Elimina una concessione dall'origine scelta. Le competenze obbligatorie non sono eliminabili.": "Remove a grant from the chosen origin. Mandatory proficiencies cannot be deleted.",
	"Elimina · ": "Delete · ",
	"Completa · ": "Complete · ",
	"L'elenco non è presente nei dati disponibili. Puoi usare + Competenza per una scelta manuale.": "The options are not in the available data. Use + Proficiency for a manual choice.",
	"Competenza: ": "Proficiency: ",
	"Scelta non prevista dai dati strutturati o limite dell'origine raggiunto.": "Choice not allowed by structured data or origin limit reached.",
	"Origine che concede il nuovo bonus, oppure senza origine": "Origin granting the new bonus, or none",
	"+ Bonus": "+ Bonus",
	"Crea un bonus e collegalo all'origine scelta qui accanto.": "Create a bonus and link it to the selected origin.",
	"Attiva o disattiva l'intera origine senza perdere i bonus.": "Enable or disable an origin without losing its bonuses.",
	"Nessun bonus per questo target.": "No bonuses for this target.",
	"Formula": "Formula",
	"Bonus strutturato: valore calcolato dalla fonte 5etools": "Structured bonus: value calculated from 5etools source",
	"Disattiva solo questo bonus (anche se automatico).": "Disable only this bonus (even if automatic).",
	"Elimina questo bonus, senza toccare gli altri.": "Delete this bonus without affecting others.",
	"Nome del tracker": "Tracker name",
	"Numero massimo di utilizzi": "Maximum number of uses",
	"Origine del tracker; viene registrata solo quando aggiungi la risorsa": "Tracker origin; saved when the resource is added",
	"+ Tracker": "+ Tracker",
	"Attiva/disattiva le risorse con questa origine, senza eliminarle": "Enable/disable resources with this origin without deleting them",
	"Nessun tracker disponibile.": "No trackers available.",
	"Massimo derivato dai dati 5etools": "Maximum derived from 5etools data",
	"Massimo utilizzi": "Maximum uses",
	"Rimuovi solo questo tracker": "Remove only this tracker",
	"Inserisci il nome della nuova risorsa.": "Enter the new resource name.",
	"+ Talento": "+ Feat",
	"Cerca talento nel compendio…": "Search feats in compendium…",
	"Scegli l'origine che concede il talento (o senza origine)": "Choose the feat-granting origin (or none)",
	"Aggiungi talento": "Add feat",
	"Rimuovi talento": "Remove feat",
	"Da quale origine rimuovere questo talento?": "From which origin should this feat be removed?",
	"Aggiungi un talento e poi attribuiscigli un'origine. La lista sinistra mostra solo chi concede talenti.": "Add a feat, then assign an origin. The left list shows only feat-granting origins.",
	"Disattiva l'origine e tutti i talenti e benefici che dipendono da essa.": "Disable the origin and all dependent feats and benefits.",
	"Nessun talento disponibile.": "No feats available.",
	"Attiva o disattiva il talento e le origini che dipendono da esso.": "Enable or disable the feat and origins depending on it.",
	"Elimina la concessione da una specifica origine.": "Remove the grant from a specific origin.",
	"Un talento non può essere origine di se stesso.": "A feat cannot be its own origin.",
	"+ Nuovo documento": "+ New document",
	"Documento": "Document",
	"Visualizzazione": "View",
	"Modifica": "Edit",
	"Titolo del documento": "Document title",
	"Testo": "Text",
	"Scrivi il testo del documento…": "Write document text…",
	"Aggiunto: ": "Added: ",
	"Documento · ": "Document · ",
	"Termina modifica": "Finish editing",
	"Scalata": "Climbing",
	"Nuoto": "Swimming",
	"Volo": "Flying",
	"Scavo": "Burrowing",
	"Base": "Base",
	"Massimo": "Maximum",
	"Seleziona": "Select",
	"Nessuno": "None",
	"Elimina": "Delete",
	"Aggiungi": "Add",
	"Mostra": "Show",
	"Nascondi": "Hide",
	"Ricerca": "Search",
	"Tutti": "All",
	"Tutte": "All",
	"Livello base": "Base level",
	"STR": "STR",
	"DEX": "DEX",
	"CON": "CON",
	"INT": "INT",
	"WIS": "WIS",
	"CHA": "CHA",
	"Lingua scheda": "Sheet language",
	"Cambia solo la lingua della GUI delle schede creatura": "Change only the creature-sheet GUI language",
	"Genera il token di questa creatura": "Spawn this creature's token",
	"Livello della classe base (il GS dei mostri è indipendente)": "Base class level (monster CR is independent)",
	"Lunga: %d ft": "Long: %d ft",
	"Max %d": "Max %d",
	"Tira d6: ricarica con %d–6": "Roll d6: recharge on %d–6",
	"Taglia · ": "Size · ",
	"Acrobazia": "Acrobatics",
	"Addestrare Animali": "Animal Handling",
	"Arcano": "Arcana",
	"Atletica": "Athletics",
	"Inganno": "Deception",
	"Storia": "History",
	"Intuizione": "Insight",
	"Intimidire": "Intimidation",
	"Indagare": "Investigation",
	"Medicina": "Medicine",
	"Natura": "Nature",
	"Percezione": "Perception",
	"Intrattenere": "Performance",
	"Persuasione": "Persuasion",
	"Religione": "Religion",
	"Rapidità di Mano": "Sleight of Hand",
	"Furtività": "Stealth",
	"Sopravvivenza": "Survival",
	"Origini dei bonus": "Bonus origins",
	"Bonus per statistica": "Bonuses by statistic",
	"Tutti i target": "All targets",
	"PF massimi": "Maximum HP",
	"PF seconda forma": "Second-form HP",
	"Classe Armatura": "Armor Class",
	"Iniziativa": "Initiative",
	"Velocità": "Speed",
	"Modificatore": "Modifier",
	"Tiro salvezza": "Saving throw",
	"Velocità · Camminata": "Speed · Walking",
	"Velocità · Scalata": "Speed · Climbing",
	"Velocità · Nuoto": "Speed · Swimming",
	"Velocità · Volo": "Speed · Flying",
	"Velocità · Scavo": "Speed · Burrowing",
	"Attacco incantesimi": "Spell attack",
	"CD incantesimi": "Spell save DC",
	"Danni incantesimi": "Spell damage",
	"TS concentrazione": "Concentration save",
	"Abilità": "Skill",
	"Risorsa": "Resource",
	"Slot livello ": "Level  slot ",
	"Slot del Patto": "Pact slot",
	"Origini delle competenze": "Proficiency origins",
	"Singole competenze": "Individual proficiencies",
	"Armi": "Weapons",
	"Armature / Scudi": "Armor / Shields",
	"Tiri salvezza": "Saving throws",
	"Strumenti": "Tools",
	"Lingue": "Languages",
	"Nessuna origine": "No origin",
	"Senza origine": "No origin",
	"Origini": "Origins",
	"Origini dei tracker": "Tracker origins",
	"Risorse / Tracker": "Resources / Trackers",
	"Origini dei talenti": "Feat origins",
	"Talenti concessi": "Granted feats",
	"Origini attive": "Active origins",
	"Competenze concesse": "Granted proficiencies",
	"Scegli origine": "Choose origin",
	"Copia": "Copy",
	"Apri": "Open",
	"Salva": "Save",
	"Rimuovi documento": "Remove document",
	"Nuovo documento": "New document",
	"Aggiungi documento": "Add document",
	"Conferma eliminazione": "Confirm deletion",
	"Componenti:": "Components:",
	"Durata:": "Duration:",
	"Fonte:": "Source:",
	"Livello ": "Level ",
	"Massimo:": "Maximum:",
	"Effetti": "Effects",
	"Punti ferita": "Hit points",
	"Resistenza": "Resistance",
	"Immunità": "Immunity",
	"Vulnerabilità": "Vulnerability",
	"Effetto": "Effect",
	"Condizioni": "Conditions",
	"Altri effetti": "Other effects",
	"Diseases / magical diseases": "Diseases / magical diseases",
	"Tutti gli oggetti": "All items",
	"Rarità": "Rarity",
	"Comune": "Common",
	"Non comune": "Uncommon",
	"Raro": "Rare",
	"Molto raro": "Very rare",
	"Leggendario": "Legendary",
	"Artefatto": "Artifact",
	"Mischia": "Melee",
	"Distanza": "Ranged",
	"Una mano": "One hand",
	"Due mani": "Two hands",
	"Principale": "Main",
	"Secondaria": "Off hand",
	"Scudo": "Shield",
	"Armatura": "Armor",
	"Equipaggia": "Equip",
	"Disequipaggia": "Unequip",
	"SALTO IN LUNGO": "LONG JUMP",
	"SALTO IN ALTO": "HIGH JUMP",
	"Con rincorsa (almeno 10 ft): ": "With a run-up (at least 10 ft): ",
	"Da fermo (senza rincorsa): ": "Standing (without a run-up): ",
	"Doppio clic per modificare i valori consentiti.": "Double-click to edit permitted values.",
	"Clic destro per gestire i bonus e le loro origini.": "Right-click to manage bonuses and their origins.",
	"Nessuna competenza": "No proficiency",
	"nessuna competenza": "no proficiency",
	"nessuno": "none",
	"Modifica da Visualizza e modifica → Competenze": "Edit under View and edit → Proficiencies",
	"Competenza:": "Proficiency:",
	"Percezione passiva:": "Passive Perception:",
	"Vai al privilegio: ": "Go to feature: ",
	"Ripristina le azioni all'inizio del turno": "Reset actions at the start of the turn",
	"Ripristina tutti gli utilizzi (manuale)": "Restore all uses (manual)",
	"Nessuna velocità speciale concessa; scalare o nuotare è comunque possibile con il normale costo aggiuntivo di movimento.": "No special speed granted; climbing or swimming is still possible at the usual extra movement cost.",
	"Seleziona almeno un valore per vedere l'anteprima.": "Select at least one value to preview.",
	"Competenze e abilità: risincronizzate dalle origini; TS, abilità e modificatori si aggiornano dalle formule.": "Proficiencies and skills: synced from origins; saves, skills and modifiers update from formulas.",
	"Nessuna classe magica.": "No spellcasting class.",
	"non disponibili": "unavailable",
	"PF non calcolabili: ": "HP cannot be calculated: ",
	"PF massimi → ": "Maximum HP → ",
	"Competenza → ": "Proficiency → ",
	"Dadi vita: ": "Hit dice: ",
	"XP minimi: ": "Minimum XP: ",
	"Iniziativa: ": "Initiative: ",
	"Iniziativa ": "Initiative ",
	"Portata ": "Reach ",
	"Slot dal livello: ": "Slots from level: ",
	"Patto ": "Pact ",
	"Massimi derivati dai dati strutturati: ": "Maxima derived from structured data: ",
	"Nessuna arma": "No weapon",
	"nessun effetto VTT associato.": "no associated VTT effect.",
	"effetto VTT non attivabile senza un token collegato.": "VTT effect unavailable without a linked token.",
	"Tutte le origini": "All origins",
	"Tutte le competenze": "All proficiencies",
	"Valore": "Value",
	"Origini:": "Origins:",
	"Doppio clic": "Double-click",
	"Gli incantesimi effettivamente scelti non vengono cambiati. I PF attuali sono conservati (limitati al nuovo massimo).": "Selected spells are not changed. Current HP are preserved (capped at the new maximum).",
	"CA ": "AC ",
	"(scudo compreso)": "(including shield)",
	"Camminata: ": "Walking: ",
	"Nessuna velocità speciale": "No special speed",
	"Mano principale": "Main hand",
	"Mano secondaria": "Off hand",
	"Tutte le armi": "All weapons",
	"Naturale": "Natural",
	"CA naturale · formula": "Natural AC · formula",
	"CA naturale": "Natural AC",
	"Formula per la CA senza armatura: per esempio 10 + dex_mod, 13 + dex_mod o 16. Le variabili seguono le formule dei bonus.": "Unarmored AC formula: e.g. 10 + dex_mod, 13 + dex_mod, or 16. Variables follow bonus formulas.",
	"Armatura indossata; scegli Naturale per utilizzare la formula senza armatura.": "Worn armor; choose Natural to use the unarmored formula.",
	"Base precedente (compatibilità)": "Previous base (compatibility)",
	"Occupata": "Occupied",
	"una mano": "one-handed",
	"due mani": "two-handed",
	"PORTATA ATTIVA": "ACTIVE REACH",
	"Usa portata": "Use reach",
	"Attiva questo attacco per la portata tattica, senza cambiare l'equipaggiamento.": "Use this attack for tactical reach without changing equipment.",
	"Mostra anche armi senza Finesse nella mano secondaria. Finesse non è un requisito per combattere con due armi: normalmente serve la proprietà Leggera.": "Also show offhand weapons without Finesse. Finesse is not required to fight with two weapons: the Light property is normally required.",
	"Spunta la casella di un oggetto nell’elenco per equipaggiarlo. Armi, scudi e armature: Statistiche.": "Tick an item's checkbox to equip it. Weapons, shields and armor: Statistics.",
	"Clicca sulla casella a sinistra per equipaggiare o riporre l’oggetto.": "Click the checkbox on the left to equip or stow the item.",
	"Equipaggiato": "Equipped",
	"Indossata": "Worn",
	"taglia": "size",
	"L'armatura sostituisce la formula naturale": "Armor replaces natural AC formula",
	"Base precedente": "Previous base",
	"Formula di CA naturale (senza armatura), modificabile premendo Invio.": "Natural AC formula (unarmored), editable by pressing Enter.",
	"Usa l'attacco della mano secondaria": "Use the offhand attack",
	"Attacco aggiuntivo con due armi": "Two-weapon bonus attack",
	"Lancia l'arma della mano secondaria": "Throw the offhand weapon",
	"Guerriero a due armi": "Two-weapon fighter",
}
const IT: Dictionary = {
	"STR": "FOR",
	"DEX": "DES",
	"CON": "COS",
	"INT": "INT",
	"WIS": "SAG",
	"CHA": "CAR",
	"Car.": "Car.",
	"Save": "TS",
}

static func read_locale() -> String:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		var value := String(config.get_value("creature_gui", "language", "it"))
		if value in ["it", "en"]:
			return value
	return "it"

static func write_locale(language: String) -> void:
	if language not in ["it", "en"]:
		return
	var config := ConfigFile.new()
	config.set_value("creature_gui", "language", language)
	config.save(CONFIG_PATH)

static func text_for(source: String, language: String) -> String:
	var dictionary: Dictionary = EN if language == "en" else IT
	if dictionary.has(source):
		return String(dictionary[source])
	if source.contains("\n"):
		var lines := source.split("\n")
		var changed := false
		for index in range(lines.size()):
			var translated := text_for(lines[index], language)
			if translated != lines[index]:
				lines[index] = translated
				changed = true
		if changed:
			return "\n".join(lines)
	# Compose only UI portions (for example skill name · DEX). Catalog names
	# and free-form input are never passed through a broad text replacement.
	if source.contains(" · "):
		var fragments := source.split(" · ")
		var changed := false
		for index in range(fragments.size()):
			var translated := text_for(fragments[index], language)
			if translated != fragments[index]:
				fragments[index] = translated
				changed = true
		if changed:
			return " · ".join(fragments)
	if language == "it":
		return source
	# Common generated GUI messages: translate fixed labels, keep their numbers
	# and original creature/spell/item names intact.
	for prefix in ["Strumenti: ", "Linguaggi: ", "Completa le scelte: ",
		"CA ", "Camminata: ",
		"Con rincorsa (almeno 10 ft): ", "Da fermo (senza rincorsa): ",
		"PF massimi → ", "Competenza → ", "PF non calcolabili: ",
		"Vai al privilegio: ", "Slot dal livello: ",
		"Dadi vita: ", "XP minimi: ", "Iniziativa: ", "Portata ",
		"Massimi derivati dai dati strutturati: ",
		"Taglia · ", "Slot livello ", "Livello ",
		"Competenza: ", "Elimina · ", "Completa · ", "Aggiunto: ",
		"Documento · ", "ID catalogo: ", "Origini:\n"]:
		if source.begins_with(prefix):
			return String(EN[prefix]) + source.substr(prefix.length())
	for fmt in ["LIVELLO %d", "%d tratti e descrizioni", "Lunga: %d ft", "Max %d", "Tira d6: ricarica con %d–6", "Consuma uno slot di livello %d",
		"Ricarica uno slot di livello %d"]:
		var parts := fmt.split("%d")
		if parts.size() == 2 and source.begins_with(parts[0]) and source.ends_with(parts[1]):
			var middle := source.substr(parts[0].length(), source.length() - parts[0].length() - parts[1].length())
			if middle.is_valid_int():
				return String(EN[fmt]) % int(middle)
	return source

static func apply(root: Node, language: String) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root is Label or root is Button:
		_translate_property(root, "text", language)
	# Opt in only for our computed summaries, never 5etools descriptions.
	if root is RichTextLabel and bool(root.get_meta("creature_gui_text", false)):
		_translate_property(root, "text", language)
	if root is LineEdit or root is TextEdit:
		_translate_property(root, "placeholder_text", language)
	if root is Control:
		_translate_property(root, "tooltip_text", language)
	if root is Window:
		_translate_property(root, "title", language)
	if root is AcceptDialog:
		_translate_property(root, "dialog_text", language)
		_translate_property(root, "ok_button_text", language)
	if root is ConfirmationDialog:
		_translate_property(root, "cancel_button_text", language)
	if root is TabContainer:
		var tabs := root as TabContainer
		for i in range(tabs.get_tab_count()):
			var tab: Node = tabs.get_tab_control(i)
			var value := tabs.get_tab_title(i)
			var result := _localized(tab, "tab_title", value, language)
			if result != value:
				tabs.set_tab_title(i, result)
	if root is OptionButton:
		var options := root as OptionButton
		for i in range(options.item_count):
			var value := options.get_item_text(i)
			var result := _localized(options, "option_" + str(i), value, language)
			if result != value:
				options.set_item_text(i, result)
	elif root is PopupMenu:
		var menu := root as PopupMenu
		for i in range(menu.item_count):
			if menu.is_item_separator(i):
				continue
			var value := menu.get_item_text(i)
			var result := _localized(menu, "item_" + str(i), value, language)
			if result != value:
				menu.set_item_text(i, result)
	for child in root.get_children():
		apply(child, language)

static func _translate_property(node: Object, property_name: String, language: String) -> void:
	var current: String = String(node.get(property_name))
	var localized := _localized(node, property_name, current, language)
	if localized != current:
		node.set(property_name, localized)

static func _localized(node: Object, key: String, current: String, language: String) -> String:
	var initial_key := "creature_locale_original_" + key
	var last_key := "creature_locale_last_" + key
	var locale_key := "creature_locale_language_" + key
	# No redundant translations or layout invalidation during periodic refresh.
	if (node.has_meta(last_key) and current == String(node.get_meta(last_key))
		and String(node.get_meta(locale_key, "")) == language):
		return current
	var original: String = String(node.get_meta(initial_key, current))
	if current != String(node.get_meta(last_key, original)):
		original = current
		node.set_meta(initial_key, original)
	elif not node.has_meta(initial_key):
		node.set_meta(initial_key, original)
	var localized := text_for(original, language)
	node.set_meta(last_key, localized)
	node.set_meta(locale_key, language)
	return localized
