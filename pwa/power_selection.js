import {migrateSelectionRecord} from './selection_compatibility.js';
// One selection engine. Source definitions only supply options and stage data.
import {targetableInventoryItems,itemAttunementCount} from './item_controls.js';
import {isContentAvailableForRules} from './source_edition.js';
const rows=v=>Array.isArray(v)?v:[];
const low=v=>String(v??'').trim().toLowerCase();
const identity=v=>typeof v==='string'?v:v?.id;
export const POWER_SELECTION_TRIGGERS={level_up:'Passaggio di livello',short_rest:'Riposo breve',long_rest:'Riposo lungo',daily:'Giornaliero',turn:'Turno'};
export const powerSelectionTriggerLabel=v=>POWER_SELECTION_TRIGGERS[v]||v||'';
export function powerSelectionLimit(spec,level){
 if(spec==null)return null;if(typeof spec==='number')return spec;
 const entries=spec.by_class_level||Object.entries(spec);
 let limit=0;for(const [at,value] of entries)if(level>=Number(at))limit=Number(value)||0;return limit;
}
function definitions(catalog){
 const optional=catalog.optionalFeatureProgressions||{};
 return [...rows(catalog.selections),...rows(optional.progressions).map(rule=>({...rule,
  forget:'unapply',unique_across_selections:true,source:{type:'inline',options:rows(optional.options).filter(option=>rows(option.types).some(type=>rows(rule.feature_types).includes(type)))}}))];
}
function member(record,owner={}){
 return rows(record.classes?.length?record.classes:[{name:record.class,source:record.class_source,level:record.level,subclass:record.subclass}]).find(row=>
 low(row.name)===low(owner.class_name)&&(!owner.class_source||low(row.source||record.class_source)===low(owner.class_source))&&
 (!owner.subclass||low(row.subclass)===low(owner.subclass)));
}
function optionsFor(record,rule){return [...rows(rule.source?.options),...rows(record.power_selection_custom_options?.[rule.id])].filter(row=>!row.hidden&&(!row.source||row._homebrew||isContentAvailableForRules(row,record.rules_version||'2014'))).map(row=>({...row,
 min_level:row.min_level||(rows(row.prerequisite).length?Math.min(...rows(row.prerequisite).map(p=>Number(p.level?.level||p.level)||0)):0),
 details:row.details||(!row._homebrew&&row.source?{category:'optional_features',name:row.name,source:row.source}:undefined)}));}
export function normalizeSelectionRecord(record={},catalog={}){return migrateSelectionRecord(record,definitions(catalog),optionsFor,member);}
export function powerSelectionModels(raw={},calculated={},catalog={}){
 const record=normalizeSelectionRecord(raw,catalog),models=[];
 for(const rule of definitions(catalog)){
  const owner=member(record,rule.owner);if(!owner||!isContentAvailableForRules({source:rule.owner?.class_source},record.rules_version||'2014'))continue;
  const level=Number(owner.level)||0,feature=rows(calculated.features).find(f=>low(f.name)===low(rule.owner?.trait)&&low(f.class_name||f.requirements?.class_name||String(f.origin_key).split('|')[2])===low(rule.owner?.class_name)&&(!rule.owner?.class_source||low(f.class_source||f.requirements?.class_source||String(f.origin_key).split('|')[1])===low(rule.owner.class_source))&&!f.disabled&&!f.inactive&&record.trait_enabled?.[f.key]!==false);
  if(!feature)continue;
  const origin=feature?.origin_id||'';
  if([origin,feature.origin_key,String(feature.origin_key||'').split('|').slice(0,3).join('|')].some(id=>id&&(record.origin_enabled?.[id]===false||rows(record.proficiency_origins).some(row=>row.id===id&&row.disabled))))continue;
  const parent=rule.requires_application,binding=parent?rows(record.power_applications?.[parent.selection]).find(row=>!parent.bound||rows(record.inventory).some(item=>(item.instance_id||item.id)===row.target_item_id)):null;
  if(parent&&!binding)continue;
  const options=optionsFor(record,rule),layers={};
  const required=Object.entries(rule.required||{}).filter(([at])=>Number(at)<=level).flatMap(([,values])=>rows(values).map(key=>{const [name,source]=key.split('|');return options.find(o=>low(o.name)===low(name)&&(!source||low(o.source)===low(source)))?.id;})).filter(Boolean);
  for(const [stage,spec] of Object.entries(rule.layers||{})){
   let selected=stage==='applied'?rows(record.power_applications?.[rule.id]):rows(record.power_selections?.[rule.id]?.[stage]);
   if(stage==='learned')selected=[...required,...selected.filter(row=>!required.includes(identity(row)))];
   if(spec.mode==='automatic')selected=rows(layers[spec.from||'learned']?.selected??record.power_selections?.[rule.id]?.[spec.from||'learned']).map(id=>({id:identity(id)}));
   selected=selected.filter(row=>options.some(o=>o.id===identity(row)&&(stage!=='applied'||o.min_level<=level)));
   if(stage==='applied'&&rule.application?.destination==='item')selected=selected.filter(row=>rows(record.inventory).some(item=>(item.instance_id||item.id)===row.target_item_id&&Number(item.quantity??1)>0));
   let limit=powerSelectionLimit(spec.limit,level);
   if(stage==='applied'&&rule.capacity_bonus_field)limit+=rows(catalog.capacity_grants||calculated.selection_capacity_grants).reduce((n,r)=>n+Number(r[rule.capacity_bonus_field]||0),0);
   if(stage==='applied'&&!rule.application?.target&&!spec.target)selected=selected.map(identity);
   layers[stage]={enabled:true,selected,used:selected.length,limit,trigger:spec.trigger||null,change_label:powerSelectionTriggerLabel(spec.trigger),automatic:spec.mode==='automatic',target:stage==='applied'?rule.application?.target||spec.target:null};
  }
  if(layers.learned?.limit===0&&!layers.learned.selected.length)continue;
  models.push({...rule,benefit_type:rule.benefit_type||'option_selection',source_type:'option_catalog',ui:'generic',options,layers,level,
   origin_id:binding?'item-instance:'+binding.target_item_id:origin,source_origin_id:origin,required});
 }
 // Spell selection extends the same learned/prepared/applied layer contract.
 // A benefit declares both the spell catalogue and the owning class level;
 // this read-only projection deliberately preserves existing spell storage/UI.
 for(const template of rows(catalog.templates))
   if(['casting_classes','spell_selection'].includes(template.source))
   for(const member of rows(calculated.casting_classes)){
     const declared=member.selection_layers||{};
     const layers={};
     if(Object.keys(declared).length){
       for(const [stage,spec] of Object.entries(declared)){
         layers[stage]={enabled:true,selected:[],limit:spec.limit??null,
           trigger:spec.trigger||null,change_label:powerSelectionTriggerLabel(spec.trigger),
           automatic:spec.mode==='automatic'||spec.mode==='class_list',
           storage:spec.storage||null};
       }
     }else for(const [stage,spec] of Object.entries(template.layers||{})){
       if(stage==='learned'&&member.mode==='Conosciuti'||
         stage==='prepared'&&member.mode==='Preparati')
         layers[stage]={enabled:true,selected:[],limit:member.limit,
           trigger:spec.trigger||null,change_label:powerSelectionTriggerLabel(spec.trigger)};
     }
     models.push({id:template.id+':'+member.id,title:member.name+' · Incantesimi',
       benefit_type:'spell_selection',source_type:'spell_catalog',
       source:member.spell_list_source||{type:'spell_catalog',class_name:member.spell_list_class_name||member.name},
       spell_list_class_name:member.spell_list_class_name||member.name,
       level_class_name:member.level_class_name||member.name,
       origin_id:member.granting_trait_id||'',
       ui:'existing',options:[],layers,cantrips:member.cantrips});
   }
 // Dependent choices require an available, applied parent, including its source gates.
 let available=models;
 for(let pass=0;pass<models.length;pass++){
  const next=available.filter(model=>!model.requires_application||available.some(parent=>parent.id===model.requires_application.selection&&rows(parent.layers.applied?.selected).length));
  if(next.length===available.length)break;available=next;
 }
 return available;
}
export function optionalFeatureSelectionModels(record,calculated,catalog){return powerSelectionModels(record,calculated,{optionalFeatureProgressions:catalog});}
function statePatch(record){return {selection_state_version:2,power_selections:record.power_selections||{},power_applications:record.power_applications||{},inventory:record.inventory||[],optional_features_catalog:record.optional_features_catalog||[],fighting_styles:record.fighting_styles||[],...(record.resource_tracker_spent?{resource_tracker_spent:record.resource_tracker_spent}:{}),...(record.trait_state_selection?{trait_state_selection:record.trait_state_selection}:{}),...(record.active_class_features?{active_class_features:record.active_class_features}:{})};}
export function powerSelectionPatch(raw,calculated,catalog,id,stage,optionId,details=[]){
 const record=structuredClone(normalizeSelectionRecord(raw,catalog)),model=powerSelectionModels(record,calculated,catalog).find(m=>m.id===id),option=model?.options.find(o=>o.id===optionId),layer=model?.layers[stage];
 if(!layer||!option||!['learned','prepared'].includes(stage))throw Error('Selezione non disponibile.');
 const old=layer.selected,exists=old.some(row=>identity(row)===optionId),updating=exists&&option.subchoices&&rows(details).length>0;
 if(model.required.includes(optionId))throw Error('Questa opzione è obbligatoria.');
 if(stage==='prepared'&&!exists&&model.layers.learned&&!model.layers.learned.selected.some(row=>identity(row)===optionId))throw Error('Devi prima imparare questa opzione.');
 if(exists&&!updating&&model.forget!=='unapply'&&(rows(record.power_applications?.[id]).some(row=>row.id===optionId)||stage==='learned'&&rows(record.power_selections?.[id]?.prepared).some(row=>identity(row)===optionId)))throw Error('Disapplica prima il potere o rimuovi l’opzione dalla lista preparata.');
 if(!exists&&model.unique_across_selections&&powerSelectionModels(record,calculated,catalog).some(other=>other.id!==id&&other.layers.learned?.selected.some(row=>identity(row)===optionId)))throw Error('Opzione già scelta in un altro privilegio.');
 if(!exists&&option.min_level>model.level)throw Error('Livello insufficiente.');
 // Learned counts are guidance (as for spells); prepared choices retain their capacity.
  if(!exists&&stage!=='learned'&&layer.limit!==null&&old.length>=layer.limit)throw Error('Numero massimo di opzioni raggiunto.');
 let value=optionId;
 if(option.subchoices){const names=rows(details).map(v=>String(v).trim());if(names.length!==option.subchoices.count||new Set(names.map(low)).size!==names.length||names.some(n=>!n||n.length>70||/[<>{}]/.test(n)))throw Error('Specifica tutte le sotto-opzioni richieste, senza duplicati.');value={id:optionId,subchoices:names};}
 record.power_selections={...record.power_selections,[id]:{...record.power_selections?.[id],[stage]:exists&&!updating?old.filter(row=>identity(row)!==optionId):[...(old.filter(row=>identity(row)!==optionId)),value]}};
 if(exists&&!updating)record.power_applications={...record.power_applications,[id]:rows(record.power_applications?.[id]).filter(row=>row.id!==optionId)};
 return statePatch({...record,inventory:projectSelectionBenefits(record,{powerSelections:catalog,optionalFeatureProgressions:catalog.optionalFeatureProgressions},calculated.features||[]).inventory});
}
export function powerSelectionTargets(record,model,option){const target=model?.layers.applied?.target;if(!target)return [];const selector=target.selector==='option.item_selector'?option.item_selector||{}:target;return targetableInventoryItems(record,selector,item=>!item.disabled&&(!target.slot||rows(item.equipped_slots).includes(target.slot))&&(!target.extension_field||!item[target.extension_field]?.creator_id||item[target.extension_field].creator_id===record.id));}
export function powerApplicationPatch(raw,calculated,catalog,id,optionId,apply,{itemIndex=-1,effectChoice={}}={}){
 const record=structuredClone(normalizeSelectionRecord(raw,catalog)),model=powerSelectionModels(record,calculated,catalog).find(m=>m.id===id),option=model?.options.find(o=>o.id===optionId),layer=model?.layers.applied;
 if(!option||!layer)throw Error('Applicazione non disponibile.');
 if(layer.automatic)throw Error('Applicazione automatica dalla conoscenza.');
 const old=rows(record.power_applications?.[id]),exists=old.some(row=>row.id===optionId);
 if(apply&&exists&&!layer.target)throw Error('Potere già applicato.');
 if(apply&&option.min_level>model.level)throw Error('Livello insufficiente.');
 const prerequisite=model.layers.prepared||model.layers.learned;
 if(apply&&prerequisite&&!prerequisite.selected.some(row=>identity(row)===optionId))throw Error('Devi prima imparare questa opzione.');
 if(apply&&!exists&&!model.application?.exclusive&&layer.limit!==null&&layer.selected.length>=layer.limit)throw Error('Numero massimo di applicazioni raggiunto.');
 let target;
 if(apply&&layer.target){
  if(!powerSelectionTargets(record,model,option).some(row=>row.index===itemIndex))throw Error('Scegli un oggetto compatibile.');
  const inventory=structuredClone(record.inventory);target=inventory[itemIndex];
  if(Number(target.quantity??1)>1){
   const count=itemAttunementCount(target),remaining={...structuredClone(target),quantity:Number(target.quantity)-1,instance_id:'instance_'+crypto.randomUUID(),equipped:false,equipped_slots:[],attuned_count:Math.max(0,count-1),attuned:count>1};
   inventory.splice(itemIndex+1,0,remaining);target.quantity=1;target.attuned_count=Math.min(1,count);target.attuned=count>0;
  }
  if(exists&&old.find(row=>row.id===optionId)?.target_item_id===(target.instance_id||target.id))throw Error('Potere già applicato.');
  const previousIdentity=target.instance_id||target.id;
  target.instance_id=target.instance_id||'instance_'+crypto.randomUUID();record.inventory=inventory;
  for(const [key,values] of Object.entries(record.power_applications||{}))record.power_applications[key]=rows(values).map(row=>row.target_item_id===previousIdentity?{...row,target_item_id:target.instance_id}:row);
 }
 if(apply&&option.effect_choice&&!rows(option.effect_choice.options).includes(effectChoice[option.effect_choice.key]))throw Error('Scelta effetto non valida.');
 const next=model.application?.exclusive?[]:old.filter(row=>row.id!==optionId);
 if(apply)next.push({id:optionId,...(target?{target_item_id:target.instance_id}:{}),...(Object.keys(effectChoice).length?{effect_choice}:{})});
 if(model.application_tracker_id){
  const tracker=rows(calculated.trackers).find(row=>row.id===model.application_tracker_id&&!row.disabled);if(!tracker)throw Error('Tracker non disponibile.');
  const spent=Number(record.resource_tracker_spent?.[tracker.id]||0);if(apply&&!exists&&spent>=tracker.max)throw Error('Risorse insufficienti.');
  record.resource_tracker_spent={...record.resource_tracker_spent,[tracker.id]:Math.max(0,spent+(apply&&!exists?1:!apply&&exists?-1:0))};
 }
 record.power_applications={...record.power_applications,[id]:next};
 const projected=projectSelectionBenefits(record,{powerSelections:catalog,optionalFeatureProgressions:catalog.optionalFeatureProgressions},calculated.features||[]);
 return statePatch({...record,inventory:projected.inventory});
}
// Old state buttons resolve to the same declared option and mutation as Powers.
// Undefined means this state belongs to the separate transient-state domain.
export function powerStateActivationPatch(record,calculated,catalog,stateId){
 const models=powerSelectionModels(record,calculated,catalog);
 for(const model of models)for(const option of model.options){
  if(!rows(option.effects).some(effect=>effect.type==='state_selection'&&effect.value===stateId))continue;
  const active=rows(model.layers.applied?.selected).some(row=>identity(row)===option.id);
  return powerApplicationPatch(record,calculated,catalog,model.id,option.id,!active);
 }
 if(definitions(catalog).some(rule=>optionsFor(record,rule).some(option=>rows(option.effects).some(effect=>effect.type==='state_selection'&&effect.value===stateId))))throw Error('Selezione non disponibile.');
 return undefined;
}
export function powerSelectionCustomPatch(record,calculated,catalog,id,stage,optionId,name,description='',settings={}){
 const model=powerSelectionModels(record,calculated,catalog).find(m=>m.id===id);
 if(!(model?.allow_custom||model?.source?.type==='inline')||!/^homebrew:[a-z0-9-]{8,80}$/.test(optionId)||!String(name).trim())throw Error('Opzione homebrew non valida.');
 const custom={...(record.power_selection_custom_options||{}),[id]:[...rows(record.power_selection_custom_options?.[id]),{id:optionId,name:String(name).trim(),description,source:'HOMEBREW',_homebrew:true}]};
 return {...powerSelectionPatch({...record,power_selection_custom_options:custom},calculated,catalog,id,stage,optionId),power_selection_custom_options:custom};
}
// Project effects of every applied option to its declared recipient, never a new trait.
export function projectSelectionBenefits(raw,catalogs,features=[]){
 const catalog={...(catalogs.powerSelections||{}),optionalFeatureProgressions:catalogs.optionalFeatureProgressions||{}};
 const record=normalizeSelectionRecord(raw,catalog),models=powerSelectionModels(record,{features},catalog),inventory=structuredClone(rows(record.inventory)).map(item=>({...item,option_extensions:rows(item.option_extensions).filter(e=>!e.selection_id)}));
 const optional=rows(record.optional_features_catalog).filter(row=>!row.selection_origin_id);const states={...record.trait_state_selection};
 const fields={bonus:'formula_bonuses',proficiency:'proficiency_choices',resources:'resource_trackers',spells:'origin_spell_grants',actions:'action_grants',senses:'sense_grants',defenses:'damage_defense_entries',effect_extensions:'effect_extensions',roll_mode:'roll_mode_grants',base_override:'base_value_overrides'};
 const grants=Object.fromEntries(Object.values(fields).map(field=>[field,rows(record[field]).filter(row=>!row.selection_origin_id)]));
 // Model state choices are derived, not another persisted selection engine.
 for(const rule of definitions(catalog))for(const option of optionsFor(record,rule))for(const e of rows(option.effects))if(e.type==='state_selection')delete states[e.key];
 for(const model of models)for(const application of rows(model.layers.applied?.selected)){
  const option=model.options.find(o=>o.id===identity(application));if(!option)continue;
  const item=application.target_item_id?inventory.find(i=>(i.instance_id||i.id)===application.target_item_id):null;
  if(model.application?.destination==='item'){
   if(!item)continue;
   item.option_extensions=[...rows(item.option_extensions),{selection_id:model.id,id:option.id,name:option.name,description:option.description,details:option.details,origin_id:model.source_origin_id,level:model.level,requires_attunement:option.requires_attunement,effect_choice:application.effect_choice||{},definition:option.item_effects||{id:option.id,name:option.name}}];
  }
  for(const [index,effect] of [...rows(model.application?.effects),...rows(option.effects)].entries()){
   if(fields[effect.type]){const {type,...values}=effect;grants[fields[type]].push({...values,...values.data,id:'selection:'+model.id+':'+option.id+':'+index,selection_origin_id:model.id,origin_id:item?'item-instance:'+(item.instance_id||item.id):model.origin_id,parent_origin:model.source_origin_id,origin_name:option.name,automatic:false,disabled:false});}
   if(effect.type==='catalog_feature')optional.push({name:option.name,source:option.source,origin_id:model.origin_id,selection_origin_id:model.id,entries:[option.description||'']});
   if(effect.type==='state_selection')states[effect.key]=effect.value;
  }
 }
 return {...record,...grants,inventory,optional_features_catalog:optional,trait_state_selection:states,selection_models:models,selection_definition_ids:definitions(catalog).map(rule=>rule.id)};
}
