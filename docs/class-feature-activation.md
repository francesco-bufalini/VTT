# Attivazione dei privilegi di classe

I comandi in Poteri e in Cosa posso fare? usano `class_feature_activation.gd`.
Il privilegio deve essere presente fra le origini attive della creatura. Aprire o
annullare la finestra non consuma utilizzi. Stato e consumo sono salvati nella
scheda locale; nessuna scheda privata di un altro proprietario viene modificata.

## Effetti applicati

- Ira: utilizzo del tracker della classe, stato attivo, vantaggio ai tiri di
  Forza della scheda, resistenze fisiche e bonus ai danni degli attacchi di Forza.
  Il 2014 esclude gli attacchi a distanza, inclusi quelli con armi lanciate;
  il 2024 include gli attacchi con armi o colpi senz'armi basati su Forza.
  Armatura pesante e condizioni incompatibili sospendono i benefici. Attivarla
  interrompe la concentrazione; gli incantesimi non possono essere lanciati
  dalla scheda finche Ira e attiva. Termina non restituisce utilizzi.
- Attacco Irruento: vantaggio per gli attacchi di Forza pertinenti all'edizione.
- Recuperare Energie: cura di 1d10 + livello da Guerriero, entro i PF massimi.
- Imposizione delle Mani: scelta di punti e bersaglio fra le creature locali;
  consumo del paladino e cura del bersaglio sono una sola scrittura atomica.
- Fonte di Magia: conversione slot/punti e creazione di slot temporanei separati
  dalla progressione di classe. Gli slot creati spariscono al riposo lungo.
- Recupero Arcano: scelta degli slot consumati, ciascuno di livello 1-5, entro
  meta del livello da Mago arrotondata per eccesso e con consumo dell'utilizzo.
- Gli altri privilegi elencati (Impeto d'Azione, opzioni Ki/Focus, Incanalare
  Divinita, reazioni difensive) registrano l'attivazione e la risorsa prevista.
  Bersagli, condizioni di innesco e risultati dei tiri del tavolo restano quelli
  descritti dal privilegio: la VTT non inventa azioni, salvezze o danni risolti.

Gli stati temporanei si terminano con il relativo pulsante; la durata e gli
inneschi di fine turno sono gestiti dal giocatore. I riposi rimuovono gli stati.

## Metamagia

Sono disponibili le opzioni realmente selezionate nel personaggio. La finestra
di lancio modifica la copia di quell'incantesimo, senza cambiare il catalogo.
Gittata, tempo di lancio, componenti, durata e numero di bersagli passano anche
al targeting VTT. Il consumo di punti avviene una sola volta quando il targeting
si completa; Esc e i completamenti duplicati non consumano altri punti.

Raddoppiato richiede conferma dei requisiti del bersaglio: il 2014 paga il
livello dello slot (minimo 1), il 2024 paga 1 punto e aggiunge il bersaglio
previsto dall'aumento di livello. Careful e Heightened accompagnano il lancio
con le relative informazioni; salvezze e danni sono risolti dal tavolo come
per l'incantesimo base. Empowered e Seeking si usano dopo il tiro dai privilegi,
con rilancio dei dadi nella chat e consumo al momento dell'utilizzo.

Fonti ufficiali verificate: [Barbaro 2014](https://www.dndbeyond.com/classes/9-barbarian),
[Stregone 2014](https://www.dndbeyond.com/classes/6-sorcerer),
[classi 2024](https://www.dndbeyond.com/sources/dnd/br-2024/character-classes).

## Presentazione e regressioni

Risorse si trova sotto Attacchi disponibili nelle Statistiche. Attacco Extra e
Multiattacco sono nella box Attaccare, con moltiplicatore quando determinabile e
il testo completo nell'hint. I livelli di classi diverse non sommano gli attacchi.

Regressioni: `test_class_feature_activation.gd`, `test_class_feature_ui.gd`,
`test_metamagic_cast_lifecycle.gd` e `test_attack_action_summary.gd`. La prova
visiva usa `test_class_feature_ui.gd -- --visual` con un archivio temporaneo.
