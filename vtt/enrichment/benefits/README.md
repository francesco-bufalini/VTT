# Supplementi meccanici per tipo di beneficio

Questa cartella raccoglie **solo i benefici non già disponibili come campi
strutturati di 5eTools**, in un singolo catalogo `<tipo>.json` per meccanica.

Un background non possiede un file separato: ogni integrazione sarà una voce
nel catalogo pertinente (per esempio `proficiency.json`, `roll_bonus.json`,
`resource.json`), con `granted_by.kind = "5etools"` e
`ref = { "category": "background", "name": "...", "source": "..." }`.

## Prima di aggiungere una voce

1. Verificare `data/backgrounds.json` nel mirror 5eTools usato per il
   compendio. Competenze, talenti iniziali, caratteristiche, incantesimi
   aggiuntivi ed equipaggiamento spesso sono già espressi strutturalmente.
2. Se il campo c'è in 5eTools ma manca negli indici VTT/PWA, **correggere
   importatore o generatore**. Non duplicarlo in un supplemento.
3. Solo se la meccanica manca realmente in 5eTools, aggiungerla sotto il
   suo tipo con origine canonica `name + source`, senza copiare la prosa.
4. Le aggiunte manuali appartengono esclusivamente alla scheda del
   personaggio, `scope: character`, mai ai file condivisi.

Per classificare le differenze tra i dati upstream e gli indici locali:

```sh
python scripts/audit_background_benefits.py \
  --upstream /path/to/5etools-src/data/backgrounds.json \
  --output /tmp/vtt-background-audit.json
```

L'assenza di un file `<tipo>.json` significa che non è ancora stato
individuato un supplemento verificato per quel tipo; non significa che il
background non conceda quel beneficio. Le concessioni 5eTools restano la
fonte primaria. La migrazione del runtime non è ancora completata.

---

## Classi e sottoclassi: primo lotto

**Cataloghi per tipo**, non per origine. I benefici sono concessi da un
`granted_by.ref` 5eTools con nome/fonte canonica e classe/sottoclasse;
il motore non associa privilegi tramite descrizioni localizzate.

### Benefici migrati

| Nuovo catalogo | Origine temporanea legacy | Regole |
| --- | --- | ---: |
| [`action.json`](action.json) | `vtt/data/action_feature_overrides.json` | 52 |
| [`roll_bonus.json`](roll_bonus.json) | `pwa/catalog/roll_bonus_rules.json` | 15 |

Sono incluse le varianti `PHB`/`XPHB`/`TCE`, i privilegi di sottoclasse
quali Rune Knight, Champion, Fey Wanderer, Samurai, Cavalier e Zealot,
e tutte le opzioni di attivazione precedentemente note. Ogni voce
contiene **una sola meccanica** e il riferimento al tratto 5eTools
che la concede. Le descrizioni originali rimangono nei dati di 5eTools.

`pwa/class_benefit_catalogs.js` proietta i nuovi cataloghi nella forma
dati già interpretata dalle azioni e dal sistema dei bonus ai tiri.
`sheet_rules.loadRuleCatalogs()` e `action_economy.loadFeatureActionOverrides()`
leggono ora i JSON tipizzati con fallback al file precedente **solo quando
il nuovo URL non è disponibile** su host vecchi. Un JSON v2 malformato
non viene sostituito silenziosamente con i dati legacy.

I vecchi file rimangono temporaneamente nel repository come sorgenti
di confronto per le regressioni e per i lettori non ancora migrati.
**Non aggiungere nuovi privilegi ai due cataloghi legacy**: usare i file
nuovi; una fase successiva rimuoverà le copie dopo aver verificato
tutti gli altri lettori e i generatori.

### Ancora da migrare nelle classi

- `feature_timing_recovery_rules.json`: attivazioni contestuali,
  recuperi, progressioni di attacchi e sequenze OR.
- `class_resource_overrides.json`: capienza delle risorse di classe.
- `trait_states.json`: stati e scelte di sottoclasse (le regole globali
  di Exhaustion devono rimanere fuori dai benefici).
- `spellcasting_benefits.json`, `optional_feature_progressions.json`,
  `power_selections.json`, `feature_item_grants.json` e altre
  meccaniche concesse dai privilegi.

Ogni lotto deve migrare la proiezione runtime e la validazione,
evitando di concedere nuove competenze, spell o altri benefici già
strutturati in 5eTools. Le modifiche manuali degli utenti rimangono
nella scheda e non vengono riscritte da questa migrazione.

---

## Razze: attacchi naturali e vincoli al volo

[attack.json](attack.json) contiene 20 attacchi naturali supplementari
ricavati esclusivamente in fase di build dai tratti 5eTools con meccanica
univoca. [movement.json](movement.json) aggiunge 10 vincoli all'uso della
velocità di volo quando si indossano armature medie o pesanti. Non si
duplicano le velocità o le competenze già strutturate in 5eTools.

Le voci identificano il privilegio `species_trait` e la fonte esatta.
`pwa/tools/species_mechanics.mjs` può rigenerare i file e la suite
verifica la parità con la precedente proiezione dei benefici.
La PWA utilizza `pwa/species_benefit_catalogs.js` come adattatore,
senza interpretare le descrizioni originali durante la partita.

Le capacità di `species_powers.json` restano da migrare; le
difese già strutturate in 5eTools non vanno semplicemente copiate
in un catalogo `defense.json`.

---

## Classi e sottoclassi: secondo lotto — risorse e azioni composte

Le nuove dichiarazioni sono raggruppate **solo per meccanica**, non per classe:

| Tipo | Voci di classi/sottoclassi | Origine legacy |
| --- | ---: | --- |
| [`action.json`](action.json) | 65 ulteriori (117 totali di classe) | `feature_timing_recovery_rules.actions` |
| [`activation.json`](activation.json) | 31 | `feature_timing_recovery_rules.contextual_actions` |
| [`resource_recovery.json`](resource_recovery.json) | 17 | `feature_timing_recovery_rules.recoveries` |
| [`attack_count.json`](attack_count.json) | 0 (solo compatibilità legacy/homebrew) | Vecchie concessioni `attack_count_grants` |
| [`action_sequence.json`](action_sequence.json) | 38 (12 sequenze preesistenti + 26 multiattacchi) | `feature_timing_recovery_rules.attack_actions` e `attack_count_grants` |
| [`resource.json`](resource.json) | 90 | `class_resource_overrides.classes[].resources` |

I 26 benefici precedentemente espressi come `attack_count` (Extra Attack, Thirsting Blade e Devouring Blade) sono ora vere `action_sequence`, ognuna con uno step `{ "selector": { "kind": "attack" }, "count": N }`, costo di un'azione e `attack_replacement: true`. Il motore presenta soltanto la sequenza attiva più potente, senza sommare gli attacchi concessi da più tratti, e lascia l'Attacco di base quando non è attiva alcuna sostituzione. I multiattacchi dei mostri continuano a usare le proprie sequenze, anche quando includono attacchi specifici o capacità.

`pwa/class_benefit_progression.js` ricompone solo **in memoria** le strutture
attualmente usate dall'app, rispettando i nomi dei tracker, le priorità,
le sequenze OR e le condizioni per classe/sottoclasse. Il nuovo `resource.json`
integra il catalogo della classe; i valori dei contatori derivati dalle
**tabelle strutturate di 5eTools** restano prioritari nel calcolo di
`resourceTrackers()`. I dettagli ridondanti delle tabelle sono ancora presenti
nei supplementi legacy per compatibilità, ma non devono essere aggiunti come
nuove concessioni se già forniti da 5eTools.

L'`action.json` comune distingue le 52 precedenti regole di override dalle
65 attivazioni temporizzate mediante il campo transitorio `projection`.
È una distinzione esclusivamente dell'adattatore di migrazione, non una
nuova tipologia di beneficio: il file resta **uno per tipo**.

I vecchi JSON rimangono esclusivamente per compatibilità con host precedenti,
test di regressione e sistemi non ancora migrati. Non usarli per nuovi
benefici. I dati globali non collegati a un privilegio, incluse le regole
generali di riposo, **non** diventano concessioni di classe.

Verifica: `pwa/tests/class_benefit_progression_migration.test.mjs` confronta
**tutte** le 241 nuove voci con le proiezioni legacy originali e controlla
i riferimenti alle sottoclassi e il fallback degli host vecchi.

**Ancora da migrare:** stati, concessioni di oggetti/incantesimi, meccaniche
speciali e scelte dei privilegi. Le aggiunte manuali dei giocatori rimangono
memorizzate nelle rispettive schede, non nel catalogo condiviso.

---

## Capacità delle specie: azioni, tracker e dadi

Il primo lotto di `species_powers.json` è stato spostato nei cataloghi per tipo:
`action.json` (20 azioni razziali), `resource.json` (12 risorse condivise da
azioni e bonus ai dadi) e `roll_bonus.json` (2 bonus razziali aggiuntivi).
Un singolo privilegio può concedere più benefici: l'azione fa riferimento
alla risorsa mediante il suo ID, senza copiarne usi e recupero.

Il campo `action_runtime`, validato con `$defs.actionRuntime` in
`authoring/benefit.schema.json`, definisce le opzioni delle azioni
(cura, condizione temporanea, risposta ai danni, riferimento ad attacco
esistente, tiro descrittivo). `speciesPowersFromBenefits` ricostruisce
la struttura usata dalla PWA senza duplicare descrizioni 5eTools.

Rimangono in `species_powers.json` solo le meccaniche non ancora migrate:
teletrasporti, forme e ascendenti draconici, scelte per il riposo,
incantesimi concessi e annotazioni passive. La migrazione è parziale,
e queste proprietà non vanno copiate in altri cataloghi finché il
runtime non sarà aggiornato per consumarle.

---

## Scelte di privilegi: option_grant e option_list

Le 17 progressioni di opzioni di classi e sottoclassi, i 3 selettori
speciali e le 21 concessioni di incantesimi sono ora dichiarati in
[`option_grant.json`](option_grant.json) (41 concessioni in totale).

Le 272 opzioni di `optional_feature_progressions.json` sono conservate
con ID e payload esatti in [`option_list.json`](option_list.json): una voce
source-qualified per ciascuna optional feature 5eTools, inclusi i suoi
`types` e gli eventuali effetti specifici. Le 17 concessioni usano ora
`source.type = "list_refs"` con `feature_types` per interrogare questo
catalogo condiviso, senza duplicare le opzioni tra Fighting Style,
Maneuvers o altre concessioni. `pwa/power_selection.js` legge i nuovi
dati in priorità e usa le opzioni legacy soltanto quando il nuovo
catalogo non è disponibile sui vecchi host/offline shell.

I file precedenti rimangono temporaneamente per compatibilità con codice
e test non ancora migrati. Non aggiungere nuove opzioni ai dati legacy.
I privilegi di magia delle classi mantengono inoltre la precedente logica
runtime di selezione degli incantesimi: la concessione tipizzata non è
ancora una sostituzione del relativo motore.

Al caricamento, `sheet_rules.loadRuleCatalogs()` verifica che tutte le famiglie
di opzioni richieste dai grant tipizzati siano presenti in `option_list.json`:
in tal caso **non scarica** il catalogo legacy da 272 opzioni. Se il
catalogo tipizzato manca o è incompleto, il vecchio JSON rimane il fallback.

---

## Dadi progressivi di classe e sottoclasse

Le tre progressioni supplementari di `pwa/catalog/scaling_dice.json` sono
dichiarate in [`scaling_die.json`](scaling_die.json), con origini 5eTools
qualificate. Comprendono Ispirazione Bardica (PHB/XPHB) e Superiorità
(Battle Master, PHB). L'adattatore `pwa/scaling_dice.js` ricostruisce la
forma attesa dal calcolo della scheda conservando ID, livello e priorità.
I dadi homebrew della scheda restano separati. Il vecchio JSON serve
soltanto ai client precedenti; un catalogo v2 presente ma invalido
non deve essere sostituito silenziosamente dal legacy.

---

## Oggetti concessi da privilegi

Il catalogo [`item_grant.json`](item_grant.json) contiene le cinque
concessioni di oggetti non espresse dai soli campi strutturati 5eTools:
Armor Modifications, Eldritch Cannon, The Right Tool for the Job,
Performance of Creation e Tinker (Rock Gnome). Ogni record ha un
`granted_by` con fonte di classe/sottoclasse o specie; le istanze
individuali create restano nella scheda e non nel catalogo condiviso.

`pwa/feature_item_grants.js` ricostruisce temporaneamente il contratto
runtime v1; le proprietà di selezione e uso dell'oggetto che non hanno
ancora campi comuni nel modello tipizzato sono conservate in
`benefit.parameters`, non in nuovi file separati per privilegio.
Il vecchio `pwa/catalog/feature_item_grants.json` resta disponibile
solo per host precedenti e per confronto di regressione.

---

## Estensioni degli effetti

[`effect_extension.json`](effect_extension.json) contiene 26 estensioni
concedibili dai tratti 5eTools (invocazioni del Warlock, College of Creation,
Arcane Armor e infusioni dell'Artefice). Le identità delle infusioni
provengono da `vtt/data/artificer_infusions_5etools.json`. L'operazione
è espressa in `benefit.effects[]`, con metadati di destinazione supplementari
in `effects[].parameters`. `pwa/effect_extensions.js` proietta i record
nella struttura runtime già in uso, mantenendo i vincoli sulle singole
istanze di oggetti; il vecchio JSON resta solo per host precedenti.

Le 3 scelte personalizzate di `power_selections.json` e le 21 progressioni
di `spellcasting_benefits.json` non sono più scaricate sui client dotati
del catalogo tipizzato completo. I metadati delle concessioni rimangono in
`option_grant.json` e i profili slot in `resource.json`; il motore legge
direttamente entrambi. I vecchi file sono consultati solo come fallback se
una delle famiglie tipizzate risulta incompleta.

---

## Capacità locali e option grant annidati

`option_list.json` definisce anche capacità intermedie non presenti come voci
separate in 5eTools (`local:arcane-armor`, `local:armor_model:guardian`,
`local:armor_model:infiltrator`). Le opzioni possono concedere il beneficio
`{type: "option_grant", grant_id: "..."}`: il motore attiva il grant figlio
solo quando l'opzione che lo concede è applicata a un tratto o a un oggetto.
Le capacità passive applicate espongono benefici nel tratto Stato generato;
quelle applicate a oggetti espongono i benefici nell'estensione dell'oggetto.

Arcane Armor può estendere più armature separatamente, senza limite né trigger;
ogni estensione concede il proprio Armor Model con due capacità locali,
una sola applicabile (trigger riposo corto). Le due vecchie voci Armor Model
non sono più nel catalogo degli stati legacy; le regole globali di Exhaustion
rimangono fuori da questa migrazione. Druidic Warrior, Blessed Warrior e
Pact of the Tome concedono lo stesso tipo di `option_grant` annidato per la
scelta di trucchetti (filtri e quantità dichiarati nei dati, senza logiche
specifiche sul tipo di slot). Non si aggiunge alcuna migrazione di schede
personaggio pre-release.

## Flavour di tratto e concessioni di talenti

`flavours.json` dichiara varianti nominate di un tratto 5eTools/homebrew; non è un
beneficio primitivo. Ogni voce è legata all'identità originale tramite
`granted_by`; ogni flavour ha un ID globale stabile. I cataloghi per tipo
possono riferirsi a `granted_by: {kind: "flavour", ref: {category: "flavour", id: "..."}}`.
Solo il flavour selezionato concede i relativi benefici. La scelta viene salvata
per istanza del tratto (`trait_flavours[origin_id]`), inclusi privilegi ripetuti
ad ogni livello.

`bonus.json` contiene due concessioni +1 indipendenti per il flavour ASI
«incremento caratteristiche»: entrambe consentono di scegliere la stessa
caratteristica, dando complessivamente +2, o caratteristiche differenti.
`feat_grant.json` contiene la concessione standardizzata di un talento per
l'altro flavour ASI. `defense.json` attribuisce le resistenze draconiche ai
flavour di ascendenza; la logica speciale del soffio rimane indipendente.
Il talento Athlete PHB dimostra una scelta tra flavour di bonus permanente.

Le scelte esistenti (`advancement_choices`, `origin_draconic_ancestry` e
`ability_choice` dei talenti) vengono lette per compatibilità; una scelta
esplicita del nuovo flavour diventa la fonte di verità, senza sommare i bonus
legacy. La validazione usa `authoring/flavours.schema.json` e i normali
schemi dei benefici per gli effetti collegati ai flavour.

### Migrazione delle scelte di caratteristica dei talenti

I dati 5eTools di `pwa/catalog/ability_grants.json` rimangono fonte per i
riferimenti e le descrizioni, ma le 151 scelte semplici di caratteristica in
più (oltre ad Athlete PHB già migrato) hanno ora un flavour per ogni
caratteristica ammessa, con un beneficio `bonus` separato per +1. Il motore
legacy viene usato soltanto per le scelte non ancora salvate nel nuovo formato;
quando si sceglie un flavour, il vecchio `ability_choice` del talento viene
azzerato e il calcolo sopprime il suo vecchio incremento per evitare doppioni.
Ogni feat usa l'identità stabile `feat|source|name`, anche se compare con
più sezioni nella scheda.

Restano in attesa di migrazione dedicata `Resilient` PHB/XPHB (la scelta
concede anche competenza in un tiro salvezza, con vincolo ulteriore nel 2024),
`Potent Dragonmark` EFA (la caratteristica deve essere quella scelta dal
Dragonmark) e il talento `Ability Score Improvement` XPHB (possiede due
varianti di distribuzione dei punteggi, distinte dall'ASI di classe).

## Beneficio state_activation: attivazione degli Stati

`state_activation.json` definisce **soltanto** attivazione e disattivazione
di uno Stato passivo identificato da `state_id`: `mode` (`toggle`,
`activate`, `deactivate`), economia di azione (`activation` e
`deactivation`) e facoltativamente `resource.id` / `resource.cost`.
Il costo si applica esclusivamente durante l'attivazione e fa riferimento
a un tracker già concesso da `resource.json`, senza crearne uno nuovo.

Le definizioni degli Stati e i benefici che questi applicano rimangono
separati. `trigger` è informazione contestuale, non un esecutore automatico
di eventi. La PWA integra queste voci nei propri Stati di classe/sottoclasse
esistenti; gli ID salvati restano invariati. Il catalogo parte vuoto:
le scelte permanenti come i Totem non vengono trasformate arbitrariamente
in attivazioni gratuite.
