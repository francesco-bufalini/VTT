// Godot SpellcastingTab mirrors legacy 'spells' with available 'prepared_spells'.
const arr=v=>Array.isArray(v)?v:[];
export const spellId=row=>String(typeof row==="string"?row:row?.id||"").trim();
export function availableSpells(creature={}){
  const out=[],seen=new Set();
  for(const row of [...arr(creature.prepared_spells),...arr(creature.spells)]){
    const id=spellId(row);
    if(id&&!seen.has(id)){seen.add(id);out.push(row);}
  }
  return out;
}
export function spellRecord(value){
  const id=spellId(value),level=Number(value?.level);
  if(!id||typeof value?.name!=="string"||!value.name.trim()||
    !Number.isInteger(level)||level<0||level>9)throw Error("Incantesimo non valido.");
  return {id,name:value.name,source:String(value.source||""),level};
}
export function addSelectedSpell(creature,entry,target="prepared_spells"){
  if(!["prepared_spells","spellbook_spells"].includes(target))throw Error("Elenco non valido.");
  const spell=spellRecord(entry),rows=target==="prepared_spells"?
    availableSpells(creature):arr(creature.spellbook_spells).slice();
  if(rows.some(row=>spellId(row)===spell.id))throw Error("Incantesimo già presente.");
  rows.push(spell);
  return target==="prepared_spells"?{prepared_spells:rows,spells:rows}:{spellbook_spells:rows};
}
export function removeSelectedSpell(creature,target,index){
  if(!["prepared_spells","spellbook_spells"].includes(target))throw Error("Elenco non valido.");
  const rows=target==="prepared_spells"?availableSpells(creature):arr(creature.spellbook_spells).slice();
  if(!Number.isInteger(index)||index<0||index>=rows.length)throw Error("Incantesimo assente.");
  rows.splice(index,1);
  return target==="prepared_spells"?{prepared_spells:rows,spells:rows}:{spellbook_spells:rows};
}
