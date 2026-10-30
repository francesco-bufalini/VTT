// Native nonspell capabilities: eligibility comes from the same projected
// feature/origin graph as the sheet, never from guessed class-level thresholds.
import {companionOwnerActions} from './companion_rules.js';
import {featureActionEntries,classFeatureDescriptors} from "./feature_mechanics.js";
import {activeItemOptionEffects,ownedItemDisplayName} from "./item_controls.js";
const rows=v=>Array.isArray(v)?v:[];
const norm=v=>String(v??"").trim().toLowerCase();

// These are native compatibility IDs, not rules for automatically granting powers.
const nativeIds=new Map([
  ["bard|bardic inspiration","vtt_bardic_inspiration"],
  ["druid|wild shape","vtt_wild_shape"]
]);
const text=value=>{
  if(typeof value==="string")return value;
  if(Array.isArray(value))return value.map(text).filter(Boolean).join("\n");
  if(value&&typeof value==="object")return [value.name,text(value.entries??value.entry??value.description??value.text)]
    .filter(Boolean).join(" · ");
  return "";
};
const inactive=(creature,id)=>!!id&&(creature.origin_enabled?.[id]===false||
  rows(creature.proficiency_origins).some(x=>x?.id===id&&x.disabled));
const trackerFor=(projection,name,owner="")=>rows(projection.trackers).find(row=>
  norm(row.name)===norm(name)&&(!owner||norm(row.origin_class)===norm(owner)))||null;
const attachTracker=(power,projection,owner="")=>{
  if(!power.tracker_id&&!power.resource_name)return power;
  const tracker=power.tracker_id?rows(projection.trackers).find(t=>t.id===power.tracker_id):
    trackerFor(projection,power.resource_name,owner);
  if(!tracker)return power;
  return {...power,tracker_id:tracker.id,tracker_name:tracker.name,
    tracker_max:tracker.max,tracker_remaining:Math.max(0,Number(tracker.max||0)-Number(tracker.spent||0))};
};

export async function loadActivatedAbilities(){
  const response=await fetch("/catalog/activated_abilities.json",{cache:"no-store"});
  if(!response.ok)throw new Error("Catalogo delle capacità non disponibile.");
  const value=await response.json();
  if(!Array.isArray(value?.abilities))throw new Error("Catalogo delle capacità non valido.");
  return value.abilities;
}

// includeUnavailable is only for read-only previews. Never use these entries
// to authorize an activation or bypass the normal eligibility checks.
export function abilitiesForCreature(creature={},manifest=[],projection={},options={}){
 creature=projection.selection_record||creature;
  const includeUnavailable=options.includeUnavailable===true;
  const result=[],seen=new Set();
  const add=(definition,origin,originId="",owner="")=>{
    if(!definition?.id||(!includeUnavailable&&inactive(creature,originId)))return;
    const identity=includeUnavailable?definition.id+'|'+originId:definition.id;
    if(seen.has(identity))return;
    seen.add(identity);
    // Ability entries retain requirements, feature identity, effect and payment
    // metadata; only spell-specific fields are intentionally excluded.
    const {school,components,level,...rest}=definition;
    result.push(attachTracker({...rest,action_kind:"ability",origin,origin_id:originId,
      ...(includeUnavailable?{unavailable:!!definition.unavailable||
        inactive(creature,originId)||!!originId&&rows(projection.features)
          .some(f=>f.origin_id===originId&&(f.inactive||f.disabled))}: {})
    },projection,owner));
  };
  const features=rows(projection.features).filter(f=>f&&
    (includeUnavailable||!f.disabled&&!f.inactive&&
      !inactive(creature,f.origin_id)&&!inactive(creature,f.origin_key)));
  const timed=featureActionEntries(creature,rows(projection.trackers),
    projection.feature_rules||{},features);

  const classDescriptors=classFeatureDescriptors(creature,projection);
  // A class trait may grant several distinct actions. One descriptive
  // command must not turn its other real, executable powers into descriptions.
  const descriptiveDescriptors=classDescriptors.filter(row=>row.descriptive_only&&
    !classDescriptors.some(other=>other.feature_id===row.feature_id&&!other.descriptive_only));
  const descriptiveOwners=new Set(descriptiveDescriptors.map(row=>row.feature_id));
  // Class capabilities are unlocked only by an actual structured trait. The
  // preexisting IDs remain stable for saved grants and Android interoperability.
  for(const feature of features){
    const parts=String(feature.origin_key||"").split("|");
    if(parts[0]!=="class"||parts.length<3)continue;
    const owner=parts[2];
    const id=nativeIds.get(owner+"|"+norm(feature.name));
    const explicit=feature.action_type||feature.activation_type||feature.activation;
    const descriptive=descriptiveDescriptors.find(row=>row.feature_id===feature.origin_id);
    if(!id&&!explicit&&!descriptive)continue; // Never turn passive features into actions.
    const action=timed.find(a=>id==="vtt_wild_shape"&&a.rule_action_id==="wild_shape")||
      timed.find(a=>norm(a.feature)===norm(feature.name)&&
        (String(a.origin_id||"").startsWith("feature:"+parts.slice(0,3).join("|"))||
         String(a.origin_id||"")===parts.slice(0,3).join("|")));
    const tracker=trackerFor(projection,feature.name,owner);
    const definition={
      id:id||"feature:"+feature.key,name:descriptive?.name||feature.name,
      descriptive_only:descriptiveOwners.has(feature.origin_id),
      ...(descriptive?{class_feature_id:descriptive.class_feature_id}:{}),
      source:feature.source||parts[1].toUpperCase(),
      feature_id:feature.origin_id,
      feature_name:feature.name,
      origin_name:'Tratto · '+feature.name,
      requirements:feature.requirements,
      action_type:action?.time||descriptive?.time||(typeof explicit==="object"?explicit?.type||explicit?.unit:explicit)||"",
      activation_mode:action?.time||descriptive?.time||(typeof explicit==="object"?explicit?.type||explicit?.unit:explicit)||"contextual",
      resource_name:action?.tracker||tracker?.name||"",
      tracker_id:action?.tracker_id||tracker?.id||"",
      resource_cost:action?.cost??(tracker?1:0),
      target_mode:action?.target_mode||"",
      target_range_feet:action?.target_range_feet||0,
      exclude_self:action?.exclude_self===true,
      description:text(feature.entries??feature.description??"")
    };
    add(definition,"Classe · "+owner+" · "+parts[1].toUpperCase(),feature.origin_id,owner);
  }

  const defs=new Map(rows(manifest).map(a=>[norm(a.name)+"|"+norm(a.source),a]));
  const ids=new Map(rows(manifest).map(a=>[a.id,a]));
  for(const feature of rows(creature.optional_features_catalog)){
    // Infusions are choices attached to inventory items, not free optional powers.
    if(String(feature?.id||'').startsWith('infusion|'))continue;
    if(!feature||(!includeUnavailable&&(feature.disabled||inactive(creature,feature.origin_id))))continue;
    const key=norm(feature.name)+"|"+norm(feature.source);
    let ability=defs.get(key);
    if(!ability&&!feature.source){
      const source=creature.rules_version==="2024"?"xphb":"phb";
      ability=defs.get(norm(feature.name)+"|"+source)||
        defs.get(norm(feature.name)+"|tce");
    }
    if(ability)add({...ability,unavailable:!!feature.disabled,
      description:ability.description||text(feature.entries??feature.description)},
      feature.origin_name||"Privilegio opzionale · "+feature.name,
      feature.origin_id||'optional|'+norm(feature.source)+'|'+norm(feature.name));
  }
  for(const grant of rows(creature.origin_spell_grants)){
    if(!grant||(!includeUnavailable&&(grant.disabled||inactive(creature,grant.origin_id))))continue;
    const id=String(grant.ability_id||grant.spell_id||"");
    const definition=ids.get(id);
    if(definition)add({...definition,unavailable:!!grant.disabled,
      tracker_id:grant.tracker_id||definition.tracker_id,
      resource_cost:grant.tracker_cost??definition.resource_cost},
      grant.origin_name||"Origine",grant.origin_id);
    else if(id==="vtt_bardic_inspiration"||id==="vtt_wild_shape")continue;
    else if(grant.action_kind==="ability"&&id){
      add({id,name:grant.name||id,description:grant.description||"",
        unavailable:!!grant.disabled,
        tracker_id:grant.tracker_id,resource_cost:grant.tracker_cost,
        action_kind:"ability",activation_mode:grant.activation_mode||"contextual"},
      grant.origin_name||"Origine",grant.origin_id);
    }
  }
  // Activate only real, equipped/attuned item copies. Infusion actions reuse
  // the same ability + tracker pipeline as class powers and other abilities.
  for(const applied of activeItemOptionEffects(creature,projection.infusion_catalog||[],projection.features||[])){
    const {item,definition,index}=applied;
    const trait='item:'+String(item.id)+'|'+applied.id;
    const display=ownedItemDisplayName(item);
    for(const action of rows(definition.item_abilities)){
      if(!action?.id||!action.name||!action.action_type||action.action_type==='passive')continue;
      const cost=Math.max(0,Number(action.resource_cost)||0);
      const trackerId=cost?applied.tracker_id:'';
      if(cost&&!rows(projection.trackers).some(t=>t.id===trackerId&&!t.disabled))continue;
      add({id:'infusion-action:'+applied.id+':'+action.id,name:action.name,
        source:definition.source||'TCE',feature_id:trait,feature_name:display,
        origin_name:'Oggetto · '+display,action_type:action.action_type,
        activation_mode:action.action_type,tracker_id:trackerId,resource_cost:cost,
        resource_name:cost?display+' · Cariche':'',infusion_action:true,
        infusion_id:definition.id,infusion_inventory_index:index,
        description:action.description||'',target_mode:action.target_mode||'',
        target_range_feet:Math.max(0,Number(action.target_range_feet)||0),
        exclude_self:action.exclude_self===true
      },'Oggetto · '+display,trait);
    }
  }
  // Trait-granted attacks are independent, unlimited capabilities. Their optional
  // damage dice have their own counters and never pay for the attack itself.
  for(const attack of rows(projection.attacks)){
    const feature=features.find(row=>row.origin_id===attack.origin_id);
    if(!feature||!String(feature.origin_id||'').startsWith('feature:'))continue;
    if(result.some(row=>row.roll_attack?.id===attack.id))continue;
    add({id:'trait-attack:'+attack.id,name:attack.name,feature_id:feature.origin_id,
      feature_name:feature.name,origin_name:'Tratto · '+feature.name,
      action_type:attack.action_type||'action',activation_mode:attack.action_type||'action',
      tracker_id:'',resource_name:'',resource_cost:0,
      roll_attack:{kind:'attack',id:attack.id},description:attack.description||text(feature.entries)
    },'Tratto · '+feature.name,feature.origin_id);
  }
  for(const power of companionOwnerActions(creature,projection,projection.companion_rules))
    add(power,power.origin_name,power.feature_id);
  // Explicit typed species grants use the same activation and tracker path
  // as class features, without guessing action timing from descriptions.
  for(const power of rows(projection.racial_abilities))
    add(power,'Specie · '+(creature.species||'')+' · '+(creature.species_source||''),
      power.origin_id||'');
  return result.sort((a,b)=>String(a.name||"").localeCompare(String(b.name||"")));
}
