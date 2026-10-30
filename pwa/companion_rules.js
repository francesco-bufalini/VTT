// Structured companion rules shared by spells, feature buttons, and the
// familiar picker. No feature is detected from its description text.
import {creatureMatchesFilter} from './creature_variants.js';
import {activeInfusions} from './item_controls.js';
import {SKILL_ABILITY} from './skill_definitions.js';

const normal=value=>String(value??'').toLowerCase().normalize('NFD')
  .replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,' ').trim();
const rows=value=>Array.isArray(value)?value:[];
const clamp=(n,min,max)=>Math.min(max,Math.max(min,n));
const scoreMod=n=>Math.floor((Number(n??10)-10)/2);
export function classInfo(owner,name){
 const member=rows(owner.classes).find(m=>normal(m.name)===normal(name));
 const isPrimary=normal(owner.class)===normal(name);
 return {level:Number(member?.level??(isPrimary?owner.level:0))||0,
  subclass:String(member?.subclass||member?.subclass_name||(isPrimary?owner.subclass:'')||'')};
}
export function matchesCompanionFeature(owner,projection,rule,feature){
 if(!feature||!rows(rule.editions).includes(String(owner.rules_version||'2014')))return false;
 const name=normal(feature.name);
 if(!rows(rule.names).some(item=>normal(item)===name))return false;
 const member=classInfo(owner,rule.class_name);
 if(member.level<Number(rule.min_class_level||0))return false;
 if(rule.subclass&&normal(member.subclass||owner.subclass)!==normal(rule.subclass))return false;
 const origin=String(feature.origin_key||'');
 if(!origin.startsWith('class|')&&!(rule.requires_optional_feature&&
     rows(owner.optional_features_catalog).some(row=>normal(row.name)===name&&!row.disabled)))return false;
 if(origin.startsWith('class|')&&!origin.toLowerCase().includes('|'+normal(rule.class_name).replaceAll(' ','_')))return false;
 const classSource=feature.class_source||origin.split('|')[1];
 if(rule.class_source&&classSource&&normal(classSource)!==normal(rule.class_source))return false;
 if(rule.subclass_source&&feature.source&&normal(feature.source)!==normal(rule.subclass_source))return false;
 if(feature.disabled||feature.inactive||owner.origin_enabled?.[feature.origin_id]===false)return false;
 return true;
}
export function featureCompanionRule(owner,projection,data,originId){
 return rows(data?.features).find(rule=>rows(projection?.features).some(feature=>
  feature.origin_id===originId&&matchesCompanionFeature(owner,projection,rule,feature)))||null;
}
export function eligibleCompanionFeatureRules(owner,projection,data,{manualOnly=false}={}){
 return rows(data?.features).filter(rule=>(!manualOnly||rule.activation==='manual')&&
  rows(projection?.features).some(feature=>matchesCompanionFeature(owner,projection,rule,feature)));
}
// The companion sheet persists; its availability follows the benefit's typed source.
export function companionGrantActive(owner={},child={}){
 if(child.companion_selected===false)return false;
 const grant=child.companion_grant;
 if(!grant?.kind)return true;
 if(grant.kind==='item_option')return rows(owner.inventory).some(item=>Number(item.quantity??1)>0&&rows(item.option_extensions).some(option=>option.id===grant.id));
 if(grant.kind==='inventory_infusion')return rows(owner.inventory).some(item=>
  Number(item?.quantity??1)>0&&item?.infusion?.id===grant.id&&!item.disabled);
 if(grant.kind==='spell_effect')return rows(owner.proficiency_origins).some(row=>
  row.id===grant.id&&row.group==='spell'&&!row.disabled&&owner.origin_enabled?.[grant.id]!==false);
 if(grant.kind==='feature')return owner.origin_enabled?.[grant.id]!==false&&
  !rows(owner.proficiency_origins).some(row=>row.id===grant.id&&row.disabled);
 return false;
}
export function infusionCompanionRule(data,definitions=[],id='',owner={}){
 const definition=rows(definitions).find(row=>row.id===id);
 const ruleId=definition?.companion?.rule_id;
 return ruleId?rows(data?.features).find(rule=>rule.id===ruleId&&
  rows(rule.editions).includes(String(owner.rules_version||'2014')))||null:null;
}
// Creator commands are explicit data, separate from summoning/payment. A
// transferred infused object cannot grant its original creator's commands.
export function companionOwnerActions(owner={},projection={},data={}){
 const result=[];
 const append=(rule,originId,sourceName)=>{
  if(!originId||owner.origin_enabled?.[originId]===false||
    rows(owner.proficiency_origins).some(row=>row.id===originId&&row.disabled))return;
  for(const action of rows(rule.owner_actions)){
   if(!action.id||!action.name||!action.action_type)continue;
   result.push({...action,id:'companion-owner:'+rule.id+':'+originId+':'+action.id,
    feature_id:originId,feature_name:sourceName,origin_name:'Tratto · '+sourceName,
    companion_command:true,companion_rule_id:rule.id,
    activation_mode:action.action_type,tracker_id:'',resource_name:'',resource_cost:0});
  }
 };
 for(const rule of rows(data?.features)){
  if(!rows(rule.editions).includes(String(owner.rules_version||'2014')))continue;
  if(rule.activation==='item'){
   for(const applied of activeInfusions(owner,projection.infusion_catalog||[],projection.features||[])){
    if(applied.infusion.creator_id!==owner.id||applied.definition.companion?.rule_id!==rule.id)continue;
    append(rule,'item:'+String(applied.item.id)+'|'+applied.id,applied.definition.name);
   }
  }else{
   const feature=rows(projection.features).find(row=>matchesCompanionFeature(owner,projection,rule,row));
   if(feature)append(rule,feature.origin_id,feature.name);
  }
 }
 return result;
}
export function companionSpellEffectPatch(owner={},rule={},spellId=''){
 if(rule.grant_kind!=='spell_effect')return {};
 const id='spell:'+String(spellId),origins=structuredClone(rows(owner.proficiency_origins));
 const row=origins.find(entry=>entry.id===id&&entry.group==='spell');
 if(row)Object.assign(row,{applied:true,disabled:false});
 else origins.push({id,group:'spell',name:'Incantesimo · '+String(rule.names?.[0]||spellId),
  applied:true,disabled:false,automatic:false});
 return {proficiency_origins:origins,origin_enabled:{...(owner.origin_enabled||{}),[id]:true}};
}
export function spellCompanionRule(data,spell,owner){
 const candidates=[normal(spell?.name),normal(spell?.id)];
 return rows(data?.spells).find(rule=>rows(rule.editions).includes(String(owner.rules_version||'2014'))&&
  rows(rule.names).some(n=>candidates.some(c=>c===normal(n)||c.endsWith(' '+normal(n)))))||null;
}
// Numeric companion proficiency ranks are typed data, not guessed from prose.
// Both the initial bestiary snapshot and linked sheets use this same projection.
export function companionTemplateProficiencies(template={},proficiency=2){
 const skill={},save={},skill_ranks={},save_ranks={};
 const ranks=template.owner_bindings||{},abilities=template.abilities||{};
 for(const [key,value] of Object.entries(ranks.skill_ranks||{})){
  const rank=Number(value),ability=SKILL_ABILITY[key];
  if(!ability||![1,2].includes(rank))continue;
  skill_ranks[key]=rank;
  skill[key]=scoreMod(abilities[ability])+rank*proficiency;
 }
 for(const [key,value] of Object.entries(ranks.save_ranks||{})){
  const rank=Number(value);
  if(!['str','dex','con','int','wis','cha'].includes(key)||![1,2].includes(rank))continue;
  save_ranks[key]=rank;
  save[key]=scoreMod(abilities[key])+rank*proficiency;
 }
 return {skill,save,skill_ranks,save_ranks};
}
export function companionTemplateStat(template,owner,{size='',name=''}={}){
 if(!template||typeof template!=='object'||!template.name)throw Error('Profilo creatura mancante.');
 const classLevel=classInfo(owner,template.hp?.class_name).level;
 const hp=Math.max(1,Math.floor(Number(template.hp?.base||1)+
  (Number(template.hp?.per_class_level)||0)*classLevel+
  (template.hp?.ability_mod?scoreMod(owner.abilities?.[template.hp.ability_mod]):0)));
 const totalLevel=rows(owner.classes).reduce((sum,m)=>sum+Math.max(0,Number(m.level)||0),0)||
   Number(owner.level)||1;
 // A saved owner.proficiency_bonus can be stale after level-up. The live
 // projection uses calculateSheet; initial templates use class-level PB.
 const pb=clamp(2+Math.floor((Math.max(1,totalLevel)-1)/4),2,9);
 const armor=typeof template.ac==='object'?Number(template.ac.base||10)+Number(template.ac.per_pb||0)*pb:Number(template.ac)||10;
 const abilities=template.abilities||{};
 const trained=companionTemplateProficiencies(template,pb);
 const stat={name:String(name||template.name).trim().slice(0,160),source:template.source||'',
  type:template.type||'construct',size:(size||template.size||'M').slice(0,1).toUpperCase(),
  ...(template.alignment?{alignment:structuredClone(template.alignment)}:{}),
  ac:[armor],hp:{average:hp},
  ...(template.hp?.hit_die?{hit_dice:classLevel+'d'+Number(template.hp.hit_die)}:{}),
  speed:structuredClone(template.speed||{}),
  ...Object.fromEntries(['str','dex','con','int','wis','cha'].map(k=>[k,Number(abilities[k])||10])),
  skill:trained.skill,save:trained.save,
  languages:structuredClone(template.languages||[]),
  ...(template.passive!==undefined?{passive:typeof template.passive==='number'?template.passive:
   10+scoreMod(abilities.wis)+(trained.skill_ranks.perception||0)*pb}:{}),
  resist:structuredClone(template.resist||[]),vulnerable:structuredClone(template.vulnerable||[]),
  immune:structuredClone(template.immune||[]),conditionImmune:structuredClone(template.conditionImmune||[]),
  senses:structuredClone(template.senses||[]),
  trait:structuredClone(template.trait||[]),action:structuredClone(template.action||[]),
  reaction:structuredClone(template.reaction||[]),bonus:structuredClone(template.bonus||[]),
  spellcasting:structuredClone(template.spellcasting||[])};
 return stat;
}
// Legacy familiar sheets were created before all published fields were
// captured. Fill only missing descriptive entries in a read-only view, never
// rewrite the saved creature or its HP, inventory or manual ability values.
export function companionStatBlockView(creature={},catalog={}){
 if(!creature.parent_creature_id||!creature.companion_rule_id||
   !creature.companion_template_id)return creature;
 const rule=[...rows(catalog?.features),...rows(catalog?.spells)]
   .find(row=>row.id===creature.companion_rule_id);
 if(!rule||rule.template!==creature.companion_template_id)return creature;
 const template=catalog?.templates?.[rule.template];
 if(!template)return creature;
 const old=creature.stat_block||{},stat={...old};
 const copyIfMissing=field=>{
  if(stat[field]===undefined&&template[field]!==undefined)
   stat[field]=structuredClone(template[field]);
 };
 for(const field of ['languages','passive','senses','resist','vulnerable','immune',
   'conditionImmune','spellcasting'])copyIfMissing(field);
 // Older catalog versions omitted entire reactions or individual traits.
 // Reconcile by stable source names without replacing saved text.
 for(const field of ['trait','reaction','bonus']){
  const current=rows(old[field]),additional=rows(template[field]).filter(row=>
   !current.some(saved=>normal(saved?.name)===normal(row?.name)));
  if(additional.length||!Array.isArray(old[field])&&Array.isArray(template[field]))
   stat[field]=[...current,...structuredClone(additional)];
 }
 return {...creature,stat_block:stat};
}
export function companionSources(rule,data,bestiary=[],owner={}){
 if(!rule)return [];
 const templates=Object.entries(data?.templates||{})
  .filter(([id])=>id===rule.template).map(([id,template])=>({
   key:'template:'+id,id:'template:'+id,name:template.name,source:template.source||'',
   template_id:id,load:async options=>companionTemplateStat(template,owner,options||{})
  }));
 const names=new Set(rows(rule.monsters).map(normal));
 const filtered=bestiary.filter(entry=>(
   names.has(normal(entry.name))||
   (rule.filter&&creatureMatchesFilter({...(entry.stat_block||entry),id:entry.id},rule.filter))
 ));
 return [...templates,...filtered];
}
export function validCompanionChoice(rule,choice){
 return !!(rule&&choice&&typeof choice.load==='function'&&typeof choice.key==='string');
}
