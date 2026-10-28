import {featureItemGrants} from "./feature_item_grants.js";
// Native-compatible inventory item instance helpers.
// Keep the mobile spell-scroll inventory in parity with the desktop table.
// These are display helpers: scrolls remain ordinary owned inventory instances.
// Per-creature flat storage: old inventory rows without container_id belong to Zaino.
export const DEFAULT_INVENTORY_CONTAINER = "backpack";
export function inventoryContainers(record={}){
  const rows=Array.isArray(record.inventory_containers)?record.inventory_containers:[];
  const used=new Set([DEFAULT_INVENTORY_CONTAINER]);
  return [{id:DEFAULT_INVENTORY_CONTAINER,name:"Zaino"},...rows.flatMap(row=>{
    const id=String(row?.id||"").trim(),name=String(row?.name||"").trim();
    if(!id||!name||used.has(id))return [];
    used.add(id);return [{id,name}];
  })];
}
export function itemContainerId(item={},containers=[]){
  const id=String(item?.container_id||DEFAULT_INVENTORY_CONTAINER);
  return containers.some(row=>row.id===id)?id:DEFAULT_INVENTORY_CONTAINER;
}
export function moveInventoryItem(record,index,destination){
  const containers=inventoryContainers(record);
  if(!containers.some(row=>row.id===destination))throw Error("Contenitore non disponibile.");
  const inventory=structuredClone(Array.isArray(record.inventory)?record.inventory:[]);
  if(!inventory[index])throw Error("Oggetto non trovato.");
  if(destination===DEFAULT_INVENTORY_CONTAINER)delete inventory[index].container_id;
  else inventory[index].container_id=destination;
  return {inventory};
}
export function createInventoryContainer(record,id,name){
  id=String(id||"").trim();name=String(name||"").trim();
  if(!id||id===DEFAULT_INVENTORY_CONTAINER||!name||name.length>80||
    inventoryContainers(record).some(row=>row.id===id||row.name.toLowerCase()===name.toLowerCase()))
    throw Error("Nome o identificativo del contenitore non valido.");
  return {inventory_containers:[...inventoryContainers(record).slice(1),{id,name}]};
}
export function deleteInventoryContainer(record,id,destination){
  const containers=inventoryContainers(record);
  if(id===DEFAULT_INVENTORY_CONTAINER||!containers.some(row=>row.id===id))
    throw Error("Lo Zaino non si può eliminare.");
  if(id===destination||!containers.some(row=>row.id===destination))
    throw Error("Seleziona un altro contenitore di destinazione.");
  const inventory=structuredClone(Array.isArray(record.inventory)?record.inventory:[]);
  for(const item of inventory)if(itemContainerId(item,containers)===id){
    if(destination===DEFAULT_INVENTORY_CONTAINER)delete item.container_id;
    else item.container_id=destination;
  }
  return {inventory,inventory_containers:containers.slice(1).filter(row=>row.id!==id)};
}
export function isSpellScroll(item={}){
  if(item.category==="documents")return false;
  const type=String(item.type||"").split("|")[0].toUpperCase();
  const name=String(item.name||"").toLowerCase();
  return type==="SC"||name.includes("spell scroll")||name.includes("pergamena di incantesimo");
}
export function spellScrollName(item={}){
  let value=item.spell_name??item.spellName??item.spell??"";
  if(Array.isArray(value))value=value[0]??"";
  if(value&&typeof value==="object")value=value.name??"";
  const spellName=String(value||"").trim();
  if(spellName)return spellName;
  const name=String(item.name||"").trim();
  if(/^(?:spell scroll|pergamena di incantesimo)\s*(?:\(.*\))?$/i.test(name))
    return "Incantesimo non specificato";
  return name||"Incantesimo non specificato";
}
export function spellScrollLevel(item={}){
  const level=item.spell_level??item.spellLevel??item.level;
  if(level!==undefined&&level!==null&&String(level).trim()!=="")return String(level);
  const name=String(item.name||"");
  const match=/(\d+)(?:st|nd|rd|th|°|º)?[- ]level/i.exec(name)||
    /(\d+)[°º]?\s*livello/i.exec(name);
  return match?match[1]:"—";
}
// Scrolls are created from an actual spell and its selected casting level,
// not from a generic magic item entry. The desktop's SC + spell fields remain
// readable, while each scroll remains a normal owned inventory stack.
export function addSpellScroll(inventory,spell,level,instanceId){
  if(!Array.isArray(inventory))throw Error("Inventario non valido.");
  const spellId=String(spell?.id||"").trim(),spellName=String(spell?.name||"").trim();
  const base=Number(spell?.level),selected=Number(level);
  if(!spellId||!spellName||spell?.internal_grant||
     !Number.isInteger(base)||base<0||base>9||
     !Number.isInteger(selected)||selected<base||selected>9||
     (base===0&&selected!==0))
    throw Error("Seleziona un incantesimo e un livello valido.");
  const rows=structuredClone(inventory),id="local_spell_scroll:"+spellId;
  const existing=rows.findIndex(item=>isSpellScroll(item)&&item.id===id&&
    item.spell_id===spellId&&Number(item.spell_level)===selected&&
    !item.equipped&&!item.attuned&&!item.infusion);
  if(existing>=0){
    const amount=Number(rows[existing].quantity)||1;
    if(!Number.isInteger(amount)||amount<1||amount>=99999)
      throw Error("Quantità massima raggiunta per questa pergamena.");
    rows[existing].quantity=amount+1;
    return {inventory:rows,index:existing};
  }
  if(!String(instanceId||"").trim())throw Error("Identificativo copia mancante.");
  rows.push({id,instance_id:String(instanceId),name:"Pergamena di incantesimo ("+spellName+")",
    type:"SC",source:String(spell.source||""),spell_id:spellId,spell_name:spellName,
    spell_level:selected,spell_base_level:base,
    description:String(spell.description||""),
    quantity:1,equipped:false,equipped_slots:[],attuned:false,active:true,
    instance_overrides:{}});
  return {inventory:rows,index:rows.length-1};
}
const array=v=>Array.isArray(v)?v:[];
export function itemKind(item={}){
  if(item.category==="documents")return "document";
  if(["weapon","shield","armor","tool","magic","other"].includes(item.custom_item_type))return item.custom_item_type;
  const code=String(item.type||"").split("|")[0].toUpperCase();
  if(["M","R"].includes(code)&&(item.weapon_category||item.damage||item.properties!==undefined))return "weapon";
  if(code==="S")return "shield";
  if(["LA","MA","HA"].includes(code))return "armor";
  if(["AT","INS","T","SCF","GS","P","MNT"].includes(code))return "tool";
  if(String(item.id||"").startsWith("magic_item:"))return "magic";
  return "other";
}

// Native ItemInstance.resolve allowlist: per-copy fields never mutate compendium data.
export const ITEM_INSTANCE_FIELDS=["damage","versatile_damage","damage_type","range","properties",
  "ac","bonus_ac","bonus_weapon","weight","weapon_size"];
export const WEAPON_SIZES=["Tiny","Small","Medium","Large","Huge","Gargantuan"];
// Category defaults follow D&D armor rules; catalog/homebrew limits take precedence.
export function armorDexterityLimit(armor={}){
 const item=resolveOwnedItem(armor);
 if(itemKind(item)!=="armor")return null;
 if(item.dexterity_max!==undefined&&item.dexterity_max!==null&&String(item.dexterity_max).trim()!==""){
  const limit=Number(item.dexterity_max);
  if(Number.isFinite(limit))return limit;
 }
 const type=String(item.type||"").split("|")[0].toUpperCase();
 return type==="HA"?0:type==="MA"?2:null;
}
export function armorDexterityBonus(armor={},modifier=0){
 const cap=armorDexterityLimit(armor),dex=Number(modifier);
 // Heavy armor never adds or subtracts DEX (including negative modifiers).
 return cap===0?0:Math.min(Number.isFinite(dex)?dex:0,cap??Infinity);
}
export function armorDexterityLabel(armor={}){
 const cap=armorDexterityLimit(armor);
 return cap===0?"DES non applicata":cap===null?"+ DES (senza limite)":
  "+ DES (max "+(cap>=0?"+":"")+cap+")";
}
export function resolveOwnedItem(saved={}){
  const effective={...saved},overrides=saved?.instance_overrides;
  if(overrides&&typeof overrides==="object"&&!Array.isArray(overrides))
    for(const key of ITEM_INSTANCE_FIELDS)
      if(Object.hasOwn(overrides,key))effective[key]=structuredClone(overrides[key]);
  if(saved?.infusion?.requires_attunement===true)effective.req_attune=true;
  return effective;
}
// Fold truly identical owned copies into one stack. An instance ID identifies
// a physical copy, not a different item definition; equipped hand/body slots
// are kept separately so two shields can occupy different hands.
export function consolidateOwnedItems(inventory){
  if(!Array.isArray(inventory))return [];
  const rows=[],groups=new Map();
  const stable=value=>Array.isArray(value)?value.map(stable):
    value&&typeof value==="object"?Object.fromEntries(
      Object.keys(value).sort().map(key=>[key,stable(value[key])])):value;
  for(const original of inventory){
    const row=structuredClone(original);
    const quantity=Number(row?.quantity??1),kind=itemKind(row||{});
    const slots=array(row?.equipped_slots);
    const canStack=row&&typeof row==="object"&&!Array.isArray(row)&&
      String(row.id||row.name||"").trim()&&kind!=="document"&&
      !row.infusion&&row.standalone_instance!==true&&itemAttunementCount(row)===0&&row.attuned!==true&&
      Number.isInteger(quantity)&&quantity>=1&&quantity<=99999&&
      slots.every(slot=>["main","off","body"].includes(slot))&&
      new Set(slots).size===slots.length&&slots.length<=quantity;
    if(!canStack){rows.push(row);continue;}
    const identity={...row};
    delete identity.instance_id;delete identity.quantity;delete identity.equipped_slots;
    identity.instance_overrides=identity.instance_overrides||{};
    identity.equipped=identity.equipped===true;
    identity.attuned=identity.attuned===true;
    if(!Number(identity.attuned_count))delete identity.attuned_count;
    identity.active=identity.active!==false;
    const key=JSON.stringify(stable(identity));
    const candidates=groups.get(key)||[];
    const found=candidates.find(index=>{
      const previous=rows[index],used=array(previous.equipped_slots);
      return Number(previous.quantity??1)+quantity<=99999&&
        slots.every(slot=>!used.includes(slot));
    });
    if(found!==undefined){
      rows[found].quantity=Number(rows[found].quantity??1)+quantity;
      rows[found].equipped_slots=[...array(rows[found].equipped_slots),...slots];
    }else{
      groups.set(key,[...candidates,rows.length]);
      rows.push(row);
    }
  }
  return rows;
}

// Native inventory behavior: editing one item in a stack splits it off.
export function changeItemOverride(inventory,index,key,value){
  if(!Array.isArray(inventory)||!Number.isInteger(index)||index<0||index>=inventory.length)
    throw Error("Oggetto non trovato.");
  const rows=structuredClone(inventory),item=rows[index];
  if(!item||typeof item!=="object"||!["weapon_size","damage","versatile_damage","damage_type","range","ac","bonus_ac","bonus_weapon"].includes(key))
    throw Error("Proprietà di istanza non modificabile.");
  const kind=itemKind(item);
  if(key==="weapon_size"&&kind!=="weapon"||
     ["damage","versatile_damage","range","bonus_weapon"].includes(key)&&kind!=="weapon"||
     ["ac","bonus_ac"].includes(key)&&!["armor","shield"].includes(kind))
    throw Error("Proprietà incompatibile con l'oggetto.");
  let normalized=String(value??"").trim(),valid=true;
  if(key==="weapon_size")valid=!normalized||WEAPON_SIZES.includes(normalized);
  else if(["damage","versatile_damage"].includes(key))
    valid=!normalized||/^([1-9]\d{0,2})d(4|6|8|10|12|20|100)(?:\s*[+-]\s*\d{1,3})?$/i.test(normalized);
  else if(key==="range"){
    valid=!normalized||/^[1-9]\d{0,3}(?:\/[1-9]\d{0,3})?$/.test(normalized);
    const distances=normalized.split("/").map(Number);
    if(normalized&&distances.length>1&&distances[1]<distances[0])valid=false;
  }else if(["ac","bonus_ac","bonus_weapon"].includes(key)){
    if(normalized!==""){
      const n=Number(normalized),lo=key==="ac"?0:-20,hi=key==="ac"?40:20;
      valid=Number.isInteger(n)&&n>=lo&&n<=hi;
      if(valid)normalized=n;
    }
  }else if(key==="damage_type")valid=normalized.length<=60&&(!normalized||/^[a-zA-Z _-]+$/.test(normalized));
  if(!valid)throw Error("Valore non valido per "+key);
  const current=item.instance_overrides&&typeof item.instance_overrides==="object"?
    {...item.instance_overrides}:{};
  if(normalized===(current[key]??""))return rows;
  if(Number(item.quantity||1)>1){
    const attuned=itemAttunementCount(item);
    rows[index].quantity=Number(item.quantity)-1;
    if(requiresAttunement(item)){
      rows[index].attuned_count=Math.min(attuned,rows[index].quantity);
      rows[index].attuned=rows[index].attuned_count>0;
    }
    const one=structuredClone(item);
    one.quantity=1;one.equipped_slots=[];one.equipped=false;one.attuned=false;
    if(requiresAttunement(item)){
      one.attuned_count=Math.max(0,attuned-rows[index].quantity);one.attuned=one.attuned_count>0;
    }
    one.instance_id="pwa_instance_"+crypto.randomUUID();
    rows.splice(index+1,0,one);
    index++;
  }
  const changed=rows[index],overrides={...(changed.instance_overrides||{})};
  if(normalized==="")delete overrides[key];
  else overrides[key]=normalized;
  changed.instance_overrides=overrides;
  return rows;
}

// Match desktop slot-size editing: a stack's equipped copy is split
// without resetting the opposite hand or modifying every copy.
export function changeEquippedWeaponSize(inventory,slot,size){
  if(!['main','off'].includes(slot)||size&&!WEAPON_SIZES.includes(size))
    throw Error("Taglia arma non valida.");
  const rows=structuredClone(array(inventory));
  const index=rows.findIndex(row=>array(row?.equipped_slots).includes(slot));
  if(index<0||itemKind(rows[index])!=='weapon')throw Error("Nessuna arma impugnata.");
  const item=rows[index],previous=String(item.instance_overrides?.weapon_size||'');
  if(previous===size)return rows;
  let target=item;
  if(Number(item.quantity??1)>1){
    item.quantity=Number(item.quantity)-1;
    item.equipped_slots=array(item.equipped_slots).filter(s=>s!==slot);
    target=structuredClone(target);
    target.quantity=1;
    target.instance_id="pwa_instance_"+crypto.randomUUID();
    target.equipped_slots=[slot];
    rows.splice(index+1,0,target);
  }
  target.instance_overrides={...(target.instance_overrides||{})};
  if(size)target.instance_overrides.weapon_size=size;
  else delete target.instance_overrides.weapon_size;
  return rows;
}

export function requiresAttunement(item={}){
  const v=item.req_attune??item.reqAttune??item.requires_attunement??
    item.requiresAttunement??item.infusion?.requires_attunement??false;
  return v===true||(typeof v==="string"&&v.trim().length>0);
}
// A legacy boolean attunes one physical copy, never the entire stack.
export function itemAttunementCount(item={}){
  if(!requiresAttunement(resolveOwnedItem(item)))return 0;
  const quantity=Math.max(0,Math.floor(Number(item.quantity??1)||0));
  const count=Object.hasOwn(item,'attuned_count')?Number(item.attuned_count):item.attuned===true?1:0;
  return Math.min(quantity,Math.max(0,Math.floor(Number.isFinite(count)?count:0)));
}
export function inventoryAttunementCounts(inventory=[],maximum=3){
  let available=Math.max(0,Math.floor(Number(maximum)||0));
  return array(inventory).map(item=>{
    const count=Math.min(itemAttunementCount(item),available);
    available-=count;return count;
  });
}
export function itemBenefitCopies(item={}){
  if(requiresAttunement(resolveOwnedItem(item)))return itemAttunementCount(item);
  return ['weapon','armor','shield'].includes(itemKind(item))?1:
    Math.max(0,Math.floor(Number(item.quantity??1)||0));
}
export const isCatalogItem=item=>!!String(item?.id||"")&&!String(item.id).startsWith("local_");
export function createOwnedItem(entry,id){
  if(!entry||typeof entry!=="object"||!String(entry.id||"")||!String(entry.name||""))throw Error("Oggetto senza ID o nome.");
  const result=structuredClone(entry);
  delete result._category;delete result._homebrew;
  Object.assign(result,{instance_id:id,quantity:1,equipped:false,equipped_slots:[],attuned:false,attuned_count:0,active:true,instance_overrides:{}});
  return result;
}
export function changeOwnedItem(inventory,index,key,value,{attunementMax=3}={}){
  if(!Number.isInteger(index)||index<0||index>=array(inventory).length)throw Error("Oggetto non trovato.");
  if(!["quantity","equipped","attuned","attuned_count","active","name","description"].includes(key))throw Error("Campo non modificabile.");
  const items=structuredClone(inventory),item=items[index],kind=itemKind(item);
  if(!item||typeof item!=="object"||Array.isArray(item))throw Error("Oggetto non valido.");
  if(key==="quantity"){
    const qty=Number(value);
    if(!Number.isInteger(qty)||qty<1||qty>99999||kind==="document")throw Error("Quantità non valida.");
    item.quantity=qty;
    if(Object.hasOwn(item,'attuned_count')||item.attuned){
      item.attuned_count=itemAttunementCount(item);item.attuned=item.attuned_count>0;
    }
  }else if(key==="equipped"){
    if(["weapon","armor","shield","document"].includes(kind))throw Error("Equipaggia da Battaglia.");
    item.equipped=Boolean(value);
  }else if(key==="attuned"||key==="attuned_count"){
    if(!requiresAttunement(resolveOwnedItem(item)))throw Error("Oggetto senza sintonia.");
    const count=key==='attuned'?(value?Math.max(1,itemAttunementCount(item)):0):Number(value);
    if(String(value).trim()===''||!Number.isInteger(count)||count<0||count>Number(item.quantity??1))
      throw Error('Sintonie non valide: non possono superare la quantità posseduta.');
    const occupied=items.reduce((sum,row,i)=>sum+(i===index?0:itemAttunementCount(row)),0);
    if(count>itemAttunementCount(item)&&occupied+count>Math.max(0,Number(attunementMax)||0))
      throw Error('Limite massimo di sintonie raggiunto.');
    item.attuned_count=count;item.attuned=count>0;
  }else if(key==="active")item.active=Boolean(value);
  else{
    if(isCatalogItem(item)||typeof value!=="string"||value.length>(key==="name"?160:12000)||
      (key==="name"&&!value.trim()))throw Error("Campo non modificabile.");
    item[key]=value;
  }
  return items;
}


const sameText=(a,b)=>String(a??"").trim().toLowerCase()===String(b??"").trim().toLowerCase();
export function artificerLevel(record={}){
 const classes=array(record.classes);
 const members=classes.length?classes:[{name:record.class,source:record.class_source,level:record.level}];
 return Math.max(0,Math.min(20,Number(members.find(c=>sameText(c?.name,"Artificer")&&sameText(c?.source,"TCE"))?.level)||0));
}
// A class level is a prerequisite, never the source of a privilege.
export function infusionGrantingTrait(record={},features=null){
 const rows=Array.isArray(features)?features:[];
 const feature=rows.find(f=>sameText(f?.name,"Infuse Item")&&
   sameText(f.class_name||f.requirements?.class_name||String(f.origin_key||"").split("|")[2],"Artificer")&&
   sameText(f.class_source||f.requirements?.class_source||String(f.origin_key||"").split("|")[1],"TCE")&&
   String(f.origin_key||"").startsWith("class|"));
 if(!feature||feature.inactive||feature.disabled)return null;
 const base="class|tce|artificer";
 if([feature.origin_id,feature.origin_key,base].some(id=>id&&
     (record.origin_enabled?.[id]===false||array(record.proficiency_origins).some(o=>o?.id===id&&o.disabled))))
   return null;
 return feature;
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

/** One selectable infusion per Replicate Magic Item catalog choice.
 * The original definition remains resolvable for existing saved characters. */
export function expandedInfusionDefinitions(definitions=[]){
 const result=[];
 for(const entry of Array.isArray(definitions)?definitions:[]){
  if(entry?.application_kind!=="replicate"){result.push(entry);continue;}
  result.push({...entry,legacy_replicate:true});
  for(const item of Array.isArray(entry.replicable_items)?entry.replicable_items:[]){
   const name=String(item?.name||"").trim();
   if(!name)continue;
   const suffix=name.normalize("NFKD").replace(/[\u0300-\u036f]/g,"").toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"");
   result.push({id:entry.id+"|"+suffix,name:"Replicate Magic Item · "+name,
    source:entry.source||"TCE",min_level:Math.max(2,Number(item.level)||2),
    application_kind:"replicate_variant",replicates_item_name:name,
    item_selector:{},requires_attunement:false,
    description_source_name:entry.name,description_source:entry.source||"TCE"});
  }
 }
 return result;
}

export function learnedInfusions(record={},definitions=[]){
 return array(record.optional_features_catalog).flatMap((saved,index)=>{
   const option=array(definitions).find(row=>row.id===saved?.id);
   return option?[{...option,plan_item_id:saved.plan_item_id||"",plan_item_name:saved.plan_item_name||"",saved_index:index}]:[];
 });
}
// The original item selector is authoritative for actual armor, weapon and
// shield requirements. Non-equipment examples (boots, rods, rings, gems, etc.)
// are advisory: any nonmagical object may receive those infusions.
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
// Generic learnt/prepared feature selections; other nonspell features may reuse
// this collection instead of masquerading as class spells or trackers.
const preparationIdentity=row=>[String(row?.kind||""),String(row?.id||""),String(row?.plan_item_id||"")].join("|");
export function preparedFeatureRows(record={}){
 return array(record.prepared_features);
}
export function featurePreparationPatch(record,choice,enabled,known=[]){
 const item={kind:String(choice?.kind||""),id:String(choice?.id||""),
   plan_item_id:String(choice?.plan_item_id||""),origin_id:String(choice?.origin_id||"")};
 if(!item.kind||!item.id)throw Error("Capacità non disponibile.");
 const choices=preparedFeatureRows(record,known).map(row=>({...row}));
 const key=preparationIdentity(item);
 const present=choices.some(row=>preparationIdentity(row)===key);
 if(enabled&&!present)choices.push(item);
 if(!enabled&&present)return {prepared_features:choices.filter(row=>preparationIdentity(row)!==key)};
 return {prepared_features:choices};
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
// Reusable inventory targeting contract for infusions and object-targeting spells.
// Eligibility comes exclusively from typed selectors, never narrative text.
export function targetableInventoryItems(record,selector={},predicate=()=>true){
 return array(record.inventory).flatMap((item,index)=>{
   if(!item||Number(item.quantity??1)<=0||item.category==="documents")return [];
   const resolved=resolveOwnedItem(item),kind=itemKind(resolved),id=String(item.id||"");
   if(array(selector.kinds).length&&!selector.kinds.includes(kind))return [];
   if(selector.nonmagical&&(id.startsWith("magic_item:")||resolved.magic===true||
      !["","none","unknown","—"].includes(String(resolved.rarity||"").toLowerCase())))return [];
   if(selector.id_prefix&&!id.startsWith(selector.id_prefix))return [];
   if(array(selector.item_types).length&&!selector.item_types.includes(String(resolved.type||"").split("|")[0].toUpperCase()))return [];
   if(array(selector.properties_all).length&&!selector.properties_all.every(code=>hasProperty(resolved,code)))return [];
   if(array(selector.name_contains_any).length&&!selector.name_contains_any.some(part=>
      String(resolved.name||"").toLowerCase().includes(String(part).toLowerCase())))return [];
   return predicate(item,index)?[{item,index}]:[];
 });
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
 const old=item.infusion;
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
 return {inventory:items};
}
export function clearInfusionPatch(record,index){
 const items=structuredClone(array(record.inventory));
 if(!items[index]?.infusion?.id)throw Error("Nessuna infusione da rimuovere.");
 delete items[index].infusion;items[index].attuned=false;items[index].attuned_count=0;
 return {inventory:items};
}
export function forgetInfusionPatch(record,known){
 const current=array(record.optional_features_catalog);
 const index=current.findIndex(row=>row.id===known?.id&&
   String(row.plan_item_id||"")===String(known.plan_item_id||""));
 if(index<0)throw Error("Infusione non trovata.");
 const updated=structuredClone(current);updated.splice(index,1);
 const inventory=structuredClone(array(record.inventory));
 for(const item of inventory){
   const inf=item.infusion||{};
   if(inf.creator_id===record.id&&inf.id===known.id&&
     String(inf.plan_item_id||"")===String(known.plan_item_id||"")){
     delete item.infusion;item.attuned=false;item.attuned_count=0;
   }
 }
 return {optional_features_catalog:updated,inventory,
   prepared_features:array(record.prepared_features).filter(row=>!(row?.kind==="infusion"&&row.id===known.id))};
}

export const infusionInstanceOrigin=(item,index=0)=>
  "infusion:"+String(item?.infusion?.creator_id||"unknown")+"|"+
  String(item?.infusion?.id||"unknown")+"|"+
  String(item?.instance_id||item?.id||index);
export function activeInfusions(record={},definitions=[],features=[]){
 const source=infusionGrantingTrait(record,features);
 return array(record.inventory).flatMap((owned,index)=>{
   const inf=owned?.infusion;
   if(!inf?.id||Number(owned.quantity??1)<=0||owned.disabled||owned.active===false)return [];
   // Carried items without a slot are automatically in use.
   if(["weapon","shield","armor"].includes(itemKind(owned))&&
      !array(owned.equipped_slots).length)return [];
   if(requiresAttunement(resolveOwnedItem(owned))&&!itemAttunementCount(owned))return [];
   if(inf.creator_id===record.id&&!source)return [];
   const definition=array(definitions).find(row=>row.id===inf.id);
   if(!definition)return [];
   return [{id:infusionInstanceOrigin(owned,index),index,item:owned,infusion:inf,
     name:definition.name,definition,origin_id:inf.origin_id||source?.origin_id||""}];
 });
}
export function infusionNumericBonuses(record,item,definitions=[],features=[]){
 const inf=item?.infusion;
 if(!inf?.id||inf.creator_id===record.id&&!infusionGrantingTrait(record,features))return {};
 const row=array(definitions).find(r=>r.id===inf.id);
 const data=row?.numeric_item_bonuses;
 if(!data||!infusionEligible(row,item))return {};
 const level=inf.creator_id===record.id&&artificerLevel(record)>=2?
   artificerLevel(record):Math.max(0,Number(inf.level)||0);
 if(level<Number(row.min_level||2))return {};
 const selector=data.item_selector||{};
 if(array(selector.item_types).length&&!selector.item_types.includes(String(item.type||"").split("|")[0].toUpperCase()))return {};
 const mult=level>=Number(data.upgrade_level||99)?2:1;
 return Object.fromEntries(["bonus_ac","bonus_weapon","bonus_spell_attack"]
  .filter(key=>Number.isFinite(Number(data[key])))
  .map(key=>[key,Number(data[key])*mult]));
}

export function hasProperty(item,code){
  return Array.isArray(item?.properties) && item.properties.some(value=>
    String(value).split("|")[0].trim().toUpperCase()===code);
}
export function validSlot(item,slot){
  const kind=itemKind(item);
  return (kind==="weapon"&&["main","off"].includes(slot)&&
    (slot==="main"||!hasProperty(item,"2H"))) ||
    (kind==="shield"&&["main","off"].includes(slot)) ||
    (kind==="armor"&&slot==="body");
}
export function equipSlot(inventory,slot,index,{allowOffhandWithTwoHanded=false}={}){
  if(!["main","off","body"].includes(slot))throw Error("Slot equipaggiamento non valido.");
  const rows=structuredClone(Array.isArray(inventory)?inventory:[]);
  if(index!==-1&&(!Number.isInteger(index)||index<0||index>=rows.length||
    !validSlot(rows[index],slot)))throw Error("Oggetto incompatibile con lo slot.");
  // This explicit character option relaxes the occupied off hand; a 2H
  // weapon itself is still never a valid offhand weapon.
  if(slot==="off"&&!allowOffhandWithTwoHanded&&index>=0&&
    rows.some(row=>array(row.equipped_slots).includes("main")&&hasProperty(row,"2H")))
    throw Error("Mano secondaria occupata da un'arma a due mani.");
  const twoHanded=index>=0&&hasProperty(rows[index],"2H");
  for(const row of rows){
    const slots=Array.isArray(row.equipped_slots)?row.equipped_slots:[];
    row.equipped_slots=slots.filter(v=>v!==slot&&
      !(slot==="main"&&twoHanded&&!allowOffhandWithTwoHanded&&v==="off")&&
      !(slot==="off"&&!allowOffhandWithTwoHanded&&hasProperty(row,"2H")&&v==="main"));
  }
  if(index>=0){
    const row=rows[index],slots=row.equipped_slots;
    if(Number(row.quantity??1)<2&&slots.length&&!slots.includes(slot))slots.length=0;
    if(!slots.includes(slot))slots.push(slot);
  }
  const used=new Set();
  for(const row of rows){
    const slots=[];
    for(const candidate of row.equipped_slots){
      if(!used.has(candidate)&&validSlot(row,candidate)&&slots.length<Number(row.quantity??1)){
        slots.push(candidate);used.add(candidate);
      }
    }
    row.equipped_slots=slots;
  }
  const main=rows.find(row=>row.equipped_slots.includes("main"));
  if(main&&hasProperty(main,"2H")&&!allowOffhandWithTwoHanded)
    for(const row of rows)row.equipped_slots=row.equipped_slots.filter(v=>v!=="off");
  return rows;
}

/** One equipment state shared by the inventory and the corresponding item trait. */
export function setItemEquipped(inventory,index,enabled,{allowOffhandWithTwoHanded=false}={}){
  const rows=structuredClone(Array.isArray(inventory)?inventory:[]);
  const item=rows[index];
  if(!item)throw Error("Oggetto non trovato.");
  const kind=itemKind(item);
  if(kind==="document")throw Error("Un documento non è equipaggiabile.");
  if(!enabled){
    item.equipped=false;
    item.equipped_slots=[];
    return rows;
  }
  if(["weapon","shield","armor"].includes(kind)){
    const slot=kind==="armor"?"body":kind==="shield"?"off":"main";
    return equipSlot(rows,slot,index,{allowOffhandWithTwoHanded});
  }
  item.equipped=true;
  return rows;
}
