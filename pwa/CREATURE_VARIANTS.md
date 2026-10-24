# Forme e varianti della creatura

Nella scheda, **Forme e varianti** mostra la base, le varianti e la forma attuale.
Le varianti sono contenute nella base e non creano nuove voci nell'archivio.
Per ogni variante si scelgono le sezioni da personalizzare, anche separando le
sei caratteristiche. Le sezioni non selezionate sono condivise: modificarle
dalla variante modifica la base e tutte le altre forme che le ereditano.
Le sezioni personalizzate si modificano dai normali controlli della scheda.
Il comando delle forme è un’icona nella barra del nome. Rinominare una variante,
anche dai normali campi della scheda, personalizza il nome e lo aggiorna ovunque
nella scheda; l’elenco creature continua a mostrare il nome della base.
Deselezionare una sezione nell'editor della variante scarta quella sua
personalizzazione e ripristina l'ereditarietà. Eliminare la variante attuale
riporta prima alla base.

**Nome**, **aspetto e miniatura** e **specie e tipo** sono distinti: un alias o
un mascheramento non cambia automaticamente tratti e regole razziali.
**Intera scheda** personalizza tutti i dati di gioco, anche i campi futuri,
mantenendo ID, proprietario, tipo archivio e collegamenti della creatura base.

Dopo aver scelto le sezioni, **Apri bestiario** offre i mostri dell'archivio
locale, l'homebrew e il catalogo del desktop. Si può importare una creatura in
tutte le sezioni selezionate e successivamente importarne altre in singole
sezioni. Ogni importazione è una copia modificabile; la fonte viene registrata
in `sources` e non aggiorna automaticamente i dati di una variante già creata.
Il desktop usa `Bestiary5etoolsClient` già esistente per cache, homebrew e
risoluzione di `_copy`. Il service worker conserva i cataloghi consultati per
l'uso offline. Le creature non ancora consultate richiedono il desktop connesso.
La variante salvata funziona offline senza la sua fonte.

## Schema leggibile, versione 1

La radice del record contiene sempre i dati della **base**. `current_form_id`
vuoto indica la base. La forma attuale è una proiezione della base e dei soli
valori delle sezioni possedute dalla variante. Non si salva una seconda copia
della creatura e non si scrivono valori derivati nella base per cambiare forma.

```json
{
  "id": "creature_123",
  "name": "Lyria",
  "current_hp": 30,
  "max_hp_base": 40,
  "variant_schema_version": 1,
  "current_form_id": "alias_1",
  "variants": [
    {
      "id": "alias_1",
      "name": "Identità segreta",
      "preset": "alias",
      "sections": ["name"],
      "creature_filter": {},
      "sources": {},
      "values": {"name": "Ombra"}
    },
    {
      "id": "wolf_1",
      "name": "Forma di lupo",
      "preset": "custom",
      "sections": ["appearance", "hp", "str"],
      "creature_filter": {"type": ["beast"], "max_cr": 1},
      "sources": {
        "hp": {"id": "bestiary:Wolf|MM", "name": "Wolf", "source": "MM"},
        "str": {"id": "bestiary:Brown Bear|MM", "name": "Brown Bear", "source": "MM"}
      },
      "values": {
        "current_miniature_id": "wolf",
        "size_name": "Medium",
        "footprint": 1,
        "current_hp": 7,
        "max_hp_base": 11,
        "temporary_hp": 0,
        "abilities": {"str": 19}
      }
    }
  ]
}
```

I campi di `values` sono dati normali della scheda. Anche PF attuali, slot spesi
e inventario possono essere salvati nella variante quando la relativa sezione
è personalizzata. Le sezioni dichiarano la proprietà anche per campi mancanti:
un campo assente in una sezione personalizzata non eredita il valore base.
Gli ID delle sezioni e i loro percorsi sono definiti in `VARIANT_SECTIONS` in
`creature_variants.js`; `*` indica l'intera scheda. L'export portatile, i backup
e l'archivio desktop preservano la struttura e i dati live. Le revisioni delle
schede continuano a impedire sovrascritture da finestre concorrenti.

## Preset riusabili da tratti e incantesimi

Un preset è un oggetto JSON con `id`, `sections` e `creature_filter`, passato
come `preset` a `createVariant(record, options)`. Il chiamante decide se pagare
una risorsa e quando attivarlo: il modello non interpreta il testo delle
capacità né attribuisce privilegi per nome o livello. Esempio di dato da
associare a una capacità personalizzata:

```json
{
  "id": "trasformazione-parziale",
  "sections": ["appearance", "hp"],
  "creature_filter": {
    "ids": [],
    "type": ["beast"],
    "sources": ["MM"],
    "max_cr": 1,
    "no_fly": true,
    "no_swim": false
  }
}
```

`ids` non vuoto restringe a creature specifiche; i filtri sono combinati.
I preset inclusi (alias, mascheramento, solo aspetto, forma selvatica,
polymorph e personalizzato) sono proposte modificabili, non un'implementazione
universale delle regole 2014/2024. In particolare i limiti di GS, movimento,
creature conosciute e i costi di altri incantesimi/tratti devono essere
specificati dalla capacità che concede la trasformazione. Il normale comando
Forma selvatica già esistente crea una variante e mantiene il suo pagamento.

## PF e migrazione

I PF appartengono alla forma attuale: non esiste una seconda riserva PWA.
I PF temporanei assorbono i danni prima dei PF attuali. Con PF personalizzati,
i danni che superano i PF rimasti aprono una scelta: restare nella variante
con 0 PF oppure tornare alla base applicandole l'eccesso (assorbito prima dai
suoi eventuali PF temporanei). La base non perde PF prima della conferma.
Anche l'inserimento manuale di PF negativi apre questa scelta. Un danno che
porta esattamente a zero non produce eccesso e non apre il popup.

Le vecchie riserve `second_form_hp` / `second_form_max_hp` positive vengono
migrate, alla prima apertura, nella variante `legacy-second-form`; i PF base
restano intatti. La migrazione è idempotente e il vecchio editor PWA sparisce.
I vecchi campi eventualmente conservati dal codice Android non sono letti dal
nuovo flusso PWA.

## Verifiche

```text
node --test pwa/tests/creature_variants.test.mjs
node pwa/tests/creature_variants_browser.mjs
Godot --headless --path . --script res://tests/test_creature_variants.gd
```

Le prove browser usano un profilo isolato e dati sintetici. La regressione
Godot è inclusa nella suite veloce di `scripts/validate.ps1 -Tests`.
