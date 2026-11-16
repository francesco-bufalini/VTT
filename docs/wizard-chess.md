# Scacchi dei Maghi — I Figli dell'Apocalisse

Nuovo scenario incorporato nel menu **Campagne attive → I Figli dell'Apocalisse → Scacchi dei Maghi**.

## Giocare

La scena crea una scacchiera tridimensionale 8×8 e 32 token stilizzati. I token chiari sono i **bianchi** (in basso, vicino al giocatore); i token scuri sono i **neri**. Le lettere sui token indicano K = Re, Q = Regina, R = Torre, B = Alfiere, N = Cavallo, P = Pedone.

1. I bianchi giocano per primi. Clicca un token del colore di turno.
2. Le caselle di destinazione legale diventano verdi; cliccane una per muovere e, se occupata da un avversario, catturare.
3. **All'inizio di ciascun turno, prima della mossa**, puoi usare **una trasformazione**: se possiedi pezzi catturati dall'avversario nei turni precedenti, scegli il tipo di pezzo dal pannello «MAGIA: TRASFORMA UN PEZZO», poi clicca un tuo token evidenziato in azzurro per sostituirlo. Il Re non può essere trasformato. Il pezzo catturato usato viene rimosso dalla riserva. La trasformazione **è temporanea**: il token può muoversi con la nuova forma durante il turno in corso, resta trasformato durante la mossa avversaria e **ritorna alla propria forma originale all'inizio del successivo turno del proprietario**, anche se si è spostato. Se viene catturato prima, non ritorna; la riserva riceve il pezzo originale. La trasformazione non passa il turno: devi ancora eseguire una mossa normale. Puoi anche saltare la trasformazione e muovere direttamente.
4. Il turno passa automaticamente al colore opposto **dopo la mossa normale**. Il re sotto scacco è evidenziato in rosso.
5. Alla promozione del pedone, scegli Regina, Torre, Alfiere o Cavallo.
6. **Annulla ultima azione** annulla separatamente trasformazione e mossa, ripristinando anche le riserve; **Nuova partita** ripristina tutti i pezzi e svuota le riserve.
7. **Torna agli scenari** riapre la lista della campagna.

## Poteri dei pezzi

I poteri si attivano selezionando un pezzo e usando il pulsante corrispondente nel pannello **POTERI DEI PEZZI**. Ogni pedone, torre, alfiere e cavallo ha un'identità propria: il relativo potere è **una volta per partita per quel token fisico**, anche se viene catturato e successivamente riportato in campo. I poteri gratuiti non consumano la normale mossa; lo **Scatto** e la **Carica** sostituiscono la mossa normale. I poteri persistono nel salvataggio e possono essere annullati con **Annulla ultima azione**.

- **Pedone — Scatto:** una sola volta, può avanzare fino a **tre caselle** lungo la stessa colonna, purché libere, oppure spostarsi di **una casella diagonalmente in avanti**, anche se vuota. Può catturare un nemico nella casella diagonale. La mossa deve rispettare scacco e muri e può comportare una promozione.
- **Torre — Muro:** una sola volta può creare un muro sulla **riga** o sulla **colonna** che la contiene. Il muro resta fino a fine partita, anche se la Torre viene catturata. I pezzi avversari non possono entrare sulle caselle del muro né attraversarlo; i pezzi del giocatore che l'ha creato sono liberi di attraversarlo. I muri sono evidenziati in azzurro (bianchi) o viola (neri).
- **Alfiere su casella chiara — Resurrezione:** una sola volta può scegliere un proprio pezzo catturato non maledetto e rimetterlo su una **casella vuota adiacente**, anche in diagonale. Il pezzo recuperato viene tolto dalla riserva e mantiene i suoi precedenti utilizzi dei poteri.
- **Alfiere su casella scura — Maledizione:** una sola volta può maledire un pezzo avversario non sovrano, ovunque sulla scacchiera. Il pezzo maledetto non può più essere **trasformato** né **resuscitato**, neanche in turni successivi; la maledizione segue il suo token e non scompare se viene catturato. I pezzi maledetti sono marcati da un simbolo ✖.
- **Cavallo — Carica travolgente:** una sola volta può percorrere una L nella quale segue prima **due caselle nella direzione lunga**, poi **una casella perpendicolare**. Cattura **tutti** i pezzi nemici incontrati sulle tre caselle, non può travolgere alleati o sovrani nemici, né attraversare muri ostili. La casella finale deve essere raggiungibile senza lasciare il proprio sovrano sotto scacco.
- **Regina — Colpo di Stato:** **una sola volta per colore**, anche durante il turno avversario, una Regina presente sulla scacchiera può diventare il nuovo **pezzo sovrano**. Conserva le mosse della Regina, ma da quel momento **scacco, scacco matto e stallo** riguardano lei anziché il precedente Re. Il vecchio Re diventa un normale pezzo che si muove come un Re ed è catturabile, senza arrocco. La Regina sovrana è contrassegnata dal simbolo ★. Non si può incoronare una Regina temporaneamente trasformata.

Il potere del Cavallo usa un tragitto definito (prima la parte lunga della L): la disposizione delle caselle intermedie è quindi rilevante. Un pezzo riportato in campo o trasformato conserva la propria identità per il conteggio degli utilizzi. Le trasformazioni temporanee già presenti nel minigioco continuano a scadere all'inizio del turno successivo del proprietario.

## Aspetto dei pezzi: set Lewis

I 32 segnalini impiegano ora **sei modelli scultorei distinti** derivati dal set Lewis fornito in `lewis_chess_set.glb`: Pedone, Torre, Cavallo, Alfiere, Regina e Re. L'originale contiene 11 modelli e texture; per il minigioco sono stati selezionati i sei tipi corrispondenti e alleggeriti, conservandone la geometria essenziale. Le mesh ottimizzate sono salvate nei file `vtt/chess/lewis_*.gd` e decodificate da `lewis_mesh.gd`: **non è necessario aggiungere manualmente il GLB** all'installazione del gioco.

I **bianchi** hanno superficie in avorio chiaro con base dorata, i **neri** sono in una finitura scura color ardesia/viola con base viola. Le forme e i codici dei pezzi sono identici per entrambi i colori; le due finiture sono facilmente distinguibili anche sulla scacchiera. Le lettere, la stella ★ del Re-Regina e la maledizione ✖ rimangono visibili. Una trasformazione, una promozione, una cattura o una resurrezione aggiorna il modello corretto senza dover ricostruire le altre sculture. Il rendering condivide una mesh per tipo per limitare i tempi di aggiornamento.

**Nota di fedeltà:** i modelli sono derivati direttamente dalla geometria 3D del file GLB, ma semplificati (circa 290–400 triangoli per modello) e ricolorati; non incorporano le texture fotografiche originali. Il file completo fornito resta il riferimento per eventuali versioni ad alta definizione.

## Regole e dati

Il motore in `vtt/chess/chess_rules.gd` è indipendente dalla grafica e non considera valide le mosse che lascerebbero il proprio re sotto scacco. Le riserve di pezzi catturati sono distinte per colore e persistono nel salvataggio; anche la forma originale e la casella del token trasformato vengono salvate per garantirne il ritorno al turno seguente. La trasformazione non concede un'altra mossa o un secondo utilizzo nello stesso turno. Il motore evita di dichiarare scacco matto se una trasformazione seguita da una mossa legale può salvare il Re, e non dichiara patta per materiale insufficiente se restano pezzi recuperabili nelle riserve. Gestisce arrocco (incluse caselle attraversate sotto attacco e diritti persi), presa en passant, promozione, scacco, scacco matto, stallo, patta per materiale insufficiente, triplice ripetizione e regola delle 50 mosse. La partita è **locale, a due giocatori sullo stesso computer**, senza avversario controllato dall'IA.

Lo stato viene salvato in modo indipendente dalle mappe e ripristinato riaprendo lo scenario mediante `CampaignManager.save_active_runtime_state()` e `load_active_runtime_state()`. Gli altri scenari del VTT non vengono alterati. I token di gioco sono semplici mesh/etichette tridimensionali, non creature D&D, perciò non possono essere spostati tramite il sistema generale dei token VTT aggirando le regole.

## Test

```powershell
godot --headless --path . --script res://tests/test_wizard_chess.gd
```

La suite comprende inoltre i test per i sei effetti magici, i muri, l'identità dei pezzi e il sovrano trasferito. Verifica mosse iniziali e alternanza, impedimento dei turni doppi, scacco matto, stallo, arrocco, en passant, sottopromozione, annullamento, stato serializzato, riserve dei catturati, trasformazioni una per turno, arrocco dopo trasformazione, annullamento e fuga da scacco grazie a una trasformazione, ritorno automatico alla forma originale dopo il turno avversario (anche a seguito di spostamenti), cattura di un pezzo trasformato, trasformazioni contemporanee dei due colori, interfaccia senza ricreare pulsanti durante il click e 32 token iniziali nella scena. Il workflow `.github/workflows/wizard-chess.yml` esegue lo stesso test su GitHub Actions.
