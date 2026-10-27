// Source-qualified species defenses projected from the generated 2014-era
// 5etools catalogue. The original character record remains unchanged.
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
const same=(a,b)=>norm(a)===norm(b);
const muted=(record,id)=>Boolean(id&&(record.origin_enabled?.[id]===false||
 rows(record.proficiency_origins).some(row=>row?.id===id&&row.disabled)));
export function speciesDefenseEntries(record={},catalog={},features=[],removed=new Set()){
 if(!record.species||!record.species_source)return [];
 const available=rows(catalog?.races);
 const race=available.find(r=>record.species_id&&r.id===record.species_id&&
   same(r.source,record.species_source)&&
   (same(r.name,record.species)||record.subrace&&
    norm(r.name).startsWith(norm(record.species)+' (')))||
  available.find(r=>same(r.name,record.species)&&same(r.source,record.species_source));
 if(!race||same(race.source,'XPHB'))return [];
 const base='race|'+norm(race.source)+'|'+norm(race.name);
 const selected='race|'+norm(record.species_source)+'|'+norm(record.species);
 const parent='species|'+(record.species_id||norm(record.species))+'|'+norm(record.species_source);
 if(muted(record,base)||muted(record,selected)||muted(record,parent))return [];
 const own=entry=>{
  const feature=rows(features).find(f=>same(f.name,entry.trait)&&
   (f.origin_key===parent||f.origin_key==='species|'+race.id+'|'+norm(race.source)));
  if(feature?.inactive||feature?.disabled||feature?.key&&record.trait_enabled?.[feature.key]===false)return null;
  const origin_id=feature?.origin_id||base;
  if(muted(record,origin_id))return null;
  return {origin_id,origin_name:feature?'Tratto · '+feature.name:'Specie · '+race.name,
   origin_parent_id:base,origin_parent_name:race.name,granting_trait:entry.trait};
 };
 const chosen=record.origin_defense_choices?.[race.id]??
   record.origin_defense_choices?.[base]??record.origin_defense_choices?.[parent];
 const options=rows(race.choices).flatMap(choice=>
   typeof chosen==='string'&&rows(choice.from).some(value=>same(value,chosen))?
    [{rank:choice.rank,key:norm(chosen),trait:choice.trait}]:[]);
 const result=[];
 for(const entry of [...rows(race.entries),...options]){
  if(!entry||![-1,1,2,3].includes(entry.rank)||!entry.key||!entry.trait)continue;
  const id='defense:'+base+':'+entry.rank+':'+norm(entry.key);
  if(removed.has(id))continue;
  const origin=own(entry);
  if(!origin)continue;
  result.push({...entry,...origin,benefit_id:id,id:'auto|'+id,automatic:true,disabled:false});
 }
 return result;
}
