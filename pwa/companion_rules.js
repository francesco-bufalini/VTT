// Structured companion rules shared by spells, feature buttons, and the
// familiar picker. No feature is detected from its description text.
import {creatureMatchesFilter} from './creature_variants.js';

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
export function spellCompanionRule(data,spell,owner){
 const candidates=[normal(spell?.name),normal(spell?.id)];
 return rows(data?.spells).find(rule=>rows(rule.editions).includes(String(owner.rules_version||'2014'))&&
  rows(rule.names).some(n=>candidates.some(c=>c===normal(n)||c.endsWith(' '+normal(n)))))||null;
}
export function companionTemplateStat(template,owner,{size='',name=''}={}){
 if(!template||typeof template!=='object'||!template.name)throw Error('Profilo creatura mancante.');
 const classLevel=classInfo(owner,template.hp?.class_name).level;
 const hp=Math.max(1,Math.floor(Number(template.hp?.base||1)+
  (Number(template.hp?.per_class_level)||0)*classLevel+
  (template.hp?.ability_mod?scoreMod(owner.abilities?.[template.hp.ability_mod]):0)));
 const pb=clamp(Number(owner.proficiency_bonus)||2,2,9);
 const armor=typeof template.ac==='object'?Number(template.ac.base||10)+Number(template.ac.per_pb||0)*pb:Number(template.ac)||10;
 const abilities=template.abilities||{};
 const stat={name:String(name||template.name).trim().slice(0,160),source:template.source||'',
  type:template.type||'construct',size:(size||template.size||'M').slice(0,1).toUpperCase(),
  ac:[armor],hp:{average:hp},speed:structuredClone(template.speed||{}),
  ...Object.fromEntries(['str','dex','con','int','wis','cha'].map(k=>[k,Number(abilities[k])||10])),
  immune:structuredClone(template.immune||[]),conditionImmune:structuredClone(template.conditionImmune||[]),
  senses:structuredClone(template.senses||[]),
  trait:structuredClone(template.trait||[]),action:structuredClone(template.action||[])};
 return stat;
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
