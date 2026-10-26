// Native nonspell capabilities: eligibility comes from the same projected
// feature/origin graph as the sheet, never from guessed class-level thresholds.
import {featureActionEntries} from "./feature_mechanics.js";
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

  // Class capabilities are unlocked only by an actual structured trait. The
  // preexisting IDs remain stable for saved grants and Android interoperability.
  for(const feature of features){
    const parts=String(feature.origin_key||"").split("|");
    if(parts[0]!=="class"||parts.length<3)continue;
    const owner=parts[2];
    const id=nativeIds.get(owner+"|"+norm(feature.name));
    const explicit=feature.action_type||feature.activation_type||feature.activation;
    // A subclass feature that owns a limited-use tracker is actionable even
    // when its 5etools entry has no explicit timing. Link by exact trait ID,
    // not a similarly named resource on another class or subclass.
    const owned=parts[1]==="phb"&&parts[3]==="subclass"&&creature.rules_version!=="2024"?
      rows(projection.trackers).find(t=>!t.disabled&&t.origin_id===feature.origin_id):null;
    if(!id&&!explicit&&!owned)continue; // Passive, uncosted features stay read-only.
    const action=timed.find(a=>id==="vtt_wild_shape"&&a.rule_action_id==="wild_shape")||
      timed.find(a=>norm(a.feature)===norm(feature.name)&&
        (String(a.origin_id||"").startsWith("feature:"+parts.slice(0,3).join("|"))||
         String(a.origin_id||"")===parts.slice(0,3).join("|")));
    const tracker=owned||(id?trackerFor(projection,feature.name,owner):null);
    const definition={
      id:id||"feature:"+feature.key,name:feature.name,
      source:feature.source||parts[1].toUpperCase(),
      feature_id:feature.origin_id,
      feature_name:feature.name,
      origin_name:'Tratto · '+feature.name,
      requirements:feature.requirements,
      action_type:action?.time||(typeof explicit==="object"?explicit?.type||explicit?.unit:explicit)||"",
      activation_mode:action?.time||(typeof explicit==="object"?explicit?.type||explicit?.unit:explicit)||"contextual",
      resource_name:action?.tracker||tracker?.name||"",
      tracker_id:action?.tracker_id||tracker?.id||"",
      resource_cost:action?.cost??(tracker?1:0),
      description:text(feature.entries??feature.description??"")
    };
    add(definition,"Classe · "+owner+" · "+parts[1].toUpperCase(),feature.origin_id,owner);
  }

  const defs=new Map(rows(manifest).map(a=>[norm(a.name)+"|"+norm(a.source),a]));
  const ids=new Map(rows(manifest).map(a=>[a.id,a]));
  for(const feature of rows(creature.optional_features_catalog)){
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
  return result.sort((a,b)=>String(a.name||"").localeCompare(String(b.name||"")));
}
