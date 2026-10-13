# Spell selection, casting preview and multiclass slots

The casting confirmation dialog shows a scrollable, selectable spell description above the resource selector. Saved spell entries with only an ID resolve their description from the existing catalog. Missing descriptions get an explicit fallback. Viewing or cancelling the confirmation does not spend resources. Existing immediate cantrip/no-resource casts retain their behavior.

The preparation selector supports name A–Z, level ascending then name, and level descending then name. The Incantesimi di classe checkbox filters the list for the class being edited; switching it off shows other catalog spells within that class's individual spell-level ceiling. Search and spell-level filters combine with it. Hidden selections remain selected. In the manual selector the checkbox filters the union of eligible spells from the active classes and starts off.

Automatic slots follow the 2014 multiclass Spellcasting rule: combine full caster levels and rounded-down Paladin/Ranger contributions only when multiple classes actually grant Spellcasting. One Spellcasting class retains its own progression even with a noncaster or Warlock. Pact Magic keeps a separate pool but either slot pool can pay for an eligible known/prepared spell. Individual known/prepared spell levels remain based on each class rather than combined slot level. Existing 2024 half-caster rounding is preserved separately; Artificer keeps its existing rounded-up contribution.

Reference: https://www.dndbeyond.com/sources/dnd/basic-rules-2014/customization-options#Spellcasting
User reference: https://5thsrd.org/rules/multiclassing/

Explicit manual slot values and legacy custom values are preserved. Use the existing slot recalculation control to opt into automatic progression. Fighter/Rogue spellcasting subclasses and unsupported homebrew classes retain the existing manual calculation warning; this increment does not add subclass progression metadata.

Regression: tests/test_spell_selection_and_multiclass.gd, tests/test_creature_presence.gd, tests/test_class_spell_selection.gd, tests/test_creature_spellcasting_cast.gd and tests/test_spellcasting_columns.gd.