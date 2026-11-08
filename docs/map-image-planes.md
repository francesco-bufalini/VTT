# Mappe 2D importate nel VTT desktop

In **Master → Importa immagine su piano 2D…** (nella barra superiore o nel menu contestuale), seleziona un file PNG, JPG o WebP.

1. Nella finestra di calibrazione, imposta **larghezza** e **altezza** in cubi. Le dimensioni del piano cambiano con l'immagine, mentre le caselle della griglia visualizzata nell'anteprima rimangono della stessa dimensione. Disattiva **Mantieni proporzioni originali** per modificare le due dimensioni indipendentemente.
2. Regola gli **spostamenti X e Z** tra **−0,99 e +0,99 cubi**, in incrementi di 0,01, per far coincidere le linee della griglia stampata sull'immagine con quelle del VTT. L'immagine e il piano si spostano insieme, **non** la griglia globale.
3. Premi **Posiziona sulla mappa 3D**. Muovi il mouse sulla mappa: appare un'anteprima trasparente del piano. Clic sinistro per confermare. Clic destro o **Esc** annulla.

Il piano è orizzontale, con la superficie dell'immagine **un cubo sopra** il punto selezionato. Il supporto fisico sottostante è un parallelepipedo alto **esattamente un cubo**; la griglia tattica resta indipendente ed è rilevata sulla sua superficie. La base segue il terreno cliccato, con X/Z iniziali allineati ai multipli della cella; gli spostamenti frazionari restano applicati alla geometria del piano. È possibile importare più immagini entro i limiti di dimensione dell'istantanea condivisa.

Per rimuovere un'immagine importata, apri **Master → Gestisci piani immagine 2D…**, seleziona un piano e premi **Rimuovi piano selezionato**. Importazioni e rimozioni partecipano al normale **Ctrl+Z / Ctrl+Y**, al salvataggio locale, all'autosalvataggio, al ripristino e alla sincronizzazione mappa. I vecchi file di mappa, senza piani immagine, continuano a essere caricabili.

Le immagini sono incorporate (PNG o WebP compresso) nei dati della mappa, così non dipendono da un percorso locale del computer. Il caricamento accetta file fino a 24 MB e immagini fino a 8192 pixel per lato; al salvataggio le immagini grandi vengono ridimensionate e, se necessario, compresse. Per contenere le dimensioni degli snapshot si applicano i limiti di **12 piani**, **1,2 MB di contenuto binario per immagine** e **3,2 MB di immagini codificate in totale**. I piani hanno dimensioni comprese tra 0,5 e 200 cubi per lato.

Verifica mirata: `tests/test_map_image_planes.gd`, incluso nella suite `scripts/validate.ps1 -Tests`.
