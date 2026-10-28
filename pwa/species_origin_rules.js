// Shared source and ownership resolution for typed species benefits.
export const norm=value=>String(value??'').trim().toLowerCase();
export const same=(a,b)=>norm(a)===norm(b);
export const sourceMuted=(record,id)=>!!id&&(record.origin_enabled?.[id]===false||
 (Array.isArray(record.proficiency_origins)?record.proficiency_origins:[])
  .some(row=>row?.id===id&&row.disabled));
export const speciesOriginKey=(record,subrace=false)=>subrace?
 'subrace|'+norm(record.subrace_source)+'|'+norm(record.subrace):
 'species|'+(record.species_id||norm(record.species))+'|'+norm(record.species_source);
export const speciesTraitOwner=(features,trait,originKey)=>
 (Array.isArray(features)?features:[]).find(row=>same(row.name,trait)&&row.origin_key===originKey);
export function flattenedSpeciesSources(record={},catalog={},exclude2024=false){
 const races=(Array.isArray(catalog.races)?catalog.races:[])
  .filter(row=>!exclude2024||!same(row.source,'XPHB'));
 const parent=races.find(row=>same(row.name,record.species)&&same(row.source,record.species_source));
 const name=record.subrace?record.species+' ('+record.subrace+')':'';
 const variants=name?races.filter(row=>same(row.name,name)):[];
 const sub=variants.find(row=>same(row.source,record.subrace_source||record.species_source))||
  (!record.subrace_source&&variants.length===1?variants[0]:null);
 return {parent,sub};
}
