// Class and subclass benefits are authored per mechanical type.
// Only projections for compatibility with existing runtime consumers live here.
// Every projection is keyed by canonical 5eTools trait identity (never prose).
const rows=value=>Array.isArray(value)?value:[];
const classCategories=new Set(['class_feature','subclass_feature']);
function grants(catalog,type){
 if(catalog?.schema_version!==2||catalog.scope!=='catalog'||catalog.benefit_type!==type||
    !Array.isArray(catalog.entries))throw Error('Catalogo benefici '+type+' non valido');
 return catalog.entries.filter(entry=>classCategories.has(entry?.granted_by?.ref?.category)).map(entry=>{
  const ref=entry.granted_by.ref,benefit=entry.benefit;
  if(entry.granted_by.kind!=='5etools'||!ref.name||!ref.source||!ref.class_name||
     !ref.class_source||!entry.id||benefit?.type!==type)
   throw Error('Origine o tipo beneficio non validi: '+String(entry?.id||''));
  return {entry,ref,benefit};
 });
}
export function projectFeatureTimingRules(catalogs={}){
 const contextual_actions=grants(catalogs.activation,'activation').map(({ref,benefit})=>{
  const {type,id,contextual_resource,...fields}=benefit;
  return {id,class_name:ref.class_name,class_source:ref.class_source,
   feature:ref.name,subclass:ref.subclass||'',...fields,
   ...(contextual_resource?{resource:contextual_resource}:{})};
 });
 const actions=grants(catalogs.action,'action')
  .filter(({entry})=>entry.projection==='timing_action')
  .map(({entry,ref,benefit})=>{
   const {type,...fields}=benefit;
   return {class_name:ref.class_name,class_source:ref.class_source,
    min_level:entry.min_level,...(ref.subclass?{subclass:ref.subclass}:{}),
    feature:ref.name,...fields};
  });
 const recoveries=grants(catalogs.resource_recovery,'resource_recovery').map(({entry,ref,benefit})=>{
  const {id,recovery,resource_name,origin_feature}=benefit;
  return {id,kind:'recovery',class_name:ref.class_name,class_source:ref.class_source,
   min_level:entry.min_level,resource_name,
   ...(origin_feature?{feature:origin_feature}:{}),...recovery};
 });
 const attack_count_grants=grants(catalogs.attack_count,'attack_count').map(({entry,ref,benefit})=>({
  class_name:ref.class_name,class_source:ref.class_source,feature:ref.name,
  min_level:entry.min_level,attacks_per_action:benefit.attack_count,
  ...(ref.subclass?{subclass:ref.subclass}:{})
 }));
 const attack_actions=grants(catalogs.action_sequence,'action_sequence').map(({entry,ref,benefit})=>{
  const {type,id,sequence,...fields}=benefit;
  return {id,class_name:ref.class_name,class_source:ref.class_source,feature:ref.name,
   min_level:entry.min_level,steps:sequence.steps,...fields,
   ...(ref.subclass?{subclass:ref.subclass}:{})};
 });
 return {version:1,contextual_actions,actions,recoveries,attack_count_grants,attack_actions};
}
export function projectClassResourceOverrides(catalog){
 const groups=new Map();
 for(const {entry,ref,benefit} of grants(catalog,'resource').filter(row=>row.benefit.kind!=='spell_slots')){
  const groupKey=ref.class_source+'|'+ref.class_name;
  if(!groups.has(groupKey))groups.set(groupKey,{
   class:ref.class_name,source:ref.class_source,resources:[]
  });
  const {type,id,resource,resource_source,...fields}=benefit;
  groups.get(groupKey).resources.push({
   name:resource,
   ...(resource_source?{source:resource_source}:{}),
   ...(ref.subclass?{subclass:ref.subclass}:{}),
   ...fields,
   ...(entry.notes?{derived_from:entry.notes}:{})
  });
 }
 return [...groups.values()];
}
class MissingTypedCatalog extends Error {}
async function readTyped(fetcher,type){
 let res;
 try{res=await fetcher('/catalog/benefits/'+type+'.json')}catch{throw new MissingTypedCatalog(type)}
 if(!res?.ok)throw new MissingTypedCatalog(type);
 const data=await res.json();
 if(data?.schema_version!==2)throw new MissingTypedCatalog(type);
 return data;
}
async function legacyTiming(fetcher){
 const res=await fetcher('/catalog/feature_timing_recovery_rules.json');
 if(!res?.ok)throw Error('Regole privilegi non disponibili');
 const data=await res.json();
 return data?.version===1&&Array.isArray(data.actions)&&Array.isArray(data.recoveries)?data:null;
}
export async function loadClassFeatureTimingBenefits(fetcher=fetch){
 try{
  const types=['action','activation','resource_recovery','attack_count','action_sequence'];
  const values=await Promise.all(types.map(type=>readTyped(fetcher,type)));
  return projectFeatureTimingRules(Object.fromEntries(types.map((type,i)=>[type,values[i]])));
 }catch(error){
  if(!(error instanceof MissingTypedCatalog))throw error;
  return legacyTiming(fetcher);
 }
}
export async function loadClassResourceBenefits(fetcher=fetch){
 try{
  return projectClassResourceOverrides(await readTyped(fetcher,'resource'));
 }catch(error){
  if(!(error instanceof MissingTypedCatalog))throw error;
  // Legacy builds can rely on the class-mechanics payload's embedded rules.
  try{
   const res=await fetcher('/catalog/class_resource_overrides.json');
   if(!res?.ok)return null;
   const old=await res.json();
   return Array.isArray(old?.classes)?old.classes:null;
  }catch{return null}
 }
}
