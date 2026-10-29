// Source-driven 5eTools optionalfeatureProgression choices. No class-specific branches.
// Existing optional_features_catalog/fighting_styles remain valid and visible.
import {isContentAvailableForRules} from './source_edition.js';

const rows=v=>Array.isArray(v)?v:[];
const low=v=>String(v??'').trim().toLowerCase();
const same=(a,b)=>low(a)===low(b);
const identity=option=>typeof option==='string'?option:String(option?.id||'');
const classMembers=record=>rows(record.classes).length?record.classes:[{
 name:record.class,source:record.class_source,subclass:record.subclass,
 subclass_source:record.subclass_source,level:record.level
}];
const maximum=(progression,level)=>{
 const entries=Array.isArray(progression)?progression.map((n,i)=>[i+1,n]):Object.entries(progression||{});
 let count=0;
 for(const [at,value] of entries)if(Number(at)<=level)count=Math.max(0,Number(value)||0);
 return count;
};
function ownerMember(record,owner){
 return classMembers(record).find(member=>same(member.name,owner.class_name)&&
  same(member.source||record.class_source||'PHB',owner.class_source)&&
  (!owner.subclass||same(member.subclass||record.subclass,owner.subclass)&&
   (!member.subclass_source&&!record.subclass_source||
    same(member.subclass_source||record.subclass_source,owner.subclass_source))));
}
function ownedFeature(features,owner){
 return rows(features).find(row=>same(row.name,owner.trait)&&
  same(row.requirements?.class_name||row.class_name||String(row.origin_key||'').split('|')[2],owner.class_name)&&
  (!row.requirements?.class_source&&!row.class_source||
   same(row.requirements?.class_source||row.class_source,owner.class_source))&&
  (!owner.subclass||same(row.requirements?.subclass||row.subclass||'',owner.subclass)||
    String(row.origin_key||'').toLowerCase().includes(low(owner.subclass)))&&
  !row.disabled&&!row.inactive);
}
function optionLevel(entry,owner){
 const levels=rows(entry.prerequisite).flatMap(row=>{
  const req=row?.level;
  if(!req)return [];
  if(typeof req==='number')return [req];
  if(typeof req==='object'&&(!req.class||same(req.class.name,owner.class_name)))
   return [Number(req.level)||0];
  return [];
 });
 return levels.length?Math.min(...levels):0;
}
function requiredOptionIds(rule,options,level){
 const ids=new Set();
 for(const [at,required] of Object.entries(rule.required||{})){
  if(Number(at)>level)continue;
  for(const key of rows(required)){
   const [name,source]=String(key).split('|');
   const option=options.find(row=>same(row.name,name)&&(!source||same(row.source,source)));
   if(option)ids.add(option.id);
  }
 }
 return [...ids];
}
function legacyChoices(record,options,claimed,progressionId){
 const candidates=[...rows(record.optional_features_catalog).filter(row=>row&&!row.disabled),
  ...rows(record.fighting_styles).map(row=>typeof row==='string'?{name:row}:row).filter(Boolean)];
 const ids=[];
 for(const row of candidates){
  // Choices saved by the generic learner belong to their original progression.
  // Only pre-existing unbound rows may be distributed to the first match.
  if(row.optional_progression_id&&row.optional_progression_id!==progressionId)continue;
  const found=options.find(opt=>!opt._homebrew&&same(opt.name,row.name)&&
   (!row.source||same(row.source,opt.source)));
  const fallback=found||(!row.source?options.find(opt=>!opt._homebrew&&same(opt.name,row.name)):null);
  if(!fallback||claimed.has(fallback.id)||ids.includes(fallback.id))continue;
  ids.push(fallback.id);claimed.add(fallback.id);
 }
 return ids;
}
export function optionalFeatureSelectionModels(record={},calculated={},catalog={}){
 const result=[],claimed=new Set();
 const sourceOptions=rows(catalog.options);
 for(const rule of rows(catalog.progressions)){
  if(rows(rule.feature_types).some(type=>rows(catalog.external_feature_types).includes(type)))continue;
  if(!isContentAvailableForRules({source:rule.owner?.class_source},record.rules_version))continue;
  const member=ownerMember(record,rule.owner||{});
  if(!member)continue;
  const level=Math.max(0,Number(member.level)||0);
  const limit=maximum(rule.progression,level);
  const saved=rows(record.power_selections?.[rule.id]?.learned);
  const custom=rows(record.power_selection_custom_options?.[rule.id]).filter(row=>row?._homebrew===true);
  const previously=new Set(saved.map(identity));
  const options=[...sourceOptions.filter(entry=>rows(entry.types).some(t=>rows(rule.feature_types).includes(t))&&
    (isContentAvailableForRules(entry,record.rules_version)||previously.has(entry.id))).map(entry=>({
     id:entry.id,name:entry.name,source:entry.source,min_level:optionLevel(entry,rule.owner),
     description:entry.description||'',prerequisite:entry.prerequisite||[]
   })),...custom];
  const byId=new Map(options.map(row=>[row.id,row]));
  const required=requiredOptionIds(rule,options,level);
  const selected=[...required];
  for(const row of saved){
   const id=identity(row);
   if(byId.has(id)&&!selected.includes(id)){selected.push(id);claimed.add(id);}
  }
  // Old sheets keep their selected optional features, without requiring migration.
  // Distribute ambiguous legacy choices to the first applicable progression.
  for(const id of legacyChoices(record,options,claimed,rule.id))if(!selected.includes(id))selected.push(id);
  const feature=ownedFeature(calculated.features,rule.owner||{});
  if(limit<=0&&!selected.length)continue;
  const layers={learned:{enabled:true,selected,limit,used:selected.length,
   trigger:rule.trigger||null,change_label:rule.trigger==='level_up'?'Passaggio di livello':'',
   storage:'optional_features_catalog',available:true}};
  // Always-on options use the same learned/applied stages as other powers.
  // Their application is derived from knowledge: no second user selection,
  // active-style cap, persisted toggles or special Fighting Style handler.
  if(rule.layers?.applied?.mode==='automatic'&&rule.layers.applied.from==='learned')
   layers.applied={enabled:true,selected:[...selected],limit:null,used:selected.length,
    trigger:null,change_label:'',storage:'derived:learned',available:true,
    automatic:true,refundable:false};
  result.push({id:rule.id,title:rule.title,origin_id:feature?.origin_id||'',
    source_type:'optionalfeature_progression',option_kind:'optional_feature',
    description:'Opzioni da 5eTools · puoi aggiungere capacità homebrew.',
    level,ui:'generic',options,required,layers});
 }
 return result;
}
export function optionalFeatureSelectionPatch(record,calculated,catalog,id,stage,optionId){
 if(stage!=='learned')throw Error('Questa selezione usa soltanto le opzioni imparate.');
 const model=optionalFeatureSelectionModels(record,calculated,catalog).find(row=>row.id===id);
 const option=model?.options.find(row=>row.id===optionId);
 const layer=model?.layers.learned;
 if(!option||!layer)throw Error('Opzione non disponibile per questa classe.');
 if(option.min_level&&option.min_level>model.level&&!layer.selected.includes(optionId))throw Error('Livello insufficiente per questa opzione.');
 if(model.required.includes(optionId))throw Error('Questa opzione è obbligatoria.');
 const selected=layer.selected.map(identity),present=selected.includes(optionId);
 if(!present&&layer.limit!==null&&selected.length>=layer.limit)
  throw Error('Numero massimo di opzioni raggiunto.');
 if(!present&&optionalFeatureSelectionModels(record,calculated,catalog).some(row=>
  row.id!==id&&row.layers.learned.selected.some(entry=>identity(entry)===optionId)))
  throw Error('Opzione già scelta in un altro privilegio.');
 const next=present?selected.filter(key=>key!==optionId):[...selected,optionId];
 const saved={...(record.power_selections||{}),[id]:{
  ...(record.power_selections?.[id]||{}),learned:next.filter(key=>!model.required.includes(key))}};
 const active=new Set(next),other=new Set();
 for(const [key,value] of Object.entries(record.power_selections||{}))
  if(key!==id)for(const row of rows(value?.learned))other.add(identity(row));
 const inUse=idValue=>active.has(idValue)||other.has(idValue);
 const allModels=optionalFeatureSelectionModels({...record,power_selections:saved},calculated,catalog);
 for(const row of allModels)if(row.id!==id)
  for(const item of row.layers.learned.selected)other.add(identity(item));
 const previously=model.options.find(row=>row.id===optionId);
 let existing=rows(record.optional_features_catalog).filter(row=>{
  if(!row||!same(row.name,previously.name)||!same(row.source||'HB',previously.source||'HB'))return true;
  return !present||inUse(optionId);
 });
 if(!present&&!existing.some(row=>same(row.name,option.name)&&same(row.source,option.source))){
  existing=[...existing,{name:option.name,source:option.source||'HOMEBREW',
   ...(option._homebrew?{_homebrew:true}:{}),
   ...(option._homebrew&&option.description?{entries:[option.description]}:{}),
   optional_progression_id:id}];
 }
 const fighting_styles=rows(record.fighting_styles).filter(row=>{
  if(!present)return true;
  const name=typeof row==='string'?row:row?.name;
  return !same(name,previously.name)||inUse(optionId);
 });
 return {power_selections:saved,optional_features_catalog:existing,fighting_styles};
}
