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

## Regole e dati

Il motore in `vtt/chess/chess_rules.gd` è indipendente dalla grafica e non considera valide le mosse che lascerebbero il proprio re sotto scacco. Le riserve di pezzi catturati sono distinte per colore e persistono nel salvataggio; anche la forma originale e la casella del token trasformato vengono salvate per garantirne il ritorno al turno seguente. La trasformazione non concede un'altra mossa o un secondo utilizzo nello stesso turno. Il motore evita di dichiarare scacco matto se una trasformazione seguita da una mossa legale può salvare il Re, e non dichiara patta per materiale insufficiente se restano pezzi recuperabili nelle riserve. Gestisce arrocco (incluse caselle attraversate sotto attacco e diritti persi), presa en passant, promozione, scacco, scacco matto, stallo, patta per materiale insufficiente, triplice ripetizione e regola delle 50 mosse. La partita è **locale, a due giocatori sullo stesso computer**, senza avversario controllato dall'IA.

Lo stato viene salvato in modo indipendente dalle mappe e ripristinato riaprendo lo scenario mediante `CampaignManager.save_active_runtime_state()` e `load_active_runtime_state()`. Gli altri scenari del VTT non vengono alterati. I token di gioco sono semplici mesh/etichette tridimensionali, non creature D&D, perciò non possono essere spostati tramite il sistema generale dei token VTT aggirando le regole.

## Test

```powershell
godot --headless --path . --script res://tests/test_wizard_chess.gd
```

La suite verifica mosse iniziali e alternanza, impedimento dei turni doppi, scacco matto, stallo, arrocco, en passant, sottopromozione, annullamento, stato serializzato, riserve dei catturati, trasformazioni una per turno, arrocco dopo trasformazione, annullamento e fuga da scacco grazie a una trasformazione, ritorno automatico alla forma originale dopo il turno avversario (anche a seguito di spostamenti), cattura di un pezzo trasformato, trasformazioni contemporanee dei due colori, interfaccia senza ricreare pulsanti durante il click e 32 token iniziali nella scena. Il workflow `.github/workflows/wizard-chess.yml` esegue lo stesso test su GitHub Actions.
