# Icone dorate generate per VTT

Questi sono gli atlanti SVG costruiti **direttamente dai 98 SVG** del pacchetto
`vtt_gold_icons.zip`, non un semplice recolor delle icone già presenti.

- `gold_0.svg`…`gold_3.svg`: 98 pittogrammi originali del pacchetto, suddivisi in
  gruppi di massimo 25 celle SVG trasparenti da 64×64.
- `manifest.json`: nomi semantici e ordine delle celle, da rispettare su Godot e PWA.
- Nessun rettangolo scuro fa parte degli asset: fondo, gloss e bordo sono nel tema UI.
- Il codice Godot usa `AtlasTexture`, quello web la stessa cella tramite
  `background-position`. Nessun asset viene scaricato da servizi esterni.

## Licenze e fonti

I primi 20 pittogrammi provengono dal precedente atlante originale del progetto
`vtt/icons/action_dashboard.svg`. Gli altri 78 derivano dai simboli **Font
Awesome Free Solid** di Fonticons, Inc., CC BY 4.0 (attribuzione richiesta).

- https://fontawesome.com/license/free
- https://creativecommons.org/licenses/by/4.0/

Sono state applicate ai tracciati originali sfumature oro/rosa; nessun file di
font è distribuito. Conservare questa nota insieme agli asset durante le release.
