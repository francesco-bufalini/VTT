# Item

Il menu **Item**, accanto a **Token**, raccoglie gli oggetti della mappa.
Il primo oggetto è **Carro romano**, importato dal GLB fornito dall'utente.
Il modello mantiene materiali e proporzioni originali: la piattaforma misura
circa 1,7 × 2 celle; l'area tattica e la collisione del piano sono 2 × 2.
Ruote e timone sporgono dall'area dei passeggeri.

1. Scegli **Item → Carro romano · posiziona (2×2)** e clicca una superficie.
   Il centro del piano si allinea a un incrocio della griglia. Esc annulla.
2. Apri **Item → Lista item / associa token…**, scegli un carro e il token
   che lo traina, quindi premi **Associa token**.
3. Il carro segue il movimento del token, anche in verticale, mantenendo
   l'offset. I token appoggiati sul piano si spostano con il carro.
4. **Sposta** riposiziona il carro e i passeggeri e aggiorna l'offset;
   **Scollega** conserva il carro in posizione; **Elimina** libera i passeggeri.
5. **Sessione → Salva** registra item, legami, posizione e supporti.
   Annulla/ripristina include il carro e i passeggeri.

Gli item hanno identificativi propri e non entrano nel gruppo dei token.
L'occupazione considera il centro del token nelle quattro celle del piano e
la sua altezza, evitando di trasportare creature molto sopra o sotto il carro.
I token trainanti si muovono indipendentemente dai piani; un token sopra
un altro carro non può essere scelto come trainante dal menu.
Nelle selezioni multiple ciascun passeggero viene spostato una sola volta.

Gli snapshot V6 includono una lista opzionale di item; i salvataggi V5
rimangono caricabili e rappresentano una mappa senza item. Tutti i partecipanti
devono usare V6 per condividere mappe con item: i vecchi client rifiutano V6
invece di perdere silenziosamente gli oggetti.

Asset: assets/items/roman_chariot_with_painted_front.glb
Fonte: file locale fornito dall'utente, nessun download di asset terzi.
SHA-256: 9d8c82e1b3da323aa20a9d63a54e8bad7a1068e0c252354e5bad527ddddbe31d
La provenienza/licenza esterna non è inclusa nel file ricevuto.
