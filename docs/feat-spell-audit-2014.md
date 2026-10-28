# Talenti 2014 che concedono incantesimi

La revisione del 28 ottobre 2026 verifica **108 talenti nelle ultime ristampe
dell'edizione 2014**. I **24 talenti ufficiali con `additionalSpells`** e le
**3 opzioni aggiuntive di Plane Shift: Kaladesh** sono tutti rappresentati
nel manifesto verificato; nessuna concessione presente nella sorgente è
rimasta senza una regola di normalizzazione.

Il [report generato](feat-spell-audit-2014.json) elenca le identità, le fonti
e la copertura. `scripts/audit_feat_spells_2014.py` fallisce se una nuova
concessione non ha una regola o se una regola non corrisponde più alla fonte.
Le ristampe 2024/2025 restano identità separate.

## Risultati della revisione

| Talento e fonte | Concessione e correzione |
| --- | --- |
| Aberrant Dragonmark — ERLW | Trucchetto Sorcerer e un incantesimo di livello 1, CON, un uso per riposo breve/lungo |
| Adept of the Black / Red / White Robes — DSotDQ | Scelta limitata alle scuole corrette; un lancio per riposo lungo oppure slot; caratteristica ereditata da Initiate of High Sorcery |
| Artificer Initiate — TCE | Trucchetto e incantesimo Artificer, INT, lancio giornaliero oppure slot |
| Cartomancer — BMT | Prestidigitation appartiene a Card Tricks; gratuito, senza scelta artificiale della caratteristica. Hidden Ace resta distinto e conserva l'interfaccia per le carte integrata dal remoto |
| Divinely Favored — DSotDQ | Trucchetto Cleric, incantesimo di livello 1 dalla lista legata all'allineamento e Augury; usi separati e slot alternativi |
| Drow High Magic — XGE | Detect Magic a volontà; Levitate e Dispel Magic con usi giornalieri distinti e CAR |
| Fey Teleportation — XGE | Misty Step con INT; recupero corretto al riposo breve/lungo, mantenendo gli usi dei vecchi contatori |
| Fey Touched / Shadow Touched — TCE | Incantesimo fisso e scelta filtrata, usi giornalieri distinti o slot; caratteristica uguale a quella aumentata dal talento |
| Gift of the Metallic Dragon — FTD | Cure Wounds appartiene a Draconic Healing, un uso giornaliero oppure slot; INT/SAG/CAR esplicita |
| Initiate of High Sorcery — DSotDQ | Una luna esplicita, un trucchetto Wizard e due incantesimi dalla sola lista di quella luna; un uso giornaliero per ciascun incantesimo oppure slot |
| Magic Initiate — PHB | Una sola classe esplicita per entrambi i trucchetti e l'incantesimo di livello 1; caratteristica della classe, nessuna mescolanza di liste |
| Outlands Envoy — SatO | Misty Step e Tongues appartengono a Crossroads Emissary; usi separati o slot; caratteristica ereditata da Scion of the Outer Planes |
| Ritual Caster — PHB | Due rituali di livello 1 dalla sola classe scelta; nessun falso contatore giornaliero e nessun lancio istantaneo o con slot da questa concessione |
| Rune Shaper — BGG | Comprehend Languages più un numero di rune scelte pari a metà competenza arrotondata per difetto; non concede tutte le 13 rune. Ogni runa ha un uso distinto; il lancio richiede conferma dell'oggetto inciso indossato/trasportato |
| Scion of the Outer Planes — SatO | Una sola affinità planare, il relativo trucchetto e una caratteristica esplicita INT/SAG/CAR |
| Spell Sniper — PHB | Una lista di classe e un trucchetto che richiede un attacco. Il filtro usa i metadati strutturati 5etools, non la descrizione del danno |
| Strixhaven Initiate — SCC | Una sola combinazione del college: due trucchetti e un incantesimo dalla lista corretta; uso giornaliero oppure slot |
| Strixhaven Mascot — SCC | Find Familiar soltanto come rituale, con la forma prevista dal college; nessun falso lancio gratuito istantaneo |
| Svirfneblin Magic — MTF | Nondetection a volontà su se stessi e tre incantesimi con usi giornalieri separati, INT |
| Telekinetic / Telepathic — TCE | Mage Hand / Detect Thoughts; caratteristica derivata dall'aumento del talento; Detect Thoughts conserva il lancio giornaliero e l'alternativa con slot |
| Wood Elf Magic — XGE | Un trucchetto Druid scelto, Longstrider e Pass Without Trace con usi giornalieri separati, SAG |
| Quicksmithing / Servo Crafting — PSK, materiale opzionale | Due effetti rituali di livello 1 / Find Familiar come rituale; contesto esplicito e nessun uso giornaliero inventato |

Gli altri talenti dell'inventario non dichiarano nuove concessioni
`additionalSpells`. L'eventuale scelta di un'invocazione tramite Eldritch
Adept appartiene alla capacità opzionale effettivamente selezionata;
War Caster permette usi condizionali di incantesimi già disponibili.
Nessuno dei due concede automaticamente tutti gli incantesimi menzionati.

## Scelte e salvataggi

Le alternative sono persistenti e modificabili dal selettore dei privilegi.
I vecchi salvataggi con liste unite devono indicare una classe/variante:
solo gli incantesimi ancora legali vengono proiettati. Le scelte precedenti
rimangono archiviate e gli ID dei benefici salvati restano riconoscibili.
I contatori leggono gli ID precedenti e il riposo li azzera insieme a quelli
attuali; cambiare variante non ricarica gratuitamente il talento.

Ogni incantesimo scelto con un uso indipendente ha il proprio contatore.
La caratteristica non può essere dedotta da un valore predefinito quando
dipende dall'aumento di caratteristica o da un altro talento.

Il selettore di lancio richiede una conferma esplicita per il completamento
dei rituali e per il contesto delle rune. Il normale tempo del rituale aumenta
di dieci minuti; non vengono offerti slot o potenziamenti da quella fonte.
Per Ritual Caster il giocatore deve confermare di avere il libro richiesto.
Questo non automatizza il trascorrere del tempo né l'incisione sugli oggetti.

## Generazione e verifica

```powershell
python scripts/audit_feat_spells_2014.py /percorso/5etools-src
python scripts/generate_additional_spells_5etools.py --feats-only /percorso/5etools-src
node pwa/tools/sync_native_catalogs.mjs --origin-spells-only
node pwa/tools/sync_native_catalogs.mjs --feat-mechanics-only
```

Le correzioni tipizzate sono in
`scripts/data/feat_spell_grants_2014.json`, con i digest della sorgente e dei
file dei metadati di attacco. Il catalogo generato è condiviso, mentre questa
revisione completa la proiezione e i selettori della PWA. Non deduce scelte
dal testo narrativo e non sostituisce gli altri effetti del talento.

Fonti: [5etools feats.json](https://github.com/5etools-mirror-3/5etools-src/blob/master/data/feats.json),
[metadati degli incantesimi](https://github.com/5etools-mirror-3/5etools-src/tree/master/data/spells)
e sezioni dei talenti conservate nel compendio locale.
