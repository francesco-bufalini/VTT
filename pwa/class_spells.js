// Local counterpart of Godot ClassSpellSelection. Structured class data is
// shared from class_mechanics.json; spell slot progressions stay in sheet_rules.
import {localClasses,spellProgression} from "./sheet_rules.js";
import {availableSpells,spellRecord,spellId} from "./spell_selection.js";
const arr=v=>Array.isArray(v)?v:[];
const norm=v=>String(v??"").trim().toLowerCase();
export const classSpellId=(name,source)=>"class|"+norm(source)+"|"+norm(name);

export function classSpellSections(record,classMechanics={},modifiers={}){
  const result=[];
  for(const member of localClasses(record)){
    const name=String(member.name||"").trim();
    const source=String(member.source||"")||
      (record.rules_version==="2024"?"XPHB":"PHB");
    const data=arr(classMechanics.classes).find(row=>
      norm(row.name)===norm(name)&&norm(row.source)===norm(source))?.spellcasting||{};
    if(!Object.keys(data).length)continue;
    const level=Math.max(1,Math.min(20,Number(member.level)||1));
    const from=key=>Number(arr(data[key])[level-1]??0)||0;
    let mode="Conosciuti",limit=-1;
    if(data.preparedSpellsProgression){
      mode="Preparati";limit=from("preparedSpellsProgression");
    }else if(data.preparedSpells){
      mode="Preparati";
      // All present native 5etools expressions have this typed form.
      // Reject unknown expressions rather than manufacturing capacities.
      const match=/^<\$level\$>\s*(?:\/\s*(2))?\s*\+\s*<\$(str|dex|con|int|wis|cha)_mod\$>$/.exec(String(data.preparedSpells).trim());
      if(match){
        const stat=match[2];
        const value=Number(modifiers[stat]);
        const bonus=Number.isFinite(value)?value:
          Math.floor((Number(record.abilities?.[stat]??10)-10)/2);
        limit=Math.max(1,Math.floor(level/(match[1]?2:1)+bonus));
      }
    }else if(data.spellsKnownProgression)limit=from("spellsKnownProgression");
    const slots=spellProgression(record,[{...member,name,source,level}]);
    const max=Math.max(...slots.slots.map((n,i)=>n>0?i:0),
      slots.pact_total?slots.pact_level:0);
    result.push({id:classSpellId(name,source),name,source,mode,
      limit:max?limit:0,max_level:max,cantrips:from("cantripProgression"),
      book:norm(name)==="wizard"});
  }
  return result;
}
export function eligibleForClass(spell,section){
  if(!section||Number(spell?.level)>section.max_level||spell?.internal_grant)return false;
  return arr(spell?.classes).some(name=>norm(name)===norm(section.name));
}
export const assignedClasses=spell=>
  [...new Set(arr(spell?.casting_classes).filter(x=>typeof x==="string"&&x))];

export function assignClassSpell(record,entry,classId="",target="prepared_spells",sections=[]){
  if(!["prepared_spells","spellbook_spells"].includes(target))throw Error("Elenco incantesimi non valido.");
  const spell=spellRecord(entry),section=sections.find(s=>s.id===classId);
  if(classId&&(!section||!eligibleForClass(entry,section)))
    throw Error("Incantesimo non disponibile per questa classe e livello.");
  const next=structuredClone(target==="prepared_spells"?
    availableSpells(record):arr(record.spellbook_spells));
  const prior=next.find(s=>spellId(s)===spell.id);
  if(prior){
    if(!classId||typeof prior!=="object"||assignedClasses(prior).includes(classId))
      throw Error("Incantesimo già presente.");
    prior.casting_classes=[...assignedClasses(prior),classId];
  }else{
    if(classId)spell.casting_classes=[classId];
    next.push(spell);
  }
  return target==="prepared_spells"?{prepared_spells:next,spells:next}:{spellbook_spells:next};
}
export function revokeClassSpell(record,target,index,classId=""){
  if(!["prepared_spells","spellbook_spells"].includes(target))throw Error("Elenco non valido.");
  const next=structuredClone(target==="prepared_spells"?
    availableSpells(record):arr(record.spellbook_spells));
  if(!Number.isInteger(index)||index<0||index>=next.length)throw Error("Incantesimo assente.");
  const item=next[index];
  if(classId&&typeof item==="object"&&assignedClasses(item).includes(classId)){
    item.casting_classes=assignedClasses(item).filter(id=>id!==classId);
    if(!item.casting_classes.length)next.splice(index,1);
  }else if(classId)throw Error("Incantesimo non assegnato alla classe.");
  else next.splice(index,1);
  return target==="prepared_spells"?{prepared_spells:next,spells:next}:{spellbook_spells:next};
}
