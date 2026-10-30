// Import boundary only: no ordinary selection or application logic.
const rows=v=>Array.isArray(v)?v:[];
const low=v=>String(v??'').trim().toLowerCase();
const identity=v=>typeof v==='string'?v:v?.id;
// Old fields are consumed at one boundary. Ordinary writes use only generic state.
export function migrateSelectionRecord(record,all,optionsFor,member){
 if(record.selection_state_version===2)return record;
 const result=structuredClone(record),selections={...(result.power_selections||{})},apps={...(result.power_applications||{})};
 const claimed=new Set();
 for(const rule of all){
  if(!member(result,rule.owner))continue;
  const options=optionsFor(result,rule),alias=value=>options.find(o=>o.id===identity(value)||rows(o.legacy_ids).includes(identity(value)))?.id||identity(value);
  const saved=selections[rule.id]||rows(rule.legacy_ids).map(id=>selections[id]).find(Boolean)||{};
  const learned=rows(saved.learned).map(alias),active=rows(apps[rule.id]).map(row=>typeof row==='string'?{id:alias(row)}:{id:alias(row),...(row.target_item_id?{target_item_id:row.target_item_id}:{}),...(row.effect_choice?{effect_choice:row.effect_choice}:{})});
  for(const old of [...rows(result.optional_features_catalog),...rows(result.fighting_styles).map(row=>typeof row==='string'?{name:row}:row)]){
   if(old.optional_progression_id&&old.optional_progression_id!==rule.id)continue;
   const option=options.find(o=>o.id===old.id||rows(o.legacy_ids).includes(old.id)||low(o.name)===low(old.name)&&(!old.source||low(o.source)===low(old.source)));
   if(!option||claimed.has(old))continue;claimed.add(old);
   if(!learned.includes(option.id))learned.push(option.id);
   if(!old.disabled&&rule.layers?.applied&&rule.application?.destination!=='item'&&!active.some(r=>r.id===option.id))active.push({id:option.id});
  }
  for(const item of rows(result.inventory))if(item.infusion){
   const option=options.find(o=>rows(o.legacy_ids).includes(item.infusion.id));
   if(option&&(!item.infusion.creator_id||item.infusion.creator_id===record.id)){
    if(!learned.includes(option.id))learned.push(option.id);
    if(!active.some(r=>r.id===option.id))active.push({id:option.id,target_item_id:item.instance_id||item.id,effect_choice:item.infusion.effect_choice||{}});
    const oldTracker='infusion-charges:infusion:'+String(item.infusion.creator_id||'unknown')+'|'+item.infusion.id+'|'+String(item.instance_id||item.id);
    const newTracker='item-option-charges:'+String(item.instance_id||item.id)+':'+option.id;
    if(Object.hasOwn(result.resource_tracker_spent||{},oldTracker)){
     result.resource_tracker_spent={...result.resource_tracker_spent,[newTracker]:result.resource_tracker_spent[newTracker]??result.resource_tracker_spent[oldTracker]};
     delete result.resource_tracker_spent[oldTracker];
    }
    delete item.infusion;
   }
  }
  if(rule.source?.options?.some(o=>rows(o.effects).some(e=>e.type==='state_selection'))){
   for(const option of options)for(const effect of rows(option.effects))if(effect.type==='state_selection'&&result[effect.field]?.[effect.key]===effect.value&&!active.length)active.push({id:option.id});
  }
  if(rule.compatibility?.selected_group&&!active.length&&result.trait_state_selection?.[rule.compatibility.selected_group]){const item=rows(result.inventory).find(i=>rows(i.equipped_slots).includes(rule.compatibility.target_slot));if(item)active.push({id:options[0]?.id,target_item_id:item.instance_id||item.id});}
  if(learned.length||selections[rule.id])selections[rule.id]={...saved,learned};
  if(active.length||Object.hasOwn(apps,rule.id))apps[rule.id]=active;
  for(const id of rows(rule.legacy_ids)){delete selections[id];delete apps[id];}
 }
 result.optional_features_catalog=rows(result.optional_features_catalog).filter(row=>!claimed.has(row));
 // Bound strings are represented by normalized optional choices now.
 result.fighting_styles=rows(result.fighting_styles).filter(row=>!all.some(rule=>optionsFor(result,rule).some(o=>low(o.name)===low(typeof row==='string'?row:row.name))));
 for(const rule of all)for(const option of optionsFor(result,rule))for(const effect of rows(option.effects))if(effect.type==='state_selection'){
  if(result.trait_state_selection)delete result.trait_state_selection[effect.key];
  if(result.active_class_features)delete result.active_class_features['trait_state:'+effect.value];
 }
 result.power_selections=selections;result.power_applications=apps;result.selection_state_version=2;return result;
}
