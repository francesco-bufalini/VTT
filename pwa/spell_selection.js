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
export function spellEligible(entry,member){
 return !entry.internal_grant&&Number(entry.level||0)<=member.max_level&&arr(entry.classes).some(name=>String(name).toLowerCase()===member.name.toLowerCase());
}
export function castingSources(entry,classes,catalog=[]){
 if(Array.isArray(entry?.casting_classes))return entry.casting_classes;
 const definition=catalog.find(row=>spellId(row)===spellId(entry))||entry;
 const matches=classes.filter(member=>spellEligible(definition||{},member));
 return matches.length===1?[matches[0].id]:[];
}
export function classSelectionCount(creature,member,classes,catalog=[]){
 const selected=availableSpells(creature).filter(row=>castingSources(row,classes,catalog).includes(member.id));
 const level=row=>Number(row?.level??catalog.find(s=>spellId(s)===spellId(row))?.level??0);
 return {cantrips:selected.filter(row=>level(row)===0).length,leveled:selected.filter(row=>level(row)>0).length};
}
export function addSelectedSpell(creature,entry,target="prepared_spells",{member,classes=[],catalog=[]}={}){
  if(!["prepared_spells","spellbook_spells"].includes(target))throw Error("Elenco non valido.");
  const spell=spellRecord(entry),rows=target==="prepared_spells"?
    availableSpells(creature):arr(creature.spellbook_spells).slice();
  if(member){
    if(!spellEligible(entry,member))throw Error('Incantesimo non disponibile per questa classe e livello.');
    if(target==='spellbook_spells'&&!member.book)throw Error('Questa classe non usa il libro degli incantesimi.');
    if(target==='prepared_spells'){
      if(member.book&&spell.level>0&&!arr(creature.spellbook_spells).some(row=>spellId(row)===spell.id))throw Error('Aggiungi prima l’incantesimo al libro.');
      const count=classSelectionCount(creature,member,classes,catalog);
      if(spell.level===0?count.cantrips>=member.cantrips:member.limit>=0&&count.leveled>=member.limit)
        throw Error('Limite di selezione della classe raggiunto.');
    }
    spell.casting_classes=[member.id];
  }
  const existing=rows.findIndex(row=>spellId(row)===spell.id);
  if(existing>=0){
    const sources=castingSources(rows[existing],classes,catalog);
    if(!member||sources.includes(member.id))throw Error('Incantesimo già presente.');
    const old=rows[existing];
    rows[existing]={...(typeof old==='object'?old:spell),casting_classes:[...sources,member.id]};
    return target==='prepared_spells'?{prepared_spells:rows,spells:rows}:{spellbook_spells:rows};
  }
  rows.push(spell);
  return target==="prepared_spells"?{prepared_spells:rows,spells:rows}:{spellbook_spells:rows};
}
export function removeSelectedSpell(creature,target,index,{classId,classes=[],catalog=[]}={}){
  if(!["prepared_spells","spellbook_spells"].includes(target))throw Error("Elenco non valido.");
  const rows=target==="prepared_spells"?availableSpells(creature):arr(creature.spellbook_spells).slice();
  if(!Number.isInteger(index)||index<0||index>=rows.length)throw Error("Incantesimo assente.");
  const sources=castingSources(rows[index],classes,catalog);
  if(classId&&sources.length>1)rows[index]={...rows[index],casting_classes:sources.filter(id=>id!==classId)};
  else rows.splice(index,1);
  return target==="prepared_spells"?{prepared_spells:rows,spells:rows}:{spellbook_spells:rows};
}
