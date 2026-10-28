# Incantesimi concessi dai privilegi 2014

Revisione del 28 ottobre 2026: 71 privilegi di 60 sottoclassi dell'edizione
2014, inclusi i supplementi precedenti alla revisione 2024. Le identità
2024 restano separate; le ristampe TCE di Artificer, Spores, Order e Glory
sono preferite alle precedenti pubblicazioni della stessa edizione.

La verifica successiva include anche il talento **Cartomancer (BMT)**:
Prestidigitation è un trucchetto conosciuto gratuito con origine **Card Tricks**,
senza slot, contatori o scelta superflua della caratteristica da incantatore.
Il collegamento e le sezioni nominate del talento sono normalizzati dal
generatore `generate_additional_spells_5etools.py`; Hidden Ace resta un beneficio
separato e non viene dedotto dalla concessione del trucchetto.

## Dati e rigenerazione

`scripts/data/feature_spell_ownership_2014.json` contiene i collegamenti
verificati fra classe, sottoclasse, fonte e tratto concedente. Il generatore
`scripts/generate_feature_spell_grants.py` legge le progressioni strutturate
`additionalSpells` di 5etools v2.37.0 e produce
`vtt/data/feature_spell_grants_2014.json`. I digest SHA-256 dei file sorgenti
sono nel catalogo per rendere verificabile lo snapshot.

```powershell
python scripts/generate_feature_spell_grants.py /percorso/5etools-src
node pwa/tools/sync_native_catalogs.mjs --feature-spells-only
```

Il secondo comando aggiorna solo la sezione `feature_spells` del catalogo
PWA esistente. La sincronizzazione generale include la stessa sezione.
Non occorrono nuove richieste di rete né nuove rotte del server Godot.

Fonti: i file strutturati
[5etools data/class](https://github.com/5etools-mirror-3/5etools-src/tree/master/data/class)
e le descrizioni dei singoli privilegi presenti nello stesso snapshot.
La distinzione fra incantesimi conosciuti e sempre preparati segue le
[Basic Rules 2014](https://www.dndbeyond.com/sources/dnd/basic-rules-2014/classes).

## Comportamento

| Tipo di concessione | Proiezione PWA |
| --- | --- |
| Domini, giuramenti, Artificer, circoli Spores/Wildfire | Incantesimi sempre preparati, con slot ordinari e caratteristica della classe |
| Ranger, Psionic Spells, Clockwork Magic, Lunar Embodiment | Incantesimi conosciuti aggiuntivi, con slot; i trucchetti sono gratuiti |
| Bonus Cantrip, Circle of Mortality, Draconic Gift, Moon Fire, Among the Dead e altre concessioni fisse | Origine collegata al tratto preciso, senza richiedere una riga di tabella |
| Circle of the Land, Divine Magic, Arcane Archer Lore, Giant Power | Un'opzione esplicita; le liste alternative non si sommano |
| Arcane Initiate, Arcane Mastery, Additional Magical Secrets | Scelte esplicite con filtri, numero di selezioni, caratteristica e livello della classe |
| Star Map | Guidance e Guiding Bolt; lanci gratuiti di Guiding Bolt pari a competenza per riposo lungo, oppure slot |
| Grasping Tentacles | Un lancio gratuito per riposo lungo, oppure slot/Pact Magic |
| Consult the Spirits | Augury e Clairvoyance condividono un unico uso per riposo breve/lungo, con SAG |
| Thousand Forms | Alter Self a volontà |
| Liste ampliate dei nove patroni Warlock | Conservate come `expanded`; non diventano incantesimi conosciuti o preparati automaticamente |

Ogni concessione richiede il tratto posseduto e attivo, la fonte esatta e
il livello nella classe pertinente. Livelli in altre classi non sbloccano
la progressione. La lettura generica delle vecchie tabelle viene esclusa
per i privilegi coperti dal catalogo, evitando doppioni e concessioni errate.

Le scelte di opzione sono salvate in `origin_spell_variants`, indicizzate
per l'identità stabile del tratto. I selettori già esistenti gestiscono
sia le opzioni sia gli incantesimi da scegliere. Il campo sopravvive al
salvataggio PWA, alle normalizzazioni native e alle forme con magia
personalizzata. Gli ID delle concessioni precedentemente ottenute dalle
tabelle, le configurazioni per incantesimo e i contatori razziali esistenti
restano compatibili.

## Confini della revisione

Il catalogo distingue le concessioni dagli effetti aggiuntivi del lancio.
Non applica automaticamente PF temporanei/concentrazione di Grasping
Tentacles, bersagli extra di Moon Fire o benefici dipendenti dalla forma.
Star Map richiede ancora che il giocatore tenga attivo il tratto solo
quando possiede e impugna la mappa.

Restano nel backlog i rituali esclusivi, gli incantesimi pagati con Ki o
Sorcery Points, i lanci dipendenti da una trasformazione/fase attiva e le
sostituzioni condizionali delle liste. Le nuove liste ampliate sono
conservate ma non aggiungono automaticamente selezioni alla scheda:
un incantesimo di quella lista deve essere scelto esplicitamente.

## Verifiche

- Test Python del generatore: scelte preservate, proprietari mancanti
  rifiutati, ristampe ed edizioni separate.
- Test PWA con cataloghi reali: modalità/costi, proprietari, multiclasse,
  disattivazione, opzioni esclusive, scelte di Arcana/Lore, contatori e
  compatibilità degli ID salvati.
- Browser mobile: scelta Coast, persistenza dopo riapertura e concessione
  dei soli Mirror Image/Misty Step al livello 3.
- Test Godot del salvataggio di `origin_spell_variants`, concessioni
  esistenti e contatori strutturati.
