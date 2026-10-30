import {traitStateActivationPatch} from './trait_state_rules.js';
// Three-layer, origin-bound power choices. Domain-specific inventories and
// spellbooks remain authoritative; adapters project them into one JSON contract.
// A trigger describes when rules permit changing a choice, but never gates UI.
import {infusionLimits,infusionGrantingTrait,learnedInfusions,learnInfusionPatch,forgetInfusionPatch,applyInfusionPatch,clearInfusionPatch,targetableInventoryItems,infusionEligible} from './item_controls.js';
import {optionalFeatureSelectionModels,optionalFeatureSelectionPatch,optionalFeatureApplicationPatch} from './optional_feature_progression.js';

const rows=value=>Array.isArray(value)?value:[];
const low=value=>String(value??'').trim().toLowerCase();
const same=(a,b)=>low(a)===low(b);
const STAGES=['learned','prepared','applied'];
export const POWER_SELECTION_TRIGGERS={
  level_up:'Passaggio di livello',short_rest:'Riposo breve',
  long_rest:'Riposo lungo',daily:'Giornaliero',turn:'Turno'
};
export const powerSelectionTriggerLabel=trigger=>POWER_SELECTION_TRIGGERS[trigger]||String(trigger||'');

function classLevel(record,owner){
 const list=rows(record.classes).length?record.classes:[{
  name:record.class,source:record.class_source,subclass:record.subclass,level:record.level
 }];
 return list.filter(row=>same(row.name,owner.class_name)&&
   (!owner.class_source||same(row.source||record.class_source,owner.class_source))&&
   (!owner.subclass||same(row.subclass||record.subclass,owner.subclass)))
  .reduce((max,row)=>Math.max(max,Math.max(0,Number(row.level)||0)),0);
}
export function powerSelectionLimit(spec,level,context={}){
 if(spec==null)return null;
 if(typeof spec==='number')return Math.max(0,Math.trunc(spec));
 if(typeof spec==='string'){
  const value=context[spec];
  return Number.isFinite(Number(value))?Math.max(0,Math.trunc(Number(value))):null;
 }
 if(spec&&typeof spec==='object'&&Array.isArray(spec.by_class_level)){
  let limit=0;
  for(const [at,count] of spec.by_class_level)
   if(level>=Number(at))limit=Math.max(0,Math.trunc(Number(count)||0));
  return limit;
 }
 return null;
}
function ownerFeature(record,features,owner){
 if(!owner)return null;
 const level=classLevel(record,owner);
 if(!level)return null;
 const feature=rows(features).find(row=>same(row.name,owner.trait)&&
  same(row.requirements?.class_name||row.class_name||String(row.origin_key||'').split('|')[2],owner.class_name)&&
  (!owner.class_source||same(row.requirements?.class_source||row.class_source||
    String(row.origin_key||'').split('|')[1],owner.class_source))&&
  !row.inactive&&!row.disabled&&record.origin_enabled?.[row.origin_id]!==false&&
  record.origin_enabled?.[row.origin_key]!==false);
 return feature?{level,origin_id:feature.origin_id,name:feature.name}:null;
}
function stageView(config,selected=[],limit=null,{available=true}={}){
 return {enabled:true,selected,limit,used:selected.length,trigger:config.trigger??null,
   change_label:powerSelectionTriggerLabel(config.trigger),target:config.target||null,
   refundable:config.refund_on_remove===true,storage:config.storage||'',
   available};
}
function spellcastingModels(record,calculated,template){
 return rows(calculated.casting_classes).map(member=>{
  const layers={},base=template.layers||{},book=member.book===true;
  if(book||member.mode==='Conosciuti')
   layers.learned=stageView(book?{...base.learned,trigger:null}:base.learned,[],book?null:member.limit);
  if(member.mode==='Preparati')
   layers.prepared=stageView(base.prepared,[],member.limit);
  // The spellbook and cantrips have separate budgets. Existing spell pickers
  // calculate their exact counts, and continue to own persistence.
  return {id:template.id+':'+member.id,title:member.name+' · Incantesimi',
   source_type:'casting_classes',option_kind:template.option_kind||'spell',
   origin_id:member.granting_trait_id||'',level:member.level,options:[],
   layers,cantrips:member.cantrips,ui:template.ui||'existing'};
 });
}
export function powerSelectionModels(record={},calculated={},catalog={}){
 const models=[];
 for(const template of rows(catalog.templates))
  if(template.source==='casting_classes')
   models.push(...spellcastingModels(record,calculated,template));
 for(const rule of rows(catalog.selections)){
  const owner=ownerFeature(record,calculated.features,rule.owner);
  if(!owner)continue;
  const source=rule.source||{},stageRules=rule.layers||{},layers={};
  let options=[];
  const values={};
  if(source.type==='inline'){
   options=[...rows(source.options),...rows(record.power_selection_custom_options?.[rule.id])];
   const saved=record.power_selections?.[rule.id]||{};
   for(const stage of STAGES){
    if(!stageRules[stage])continue;
    const source=stage==='applied'?record.power_applications?.[rule.id]:saved[stage];
    const selected=rows(source).filter(row=>options.some(opt=>opt.id===(typeof row==='string'?row:row?.id)));
    layers[stage]=stageView(stageRules[stage],selected,
      powerSelectionLimit(stageRules[stage].limit,owner.level));
   }
  }else if(source.type==='trait_states'){
   options=rows(calculated.trait_state_catalog).filter(row=>row.group===source.group)
    .map(row=>({...row,description:row.summary||''}));
   const selected=record.trait_state_selection?.[source.group]||'';
   if(stageRules.applied)layers.applied=stageView(stageRules.applied,
    selected&&(!Array.isArray(calculated.active_trait_state_ids)||calculated.active_trait_state_ids.includes(selected))&&options.some(opt=>opt.id===selected)?[selected]:[],
    powerSelectionLimit(stageRules.applied.limit,owner.level));
  }else if(source.type==='infusion_catalog'){
   const known=learnedInfusions(record,calculated.infusion_catalog||[]);
   const limits=infusionLimits(record,calculated.infusion_mechanics||{},calculated.features||[]);
   if(!infusionGrantingTrait(record,calculated.features||[]))continue;
   values.infusion_known=limits.known;values.infusion_active=limits.active;
   options=rows(calculated.infusion_catalog).filter(row=>!row.legacy_replicate)
    .map(row=>({...row,min_level:row.min_level||2,details:{category:'optional_features',
      name:row.description_source_name||row.name,source:row.description_source||row.source||rule.owner.class_source}}));
   if(stageRules.learned)layers.learned=stageView(stageRules.learned,
    known.map(row=>row.id),powerSelectionLimit(stageRules.learned.limit,owner.level,values));
   if(stageRules.applied)layers.applied=stageView(stageRules.applied,
    rows(record.inventory).flatMap((item,index)=>item.infusion?.creator_id===record.id&&
       Number(item.quantity??1)>0?[{id:item.infusion.id,inventory_index:index,
       target_item_id:item.instance_id||item.id,target_name:item.name||item.id}]:[]),
    powerSelectionLimit(stageRules.applied.limit,owner.level,values));
  }
  if(!Object.keys(layers).length)continue;
  models.push({id:rule.id,title:rule.title||owner.name,description:rule.description||'',
   origin_id:owner.origin_id,level:owner.level,option_kind:rule.option_kind||'feature',
   on_apply:rule.on_apply||'',source_type:source.type,benefit_type:rule.benefit_type||'option_selection',options,layers,ui:rule.ui||'generic',
   selection_kind:rule.selection_kind||'power'});
 }
 models.push(...optionalFeatureSelectionModels(record,calculated,catalog.optionalFeatureProgressions||{}));
 return models;
}
// Permanent inline selections use the ordinary character choice view. Their
// established power_selections storage remains the only saved selection.
export function permanentPowerChoices(record,calculated,catalog){
 return powerSelectionModels(record,calculated,catalog).flatMap(model=>
  model.selection_kind!=='subtrait'||model.source_type!=='inline'?[]:
  Object.entries(model.layers).flatMap(([stage,layer])=>!layer.enabled||layer.trigger?[]:[{
   id:'power:'+model.id+':'+stage,kind:'permanent_power',origin_id:model.origin_id,
   name:model.title,label:'Scegli sotto-tratto',count:layer.limit??model.options.length,
   selected:layer.selected.map(savedIdentity),options:model.options.map(option=>option.id),
   option_labels:Object.fromEntries(model.options.map(option=>[option.id,option.name])),
   option_rows:Object.fromEntries(model.options.map(option=>[option.id,option])),
   subchoices:Object.fromEntries(layer.selected.filter(value=>value?.subchoices)
     .map(value=>[value.id,value.subchoices])),
   remaining:Math.max(0,(layer.limit??0)-layer.selected.length),
   model_id:model.id,stage
  }])
 );
}
export function savePermanentPowerChoice(record,choice,selected,details={}){
 const next=selected.map(id=>selectedDetails(choice.option_rows[id],details[id]));
 return {power_selections:{...(record.power_selections||{}),[choice.model_id]:{
  ...(record.power_selections?.[choice.model_id]||{}),[choice.stage]:next}}};
}
function savedIdentity(row){return typeof row==='string'?row:String(row?.id||'');}
function selectedDetails(option,subchoices){
 const source=option?.subchoices;
 if(!source)return option.id;
 if(!source.free_text)throw Error('Sotto-opzioni non supportate.');
 const names=rows(subchoices).map(value=>String(value||'').trim()).filter(Boolean);
 if(names.length!==source.count||new Set(names.map(low)).size!==source.count||
   names.some(name=>name.length>70||/[<>{}\x00-\x1f]/.test(name)))
  throw Error('Specifica tutte le sotto-opzioni richieste, senza duplicati.');
 return {id:option.id,subchoices:names};
}
// Pure choice mutation: no rest/level-up check; those triggers are descriptive.
// Only inline rules use this new storage. Other catalogs keep their existing
// spellbook, inventory and state persistence until the adapter is migrated.
export function powerSelectionPatch(record,calculated,catalog,id,stage,optionId,subchoices=[]){
 const optional=optionalFeatureSelectionModels(record,calculated,catalog.optionalFeatureProgressions||{}).find(row=>row.id===id);
 if(optional)return optionalFeatureSelectionPatch(record,calculated,catalog.optionalFeatureProgressions,id,stage,optionId);
 const definition=rows(catalog.selections).find(rule=>rule.id===id);
 if(definition?.source?.type==='infusion_catalog'&&stage==='learned'){
  const model=powerSelectionModels(record,calculated,catalog).find(row=>row.id===id);
  const option=model?.options.find(row=>row.id===optionId);
  if(!option)throw Error('Opzione non disponibile.');
  const known=learnedInfusions(record,calculated.infusion_catalog||[]).find(row=>row.id===optionId);
  return known?forgetInfusionPatch(record,known):learnInfusionPatch(record,option,calculated.infusion_catalog,calculated.infusion_mechanics,-1,calculated.features||[]);
 }
 if(!definition||definition.source?.type!=='inline'||
   !['learned','prepared'].includes(stage)||!definition.layers?.[stage])
  throw Error('Lista dei poteri non disponibile.');
 const model=powerSelectionModels(record,calculated,catalog).find(row=>row.id===id);
 const option=model?.options.find(row=>row.id===optionId),layer=model?.layers[stage];
 if(!option||!layer||Number(option.min_level||0)>model.level)
  throw Error('Opzione del privilegio non disponibile.');
 const old=rows(record.power_selections?.[id]?.[stage]);
 const exists=old.some(row=>savedIdentity(row)===optionId);
 const replacing=exists&&option.subchoices&&rows(subchoices).length>0;
 const removing=exists&&!replacing;
 const saved=record.power_selections?.[id]||{};
 if(stage==='prepared'&&!exists&&definition.layers.learned&&
   !rows(saved.learned).some(row=>savedIdentity(row)===optionId))
  throw Error('Devi prima imparare questa opzione.');
 if(stage==='learned'&&removing&&rows(saved.prepared).some(row=>savedIdentity(row)===optionId))
  throw Error('Rimuovi prima questa opzione dalla lista preparata.');
 if(removing&&rows(record.power_applications?.[id]).some(row=>savedIdentity(row)===optionId))
  throw Error('Disapplica prima questa opzione.');
 const singleBranch=definition.selection_kind==='subtrait'&&layer.limit===1;
 const next=exists&&!replacing?old.filter(row=>savedIdentity(row)!==optionId):
  [...(singleBranch?[]:old.filter(row=>savedIdentity(row)!==optionId)),
    selectedDetails(option,subchoices)];
 if(!exists&&layer.limit!==null&&next.length>layer.limit)
  throw Error('Numero massimo di opzioni raggiunto.');
 return {power_selections:{...(record.power_selections||{}),[id]:{
  ...(record.power_selections?.[id]||{}),[stage]:next}}};
}
// A homebrew option belongs to its creature, not to the official source catalog.
export function powerSelectionCustomPatch(record,calculated,catalog,id,stage,optionId,name,description='',settings={}){
 const model=powerSelectionModels(record,calculated,catalog).find(row=>row.id===id);
 if(!model||model.ui!=='generic'||!model.layers?.[stage])throw Error('Lista dei poteri non disponibile.');
 name=String(name||'').trim();description=String(description||'').trim();
 if(!name||name.length>80||/[<>{}\x00-\x1f]/.test(name)||
  description.length>2000||/[<>\x00-\x08\x0b\x0c\x0e-\x1f]/.test(description))
  throw Error('Nome o descrizione homebrew non validi.');
 if(!/^homebrew:[a-z0-9-]{8,80}$/.test(String(optionId||''))||
  model.options.some(row=>row.id===optionId||String(row.name).toLowerCase()===name.toLowerCase()))
  throw Error('Nome homebrew già presente.');
 const all={...(record.power_selection_custom_options||{})};
 all[id]=[...(all[id]||[]),{id:optionId,name,description,source:'HOMEBREW',_homebrew:true}];
 const draft={...record,power_selection_custom_options:all};
 const updates=stage==='applied'?powerApplicationPatch(draft,calculated,catalog,id,optionId,true,settings):
  powerSelectionPatch(draft,calculated,catalog,id,stage,optionId);
 return {...updates,power_selection_custom_options:all};
}

// Generic 'applied' stage for future source-backed option lists. A counted
// application reserves one tracker charge, and removing it refunds exactly one.
// No spell/metamagic application layer is created.
export function powerApplicationPatch(record,calculated,catalog,id,optionId,apply,{itemIndex=-1,effectChoice={}}={}){
 if(optionalFeatureSelectionModels(record,calculated,catalog.optionalFeatureProgressions||{}).some(row=>row.id===id))
  return optionalFeatureApplicationPatch(record,calculated,catalog.optionalFeatureProgressions,id,optionId,apply);
 const model=powerSelectionModels(record,calculated,catalog).find(row=>row.id===id);
 const rule=rows(catalog.selections).find(row=>row.id===id);
 const layer=model?.layers.applied,option=model?.options.find(row=>row.id===optionId);
 if(rule?.source?.type==='infusion_catalog'){
  if(!option||!layer)throw Error('Opzione non disponibile.');
  if(!apply){
   const item=rows(record.inventory)[itemIndex];
   if(item?.infusion?.id!==optionId||item.infusion.creator_id!==record.id)throw Error('Applicazione non disponibile.');
   return clearInfusionPatch(record,itemIndex);
  }
  if(!powerSelectionTargets(record,model,option).some(row=>row.index===itemIndex))throw Error('Scegli un oggetto compatibile.');
  const known=learnedInfusions(record,calculated.infusion_catalog).find(row=>row.id===optionId);
  return applyInfusionPatch(record,known,calculated.infusion_catalog,calculated.infusion_mechanics,itemIndex,calculated.features||[],effectChoice);
 }
 if(rule?.source?.type==='trait_states'){
  if(!option||!layer)throw Error('Opzione non disponibile.');
  if(apply&&layer.target&&!powerSelectionTargets(record,model,option).some(row=>row.index===itemIndex))
   throw Error('Scegli un oggetto equipaggiato compatibile.');
  const active=layer.selected.some(row=>savedIdentity(row)===optionId);
  if(active===apply)return {};
  return traitStateActivationPatch(record,calculated.features,calculated.trait_state_catalog,optionId,calculated.trackers);
 }
 if(rule?.source?.type!=='inline'||!layer||!option)
  throw Error('Applicazione del potere non disponibile.');
 const apps={...(record.power_applications||{})},saved=rows(apps[id]);
 const target=layer.target;
 const item=Number.isInteger(itemIndex)&&itemIndex>=0?rows(record.inventory)[itemIndex]:null;
 if(apply&&target){
  if(!item||Number(item.quantity??1)<=0)throw Error('Seleziona un oggetto posseduto.');
  if(target.kind==='equipped_item'&&!rows(item.equipped_slots).includes(target.slot))
   throw Error('Equipaggia prima l’oggetto richiesto.');
  if(rows(target.kinds).length){
   const type=String(item.type||'').toUpperCase().split('|')[0];
   const kind=['HA','MA','LA'].includes(type)?'armor':type==='S'?'shield':'other';
   if(!target.kinds.includes(kind))throw Error('Tipo di oggetto incompatibile.');
  }
 }
 const itemId=item?(item.instance_id||item.id):'';
 const key=row=>row.id===optionId&&(!target||row.target_item_id===itemId);
 // When deactivating without choosing a target, remove the first matching
 // application. Each application has its own unique, stable selection identity.
 const index=saved.findIndex(row=>row.id===optionId&&(!apply||key(row)));
 if(apply&&index>=0)throw Error('Potere già applicato.');
 if(!apply&&index<0)throw Error('Potere non applicato.');
 if(apply&&layer.limit!==null&&saved.length>=layer.limit)
  throw Error('Numero massimo di applicazioni raggiunto.');
 const prerequisite=model.layers.prepared||model.layers.learned;
 if(apply&&prerequisite&&!rows(prerequisite.selected).some(row=>savedIdentity(row)===optionId))
  throw Error('Devi prima imparare o preparare questo potere.');
 const trackerId=rule.application_tracker_id||'';
 const spent={...(record.resource_tracker_spent||{})};
 if(trackerId){
  const tracker=rows(calculated.trackers).find(row=>row.id===trackerId&&!row.disabled);
  if(!tracker)throw Error('Tracker del privilegio non disponibile.');
  const current=Number(spent[trackerId]||0);
  if(apply){
   if(current+1>Number(tracker.max||0))throw Error('Risorse insufficienti.');
   spent[trackerId]=current+1;
  }else spent[trackerId]=Math.max(0,current-1);
 }
 const next=apply?[...saved,{id:optionId,...(target?{target_item_id:itemId}:{})}]:
  saved.filter((_,i)=>i!==index);
 return {power_applications:{...apps,[id]:next},
  ...(trackerId?{resource_tracker_spent:spent}:{})};
}

// A target is a property of the benefit's data contract, never of its view.
export function powerSelectionTargets(record,model,option){
 const target=model?.layers?.applied?.target;
 if(!target)return [];
 return targetableInventoryItems(record,target,(item)=>{
  if(item.disabled)return false;
  if(target.kind==='equipped_item'&&!rows(item.equipped_slots).includes(target.slot))return false;
  if(target.selector==='option.item_selector'&&!infusionEligible(option,item))return false;
  const extension=target.extension_field&&item[target.extension_field];
  if(extension?.creator_id&&extension.creator_id!==record.id)return false;
  const bound=target.option_item_id&&option[target.option_item_id];
  return !bound||item.id===bound;
 });
}
