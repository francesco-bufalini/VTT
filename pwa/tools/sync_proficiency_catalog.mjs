// Synchronise the canonical per-benefit-type catalogue with the reviewed
// native 5eTools snapshot. The old browser index is metadata-only.
import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {proficiencyIndexFromBenefits,proficiencySourceEntry,PROFICIENCY_SOURCE_SECTIONS}
 from '../proficiency_catalog.js';
const read=async path=>JSON.parse(await readFile(new URL(path,import.meta.url),'utf8'));
const write=(path,data)=>writeFile(new URL(path,import.meta.url),JSON.stringify(data,null,2)+'\n');
const norm=x=>String(x??'').trim().toLowerCase();
const arr=x=>Array.isArray(x)?x:[];
const identity=(section,row)=>[section,norm(row?.source),norm(row?.name),
 norm(row?.raceName),norm(row?.raceSource),norm(row?.class_name),norm(row?.class_source),
 norm(row?.subclass_short_name),norm(row?.subclass_source),norm(row?.id)].join('|');
const same=(a,b)=>norm(a)===norm(b);
const uniqueValues=values=>[...new Map(values.map(x=>[JSON.stringify(x),x])).values()];

export async function syncProficiencyCatalog(){
 const native=await read('../../vtt/data/proficiency_grants_5etools.json');
 const meta=await read('../catalog/proficiency_grants.json');
 const typed=await read('../../vtt/enrichment/benefits/proficiency_grant.json');
 if(typed?.benefit_type!=='proficiency_grant'||typed.schema_version!==2)
  throw Error('Il catalogo proficiency_grant v2 manca: non rigenerare il file legacy.');
 const projected=proficiencyIndexFromBenefits(meta,typed);
 // Keep the same source update policy previously applied to the browser index.
 projected.background=arr(native.background);
 projected.subrace=arr(native.subrace);
 projected.classFeature=arr(native.classFeature);
 projected.subclassFeature=arr(native.subclassFeature);
 for(const group of ['race','subrace','feat']){
  for(const row of arr(native[group])){
   const target=arr(projected[group]).find(x=>same(x.name,row.name)&&
     same(x.source,row.source)&&
     (group!=='subrace'||same(x.raceName,row.raceName)&&same(x.raceSource,row.raceSource)));
   if(!target)continue;
   for(const key of ['trait_proficiencies','trait_proficiency_choices'])
    if(row[key])target[key]=row[key];
  }
 }
 // Reviewed feat supplements remain source-qualified, but are not stored in
 // a second runtime catalog.
 const feats=await read('../../vtt/data/feat_proficiency_bonuses_2014.json');
 for(const row of arr(feats.feats)){
  const existing=projected.feat.find(x=>same(x.name,row.name)&&same(x.source,row.source));
  if(existing)for(const [key,items] of Object.entries(row)){
   if(Array.isArray(items))existing[key]=uniqueValues([...arr(existing[key]),...items]);
  }else projected.feat.push(row);
 }
 // Preserve stable grant IDs and editorial metadata for existing entries.
 const previous=new Map();
 for(const entry of arr(typed.entries)){
  const source=entry.benefit?.proficiency_grant?.source_rules;
  if(!source)continue;
  const ref=entry.granted_by?.ref||{};
  const row={name:ref.name,source:ref.source,...(source.metadata||{}),
   ...(ref.id?{id:ref.id}:{}),
   ...(ref.race?{raceName:ref.race,raceSource:ref.race_source}:{}),
   ...(ref.class_name?{class_name:ref.class_name,class_source:ref.class_source}:{}),
   ...(ref.subclass?{subclass_short_name:ref.subclass,subclass_source:ref.subclass_source}:{})};
  const key=identity(source.section,row);
  if(!previous.has(key))previous.set(key,[]);
  previous.get(key).push(entry);
 }
 const entries=arr(typed.entries).filter(x=>!x.benefit?.proficiency_grant?.source_rules);
 const emitted=new Set(entries.map(row=>row.id));
 for(const section of PROFICIENCY_SOURCE_SECTIONS){
  for(const [i,row] of arr(projected[section]).entries()){
   const key=identity(section,row),earlier=previous.get(key)?.shift();
   const fallback='migrated:'+section+':'+i+':'+encodeURIComponent(row.source+'|'+row.name);
   const result=proficiencySourceEntry(section,row,earlier?.id||fallback);
   if(emitted.has(result.id))throw Error('Concessione duplicata: '+result.id);
   emitted.add(result.id);
   entries.push(earlier?{...earlier,granted_by:result.granted_by,
    benefit:{...earlier.benefit,proficiency_grant:{
     ...earlier.benefit.proficiency_grant,source_rules:result.benefit.proficiency_grant.source_rules
    }}}:result);
  }
 }
 typed.entries=entries;
 await write('../../vtt/enrichment/benefits/proficiency_grant.json',typed);
 await write('../catalog/proficiency_grants.json',{meta:{...meta.meta,
  featureSnapshot:native.meta?.featureSnapshot||meta.meta?.featureSnapshot,
  proficiencyData:'vtt/enrichment/benefits/proficiency_grant.json'},
  languages:arr(native.languages).length?native.languages:meta.languages});
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))
 await syncProficiencyCatalog();
