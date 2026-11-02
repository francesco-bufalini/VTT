// Runtime projection of source-qualified typed proficiency benefits.
// No proficiency mechanics remain authored in the legacy index.
const rows=v=>Array.isArray(v)?v:[];
export const PROFICIENCY_SOURCE_SECTIONS=['class','race','subrace','background','feat','classFeature','subclassFeature'];
export function proficiencyIndexFromBenefits(languageCatalog={},catalog={}){
 // Language names and types come solely from the dedicated 5eTools glossary.
 // The legacy proficiency catalog has no runtime role and must not be restored.
 const index={languages:rows(languageCatalog?.languages)};
 for(const section of PROFICIENCY_SOURCE_SECTIONS)index[section]=[];
 if(catalog?.schema_version!==2||catalog?.benefit_type!=='proficiency_grant'||
   !Array.isArray(catalog.entries))return index;
 for(const entry of catalog.entries){
  if(entry?.enabled===false||entry?.benefit?.type!=='proficiency_grant')continue;
  const rules=entry.benefit.proficiency_grant?.source_rules;
  if(!rules||!PROFICIENCY_SOURCE_SECTIONS.includes(rules.section))continue;
  const ref=entry.granted_by?.ref||{};
  const record={name:ref.name,source:ref.source,...(rules.metadata||{})};
  if(ref.id)record.id=ref.id;
  if(ref.race)record.raceName=ref.race;
  if(ref.race_source)record.raceSource=ref.race_source;
  if(ref.class_name)record.class_name=ref.class_name;
  if(ref.class_source)record.class_source=ref.class_source;
  if(ref.subclass)record.subclass_short_name=ref.subclass;
  if(ref.subclass_source)record.subclass_source=ref.subclass_source;
  if(ref.level!==undefined)record.level=ref.level;
  if(rules.section==='class'){
   const starting=rows(rules.stages).find(s=>s.stage==='starting')?.fields||{};
   const multiclass=rows(rules.stages).find(s=>s.stage==='multiclass')?.fields||{};
   const {savingThrows,...skills}=starting;
   record.startingProficiencies=skills;
   if(Object.keys(multiclass).length)record.multiclassProficiencies=multiclass;
   if(savingThrows!==undefined)record.savingThrows=savingThrows;
  }else Object.assign(record,rows(rules.stages).find(s=>s.stage==='default')?.fields||{});
  index[rules.section].push(record);
 }
 return index;
}

// Used by the upstream 5eTools synchronization tool to update the same
// canonical catalog, never to recreate the retired proficiency index.
export function proficiencySourceEntry(section,origin,id){
 if(!PROFICIENCY_SOURCE_SECTIONS.includes(section)||!origin?.name||!origin?.source)
  throw Error('Origine delle competenze non valida.');
 const category=section==='race'?'species':section==='classFeature'?'class_feature':
  section==='subclassFeature'?'subclass_feature':section;
 const ref={category,name:origin.name,source:origin.source,
  ...(origin.id?{id:origin.id}:{}),
  ...(origin.raceName?{race:origin.raceName,race_source:origin.raceSource}:{}),
  ...(origin.class_name?{class_name:origin.class_name,class_source:origin.class_source}:{}),
  ...(origin.subclass_short_name?{subclass:origin.subclass_short_name,
   subclass_source:origin.subclass_source}:{}),
  ...(Number.isInteger(origin.level)?{level:origin.level}:{})};
 const fields={...origin};
 for(const key of ['name','source','id','raceName','raceSource','class_name',
  'class_source','subclass_short_name','subclass_source','level'])delete fields[key];
 let source_rules;
 if(section==='class'){
  const starting=fields.startingProficiencies||{},multiclass=fields.multiclassProficiencies||{};
  const savingThrows=fields.savingThrows||[];
  delete fields.startingProficiencies;delete fields.multiclassProficiencies;delete fields.savingThrows;
  source_rules={section,metadata:fields,stages:[
   {stage:'starting',fields:{...starting,...(savingThrows.length?{savingThrows}:{})}},
   {stage:'multiclass',fields:multiclass}]};
 }else{
  const metadata={};
  for(const key of ['trait_proficiencies','trait_proficiency_choices',
   'replaces_parent_languages','language_grant_replaced_by',
   'language_grant_requires_opt_in','proficiencyReplacements']){
   if(Object.hasOwn(fields,key)){metadata[key]=fields[key];delete fields[key];}
  }
  source_rules={section,metadata,stages:[{stage:'default',fields}]};
 }
 const key=id||'migrated:'+section+':'+encodeURIComponent(
  [origin.source,origin.name,origin.raceName||'',origin.class_name||'',
   origin.subclass_short_name||'',origin.id||''].join('|'));
 return {id:key,granted_by:{kind:'5etools',ref},
  benefit:{type:'proficiency_grant',id:key,proficiency_grant:{id:key,source_rules}}};
}
