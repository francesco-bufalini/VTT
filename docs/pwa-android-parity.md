# Parità Android / PWA mobile — inventario verificabile

Riferimento: Android in `vtt/mobile/creatures_mobile.gd`, `vtt/creature_area.gd`,
`vtt/creature_inventory_tab.gd`, `vtt/creature_spellcasting_tab.gd`.
PWA in `pwa/index.html`, `pwa/ui.js`, `pwa/native_sheet.js`, `pwa/sheet_rules.js`.
La PWA **non** include le scene 3D: la scena rimane sul desktop nativo.

## Navigazione (quattro sezioni native)

| Sezione Android | PWA | Stato |
| --- | --- | --- |
| Scheda creatura e archivio | Creature locali, selezione scheda conservata nel drawer fra le pagine | Allineata nella struttura |
| Catalogo | Catalogo, ricerca/assegnazione da dati strutturati | Parziale: alcune modifiche homebrew restano native |
| Dadi con chat | Dadi e chat con stesso autore per tiri e messaggi | Allineata per tiri base e messaggi |
| Partita | Associazione QR/codice, token, comandi, snapshot 2D, iniziativa | Parziale, limiti tecnici sotto |

Le **otto** sottosezioni della scheda mantengono ordine e nomi nativi:
Info, Caratteristiche e abilità, Battaglia, Poteri, Inventario, Tratti,
Condizioni, Modifica personaggio. Il drawer resta accessibile da Catalogo,
Dadi e Partita dopo l'apertura di una scheda. «Creature locali» torna
all'archivio; non apre una scheda diversa per errore.

## Capacità della scheda

| Ambito | Disponibile nella PWA | Gap residuo rispetto ad Android |
| --- | --- | --- |
| Archivio | Creazione, import/export anche batch, backup, cancellazione, salvataggio locale e conflitti di revisione | Nessuna sincronizzazione remota automatica di schede private |
| Info | Identità, specie/background, classi, multiclasse nel dettaglio Modifica personaggio, note/appunti/interpretazione modificabili | Miniature scelte dal catalogo nativo; campi molto specifici |
| Caratteristiche | Punteggi base modificabili; modificatori, abilità, TS e competenza calcolati localmente | Eccezioni dei privilegi non strutturati, scelte condizionali |
| Battaglia | PF, CA, iniziativa, condizioni, equipaggiamento, tracker manuali e riposi | Formule dettagliate dei singoli attacchi, bonus speciali |
| Poteri | Preparati/libro, ricerca incantesimi, slot consumati, progressione slot locale | Preparazione per classe, eccezioni, infusioni e tracker di privilegi speciali |
| Inventario/documenti | Quantità, attivazione, sintonia, equipaggiamento, documenti locali modificabili | Invio indirizzato a destinatari online |
| Tratti e origini | Note, talenti, competenze, bonus strutturati, difese, risorse | Esecuzione di alcuni privilegi specifici, feature homebrew complesse |

I risultati calcolati sulla scheda **non passano al server**. L'interprete
browser applica soltanto effetti strutturati supportati e segnala i limiti;
non trasforma descrizioni in linguaggio naturale in effetti inventati.

## Partita: equivalenze e limiti

L'app Android utilizza UDP/TCP nativo per discovery e chat; la PWA utilizza
HTTP(S) dello stesso host desktop e un codice temporaneo di 16 caratteri.
La PWA supporta chat, snapshot 2D e le azioni tattiche consentite,
ma non riproduce tutta la UI nativa di bersagli, finestre di dialogo,
rituali e trasferimenti di oggetti/documenti. La PWA deve inviare al desktop
solo la proiezione **pubblica** della creatura necessaria al token.

## Verifica

- `cd pwa && npm test`: regressioni IndexedDB, sezione unificata Dadi/chat,
  autore dei messaggi/tiri, classi multiple, note, ritorno alla scheda.
- `node --input-type=module --check < pwa/ui.js` e analoghi: sintassi.
- `tests/test_pwa_host.gd`: bridge HTTP nativo e allowlist.
- Test manuale ancora necessario su Android Chrome e iOS Safari: drawer,
  tastiera virtuale, background/resume, pairing HTTPS, quota e persistenza.

Non dichiarare «parità completa» finché non sono verificati i gap residui.

## Funzioni di dominio aggiunte (seconda fase)

- `pwa/character_core.js`: inizializzazione schede con lo schema di
  `PlayerCharacterStore.create_character()`; variazione dei consumi e recuperi
  pure, inclusi slot regolari al riposo lungo e magia del patto a entrambi i
  riposi. Non recupera automaticamente PF/dadi vita né presume tracker
  automatici che non sono stati ancora calcolati.
- `pwa/class_spells.js`: progressioni delle classi ricavate dall'indice
  5etools incluso nell'app; preparati/conosciuti/trucchetti, limite del livello
  per ogni classe, `casting_classes` con le stesse identità di Godot.
  La scelta della classe è esplicita; la PWA non inventa appartenenze mancanti
  e non sostituisce le regole di preparazione più complesse.
- `pwa/quick_homebrew.js`: creazione locale di oggetti, talenti e background
  con la forma portatile nativa `homebrew:quick_local:...`, campi oggetto
  strutturati e competenze esplicite; rifiuto della cancellazione se una
  scheda utilizza la definizione. Le definizioni usate viaggiano con
  l'esportazione della creatura.
- `network/pwa_host.gd`: distribuisce questi moduli con gli altri asset,
  verificati nel test HTTP reale. Il Service Worker li salva nella cache
  dell'app senza toccare i dati IndexedDB.

### Tracker automatici di classe

`class_trackers.js` unifica la lettura delle colonne numeriche 5etools con
`class_resource_overrides.json` usato dalla versione Godot. Genera gli stessi
ID stabili `class:<classe>:<fonte>:<colonna>`, applica le soglie di classe
e sottoclasse e distingue riposo breve, lungo e turno. Riutilizza le
operazioni pure di `character_core.js` per modificare gli utilizzi.
Il catalogo e il modulo sono precaricati dal Service Worker e distribuiti
dall'host desktop. I privilegi senza quantità strutturate restano esclusi.
