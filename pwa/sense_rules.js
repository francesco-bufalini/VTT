// Typed, source-bound sensory grants: never infer mechanics from trait descriptions.
import {removedBenefitIds} from './trait_benefit_editor.js';
import {resolveOwnedItem,itemBenefitCopies} from './item_controls.js';
const arr=v=>Array.isArray(v)?v:[];
const norm=v=>String(v??'').trim().toLowerCase();
const same=(a,b)=>norm(a)===norm(b);
export const SENSE_NAMES={normal:'Visione normale',darkvision:'Scurovisione',
 blindsight:'Vista cieca',tremorsense:'Percezione tellurica',truesight:'Vista pura',
 devils_sight:'Vista del diavolo'};
export const SENSE_OPTIONS=Object.entries(SENSE_NAMES).filter(([key])=>key!=='normal');
export const senseRange=feet=>Math.round(feet)+' ft · '+Math.round(feet*0.3048)+' m';

export function senseLightRows(distances={}){
 const result=[{type:'normal',name:'Visione normale',bright:'Linea di vista',
  dim:'Linea di vista · luce fioca',dark:'Nessuna',magical:'Nessuna'}];
 for(const [type,name] of SENSE_OPTIONS){
  const feet=Number(distances[type]||0);
  if(!(feet>0))continue;
  const r=senseRange(feet),entry={type,name,bright:r,dim:r,dark:r,magical:r};
  if(type==='darkvision')Object.assign(entry,{bright:'—',dim:r+' · luce intensa',
   dark:r+' · luce fioca',magical:'Nessuna'});
  if(type==='devils_sight')Object.assign(entry,{bright:'—',dim:'—',
   dark:r+' · visione normale',magical:r+' · visione normale'});
  if(type==='tremorsense')for(const light of ['bright','dim','dark','magical'])
   entry[light]=r+' · vibrazioni';
  result.push(entry);
 }
 return result;
}
function monsterSenses(record){
 const raw=record.stat_block?.senses??record.senses??[],result=[];
 if(raw&&!Array.isArray(raw)&&typeof raw==='object'){
  for(const [type,value] of Object.entries(raw))
   if(SENSE_OPTIONS.some(([id])=>id===norm(type)))result.push({type:norm(type),range_feet:Number(value)});
 }else for(const entry of (Array.isArray(raw)?raw:[raw]))
  for(const part of String(entry||'').split(',')){
   const m=part.trim().match(/^(darkvision|blindsight|tremorsense|truesight)\s+(\d+)\s*(ft\.?|feet|m)?/i);
   if(m)result.push({type:norm(m[1]),range_feet:Math.round(Number(m[2])*(norm(m[3])==='m'?1/0.3048:1))});
  }
 return result;
}
export function calculateSenses(record={},features=[],catalog={},sourceEnabled=()=>true){
 const hidden=removedBenefitIds(record),grants=[];
 const originOn=id=>!id||record.origin_enabled?.[id]!==false&&
  !arr(record.proficiency_origins).some(row=>row?.id===id&&row.disabled);
 const activeFeature=f=>!f.inactive&&!f.disabled&&record.trait_enabled?.[f.key]!==false&&
  originOn(f.origin_id)&&originOn(f.origin_key)&&originOn(
   String(f.origin_key||'').startsWith('class|')?String(f.origin_key).split('|').slice(0,3).join('|'):'');
 const add=row=>{
  const feet=Number(row.range_feet);
  if(!SENSE_OPTIONS.some(([id])=>id===row.type)||!Number.isInteger(feet)||feet<1||feet>10000||
   row.disabled||hidden.has('sense:'+row.id)||!originOn(row.origin_id)||
   !originOn(row.parent_origin)||!sourceEnabled(row))return;
  const sid=String(row.origin_id||'');
  if(sid.startsWith('feature:trait:')){
   const key=sid.slice('feature:trait:'.length);
   if(record.trait_enabled?.[key]===false)return;
   if(key.startsWith('item:')&&!arr(record.inventory).some(item=>
    key.startsWith('item:'+String(item.id||'')+'|')&&
    itemBenefitCopies(resolveOwnedItem(item))>0))return;
  }
  grants.push({...row,range_feet:feet});
 };
 for(const row of arr(record.sense_grants))add(row);
 for(const row of arr(catalog.species)){
  if(!same(record.species,row.name)||!same(record.species_source,row.source))continue;
  const origin='race|'+norm(row.source)+'|'+norm(row.name);
  // Custom Lineage (TCE) offers darkvision OR a skill. The raw JSON lists
  // darkvision as a field, but it must not become an unconditional benefit.
  if(row.choice_required&&
   record.origin_sense_choices?.[origin]!==row.choice_required)continue;
  const feature=features.find(f=>same(f.name,row.trait)&&String(f.origin_key||'').startsWith('species|'));
  if(feature&&!activeFeature(feature))continue;
  add({id:'auto|sense|'+origin+'|'+row.type,origin_id:feature?.origin_id||origin,
   parent_origin:feature?origin:'',origin_name:feature?'Tratto · '+feature.name:'Specie · '+row.name,
   type:row.type,range_feet:row.range_feet,automatic:true});
 }
 for(const row of arr(catalog.subraces)){
  if(!same(record.species,row.race_name)||!same(record.subrace,row.name)||
   !same(record.subrace_source,row.source)||
   row.race_source&&!same(record.species_source,row.race_source))continue;
  const origin='subrace|'+norm(row.source)+'|'+norm(row.name);
  const feature=features.find(f=>same(f.name,row.trait)&&
   String(f.origin_key||'').startsWith('subrace|'));
  if(feature&&!activeFeature(feature))continue;
  add({id:'auto|sense|'+origin+'|'+row.type,origin_id:feature?.origin_id||origin,
   parent_origin:feature?origin:'',origin_name:'Sottospecie · '+row.name,
   type:row.type,range_feet:row.range_feet,automatic:true});
 }
 for(const feature of features){
  if(!activeFeature(feature))continue;
  for(const rule of arr(catalog.features)){
   if(!same(feature.name,rule.name)||
    rule.class_name&&!same(feature.requirements?.class_name||feature.class_name,rule.class_name)||
    rule.class_source&&!same(feature.requirements?.class_source||feature.class_source,rule.class_source)||
    rule.source&&!same(String(feature.origin_key||'').split('|')[1],rule.source))continue;
   add({id:'auto|sense|'+feature.origin_id+'|'+rule.type,origin_id:feature.origin_id,
    parent_origin:feature.origin_key,origin_name:'Tratto · '+feature.name,
    type:rule.type,range_feet:rule.range_feet,mode:rule.mode||'maximum',
    fallback_feet:rule.fallback_feet,automatic:true});
  }
 }
 for(const [i,sense] of monsterSenses(record).entries())
  add({id:'statblock|sense|'+i,origin_id:'',origin_name:'Bollettino del mostro',...sense});
 const distances={};
 for(const row of grants.filter(row=>row.mode!=='increase_if_existing'))
  distances[row.type]=Math.max(distances[row.type]||0,row.range_feet);
 for(const row of grants.filter(row=>row.mode==='increase_if_existing'))
  distances[row.type]=distances[row.type]>0?distances[row.type]+row.range_feet:
   Number(row.fallback_feet)||row.range_feet;
 return {grants,distances,rows:senseLightRows(distances)};
}
