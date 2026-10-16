# VTT: memoria tecnica della costruzione dell'app
_Indice redatto il 16 ottobre 2026, prima della pulizia dei branch remoti._

Questo documento spiega **perché** sono esistiti i branch e quali regressioni evitare. Per la cronologia completa consultare [l'indice delle PR e dei branch](vtt-branch-history-2026-10-16.md); per gli SHA originali, [lo snapshot immutabile](vtt-branch-snapshot-2026-10-16.json). Una PR chiusa non significa necessariamente che il comportamento sia stato integrato; uno squash merge può lasciare commit non antenati di `main`.

## Percorso di costruzione e confini da preservare

1. **Scena desktop Godot e campagne**: il VTT è nato attorno alla scena tattica, con token 2D/3D, griglia, misure, AoE, iniziativa, stati, miniature e gestione della campagna. I vecchi backup `campaign-hub` e `main-before-*` documentano checkpoint prima di cambiamenti a geometria, flanking, token e Kaos. I 41 checkpoint antenati di main erano riferimenti storici, non funzionalità alternative da reintegrare.
2. **Creature e contenuti**: archivi creature, schede, classi, razze, origini, talenti, tracker e bonus si sono progressivamente sganciati dalla scena 3D. Preservare le distinzioni tra regole, cataloghi strutturati di 5etools/Fight Club, presentazione GUI e salvataggi. Non dedurre automaticamente effetti meccanici da prosa narrativa.
3. **Origini e progressione**: classi, razze, background, talenti, equipaggiamento e infusioni possono attribuire competenze, abilità, incantesimi, effetti e tracker, talvolta dipendenti dal livello. Distinguere scelta delle origini, assegnazione degli slot, incantesimi preparati, benefici e costi di utilizzo. La vecchia PR #52 esplorava progressioni e dadi vita da tabelle tipizzate 5etools, senza mappe manuali.
4. **Mobile Android e sincronizzazione**: navigazione touch, popup completi, lunga pressione, dimensionamento delle schede, REST/LAN e connessioni tra dispositivo e desktop sono stati corretti attraverso molte PR successive. Gli elementi touch non possono dipendere da click destro/sinistro simultanei; i pulsanti Annulla/Indietro devono realmente chiudere le finestre. Non rompere chat, destinatari di oggetti/documenti o dati dell'inventario durante cambi di GUI.
5. **Homebrew e portabilità**: definizioni locali in `user://`, ID stabili, dipendenze incluse nell'esportazione dei personaggi e importazioni non distruttive. Un ID uguale non prova l'identità del contenuto. Il fallimento di un salvataggio non deve distruggere il file precedente. La consegna di un documento non equivale alla sua persistenza nell'archivio del personaggio.
6. **PWA e desktop host**: la PWA mobile usa archiviazione locale IndexedDB, service worker e server/gateway del desktop nativo. Non reintrodurre senza valutazione un gateway Python alternativo alla soluzione HTTP Godot adottata da `main`. HTTPS e accoppiamento autentico sono necessari per l'uso remoto; l'archiviazione browser non equivale a backup permanente.
7. **Refactoring modulari**: non accorpare comportamenti visivamente simili che hanno semantiche diverse. Esempio: gli elenchi di creature attraversate dalle misure e i bersagli di un'azione non includono necessariamente gli stessi token. Estrarre helper puri, mantenere API e formati, usare adapter sottili e testare 2D/3D, importazioni, salvataggi, networking e touch.

## Verifica puntuale della PR #118 rispetto a main

**Conservare `fix/safe-sync-homebrew-documents` e non applicare un merge automatico.**
Controllo del 16 ottobre sulle implementazioni correnti:

| Area | Evidenza in main | Comportamento utile dalla #118 | Stato |
|---|---|---|---|
| Inbox corrotta | `DocumentInbox.pending()` restituisce `[]` anche su JSON non valido | Rifiutare ricezioni anziché trattare il file come inbox vuota | **Da recuperare** |
| Inbox piena | `receive()` usa `while rows.size() > MAX_DOCUMENTS: rows.remove_at(0)` | Non eliminare una consegna già riconosciuta; rifiutare il nuovo pacchetto | **Da recuperare** |
| Persistenza documenti | `take_all()` svuota l'inbox prima che il salvataggio del personaggio sia confermato | Acknowledge dopo persistenza (nella #118 tramite `acknowledge_inventory`) | **Da adattare** alle attuali API inventario |
| Contenuti portabili | `PortableCreatureContent.install()` ignora ID già presenti, anche se il contenuto differisce | Confronto dei dati e metadata, rifiuto esplicito di conflitti, protezione pacchetti non caricati | **Da recuperare**, evitando false differenze semantiche |
| Definizioni documenti | `DocumentStore._write_json()` scrive direttamente sul file finale | Scrivere su temporaneo e sostituire con rollback su Windows | **Da recuperare** |
| Catalogo rapido | `QuickCustom._persist()` ha già validazioni dimensione, temporaneo, controllo errori e backup Windows | Protezione dei salvataggi | **Già presente** |
| UI touch e condivisione | La GUI è cambiata; `ShareRecipients` e le API attuali sostituiscono parte della vecchia UI | Verificare che long press, destinatari e feedback chat restino corretti | **Non copiare direttamente** |
| Test | Il branch introduce `test_document_inbox_safety.gd` e altri test | Adattare ai nuovi formati documentali | **Recupero selettivo** |

Nota: il controllo statico identifica divergenze concrete; non costituisce una prova di test runtime su Android/Godot né prova che tutte le modifiche della #118 siano ancora applicabili senza revisione.

## Lavori non integrati da poter recuperare

- **PR #9** (`refactor/vtt-geometry-boundaries-20261009`): validazione snapshot AoE ed hit-testing geometrico estratti in helper puri, test dedicati, senza cambiare schemi serializzati.
- **PR #52** (`refactor/structured-mechanics-class-tables-20261012`): generatore di meccaniche da `classTableGroups`, `classFeatures`, `hd.faces`; preserva identificativi e progressioni dei tracker esistenti. Valutare l'interprete su dati e regole aggiornati prima di integrarlo.
- **PR #64** (`fix/creature-gui-localization-captions-20261012`): internazionalizzazione delle spiegazioni numeriche, tooltip e descrizioni formattate.
- **PR #87** (`refactor/compact-creature-core-20261013`): deduplicazione logica di proprietari e store, editor e origini, progettata su versione precedente.
- **PR #121**: valori derivati creature esplicitamente sostituiti dalla PR #123 già integrata; non ripristinare accidentalmente la vecchia implementazione.
- **Backup Kaos** (`backup/campaign-hub-before-context-menu-cleanup-20261004`): sei commit esclusivi relativi a `encounter/klotis_prison.gd`, backdrop e relativo test; non reintegrare senza verifica sulla scena attuale.
- **Test bonus** (`test/bonus-cycle-performance-20261011`): regressione prestazionale non ancora presente in `main`.
- **PR #131**: base PWA alternativa, ancora aperta al momento dell'indice; verificare con l'implementazione nativa Godot HTTP attuale, non fare merge indiscriminato.

## Regole pratiche per evitare vecchi errori

- Conservare checksum, ID, record homebrew, documenti e inbox finché il salvataggio non è confermato; non usare un catch che inizializzi `[]` su file corrotto.
- Verificare modifiche di cataloghi 5etools/Fight Club contro le versioni 2014/2024 appropriate: i dati possono esprimere limiti, prerequisiti e varianti diverse.
- Isolare i cambiamenti della UI Android dalla logica di gioco e dai formati di salvataggio; verificare leggibilità, scroll e tap reali su emulatore.
- Prima di dichiarare pronto un merge, controllare che GitHub Actions e test Godot corrispondano al commit finale; un CI verde su commit precedente non basta.
- Le vecchie PR restano consultabili via `https://github.com/francesco-bufalini/VTT/pull/<numero>`; i tag `archive/2026-10-16/*` conservano anche codice selezionato dei branch con commit esclusivi.
