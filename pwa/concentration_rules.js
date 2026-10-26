// Shared, rule-version-neutral concentration damage prompt. A check is
// required for any positive damage, including damage absorbed by temporary HP.
// This module never rolls dice or assumes that opening a dialog passes a save.
export const CONCENTRATION_ROLL_CONTEXT='concentration_damage';
export function concentrationDamageCheck(creature={},damage){
 const amount=Number(damage);
 if(!Number.isSafeInteger(amount)||amount<=0)return null;
 const conditions=Array.isArray(creature.conditions)?creature.conditions:[];
 if(!conditions.includes('concentrating')&&!creature.concentrating_spell_id)return null;
 return {damage:amount,dc:Math.max(10,Math.floor(amount/2)),
   target:'save:con',context:CONCENTRATION_ROLL_CONTEXT,
   spell_id:String(creature.concentrating_spell_id||'')};
}
export function concentrationEndPatch(creature={}){
 return {conditions:(Array.isArray(creature.conditions)?creature.conditions:[])
   .filter(code=>code!=='concentrating'),concentrating_spell_id:''};
}
