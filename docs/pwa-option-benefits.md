# Benefici di selezione nella PWA

`benefit_type: "option_selection"` identifica un beneficio che offre opzioni
imparabili, preparabili o applicabili. La GUI è scelta da questo tipo, senza
controlli sul nome della classe, sul titolo del privilegio o sul catalogo sorgente.
Fighting Style, infusioni e modelli dell’Armatura Arcana usano lo stesso pannello,
lo stesso selettore e la stessa finestra di applicazione.

## Contratto dei dati

- `source` indica l’adattatore del catalogo. Gli adattatori proiettano le opzioni
  e conservano i salvataggi esistenti; non scelgono la presentazione.
- `layers.learned`, `layers.prepared`, `layers.applied` dichiarano i passaggi
  disponibili, i limiti e i trigger descrittivi. L’assenza di uno stadio lo elimina
  dalla GUI. Un limite nullo non introduce una capacità massima aggiuntiva.
- Un’opzione può contenere `details: {category, name, source}` per la descrizione
  del compendio, oppure una descrizione già disponibile nel catalogo.
- `effect_choice: {key, label, options}` dichiara una scelta dell’effetto da salvare
  con l’applicazione, per esempio il tipo di danno di un’armatura resistente.
- `layers.applied.target` dichiara la necessità di scegliere un oggetto:
  `kind`, `slot`, `kinds`, `selector`, `allow_catalog`, `label` descrivono i vincoli
  e i controlli. Se manca `target`, la finestra non mostra una scelta di oggetti.
- `selector: "option.item_selector"` usa il selettore strutturato dell’opzione.
  `extension_field` e `option_item_id` conservano i vincoli di proprietà e gli
  eventuali piani già associati a un oggetto.
- `on_apply` può dichiarare un effetto successivo all’applicazione, come la
  creazione di una sottocreatura; non cambia la finestra.

## Persistenza e verifiche

`power_selection.js` espone lettura, apprendimento, bersagli e applicazione.
Gli adattatori conservano rispettivamente `optional_features_catalog`,
`power_selections`, `power_applications`, `inventory.infusion` e
`trait_state_selection`. La GUI non scrive direttamente i dati specifici
di infusioni o modelli di armatura.

I bersagli vengono ricalcolati prima del salvataggio. L’apprendimento è distinto
dall’applicazione; i modelli esclusivi continuano a cambiare atomicamente tramite
il motore generico degli stati. La selezione di un oggetto del catalogo è offerta
solo quando i dati del bersaglio la consentono.

`pwa/tests/benefit_option_ui_browser.mjs` verifica nello stesso personaggio la
finestra comune, i diversi requisiti di bersaglio e gli effetti effettivi dei
modelli di armatura. I test browser di Fighting Style e infusioni verificano
apprendimento, applicazione, rimozione e persistenza.
