// Source-qualified benefits → legacy runtime projections during progressive migration.
// Mechanics are never inferred from description or translated feature names.
const catalog=(payload,type)=>{
 if(payload?.schema_version!==2||payload.benefit_type!==type||payload.scope!=='catalog'||!Array.isArray(payload.entries))
  throw Error('Catalogo benefici '+type+' non valido');
 for(const entry of payload.entries){
  if(!entry?.id||!entry?.granted_by?.ref?.category||!entry?.benefit||
     entry.benefit.type!==type)
   throw Error('Voce del catalogo benefici '+type+' non valida');
 }
 return payload.entries;
};
const owner=(entry,type)=>{
 const ref=entry?.granted_by?.ref||{},benefit=entry?.benefit||{};
 if(entry?.granted_by?.kind!=='5etools'||!['class_feature','subclass_feature'].includes(ref.category)||
    !ref.name||!ref.source||!ref.class_name||!ref.class_source||benefit.type!==type)
  throw Error('Origine beneficio di classe non valida: '+String(entry?.id||''));
 return {ref,benefit};
};
export function classActionOverridesFromBenefits(payload){
 return catalog(payload,'action').filter(entry=>entry.projection!=='timing_action'&&
  ['class_feature','subclass_feature'].includes(entry?.granted_by?.ref?.category)).map(entry=>{
  const {ref,benefit}=owner(entry,'action');
  const {id,type,...mechanics}=benefit;
  return {class_name:ref.class_name,feature_name:ref.name,book:ref.class_source,
   ...(entry.min_level===undefined?{}:{min_level:entry.min_level}),...mechanics};
 });
}
export function classRollBonusRulesFromBenefits(payload){
 return catalog(payload,'roll_bonus').filter(entry=>['class_feature','subclass_feature'].includes(entry?.granted_by?.ref?.category)).map(entry=>{
  const {ref,benefit}=owner(entry,'roll_bonus');
  const {type,id,...mechanics}=benefit;
  return {id:id||entry.id,class_name:ref.class_name,class_source:ref.class_source,
   ...(ref.subclass?{subclass_name:ref.subclass}:{}),feature_name:ref.name,...mechanics};
 });
}
async function load(fetcher,typedUrl,project){
 const response=await fetcher(typedUrl);
 if(!response?.ok)throw Error('Catalogo benefici non disponibile: '+typedUrl);
 return project(await response.json());
}
export const loadClassActionBenefits=(fetcher=fetch)=>load(fetcher,
 '/catalog/benefits/action.json',classActionOverridesFromBenefits);
export const loadClassRollBonusBenefits=(fetcher=fetch)=>load(fetcher,
 '/catalog/benefits/roll_bonus.json',classRollBonusRulesFromBenefits);
