// One selection engine. Source definitions only supply options and stage data.
import {targetableInventoryItems,itemAttunementCount,itemKind,requiresAttunement,activeItemOptionEffects} from './item_controls.js';
import {originSpellId,originChoiceMatches} from './spell_selection.js';
import {isContentAvailableForRules} from './source_edition.js';
import {traitStateSource} from './trait_state_rules.js';
const rows=v=>Array.isArray(v)?v:[];
const low=v=>String(v??'').trim().toLowerCase();
const identity=v=>typeof v==='string'?v:v?.id;
export const POWER_SELECTION_TRIGGERS={level_up:'Passaggio di livello',short_rest:'Riposo breve',long_rest:'Riposo lungo'};
export const powerSelectionTriggerLabel=v=>Array.isArray(v)?v.map(powerSelectionTriggerLabel).join(' / '):POWER_SELECTION_TRIGGERS[v]||v||'';
export function powerSelectionLimit(spec,level){
 if(spec==null)return null;if(typeof spec==='number')return spec;
 const entries=spec.by_class_level||Object.entries(spec);
 let limit=0;for(const [at,value] of entries)if(level>=Number(at))limit=Number(value)||0;return limit;
}
function definitions(catalog){
 const optional=catalog.optionalFeatureProgressions||{};
 const typed=rows(catalog.optionGrants?.entries).filter(entry=>entry?.benefit?.type==='option_grant')
  .map(entry=>({...entry.benefit.option_grant,origin_ref:entry.granted_by?.ref}));
 const legacy=[...rows(catalog.selections),...rows(optional.progressions).map(rule=>({...rule,
  forget:'unapply',unique_across_selections:true,source:{type:'optional_features',feature_types:rule.feature_types}}))];
 const used=new Set(typed.map(rule=>rule.id));
 return [...typed,...legacy.filter(rule=>!used.has(rule.id))];
}
function member(record,owner={}){
 return rows(record.classes?.length?record.classes:[{name:record.class,source:record.class_source,level:record.level,subclass:record.subclass}]).find(row=>
 low(row.name)===low(owner.class_name)&&(!owner.class_source||low(row.source||record.class_source)===low(owner.class_source))&&
 (!owner.subclass||low(row.subclass)===low(owner.subclass)));
}
function optionsFor(record,rule,catalog={}){
 const limit=rule.layers?.learned?.limit??rule.layers?.prepared?.limit;
 const steps=rows(limit?.by_class_level),slots=[];
 if(steps.length)for(const [at,count] of steps)while(slots.length<Number(count))slots.push(Number(at));
 else slots.push(...Array.from({length:Math.max(1,Number(limit)||1)},()=>1));
 const packages=rows(rule.source?.packages).flatMap(pack=>slots.map((at,i)=>({
  id:pack.id+':'+(i+1),name:pack.name+' · scelta '+(i+1),choice_slot:i+1,min_level:at,
  subchoices:{count:pack.count,label:pack.label||pack.name,options:pack.options}
 })));
 const source=rule.source||{};
 // Canonical optional features live in the typed option_list catalog. The
 // old optional-feature data is read only on legacy/offline hosts without it.
 const listEntries=rows(catalog.optionLists?.entries);
 const featureTypes=rows(source.feature_types);
 const legacyOptional=rows(catalog.optionalFeatureProgressions?.options).filter(option=>
   rows(option.types).some(type=>featureTypes.includes(type)));
 const listed=source.type==='list_refs'?rows(source.list_ids).length?
   rows(source.list_ids).flatMap(id=>rows(listEntries.find(entry=>
     entry.benefit?.option_list?.id===id)?.benefit?.option_list?.options)):
   listEntries.flatMap(entry=>rows(entry.benefit?.option_list?.options)).filter(option=>
     rows(option.types).some(type=>featureTypes.includes(type))):[];
 // A partially deployed typed catalog must not hide a legacy option. When
 // both are available retain legacy order and prefer typed records by ID.
 const byId=new Map(listed.map(option=>[option.id,option]));
 const legacyIds=new Set(legacyOptional.map(option=>option.id));
 const options=source.type==='optional_features'?legacyOptional:
   source.type==='list_refs'&&legacyOptional.length?
     [...legacyOptional.map(option=>byId.get(option.id)||option),
       ...listed.filter(option=>!legacyIds.has(option.id))]:listed;
 const spellOptions=source.type==='spell_catalog'&&source.filter?
   rows(catalog.spells).filter(spell=>spell?.id&&spell?.name&&
     originChoiceMatches({filter:source.filter},spell).matches).map(spell=>({
       id:spell.id,spell_id:spell.id,name:spell.name,source:spell.source,
       level:Number(spell.level)||0,ability:rule.ability,
       details:{category:'spells',name:spell.name,source:spell.source}
     })):[];
 const eligible=[...rows(source.options),...packages,...options,...spellOptions,...rows(record.power_selection_custom_options?.[rule.id])]
  .filter(row=>!row.hidden&&(!row.source||row.local===true||row._homebrew||isContentAvailableForRules(row,record.rules_version||'2014')));
 // A 2024 grant can prefer the revised 5eTools definition over an older
 // identically named option. Never silently discard an older saved choice:
 // its exact source-qualified ID stays selectable until the player replaces it.
 const sources=rows(source.preferred_sources).map(low);
 const saved=new Set(Object.entries(record.power_selections||{})
  .filter(([id])=>id===rule.id||id.startsWith(rule.id+':level:'))
  .flatMap(([,stages])=>Object.values(stages||{}).flatMap(rows).map(identity)));
 const winner=new Map();
 for(const option of eligible){
  const key=low(option.name);
  const current=winner.get(key);
  const rank=value=>saved.has(value.id)?-1:
   sources.indexOf(low(value.source))<0?sources.length:sources.indexOf(low(value.source));
  if(!current||rank(option)<rank(current))winner.set(key,option);
 }
 const normalized=sources.length?eligible.filter(row=>winner.get(low(row.name))===row):eligible;
 return normalized.map(row=>({...row,
 // Source-qualified overlay: keep 5eTools texts in their catalog and layer
 // only the missing mechanics in the typed grant definition.
 effects:[...rows(row.effects),...rows(rule.option_effects?.[row.id])],
 min_level:row.min_level||(rule.benefit_type==='option_grant'?0:rows(row.prerequisite).length?Math.min(...rows(row.prerequisite).map(p=>Number(p.level?.level||p.level)||0)):0),
 details:row.details||(!row.local&&!row._homebrew&&row.source?{category:'optional_features',name:row.name,source:row.source}:undefined)}));}
// Saved characters originally stored every copy of a repeated feature under
// one rule ID. Partition only the excess choices when its feature-level
// instances become available; preserve order, subchoices and extra choices.
export function normalizeSelectionRecord(record={},catalog={}){
 let result=record;
 for(const rule of definitions(catalog).filter(row=>row.instances?.mode==='per_feature')){
  const stage=rule.instances.stage;
  const levels=rows(rule.layers?.[stage]?.limit?.by_class_level);
  if(levels.length<2)continue;
  const classLevel=Number(member(result,rule.owner)?.level)||0;
  const available=levels.filter(([at])=>Number(at)<=classLevel);
  if(available.length<2)continue;
  const current=rows(result.power_selections?.[rule.id]?.[stage]);
  if(current.length<=Number(available[0][1])||available.slice(1).some(([at])=>
   Object.hasOwn(result.power_selections||{},rule.id+':level:'+at)))continue;
  const next={...result.power_selections};
  let start=0;
  for(let i=0;i<available.length;i++){
   const [at,count]=available[i],prior=i?Number(available[i-1][1]):0;
   const quota=Math.max(0,Number(count)-prior),last=i===available.length-1;
   const part=last?current.slice(start):current.slice(start,start+quota);
   start+=part.length;
   const id=i?rule.id+':level:'+at:rule.id;
   next[id]={...next[id],[stage]:part};
  }
  result={...result,power_selections:next};
 }
 return result;
}
export function powerSelectionModels(raw={},calculated={},catalog={}){
 const record=normalizeSelectionRecord(raw,catalog),models=[];
 const rules=definitions(catalog);
 // Active options may grant other option_grants, scoped to their concrete
 // source (a generated State or an extended item). Unapplied options do not.
 const queue=rules.filter(rule=>!rule.nested).map(rule=>({rule,depth:0}));
 const seenNested=new Set();
 for(let cursor=0;cursor<queue.length;cursor++){
  if(queue.length>512)throw Error('Troppe concessioni di opzioni annidate.');
  const {rule,nestedFeature,depth}=queue[cursor];
  if(rule.option_kind==='spell'&&rule.source?.type==='spell_catalog'&&!nestedFeature)continue;
  // Class progression continues through the existing casting engine; list
  // and fixed spell grants use the same selection phases as capabilities.
  // Source-owned grants can originate from any trait, not only a character class.
  const classOwner=Boolean(rule.owner?.class_name);
  const owner=classOwner?member(record,rule.owner):{level:record.level||1};
  if(!owner||!isContentAvailableForRules({source:rule.owner?.class_source||rule.origin_ref?.source},record.rules_version||'2014'))continue;
  const traitName=rule.owner?.trait||rule.origin_ref?.name;
  const level=Number(owner.level)||0;
  const candidates=(nestedFeature?[nestedFeature]:rows(calculated.features)).filter(f=>
   low(f.name)===low(traitName)&&
   (!classOwner||low(f.class_name||f.requirements?.class_name||String(f.origin_key).split('|')[2])===low(rule.owner.class_name))&&
   (!rule.owner?.class_source||low(f.class_source||f.requirements?.class_source||String(f.origin_key).split('|')[1])===low(rule.owner.class_source))&&
   !f.disabled&&!f.inactive&&record.trait_enabled?.[f.key]!==false)
   .sort((a,b)=>(Number(a.level)||0)-(Number(b.level)||0));
  const instances=rule.instances?.mode==='per_feature'?candidates:candidates.slice(0,1);
  for(const [index,feature] of instances.entries()){
  const firstLevel=Number(rows(rule.layers?.[rule.instances?.stage]?.limit?.by_class_level)[0]?.[0])||0;
  const instanceId=nestedFeature?.nested_instance_id||(
   rule.instances?.mode==='per_feature'&&
   Number(feature.level)!==firstLevel?rule.id+':level:'+(Number(feature.level)||0):rule.id);
  const origin=feature?.origin_id||'';
  if([origin,feature.origin_key,String(feature.origin_key||'').split('|').slice(0,3).join('|')].some(id=>id&&(record.origin_enabled?.[id]===false||rows(record.proficiency_origins).some(row=>row.id===id&&row.disabled))))continue;
  const parent=rule.requires_application,binding=nestedFeature?.nested_target_item_id?
   {target_item_id:nestedFeature.nested_target_item_id}:parent?
   rows(record.power_applications?.[parent.selection]).find(row=>!parent.bound||rows(record.inventory).some(item=>(item.instance_id||item.id)===row.target_item_id)):null;
  if(parent&&!binding)continue;
  const options=optionsFor(record,rule,catalog).map(option=>{
   if(rule.option_kind!=='trait_state'&&rule.option_origin_kind!=='trait_state')return option;
   const original=traitStateSource(option,feature,calculated.features);
   return {...option,name:original.name,description:original.description};
  }),layers={};
  const required=Object.entries(rule.required||{}).filter(([at])=>Number(at)<=level).flatMap(([,values])=>rows(values).map(key=>{const [name,source]=key.split('|');return options.find(o=>low(o.name)===low(name)&&(!source||low(o.source)===low(source)))?.id;})).filter(Boolean);
  for(const [stage,spec] of Object.entries(rule.layers||{})){
   let selected=stage==='applied'?rows(record.power_applications?.[instanceId]):rows(record.power_selections?.[instanceId]?.[stage]);
   if(stage==='learned')selected=[...required,...selected.filter(row=>!required.includes(identity(row)))];
   if(spec.mode==='automatic')selected=rows(layers[spec.from||'learned']?.selected??record.power_selections?.[rule.id]?.[spec.from||'learned']).map(id=>({id:identity(id)}));
   selected=selected.filter(row=>options.some(o=>o.id===identity(row)&&(stage!=='applied'||o.min_level<=level)));
   if(stage==='applied'&&rule.application?.destination==='item')selected=selected.filter(row=>rows(record.inventory).some(item=>(item.instance_id||item.id)===row.target_item_id&&Number(item.quantity??1)>0));
   let limit=powerSelectionLimit(spec.limit,level);
   if(rule.instances?.mode==='per_feature'&&stage===rule.instances.stage&&spec.limit?.by_class_level){
    const current=powerSelectionLimit(spec.limit,Number(feature.level)||0);
    const thresholds=rows(spec.limit.by_class_level);
    const earlier=thresholds.filter(([at])=>Number(at)<Number(feature.level))
     .reduce((previous,[,value])=>Math.max(previous,Number(value)||0),0);
    limit=Math.max(0,current-earlier);
   }
   if(stage==='applied'&&rule.capacity_bonus_field)limit+=rows(catalog.capacity_grants||calculated.selection_capacity_grants).reduce((n,r)=>n+Number(r[rule.capacity_bonus_field]||0),0);
   if(stage==='applied'&&!rule.application?.target&&!spec.target)selected=selected.map(identity);
   layers[stage]={enabled:true,selected,used:selected.length,limit,trigger:spec.trigger||null,change_label:powerSelectionTriggerLabel(spec.trigger),automatic:spec.mode==='automatic',target:stage==='applied'?rule.application?.target||spec.target:null};
  }
  if(layers.learned?.limit===0&&!layers.learned.selected.length)continue;
  // A rule with no stages, or with explicit fixed options, needs no selection UI.
  const fixed=rows(rule.fixed).length?rows(rule.fixed).map(identity):
    !Object.keys(layers).length?options.map(option=>option.id):[];
  const model={...rule,id:instanceId,title:(rule.title||feature.name)+
   (rule.instances?.mode==='per_feature'?' · livello '+(Number(feature.level)||1):''),
   benefit_type:rule.benefit_type||'option_selection',
   source_type:'option_catalog',ui:'generic',options,layers,level,fixed,
   origin_id:binding?'item-instance:'+binding.target_item_id:origin,source_origin_id:origin,required};
  models.push(model);
  for(const applied of [...rows(model.layers.applied?.selected),...rows(model.fixed)]){
   const selectedOption=model.options.find(option=>option.id===identity(applied));
   if(!selectedOption)continue;
   for(const effect of [...rows(selectedOption.effects),...rows(selectedOption.item_effects?.effects)]
     .filter(effect=>effect.type==='option_grant')){
    const child=rules.find(candidate=>candidate.id===effect.grant_id&&candidate.nested);
    if(!child)throw Error('Concessione annidata non definita: '+effect.grant_id);
    if(depth>=8)throw Error('Ciclo o profondità eccessiva nelle concessioni di opzioni.');
    const targetId=applied?.target_item_id||'';
    if(model.application?.destination==='item'){
     const item=rows(record.inventory).find(row=>(row.instance_id||row.id)===targetId);
     if(!item||Number(item.quantity??1)<=0||item.disabled||item.active===false||
       ['weapon','shield','armor'].includes(itemKind(item))&&!rows(item.equipped_slots).length||
       requiresAttunement(item)&&!itemAttunementCount(item))continue;
    }
    const childOrigin=targetId?'item-instance:'+targetId:'selection:'+model.id+':'+selectedOption.id;
    const childInstance=child.id+':from:'+childOrigin;
    if(seenNested.has(childInstance))continue;
    seenNested.add(childInstance);
    queue.push({rule:child,depth:depth+1,nestedFeature:{
     name:child.owner?.trait||child.origin_ref?.name||child.id,
     origin_id:childOrigin,origin_key:feature.origin_key,
     class_name:child.owner?.class_name||feature.class_name,
     class_source:child.owner?.class_source||feature.class_source,
     level:feature.level,nested_instance_id:childInstance,nested_target_item_id:targetId
    }});
   }
  }
  }
 }
 // Spell selection extends the same learned/prepared/applied layer contract.
 // A benefit declares both the spell catalogue and the owning class level;
 // this read-only projection deliberately preserves existing spell storage/UI.
 for(const template of rows(catalog.templates).length?rows(catalog.templates):
   [{id:'class_spellcasting',source:'spell_selection'}])
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
       benefit_type:rows(catalog.optionGrants?.entries).length?'option_grant':'spell_selection',
       option_kind:'spell',source_type:'spell_catalog',
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
function statePatch(record){return {power_selections:record.power_selections||{},power_applications:record.power_applications||{},inventory:record.inventory||[],optional_features_catalog:record.optional_features_catalog||[],fighting_styles:record.fighting_styles||[],...(record.resource_tracker_spent?{resource_tracker_spent:record.resource_tracker_spent}:{}),...(record.trait_state_selection?{trait_state_selection:record.trait_state_selection}:{}),...(record.active_class_features?{active_class_features:record.active_class_features}:{})};}
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
  if(!exists&&stage!=='learned'&&layer.limit!==null&&old.length>=layer.limit&&!old.some(row=>option.choice_slot&&model.options.find(o=>o.id===identity(row))?.choice_slot===option.choice_slot))throw Error('Numero massimo di opzioni raggiunto.');
 let value=optionId;
 if(option.subchoices){const names=rows(details).map(v=>String(v).trim());if(names.length!==option.subchoices.count||new Set(names.map(low)).size!==names.length||names.some(n=>!n||n.length>70||/[<>{}]/.test(n))||rows(option.subchoices.options).length&&names.some(n=>!option.subchoices.options.some(o=>o.id===n)))throw Error('Specifica tutte le sotto-opzioni richieste, senza duplicati.');value={id:optionId,subchoices:names};}
 record.power_selections={...record.power_selections,[id]:{...record.power_selections?.[id],[stage]:exists&&!updating?old.filter(row=>identity(row)!==optionId):[...old.filter(row=>identity(row)!==optionId&&(!option.choice_slot||model.options.find(o=>o.id===identity(row))?.choice_slot!==option.choice_slot)),value]}};
 if(exists&&!updating)record.power_applications={...record.power_applications,[id]:rows(record.power_applications?.[id]).filter(row=>row.id!==optionId)};
 return statePatch({...record,inventory:projectSelectionBenefits(record,{powerSelections:catalog,optionalFeatureProgressions:catalog.optionalFeatureProgressions},calculated.features||[]).inventory});
}
export function powerSelectionTargets(record,model,option){const target=model?.layers.applied?.target;if(!target)return [];const selector=target.selector==='option.item_selector'?option.item_selector||{}:target;return targetableInventoryItems(record,selector,item=>!item.disabled&&(!target.slot||rows(item.equipped_slots).includes(target.slot)));}
export function powerApplicationPatch(raw,calculated,catalog,id,optionId,apply,{itemIndex=-1,effectChoice={}}={}){
 const record=structuredClone(normalizeSelectionRecord(raw,catalog)),model=powerSelectionModels(record,calculated,catalog).find(m=>m.id===id),option=model?.options.find(o=>o.id===optionId),layer=model?.layers.applied;
 if(!option||!layer)throw Error('Applicazione non disponibile.');
 if(layer.automatic)throw Error('Applicazione automatica dalla conoscenza.');
 const old=rows(record.power_applications?.[id]),exists=old.some(row=>row.id===optionId);
 if(apply&&exists&&!layer.target)throw Error('Potere già applicato.');
 if(apply&&option.min_level>model.level)throw Error('Livello insufficiente.');
 const prerequisite=model.layers.prepared||model.layers.learned;
 if(apply&&prerequisite&&!prerequisite.selected.some(row=>identity(row)===optionId))
  throw Error(model.layers.prepared?'Devi prima preparare questa opzione.':'Devi prima imparare questa opzione.');
 if(apply&&!exists&&!model.application?.exclusive&&layer.limit!==null&&layer.selected.length>=layer.limit)throw Error('Numero massimo di applicazioni raggiunto.');
 let target;
 if(apply&&layer.target){
  if(!powerSelectionTargets(record,model,option).some(row=>row.index===itemIndex))throw Error('Scegli un oggetto compatibile.');
  const inventory=structuredClone(record.inventory);target=inventory[itemIndex];
  if(Number(target.quantity??1)>1){
   const count=itemAttunementCount(target),remaining={...structuredClone(target),quantity:Number(target.quantity)-1,instance_id:'instance_'+crypto.randomUUID(),equipped:false,equipped_slots:[],attuned_count:Math.max(0,count-1),attuned:count>1};
   inventory.splice(itemIndex+1,0,remaining);target.quantity=1;target.attuned_count=Math.min(1,count);target.attuned=count>0;
  }
  if(old.some(row=>row.id===optionId&&row.target_item_id===(target.instance_id||target.id)))throw Error('Potere già applicato.');
  const previousIdentity=target.instance_id||target.id;
  target.instance_id=target.instance_id||'instance_'+crypto.randomUUID();record.inventory=inventory;
  for(const [key,values] of Object.entries(record.power_applications||{}))record.power_applications[key]=rows(values).map(row=>row.target_item_id===previousIdentity?{...row,target_item_id:target.instance_id}:row);
 }
 if(apply&&option.effect_choice&&!rows(option.effect_choice.options).includes(effectChoice[option.effect_choice.key]))throw Error('Scelta effetto non valida.');
 // Applying the same capability to two objects creates two independent
 // extensions. Removing one must leave the other intact.
 const next=model.application?.exclusive?[]:layer.target?[...old]:old.filter(row=>row.id!==optionId);
 if(!apply&&layer.target){
  const targetId=record.inventory?.[itemIndex]?.instance_id||record.inventory?.[itemIndex]?.id;
  const index=next.findIndex(row=>row.id===optionId&&(!targetId||row.target_item_id===targetId));
  if(index<0)throw Error('Applicazione sull’oggetto non trovata.');
  next.splice(index,1);
 }
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
 if(definitions(catalog).some(rule=>optionsFor(record,rule,catalog).some(option=>rows(option.effects).some(effect=>effect.type==='state_selection'&&effect.value===stateId))))throw Error('Selezione non disponibile.');
 return undefined;
}
export function powerSelectionCustomPatch(record,calculated,catalog,id,stage,optionId,name,description='',settings={}){
 const model=powerSelectionModels(record,calculated,catalog).find(m=>m.id===id);
 if(!(model?.allow_custom||model?.source?.type==='inline')||!/^homebrew:[a-z0-9-]{8,80}$/.test(optionId)||!String(name).trim())throw Error('Opzione homebrew non valida.');
 const custom={...(record.power_selection_custom_options||{}),[id]:[...rows(record.power_selection_custom_options?.[id]),{id:optionId,name:String(name).trim(),description,source:'HOMEBREW',_homebrew:true}]};
 return {...powerSelectionPatch({...record,power_selection_custom_options:custom},calculated,catalog,id,stage,optionId),power_selection_custom_options:custom};
}
// Existing primitive benefit types are shared by powers and owned items.
const EFFECT_FIELDS={bonus:'formula_bonuses',dice:'dice_bonuses',attack:'attack_grants',
 scaling_die:'scaling_dice',proficiency:'proficiency_choices',
 resources:'resource_trackers',spells:'origin_spell_grants',
 actions:'action_grants',senses:'sense_grants',
 defenses:'damage_defense_entries',effect_extensions:'effect_extensions',
 roll_mode:'roll_mode_grants',base_override:'base_value_overrides'};
function appendTypedBenefit(grants,effect,origin){
 const field=EFFECT_FIELDS[effect?.type];if(!field)return false;
 const {type,...values}=effect;
 grants[field].push({...values,...values.data,...origin,
  ...(['attack','resources'].includes(effect.type)&&values.id?{id:values.id}:{})});return true;
}
// Apply only declared primitive benefits from active item extensions.
// Old saved copies can read upgraded definitions from the offline catalog.
export function projectItemOptionBenefits(record={},catalogs={}){
 const catalog=new Map(rows(catalogs.genericItemVariants?.variants).map(row=>[row.id,row]));
 const grants=Object.fromEntries(Object.values(EFFECT_FIELDS).map(field=>[field,[...rows(record[field])]]));
 for(const active of activeItemOptionEffects(record,catalogs.abilityGrants?.artificer_infusions||[],catalogs.features||[])){
  const declaration=catalog.get(active.option_id);
  for(const [ordinal,effect] of rows(declaration?.effects||active.definition.effects).entries()){
   const origin={id:'item-benefit:'+active.id+':'+ordinal,origin_id:active.id,
    parent_origin:'item:'+active.item.id,origin_name:'Oggetto · '+active.name,
    automatic:true,disabled:false};
   if(effect.type==='spells'){
    const token=String(effect.spell_token||'');
    if(!token||!active.definition.charge_tracker&&!declaration?.charge_tracker)continue;
    const spell_id=originSpellId(token,String(record.rules_version||'2014'),catalogs.spells||[]);
    if(!spell_id)continue;
    appendTypedBenefit(grants,{...effect,spell_id,mode:'granted',
     tracker_id:active.tracker_id,tracker_cost:Number(effect.tracker_cost)||1,
     payment_mode:'tracker',casting_ability_not_required:true},origin);
   }else appendTypedBenefit(grants,effect,origin);
  }
 }
 return {...record,...grants};
}
// Project effects of every applied option to its declared recipient, never a new trait.
export function projectSelectionBenefits(raw,catalogs,features=[]){
 const catalog={...(catalogs.powerSelections||{}),optionGrants:catalogs.optionGrants||catalogs.powerSelections?.optionGrants||{},
  optionLists:catalogs.optionLists||catalogs.powerSelections?.optionLists||{},
  spells:catalogs.spells||catalogs.powerSelections?.spells||[],
  optionalFeatureProgressions:catalogs.optionalFeatureProgressions||catalogs.powerSelections?.optionalFeatureProgressions||{}};
 const record=normalizeSelectionRecord(raw,catalog),models=powerSelectionModels(record,{features},catalog),inventory=structuredClone(rows(record.inventory)).map(item=>({...item,option_extensions:rows(item.option_extensions).filter(e=>!e.selection_id)}));
 const optional=rows(record.optional_features_catalog).filter(row=>!row.selection_origin_id);const states={...record.trait_state_selection};
 const grants=Object.fromEntries(Object.values(EFFECT_FIELDS).map(field=>[field,rows(record[field]).filter(row=>!row.selection_origin_id)]));
 const selectionTraits=[];
 // Spell options do not have an application stage. The last declared
 // selection phase determines which spells are castable through this grant.
 // Each grant keeps an independent origin even for the same canonical spell.
 for(const model of models.filter(row=>row.option_kind==='spell')){
  // The final declared stage is the castable set. All three stages are
  // optional; a learned-only grant and a fixed list are immediately usable.
  const phase=model.layers.applied||model.layers.prepared||model.layers.learned;
  const picked=rows(phase?.selected||model.fixed);
  const visible=new Set(picked.map(identity));
  if(model.layers.learned&&(model.layers.prepared||model.layers.applied)){
   for(const id of rows(model.layers.learned.selected)){
    const option=model.options.find(row=>row.id===identity(id));
    if(Number(option?.level)===0)visible.add(identity(id));
   }
  }
  for(const option of model.options.filter(row=>visible.has(row.id))){
   const spellId=String(option.spell_id||option.id||'');
   if(!spellId)continue;
   const payment={...(model.payment||{}),...(option.payment||{})};
   const tracker=payment.tracker;
   const slot=payment.slot;
   const trackerId=String(tracker?.id||payment.tracker_id||'');
   const usesTracker=Boolean(trackerId);
   const allowsSlot=slot!==false&&(slot===true||typeof slot==='object'||!usesTracker);
   const origin_id='option_grant:'+model.id+':'+model.source_origin_id;
   const origin={origin_id,parent_origin:model.source_origin_id,
    origin_name:model.title||option.name||model.id};
   const declaration={type:'spells',id:'option_grant:'+model.id+':'+spellId,
    spell_id:spellId,cantrip:Number(option.level)===0,owner_origin_id:model.source_origin_id,
    mode:'granted',payment_mode:usesTracker?'tracker':allowsSlot?'slot':'free',
    tracker_id:trackerId,tracker_cost:Number(tracker?.cost||payment.tracker_cost)||1,
    slot_alternative:usesTracker&&allowsSlot,
    tracker_cast_level:Number(tracker?.cast_level??payment.tracker_cast_level)||undefined,
    slot_min_level:Number(slot?.min_level??payment.slot_min_level)||undefined,
    spellcasting_ability:option.ability||model.ability||'',
    ...(option.ability||model.ability?{}:{casting_ability_not_required:true}),
    source_option_id:option.id,option_grant_id:model.id,
    automatic:true};
   appendTypedBenefit(grants,declaration,origin);
  }
 }
 // Model state choices are derived, not another persisted selection engine.
 for(const rule of definitions(catalog))for(const option of optionsFor(record,rule,catalog))for(const e of rows(option.effects))if(e.type==='state_selection')delete states[e.key];
 for(const model of models)for(const application of [
  ...new Map([...rows(model.layers.applied?.selected),...rows(model.fixed)].map(row=>[identity(row)+'|'+(row?.target_item_id||''),row])).values()
 ]){
  const option=model.options.find(o=>o.id===identity(application));if(!option)continue;
  const item=application.target_item_id?inventory.find(i=>(i.instance_id||i.id)===application.target_item_id):null;
  if(model.application?.destination==='item'){
   if(!item)continue;
   const nativeDefinition=rows(catalogs.abilityGrants?.artificer_infusions).find(row=>row.id===option.item_effects?.id);
   item.option_extensions=[...rows(item.option_extensions),{selection_id:model.id,id:option.id,name:option.name,description:option.description,details:option.details,origin_id:model.source_origin_id,level:model.level,requires_attunement:option.requires_attunement,effect_choice:application.effect_choice||{},definition:nativeDefinition?{...option.item_effects,...nativeDefinition}:option.item_effects||{id:option.id,name:option.name}}];
  }
  if(!item&&model.option_kind==='capability')selectionTraits.push({
   id:'selection:'+model.id+':'+option.id,name:option.name||option.id,
   description:option.description||'',details:option.details||null,
   source:option.source||'',selection_id:model.id,option_id:option.id,
   origin_id:'selection:'+model.id+':'+option.id,parent_origin:model.source_origin_id,
   benefits:rows(option.effects)
  });
  for(const [index,effect] of [...rows(model.application?.effects),...rows(option.effects)].entries()){
   const capabilityOrigin='selection:'+model.id+':'+option.id;
   const derived=!item&&model.option_kind==='capability'&&model.benefit_type==='option_grant';
   appendTypedBenefit(grants,effect,{
    id:capabilityOrigin+':'+index,selection_origin_id:model.id,
    // The engine still needs the real source origin for conditional bonuses.
    // UI attribution is independent: the generated State owns the benefits.
    origin_id:item?'item-instance:'+(item.instance_id||item.id):derived?capabilityOrigin:model.origin_id,
    ...(derived?{selection_trait_id:capabilityOrigin}:{}),
    parent_origin:model.source_origin_id,origin_name:option.name,automatic:false,disabled:false});
   if(effect.type==='catalog_feature')optional.push({name:option.name,source:option.source,origin_id:model.origin_id,selection_origin_id:model.id,entries:[option.description||'']});
   if(effect.type==='state_selection')states[effect.key]=effect.value;
  }
 }
 return {...record,...grants,inventory,optional_features_catalog:optional,trait_state_selection:states,
  selection_traits:selectionTraits,selection_models:models,selection_definition_ids:definitions(catalog).map(rule=>rule.id)};
}
