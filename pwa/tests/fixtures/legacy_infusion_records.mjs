// Historical record builders for import/parity tests only. Not shipped or imported by the PWA.
import {artificerLevel,infusionGrantingTrait,resolveOwnedItem,itemKind,hasProperty,itemAttunementCount,requiresAttunement,targetableInventoryItems,infusionChargeTrackerId} from '../../item_controls.js';
import {featureItemGrants} from '../../feature_item_grants.js';
const array=value=>Array.isArray(value)?value:[];
const sameText=(a,b)=>String(a??'').trim().toLowerCase()===String(b??'').trim().toLowerCase();
function clearInfusionChargeSpent(record,ids=[]){
 const removed=new Set(ids);return {resource_tracker_spent:Object.fromEntries(Object.entries(record.resource_tracker_spent||{}).filter(([key])=>!removed.has(key)))};
}
export function infusionLimits(record={},classMechanics={},features=[]){
 const level=artificerLevel(record);
 const cls=array(classMechanics?.classes).find(c=>sameText(c.name,"Artificer")&&sameText(c.source,"TCE"));
 const column=array(cls?.columns).find(c=>sameText(c.name,"Infused Items"));
 const enabled=!!infusionGrantingTrait(record,features);
 const base=level<2||!enabled?0:Math.max(0,Number(array(column?.levels)[level-1])||0);
 // Extra infusion capacity comes from an owned, enabled feature benefit.
 // It never grants extra infusions known and imposes no armor-part restriction.
 const extra=enabled?featureItemGrants(record,features,classMechanics?.feature_item_grants||[])
  .reduce((sum,grant)=>sum+Math.max(0,Number(grant.infusion_capacity_bonus)||0),0):0;
 return {level,active:base+extra,known:base*2};
}

export function learnedInfusions(record={},definitions=[]){
 return array(record.optional_features_catalog).flatMap((saved,index)=>{
   const option=array(definitions).find(row=>row.id===saved?.id);
   return option?[{...option,plan_item_id:saved.plan_item_id||"",plan_item_name:saved.plan_item_name||"",saved_index:index}]:[];
 });
}

export function infusionEligible(option,owned){
 if(!option||!owned||typeof owned!=="object")return false;
 const entry=resolveOwnedItem(owned),selector=option.item_selector||{};
 const kind=itemKind(entry),name=String(entry.name||"").toLowerCase(),id=String(owned.id||"");
 if(selector.id_prefix&&!id.startsWith(selector.id_prefix))return false;
 if(selector.nonmagical&&(id.startsWith("magic_item:")||entry.magic===true||
    !["","none","unknown","—"].includes(String(entry.rarity||"").toLowerCase())))return false;
 const kinds=array(selector.kinds),strict=kinds.some(k=>["armor","weapon","shield"].includes(k));
 const names=array(selector.name_contains_any),matchesName=names.some(part=>name.includes(String(part).toLowerCase()));
 if(strict){
   // Armor-or-robes (Mind Sharpener) accepts either side of the requirement.
   if(!kinds.includes(kind)&&!matchesName)return false;
   if(kinds.includes(kind)&&names.length&&!matchesName&&!(kinds.includes("armor")&&kind==="armor"))
     return false;
   if(array(selector.properties_all).length&&!array(selector.properties_all).every(code=>hasProperty(entry,code)))return false;
 }
 return true;
}

function replicableItem(option,entry,level){
 if(!entry||!String(entry.id||"").startsWith("magic_item:"))return false;
 if(array(option.replicable_items).some(row=>sameText(row.name,entry.name)&&level>=Number(row.level||99)))return true;
 return String(entry.rarity||"").toLowerCase()==="common"&&!["P","SC"].includes(String(entry.type||"").toUpperCase());
}

export function learnInfusionPatch(record,option,definitions,classMechanics,itemIndex=-1,features=[]){
 const caps=infusionLimits(record,classMechanics,features),known=learnedInfusions(record,definitions);
 if(!option?.id||!array(definitions).some(row=>row.id===option.id)||caps.level<Math.max(2,Number(option.min_level)||2)||
    known.length>=caps.known)throw Error("Infusione non disponibile o limite di conoscenza raggiunto.");
 let plan_item_id="",plan_item_name="";
 if(option.application_kind==="replicate"){
   const item=array(record.inventory)[itemIndex];
   if(!replicableItem(option,item,caps.level))throw Error("Oggetto magico non replicabile al livello attuale.");
   plan_item_id=item.id;plan_item_name=item.name||"";
 }
 if(known.some(row=>row.id===option.id&&row.plan_item_id===plan_item_id))throw Error("Infusione già conosciuta.");
 const trait=features===null?null:infusionGrantingTrait(record,features);
 return {optional_features_catalog:[...array(record.optional_features_catalog),
   {id:option.id,name:option.name,source:option.source||"TCE",
    ...(trait?{origin_id:trait.origin_id}:{}),...(plan_item_id?{plan_item_id,plan_item_name}:{})}],
   // Infusions become usable immediately upon learning.
   prepared_features:array(record.prepared_features).filter(row=>row?.kind!=="infusion")};
}

export function compatibleInfusionTargets(record,option,definitions=[],features=[]){
 if(!infusionGrantingTrait(record,features)||!learnedInfusions(record,definitions).some(row=>
   row.id===option?.id&&String(row.plan_item_id||"")===String(option.plan_item_id||"")))return [];
 // Preserve the generic inventory targeting utility for spells. Infusions use
 // their own typed eligibility so non-equipment examples can be bypassed.
 return targetableInventoryItems(record,{},(item)=>
   infusionEligible(option,item)&&
   (option.application_kind!=="replicate"||option.plan_item_id===item.id)&&
   (!item.infusion?.id||item.infusion.creator_id===record.id));
}

export function applyInfusionPatch(record,known,definitions,classMechanics,index,features=[],effectChoice={}){
 const caps=infusionLimits(record,classMechanics,features),items=structuredClone(array(record.inventory));
 const option=array(definitions).find(row=>row.id===known?.id),item=items[index];
 if(!option||!item||!array(record.optional_features_catalog).some(row=>
   row.id===option.id&&String(row.plan_item_id||"")===String(known.plan_item_id||"")))
   throw Error("Infusione non conosciuta oppure oggetto non disponibile.");
  if(caps.level<Math.max(2,Number(option.min_level)||2)||!infusionEligible(option,item))
   throw Error("Oggetto incompatibile o tratto Infuse Item non disponibile.");
 if(option.application_kind==="replicate"&&(!known.plan_item_id||known.plan_item_id!==item.id))
   throw Error("Questo piano replica un altro oggetto.");
 for(const [i,other] of items.entries()){
   const inf=other?.infusion;
   if(i!==index&&inf?.creator_id===record.id&&inf?.id===option.id&&
      String(inf.plan_item_id||"")===String(known.plan_item_id||""))
     throw Error("Infusione già applicata a un altro oggetto.");
 }
 const selection=option.effect_choice;
 const selected=selection?String(effectChoice?.[selection.key]||
   (item.infusion?.id===option.id?item.infusion.effect_choice?.[selection.key]:'')||''):'';
 if(selection&&(!array(selection.options).includes(selected)||!selection.key))
   throw Error('Seleziona una delle opzioni previste per l’effetto dell’infusione.');
 const old=item.infusion,oldChargeId=old?.id?infusionChargeTrackerId(item,index):'';
 if(old&&Object.keys(old).length&&old.creator_id!==record.id)throw Error("Infusione appartenente a un altro Artefice.");
 const active=items.filter(row=>Number(row?.quantity??1)>0&&row?.infusion?.creator_id===record.id).length;
 if(!old?.id&&active>=caps.active)throw Error("Limite di oggetti infusi raggiunto.");
 if(Number(item.quantity??1)>1){
   const attuned=itemAttunementCount(item);
   const remaining=structuredClone(item);
   remaining.quantity=Number(item.quantity)-1;remaining.equipped_slots=[];
   remaining.equipped=false;remaining.attuned=false;delete remaining.infusion;
   if(requiresAttunement(item)){
     remaining.attuned_count=Math.max(0,attuned-1);remaining.attuned=remaining.attuned_count>0;
     item.attuned_count=Math.min(1,attuned);item.attuned=item.attuned_count>0;
   }
   remaining.instance_id="pwa_instance_"+crypto.randomUUID();
   items.splice(index+1,0,remaining);item.quantity=1;
 }
 const trait=features===null?null:infusionGrantingTrait(record,features);
 item.infusion={id:option.id,name:option.name,source:"TCE",level:caps.level,
   creator_id:record.id,plan_item_id:known.plan_item_id||"",
   ...(trait?{origin_id:trait.origin_id}:{}),
   requires_attunement:Boolean(option.requires_attunement),
   ...(selection?{effect_choice:{[selection.key]:selected}}:{})};
 return {inventory:items,...clearInfusionChargeSpent(record,
   [oldChargeId,infusionChargeTrackerId(item,index)])};
}

export function forgetInfusionPatch(record,known){
 const current=array(record.optional_features_catalog);
 const index=current.findIndex(row=>row.id===known?.id&&
   String(row.plan_item_id||"")===String(known.plan_item_id||""));
 if(index<0)throw Error("Infusione non trovata.");
 const updated=structuredClone(current);updated.splice(index,1);
 const inventory=structuredClone(array(record.inventory)),removedChargeIds=[];
 for(const [itemIndex,item] of inventory.entries()){
   const inf=item.infusion||{};
   if(inf.creator_id===record.id&&inf.id===known.id&&
     String(inf.plan_item_id||"")===String(known.plan_item_id||"")){
     removedChargeIds.push(infusionChargeTrackerId(item,itemIndex));
     delete item.infusion;item.attuned=false;item.attuned_count=0;
   }
 }
 return {optional_features_catalog:updated,inventory,
   ...clearInfusionChargeSpent(record,removedChargeIds),
   prepared_features:array(record.prepared_features).filter(row=>!(row?.kind==="infusion"&&row.id===known.id))};
}
