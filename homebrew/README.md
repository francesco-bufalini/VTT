# Contenuti homebrew

## Tre livelli di dati

1. **Compendio**: contenuti originali 5etools e homebrew in formato JSON 5etools. Si tratta di definizioni, mai di oggetti posseduti.
2. **Integrazione VTT**: metadati aggiuntivi in `vtt/enrichment/` o `user://vtt_enrichment/`. Per incantesimi sono geometria, targeting, effetti mappa, ecc. La definizione originale non viene modificata.
3. **Istanze**: schede creature, stati di combattimento e inventario nei salvataggi. Quantità, equipaggiamento e dimensioni personalizzate appartengono a un oggetto posseduto, non alla voce del compendio.

### JSON homebrew nativo 5etools

È ora supportato anche il formato standard, con `_meta.sources` e categorie alla radice come `monster`, `spell`, `item`, `class`, `subclass`, `race`, `feat`, ecc. È sufficiente copiare il file nella cartella homebrew senza convertirlo. Vedi `examples/native_5etools.json` (solo esempio, non caricato automaticamente).

Il catalogo assegna un ID locale `homebrew:<codice-fonte-in-minuscolo>:<categoria-plurale>:<nome-normalizzato>`. Conserva invariati nome e codice fonte dopo averlo utilizzato nelle schede: il formato 5etools non fornisce l'ID locale esplicito del vecchio VTT. `_meta.sources[].json` deve corrispondere al campo `source` delle voci. Gli ID duplicati sono diagnosticati; è sempre il primo a prevalere.

I vecchi pacchetti VTT (`schema_version: 1`, `namespace`, `entries`) **continuano a funzionare** e mantengono gli ID preesistenti.

### JSON di integrazione

Da Creature → Opzioni → **Cartella integrazioni VTT** puoi aprire `user://vtt_enrichment` e aggiungere file separati per categoria:

```json
{
  "schema_version": 1,
  "category": "spells",
  "entries": [
    {
      "id": "homebrew:hbx:spells:prism_pulse",
      "fields": {
        "target_mode": "token_then_point",
        "range_feet": 60,
        "aoe_shape": "sphere",
        "aoe_radius_feet": 10
      }
    }
  ]
}
```

L'ID può riferirsi sia a voci ufficiali sia a voci homebrew. Le chiavi di identità (`id`, `name`, `source`, ecc.) e lo stato delle istanze (`quantity`, `equipped_slots`, ecc.) sono vietati nelle integrazioni. La ricarica homebrew aggiorna anche questo layer. Le estensioni vengono applicate alle **copie materializzate** del catalogo, non ai JSON originali.

### Inventario delle istanze

Ogni elemento salvato mantiene `id`, `quantity`, `equipped_slots` e può aggiungere `instance_overrides`. Il nuovo editor consente lunghezza, larghezza e altezza in metri in `instance_overrides.dimensions_m`. Se personalizzi un oggetto in una pila, l'editor separa automaticamente **una copia**: le altre conservano le misure precedenti. Queste misure non modificano automaticamente gittata, danni o scala 3D. I vecchi salvataggi senza `instance_overrides` vengono accettati.

Le proprietà che influiscono sulle regole (`damage`, `range`, `bonus_weapon`, ecc.), quando presenti esplicitamente in `instance_overrides`, si applicano solo all'oggetto equipaggiato. Gli snapshot legacy dell'inventario restano disponibili se il compendio non è installato.

---

Dal pannello **Creature**, premi **Cartella homebrew**. Inserisci pacchetti JSON nella cartella aperta e premi **Ricarica homebrew**. Il percorso è `user://homebrew` (cartella dati Godot); funziona anche nelle build esportate.

Per sviluppare nel repository usa `homebrew/local/`, ignorata da Git. `homebrew/examples/` contiene esempi disattivati: copia `starter.json` nella cartella attiva per provarli. Il caricatore legge sottocartelle fino a quattro livelli, in ordine alfabetico, prima quelle del progetto e poi quelle dell'utente.

Ogni pacchetto ha `schema_version: 1`, un `namespace` stabile e una lista `entries`. Una voce richiede `category`, `id`, `name` e `data`. Namespace e ID usano lettere minuscole ASCII, cifre, trattini e underscore. L'ID completo è `homebrew:<namespace>:<category>:<id>`: rinominare il titolo non cambia i riferimenti nelle schede.

Categorie: monsters, races, classes, spells, conditions, diseases, effects, class_features, species_traits, feats, backgrounds, optional_features. `data` usa la forma 5eTools per mostri e riferimenti; gli incantesimi richiedono i campi runtime descritti in `docs/homebrew.md` per essere lanciabili. I pacchetti VTT legacy possono ancora contenere campi runtime per compatibilità; per i nuovi contenuti 5etools, i campi VTT aggiuntivi vanno nei JSON di integrazione separati. I contenuti sono dati: nessuno script viene eseguito.

Per condizioni e malattie usa `icon_id` per scegliere una delle icone esistenti (ad esempio `poisoned`, `charmed`) oppure `icon` con un pittogramma Unicode. Senza scelta viene mostrato un punto. Gli ID e le icone delle condizioni storiche non cambiano.

I conflitti sono deterministici: stesso ID homebrew, vince il primo file in ordine di caricamento; il secondo è ignorato con diagnostica. Nomi identici con ID diversi possono coesistere. Una sostituzione richiede `overrides` con l'ID esatto di una voce esistente; non avviene mai per nome. Una sostituzione mantiene l'ID e l'icona esistenti. Le sostituzioni mancanti sono ignorate.

Vedi `package.schema.json` e `examples/starter.json`. Gli errori vengono mostrati dopo Ricarica homebrew. Limite file: 2 MiB. Condividi i pacchetti manualmente: le schede personali e i contenuti homebrew non vengono pubblicati automaticamente.
