// A saved familiar keeps its own state. Linked statistics are read from the
// current owner sheet, using explicit per-template selectors, not name matching.
import {classInfo,companionTemplateProficiencies} from './companion_rules.js';
const list=v=>Array.isArray(v)?v:[];
const number=v=>v!==null&&v!==undefined&&v!==''&&Number.isFinite(Number(v))?Number(v):null;
const mod=v=>Math.floor(((number(v)??10)-10)/2);
export function companionOwnerValues(child={},owner={},computed={},catalog={}){
 if(!child.parent_creature_id||child.parent_creature_id!==owner.id||
   child.owner_id!==owner.owner_id||!child.companion_rule_id)return null;
 const rule=[...list(catalog.features),...list(catalog.spells)].find(x=>x.id===child.companion_rule_id);
 if(!rule)return null;
 const template=rule.template&&child.companion_template_id===rule.template?
   catalog.templates?.[rule.template]:null;
 const bindings=template?.owner_bindings||rule.owner_bindings;
 if(!bindings)return null;
 const get=key=>{
   if(key==='proficiency')return number(computed.values?.proficiency??computed.stats?.proficiency);
   if(/^class_level:[a-z ]+$/i.test(key))return classInfo(owner,key.slice(12)).level;
   if(/^ability_mod:(str|dex|con|int|wis|cha)$/.test(key))
     return number(computed.values?.[key])??mod(owner.abilities?.[key.slice(12)]);
   if(/^casting_(?:hit|dc):(str|dex|con|int|wis|cha)$/.test(key))
     return number(computed.values?.[key]);
   return null;
 };
 const result={owner_id:owner.id,owner_name:String(owner.name||'Proprietario'),
   explanations:{},attacks:[]};
 const pb=get('proficiency');
 if(pb!==null&&template){
  const prof=companionTemplateProficiencies({...template,owner_bindings:bindings},pb);
  result.skill_ranks=prof.skill_ranks;
  result.save_ranks=prof.save_ranks;
  result.proficiency_origin={id:'companion:'+rule.id,
   name:'Profilo · '+String(template.name||rule.names?.[0]||'Famiglio')};
 }
 if(bindings.proficiency==='proficiency'&&pb!==null){
   result.proficiency=pb;result.explanations.proficiency='Bonus competenza del proprietario';
 }
 if(bindings.hit_points==='template'&&template?.hp){
   const hp=template.hp,level=get('class_level:'+String(hp.class_name||''));
   const ability=hp.ability_mod?get('ability_mod:'+hp.ability_mod):0;
   if(level!==null&&ability!==null){
     result.hp=Math.max(1,Math.floor((number(hp.base)??1)+(number(hp.per_class_level)??0)*level+ability));
     result.explanations.hp=String(hp.base??1)+' + '+String(hp.per_class_level??0)+' × livello '+hp.class_name+
       (hp.ability_mod?' + Mod.'+hp.ability_mod.toUpperCase()+' del proprietario':'');
   }
 }
 if(bindings.armor_class==='template'&&template&&typeof template.ac==='object'&&pb!==null){
   result.ac=(number(template.ac.base)??10)+(number(template.ac.per_pb)??0)*pb;
   result.explanations.ac=String(template.ac.base??10)+' + '+String(template.ac.per_pb??0)+' × competenza del proprietario';
 }
 for(const action of list(bindings.attacks)){
   const index=list(child.stat_block?.action).findIndex(x=>x.name===action.name);
   if(index<0||!action.hit)continue;
   const hit=get(action.hit),damageBonus=action.damage_bonus?get(action.damage_bonus):0;
   if(hit===null||damageBonus===null)continue;
   result.attacks.push({id:'monster:action:'+index,name:action.name,hit,
     damage:String(action.damage||'')+(damageBonus?(damageBonus>0?' + ':' - ')+Math.abs(damageBonus):''),
     damage_type:action.damage_type||'',ranged:!!action.ranged,
     range_feet:Number(action.range_feet??action.reach_feet??5),
     ability:action.hit.startsWith('casting_hit:')?action.hit.slice(12):'str',
     owner_hit_source:action.hit,owner_damage_source:action.damage_bonus||''});
 }
 return result;
}
