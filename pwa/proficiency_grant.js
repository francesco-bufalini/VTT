// Declarative proficiency selection grants. No species-specific runtime rules.
import {selectableProficiencyOptions} from './pending_choices.js';
import {powerSelectionTriggerLabel} from './power_selection.js';

const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
export const PROFICIENCY_GRANT_KIND_LABELS={
 skill:'Abilità',expertise:'Maestria',save:'Tiro salvezza',weapon:'Arma',
 armor:'Armatura',tool:'Strumento',language:'Lingua'
};
const disabled=(record,id)=>id&&(record.origin_enabled?.[id]===false||
 rows(record.proficiency_origins).some(row=>row?.id===id&&row.disabled));
const matchesOrigin=(record,feature,ref={})=>{
 if(ref.category==='species_trait'&&
   (norm(record.species)!==norm(ref.race)||norm(record.species_source)!==norm(ref.race_source)||
    !String(feature.origin_key||'').startsWith('species|')))return false;
 if(ref.class_name&&norm(feature.class_name||feature.requirements?.class_name)!==norm(ref.class_name))return false;
 if(ref.class_source&&norm(feature.class_source||feature.requirements?.class_source)!==norm(ref.class_source))return false;
 if(ref.subclass&&norm(feature.subclass||feature.subclass_short_name)!==norm(ref.subclass))return false;
 const owned=ref.name?norm(feature.name)===norm(ref.name):
  Boolean(ref.id&&[feature.id,feature.origin_id,feature.key].some(key=>norm(key)===norm(ref.id)));
 return owned&&!feature.disabled&&!feature.inactive&&
  record.trait_enabled?.[feature.key]!==false&&
  ![feature.origin_id,feature.origin_key,String(feature.origin_key||'').split('|').slice(0,3).join('|')]
   .some(key=>disabled(record,key));
};
export function proficiencyGrantModels(record={},calculated={},catalog={}){
 if(catalog?.schema_version!==2||catalog?.benefit_type!=='proficiency_grant')return [];
 const models=[];
 for(const entry of rows(catalog.entries)){
  if(entry?.enabled===false||entry?.benefit?.type!=='proficiency_grant')continue;
  const rule=entry.benefit.proficiency_grant,ref=entry.granted_by?.ref||{};
  if(!rule?.id||!rows(rule.groups).length)continue;
  if(ref.category==='species_trait'&&record.rules_version==='2024')continue;
  for(const feature of rows(calculated.features).filter(feature=>matchesOrigin(record,feature,ref))){
   const root_id=ref.category==='species_trait'?
    'race|'+norm(ref.race_source)+'|'+norm(ref.race):feature.origin_id;
   const slots=rows(rule.groups).flatMap((group,groupIndex)=>{
    const count=Math.max(0,Math.trunc(Number(group.count)||0));
    return Array.from({length:count},(_,i)=>({
     filter:group.filter||{},group_index:groupIndex,number:i+1,count,
     label:rows(group.filter?.kinds).map(kind=>PROFICIENCY_GRANT_KIND_LABELS[kind]||kind).join(' o ')+
      (count>1?' '+(i+1):'')
    }));
   });
   const selected=rows(record.proficiency_choices).filter(row=>
    row?.proficiency_grant_id===rule.id||row?.rest_training_group===rule.id);
   models.push({id:rule.id,title:entry.benefit.name||feature.name,
    origin_id:feature.origin_id,source_origin_id:feature.origin_id,root_id,
    trigger:rule.trigger,change_label:powerSelectionTriggerLabel(rule.trigger),
    benefit_type:'proficiency_grant',slots,selected,used:selected.length,limit:slots.length});
  }
 }
 return models;
}
export function proficiencyGrantOptions(slot,record={},index={}){
 const filter=slot?.filter||{};
 const include=rows(filter.include).map(norm),exclude=new Set(rows(filter.exclude).map(norm));
 return rows(filter.kinds).flatMap(kind=>selectableProficiencyOptions(kind,record,index)
  .filter(key=>{
   const full=kind+':'+key;
   return (!include.length||include.includes(norm(key))||include.includes(norm(full)))&&
    !exclude.has(norm(key))&&!exclude.has(norm(full));
  }).map(key=>({id:kind+':'+key,kind,key,name:key,
   label:PROFICIENCY_GRANT_KIND_LABELS[kind]||kind})));
}
export function proficiencyGrantPatch(record={},model,selected=[],allowed={}){
 if(!model?.id||!model.origin_id||!model.root_id||!rows(model.slots).length)
  throw Error('Concessione di competenze non disponibile.');
 if(!Array.isArray(selected)||selected.length!==model.slots.length)
  throw Error('Scegli tutte le competenze previste dal privilegio.');
 const picks=selected.map((raw,i)=>{
  const id=norm(raw),option=proficiencyGrantOptions(model.slots[i],record,allowed.index||{})
   .find(row=>row.id===id);
  if(!option||Array.isArray(allowed[option.kind])&&!allowed[option.kind].includes(option.key))
   throw Error('Competenza non valida per questa scelta.');
  return option;
 });
 if(new Set(picks.map(row=>row.id)).size!==picks.length)
  throw Error('Non puoi selezionare due volte la stessa competenza.');
 const unavailable=new Set(rows(allowed.unavailable).map(norm));
 if(picks.some(row=>unavailable.has(norm(row.id))))
  throw Error('Puoi scegliere soltanto competenze che non possiedi già.');
 return {proficiency_choices:[
  ...rows(record.proficiency_choices).filter(row=>
   row?.proficiency_grant_id!==model.id&&row?.rest_training_group!==model.id),
  ...picks.map(({kind,key})=>({kind,key,origin_id:model.root_id,
   granting_feature_origin_id:model.origin_id,origin_name:'Tratto · '+model.title,
   proficiency_grant_id:model.id,rest_training_group:model.id}))
 ]};
}
