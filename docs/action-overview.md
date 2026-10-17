# Action overview (Godot)

The 2014 action overview reads `vtt/data/combat_actions_5etools.json`.
Generate it with:

```powershell
python scripts/generate_combat_actions.py --data-root .5etools-cache
```

Inputs are 5etools `actions.json` and `variantrules.json`. Their SHA-256 values
are recorded in the generated file. Names are localized; descriptions retain
the supplied source text, with display tags normalized. A source label and URL
accompany each general rule. Feature descriptions come from the active feature
or an exact feature/source lookup in the existing player catalogue. No new
rule caption is composed from a feature name or guessed from prose.

Official 2014 cross-checks:
- https://www.dndbeyond.com/sources/dnd/basic-rules-2014/combat
- https://media.wizards.com/2020/dnd/downloads/SA-Compendium.pdf

Presentation:
- Attack contains equipped primary attacks, grapple, shove and prone; enabled
  Disarm/Shove Aside variants join the same collapsible list.
- Legal offhand bonus attacks are children of Two-Weapon Fighting. Their
  stable IDs and existing attack roller remain unchanged.
- An option with action and bonus-action activations is listed once in the
  bonus group, with an A icon showing the alternative action cost. Different
  resource/payment choices remain separate. Action/reaction timings also
  remain separate because their triggers differ.
- Spell selections and the generic spell launcher are excluded from this
  overview. Internal ability grants are still abilities. Spell data and the
  dedicated spellcasting pane are untouched.
- The arrow opens source descriptions. Target and dice buttons are explicit
  separate controls, so opening a description never applies a tactical effect.

The gear opens 78 opt-in 2014 variant references (PHB, DMG, XGE), including
individual DMG Action Options and Loyalty. Local choices are stored separately
from creatures in `user://action_overview.cfg`. Combat variants add their
corresponding action entries; other references are table reminders, without
new automatic campaign effects. Source links open the original rule.

Focused tests: `test_action_rules_2014.gd`, `test_action_dashboard_ui.gd`,
`test_creature_action_economy.gd`, `test_feature_timing_recovery.gd`, and
`test_combat_basic_actions.gd`. The fast Windows suite and feature-domain CI
include them. CI includes the existing shared `pwa/icons` atlases.

### Gerarchia della scheda

Su desktop la prima colonna contiene solo Azione; bonus, tiri rapidi, movimento e reazioni sono nella seconda. I figli di Attaccare, Combattere con due armi e Prove di abilità sono rientrati con rami di albero e un controllo di espansione. Il riquadro delle prove raccoglie solo le opzioni con prove esplicite che consumano un’azione e non appartengono ad Attaccare. I quattro tiri rapidi non assegnano autonomamente un costo di azione.
