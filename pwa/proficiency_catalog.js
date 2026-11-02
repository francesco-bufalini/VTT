// Runtime projection of source-qualified typed proficiency benefits.
// No proficiency mechanics remain authored in the legacy index.
const rows=v=>Array.isArray(v)?v:[];
export const PROFICIENCY_SOURCE_SECTIONS=['class','race','subrace','background','feat','classFeature','subclassFeature'];
export function proficiencyIndexFromBenefits(metadata={},catalog={}){
 if(catalog?.schema_version!==2||catalog?.benefit_type!=='proficiency_grant'||
   !Array.isArray(catalog.entries))return metadata;
 const index={meta:metadata.meta||{},languages:rows(metadata.languages)};
 for(const section of PROFICIENCY_SOURCE_SECTIONS)index[section]=[];
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
   record.startingProficiencies=skills;record.multiclassProficiencies=multiclass;
   if(savingThrows!==undefined)record.savingThrows=savingThrows;
  }else Object.assign(record,rows(rules.stages).find(s=>s.stage==='default')?.fields||{});
  index[rules.section].push(record);
 }
 return index;
}
