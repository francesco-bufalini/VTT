# Scacchi dei Maghi — I Figli dell'Apocalisse

Nuovo scenario incorporato nel menu **Campagne attive → I Figli dell'Apocalisse → Scacchi dei Maghi**.

## Giocare

La scena crea una scacchiera tridimensionale 8×8 e 32 token stilizzati. I token chiari sono i **bianchi** (in basso, vicino al giocatore); i token scuri sono i **neri**. Le lettere sui token indicano K = Re, Q = Regina, R = Torre, B = Alfiere, N = Cavallo, P = Pedone.

1. I bianchi giocano per primi. Clicca un token del colore di turno.
2. Le caselle di destinazione legale diventano verdi; cliccane una per muovere e, se occupata da un avversario, catturare.
3. Il turno passa automaticamente al colore opposto. Il re sotto scacco è evidenziato in rosso.
4. Alla promozione del pedone, scegli Regina, Torre, Alfiere o Cavallo.
5. **Annulla ultima mossa** ripristina la posizione precedente; **Nuova partita** ripristina tutti i pezzi.
6. **Torna agli scenari** riapre la lista della campagna.

## Regole e dati

Il motore in `vtt/chess/chess_rules.gd` è indipendente dalla grafica e non considera valide le mosse che lascerebbero il proprio re sotto scacco. Gestisce arrocco (incluse caselle attraversate sotto attacco e diritti persi), presa en passant, promozione, scacco, scacco matto, stallo, patta per materiale insufficiente, triplice ripetizione e regola delle 50 mosse. La partita è **locale, a due giocatori sullo stesso computer**, senza avversario controllato dall'IA.

Lo stato viene salvato in modo indipendente dalle mappe e ripristinato riaprendo lo scenario mediante `CampaignManager.save_active_runtime_state()` e `load_active_runtime_state()`. Gli altri scenari del VTT non vengono alterati. I token di gioco sono semplici mesh/etichette tridimensionali, non creature D&D, perciò non possono essere spostati tramite il sistema generale dei token VTT aggirando le regole.

## Test

```powershell
godot --headless --path . --script res://tests/test_wizard_chess.gd
```

La suite verifica mosse iniziali e alternanza, impedimento dei turni doppi, scacco matto, stallo, arrocco, en passant, sottopromozione, annullamento, stato serializzato e 32 token nella scena. Il workflow `.github/workflows/wizard-chess.yml` esegue lo stesso test su GitHub Actions.
