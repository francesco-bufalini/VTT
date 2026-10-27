// Compatibility facade for rule tests and downstream imports. The PWA uses
// the Godot-served effect_extensions.js module directly.
export {spellItemRules,spellItemTargetSelector,spellItemDamageTypes,
  itemSpellCastPatch,endItemSpellPatch,concentrationItemSpellEndPatch}
  from './effect_extensions.js';
