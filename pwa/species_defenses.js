// Source-qualified, non-destructive projection of 5etools species defenses.
// Species and subraces are separate origins; flattened 5etools variants repeat
// inherited traits, which must never grant the same defense twice.
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
const same=(a,b)=>norm(a)===norm(b);
const muted=(record,id)=>Boolean(id&&(record.origin_enabled?.[id]===false||
 rows(record.proficiency_origins).some(row=>row?.id===id&&row.disabled)));
const effectKey=entry=>String(entry.rank)+':'+norm(entry.key);
const choiceKey=choice=>String(choice.rank)+':'+norm(choice.trait);

export function selectedSpeciesDefenseRules(record={},catalog={}){
 if(!record.species||!record.species_source)return [];
 const available=rows(catalog.races).filter(row=>!same(row.source,'XPHB'));
 // Never trust a stale ID alone: changing species or editions invalidates it.
 const parent=available.find(row=>same(row.name,record.species)&&
  same(row.source,record.species_source));
 const subName=record.subrace?record.species+' ('+record.subrace+')':'';
 // Old imported characters sometimes omitted the subrace source. Prefer
 // their parent book; never guess when several other versions exist.
 const compatible=record.subrace?available.filter(row=>same(row.name,subName)):[];
 const sub=compatible.find(row=>same(row.source,record.subrace_source||record.species_source))||
  (!record.subrace_source&&compatible.length===1?compatible[0]:null);
 const results=[];
 if(parent)results.push({
  row:parent,source_id:'race|'+norm(parent.source)+'|'+norm(parent.name),
  origin_key:'species|'+(record.species_id||norm(record.species))+'|'+norm(record.species_source),
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
 const parentKey='species|'+(record.species_id||norm(record.species))+'|'+norm(record.species_source);
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
   const owner=rows(features).find(f=>same(f.name,entry.trait)&&
    f.origin_key===source.origin_key);
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
