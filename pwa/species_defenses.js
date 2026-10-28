import {norm,same,sourceMuted,speciesOriginKey,speciesTraitOwner,flattenedSpeciesSources} from './species_origin_rules.js';
// Source-qualified, non-destructive projection of 5etools species defenses.
// Species and subraces are separate origins; flattened 5etools variants repeat
// inherited traits, which must never grant the same defense twice.
const rows=value=>Array.isArray(value)?value:[];
const muted=sourceMuted;
const effectKey=entry=>String(entry.rank)+':'+norm(entry.key);
const choiceKey=choice=>String(choice.rank)+':'+norm(choice.trait);

export function selectedSpeciesDefenseRules(record={},catalog={}){
 // Fizban variants replace the entire PHB dragonborn ancestry. Their resistance
 // is derived from the single ancestry selection by dragonbornFtdResistances.
 if((/^dragonborn \((chromatic|metallic|gem)\)$/i.test(record.species||'')&&same(record.species_source,'FTD'))||
   (same(record.species,'Dragonborn')&&same(record.species_source,'PHB')&&same(record.subrace_source,'FTD')&&
    ['chromatic','metallic','gem'].includes(norm(record.subrace))))return [];
 if(!record.species||!record.species_source)return [];
 const {parent,sub}=flattenedSpeciesSources(record,catalog,true);
 const results=[];
 if(parent)results.push({
  row:parent,source_id:'race|'+norm(parent.source)+'|'+norm(parent.name),
  origin_key:speciesOriginKey(record),
  entries:rows(parent.entries),choices:rows(parent.choices)
 });
 if(sub){
  const includedEffects=new Set(rows(parent?.entries).map(effectKey));
  const includedChoices=new Set(rows(parent?.choices).map(choiceKey));
  const entries=rows(sub.entries).filter(row=>!includedEffects.has(effectKey(row)));
  const choices=rows(sub.choices).filter(row=>!includedChoices.has(choiceKey(row)));
  if(entries.length||choices.length)results.push({
   row:sub,source_id:'subrace|'+norm(record.subrace_source)+'|'+norm(record.subrace),
   origin_key:'subrace|'+norm(record.subrace_source)+'|'+norm(record.subrace),
   entries,choices
  });
 }
 return results;
}

// A flattened subrace's traits are not present in the compact base-race index.
// Project just its defense-bearing named traits so they are visible in Tratti,
// retaining their 5etools description and the usual stable activation key.
export function speciesDefenseFeatures(record={},catalog={},existing=[]){
 const additional=[];
 for(const selected of selectedSpeciesDefenseRules(record,catalog)){
  for(const name of new Set([...selected.entries,...selected.choices].map(row=>row.trait))){
   if(!name||[...rows(existing),...additional].some(row=>same(row.name,name)&&
     row.origin_key===selected.origin_key))continue;
   const source=rows(selected.row.trait_details).find(row=>same(row.name,name));
   const key=selected.origin_key+'|'+selected.origin_key+'|1|'+norm(name);
   additional.push({name,key,origin_id:'feature:'+key,
    origin_key:selected.origin_key,level:1,source:selected.row.source,
    entries:source?.entries||[],requirements:{scope:'character',min_level:1},
    bonuses:[],action_kind:'Capacità',synthetic_species_defense:true});
  }
 }
 return additional;
}

export function speciesDefenseEntries(record={},catalog={},features=[],removed=new Set()){
 const selected=selectedSpeciesDefenseRules(record,catalog);
 const parentId='race|'+norm(record.species_source)+'|'+norm(record.species);
 const parentKey=speciesOriginKey(record);
 if(muted(record,parentId)||muted(record,parentKey))return [];
 const result=[];
 for(const source of selected){
  if(muted(record,source.source_id)||muted(record,source.origin_key))continue;
  const chosen=record.origin_defense_choices?.[source.source_id]??
   record.origin_defense_choices?.[source.row.id]??
   record.origin_defense_choices?.[source.origin_key];
  const choices=source.choices.flatMap(choice=>
   typeof chosen==='string'&&rows(choice.from).some(value=>same(value,chosen))?
    [{rank:choice.rank,key:norm(chosen),trait:choice.trait}]:[]);
  for(const entry of [...source.entries,...choices]){
   if(!entry||![-1,1,2,3].includes(entry.rank)||!entry.key||!entry.trait)continue;
   const legacy='defense:race|'+norm(source.row.source)+'|'+norm(source.row.name)+
     ':'+entry.rank+':'+norm(entry.key);
   const id='defense:'+source.source_id+':'+entry.rank+':'+norm(entry.key);
   if(removed.has(id)||removed.has(legacy))continue;
   const owner=speciesTraitOwner(features,entry.trait,source.origin_key);
   if(owner?.inactive||owner?.disabled||
      owner?.key&&record.trait_enabled?.[owner.key]===false||
      muted(record,owner?.origin_id))continue;
   // No guessed fallback trait attribution: a missing indexed feature is
   // recoverable through speciesDefenseFeatures using the same source key.
   const origin_id=owner?.origin_id||source.source_id;
   result.push({...entry,origin_id,origin_name:owner?'Tratto · '+owner.name:
    'Specie · '+source.row.name,origin_parent_id:source.source_id,
    origin_parent_name:source.row.name,granting_trait:entry.trait,
    benefit_id:id,id:'auto|'+id,automatic:true,disabled:false});
  }
 }
 return result;
}
