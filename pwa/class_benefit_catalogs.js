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
async function load(fetcher,typedUrl,legacyUrl,project,legacy){
 let response;
 try{response=await fetcher(typedUrl)}catch{response=null}
 // A malformed v2 catalog is an error; older hosts that lack the new URL
 // may still serve the legacy catalog without changing saved characters.
 if(response?.ok){
  const payload=await response.json();
  if(payload?.schema_version===2)return project(payload);
  // Older mocks and non-v2 static hosts can respond 200 with the old
  // catalog at an unrecognized URL. Do not swallow malformed v2 data.
 }
 const old=await fetcher(legacyUrl);
 if(!old.ok)throw Error('Catalogo benefici non disponibile: '+typedUrl);
 return legacy(await old.json());
}
export const loadClassActionBenefits=(fetcher=fetch)=>load(fetcher,
 '/catalog/benefits/action.json','/catalog/action_feature_overrides.json',
 classActionOverridesFromBenefits,data=>{
  // Match the old PWA behavior for incomplete fixtures and older hosts:
  // missing optional activation metadata must never hide all class features.
  return data?.version===1&&Array.isArray(data.entries)?data.entries:[];
 });
export const loadClassRollBonusBenefits=(fetcher=fetch)=>load(fetcher,
 '/catalog/benefits/roll_bonus.json','/catalog/roll_bonus_rules.json',
 classRollBonusRulesFromBenefits,data=>{
  return data?.version===1&&Array.isArray(data.features)?data.features:[];
 });
