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
// Presentation only: keep item catalog identity and editable base name intact.
export function ownedItemDisplayName(item={}){
 const base=String(item.name||item.id||'Oggetto'),extension=[item.infusion?.name,...array(item.option_extensions).map(e=>e.name)].filter(Boolean).join(' · ');
 return extension?base+' - '+extension:base;
}
export function resolveOwnedItem(saved={}){
  const effective={...saved},overrides=saved?.instance_overrides;
  if(overrides&&typeof overrides==="object"&&!Array.isArray(overrides))
    for(const key of ITEM_INSTANCE_FIELDS)
      if(Object.hasOwn(overrides,key))effective[key]=structuredClone(overrides[key]);
  if(saved?.infusion?.requires_attunement===true||array(saved?.option_extensions).some(effect=>effect.requires_attunement===true))effective.req_attune=true;
  for(const extension of array(saved?.option_extensions).filter(row=>row.generic_variant)){
    const inherits=extension.definition?.inherits||{};
    const props=array(effective.properties).filter(p=>!array(inherits.propertyRemove).some(r=>String(r).split('|')[0]===String(p).split('|')[0]));
    effective.properties=[...props,...array(inherits.propertyAdd).filter(p=>!props.some(r=>String(r).split('|')[0]===String(p).split('|')[0]))];
    if(inherits.rarity)effective.rarity=inherits.rarity;
  }
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
      !row.infusion&&!array(row.option_extensions).length&&row.standalone_instance!==true&&itemAttunementCount(row)===0&&row.attuned!==true&&
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


const variantWords={
 sword:/sword|rapier|scimitar|sabre|saber|cutlass/i,
 axe:/axe|hatchet|halberd/i,bow:/bow/i,crossbow:/crossbow/i,
 spear:/spear|pike|trident/i,polearm:/glaive|halberd|pike|polearm/i,
 net:/^net$/i,arrow:/arrow/i,bolt:/bolt/i,bulletFirearm:/bullet/i,cellEnergy:/energy cell/i
};
const variantSame=(actual,expected)=>Array.isArray(expected)?
 expected.some(value=>variantSame(actual,value)):
 String(actual??'').trim().toLowerCase()===String(expected??'').trim().toLowerCase();
function variantField(item,field){
 const kind=itemKind(item);
 if(field==='weapon')return kind==='weapon';
 if(field==='armor')return kind==='armor';
 if(field==='property')return array(item.properties);
 if(field==='weaponCategory')return item.weaponCategory||item.weapon_category;
 if(field==='scfType')return item.scfType||item.scf_type;
 if(Object.hasOwn(variantWords,field))return Boolean(item[field]??(kind==='weapon'&&variantWords[field].test(String(item.name||''))));
 return item[field];
}
function variantRequirement(item,requirements){
 return Object.entries(requirements||{}).every(([field,expected])=>{
  const actual=variantField(item,field);
  if(field==='property')return (Array.isArray(expected)?expected:[expected]).some(value=>array(actual).some(p=>variantSame(String(p).split('|')[0],String(value).split('|')[0])));
  if(field==='type'){
   const [type,source]=String(expected).split('|');
   return variantSame(String(item.type||'').split('|')[0],type)&&(!source||variantSame(item.source,source));
  }
  if(typeof expected==='boolean')return Boolean(actual)===expected;
  return variantSame(actual,expected);
 });
}
export function genericVariantMatches(item,variant){
 if(!item||itemKind(item)==='document'||!array(variant?.requires).length)return false;
 const base=resolveOwnedItem({...item,option_extensions:[]});
 return variant.requires.some(requirement=>variantRequirement(base,requirement))&&
  !Object.entries(variant.excludes||{}).some(([field,value])=>variantRequirement(base,{[field]:value}));
}
export function genericVariantPatch(record,index,variant,add=true){
 const inventory=structuredClone(array(record.inventory)),selected=inventory[index];
 if(!Number.isInteger(index)||index<0||!selected||!variant?.id)throw Error('Oggetto o variante non disponibile.');
 const id=String(variant.id),attached=array(selected.option_extensions);
 if(add){
  if(!genericVariantMatches(selected,variant))throw Error('Variante incompatibile con questo oggetto.');
  if(attached.some(x=>x.id===id))throw Error('Variante già applicata.');
  if(Number(selected.quantity??1)>1){
   const quantity=Math.floor(Number(selected.quantity)),single=structuredClone(selected),slots=array(selected.equipped_slots);
   selected.quantity=quantity-1;single.quantity=1;
   single.equipped_slots=slots.slice(0,1);selected.equipped_slots=slots.slice(1);
   single.equipped=single.equipped_slots.length>0;selected.equipped=selected.equipped_slots.length>0;
   const tuned=itemAttunementCount(selected);
   single.attuned_count=tuned>0?1:0;single.attuned=tuned>0;
   selected.attuned_count=Math.max(0,tuned-single.attuned_count);selected.attuned=selected.attuned_count>0;
   single.instance_id='pwa_instance_'+crypto.randomUUID();single.standalone_instance=true;
   inventory.splice(++index,0,single);
  }
  const copy=inventory[index],inherits=variant.inherits||{},numeric={};
  for(const [field,source] of [['bonus_ac','bonusAc'],['bonus_weapon','bonusWeapon'],['bonus_weapon_attack','bonusWeaponAttack'],['bonus_weapon_damage','bonusWeaponDamage'],['bonus_spell_attack','bonusSpellAttack']]){
   const raw=String(inherits[source]??'').trim();
   if(/^[+-]?\d+$/.test(raw))numeric[field]=Number(raw);
  }
  const description=array(inherits.entries).concat(array(variant.entries)).map(entry=>
   typeof entry==='string'?entry.replace(/\{=(\w+)\}/g,(_,key)=>String(inherits[key]??'')):entry);
  copy.option_extensions=[...array(copy.option_extensions),{
   id,name:variant.name,source:variant.source,generic_variant:true,
   description,requires_attunement:Boolean(inherits.reqAttune||array(inherits.reqAttuneTags).length),
   definition:{id,name:variant.name,source:variant.source,inherits,
    ...(Object.keys(numeric).length?{numeric_item_bonuses:numeric}:{}),
    ...(Number(inherits.charges)>0?{charge_tracker:{max:Number(inherits.charges),recovery:String(inherits.recharge||'manual')}}:{})}
  }];
 }else{
  if(!attached.some(x=>x.id===id&&x.generic_variant))throw Error('Variante non applicata.');
  selected.option_extensions=attached.filter(x=>!(x.id===id&&x.generic_variant));
 }
 return {inventory,index};
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
  if(item.infusion?.requires_attunement===true||array(item.option_extensions).some(effect=>effect.requires_attunement===true))return true;
  const v=item.req_attune??item.reqAttune??item.requires_attunement??
    item.requiresAttunement??false;
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
export function clearInfusionPatch(record,index){
 const items=structuredClone(array(record.inventory));
 if(!items[index]?.infusion?.id)throw Error("Nessuna infusione da rimuovere.");
 const chargeId=infusionChargeTrackerId(items[index],index);
 delete items[index].infusion;items[index].attuned=false;items[index].attuned_count=0;
 return {inventory:items,...clearInfusionChargeSpent(record,[chargeId])};
}
export const infusionInstanceOrigin=(item,index=0)=>item?.infusion?
 'infusion:'+String(item.infusion.creator_id||'unknown')+'|'+String(item.infusion.id||'unknown')+'|'+String(item.instance_id||item.id||index):
 'item-option:'+String(item?.instance_id||item?.id||index)+':'+String(array(item?.option_extensions)[0]?.id||'');
export const itemOptionChargeTrackerId=(item,effect,index=0)=>
 effect?.legacy?'infusion-charges:'+infusionInstanceOrigin(item,index):
 'item-option-charges:'+String(item.instance_id||item.id||index)+':'+String(effect?.id||'');
export const infusionChargeTrackerId=(item,index=0)=>item.infusion?
 'infusion-charges:'+infusionInstanceOrigin(item,index):itemOptionChargeTrackerId(item,array(item.option_extensions)[0],index);
function clearInfusionChargeSpent(record,ids=[]){
 const previous=record.resource_tracker_spent||{},removed=new Set(ids.filter(Boolean));
 if(![...removed].some(id=>Object.hasOwn(previous,id)))return {};
 return {resource_tracker_spent:Object.fromEntries(
   Object.entries(previous).filter(([key])=>!removed.has(key)))};
}
// Item-bound charges remain available in inventory even if an infused
// shield, armor or weapon is temporarily not equipped or attuned.
export function infusionChargeTrackers(record={},definitions=[],features=[]){
 return array(record.inventory).flatMap((item,index)=>{
  const effects=[...array(item.option_extensions),...(item.infusion?[{...item.infusion,definition:array(definitions).find(d=>d.id===item.infusion.id),legacy:true}]:[])];
  return effects.flatMap(effect=>{
   const charge=effect.definition?.charge_tracker,max=Number(charge?.max);
   if(!Number.isSafeInteger(max)||max<1||max>1000||Number(item.quantity??1)<=0||item.disabled)return [];
   if(effect.legacy&&effect.creator_id===record.id&&!infusionGrantingTrait(record,features))return [];
   const id=itemOptionChargeTrackerId(item,effect,index),name=ownedItemDisplayName(item);
   return [{id,name:name+' · Cariche',max,recharge:'manual',recharge_note:charge.recovery||'',automatic:true,item_bound:true,inventory_index:index,
    origin_id:'tracker:auto:'+id,origin_name:'Oggetto · '+name}];
  });
 });
}
export function activeItemOptionEffects(record={},definitions=[],features=[]){
 return array(record.inventory).flatMap((owned,index)=>{
  if(Number(owned.quantity??1)<=0||owned.disabled||owned.active===false)return [];
  if(['weapon','shield','armor'].includes(itemKind(owned))&&!array(owned.equipped_slots).length)return [];
  if(requiresAttunement(owned)&&!itemAttunementCount(owned))return [];
  const effects=[...array(owned.option_extensions),...(owned.infusion?[{...owned.infusion,definition:array(definitions).find(d=>d.id===owned.infusion.id),legacy:true}]:[])];
  return effects.flatMap(effect=>{
   if(effect.legacy&&effect.creator_id===record.id&&!infusionGrantingTrait(record,features))return [];
   if(effect.origin_id&&(record.origin_enabled?.[effect.origin_id]===false||!features.some(f=>f.origin_id===effect.origin_id&&!f.disabled&&!f.inactive)))return [];
   const definition=effect.definition;if(!definition)return [];
   const id=effect.legacy?infusionInstanceOrigin(owned,index):'item-option:'+String(owned.instance_id||owned.id)+':'+effect.id;
   return [{id,index,item:owned,option_id:effect.id,tracker_id:itemOptionChargeTrackerId(owned,effect,index),infusion:{...effect,id:definition.id,creator_id:effect.creator_id||record.id},name:effect.name||definition.name,definition,origin_id:effect.origin_id||''}];
  });
 });
}
export const activeInfusions=activeItemOptionEffects;
export function itemOptionNumericEffects(record,item,definitions=[],features=[]){
 return activeItemOptionEffects({...record,inventory:[item]},definitions,features).flatMap(active=>{
  const data=active.definition.numeric_item_bonuses;if(!data)return [];
  const selector=data.item_selector||{};
  if(array(selector.item_types).length&&!selector.item_types.includes(String(item.type||'').split('|')[0].toUpperCase()))return [];
  const level=active.infusion.level||artificerLevel(record),mult=level>=Number(data.upgrade_level||99)?2:1;
  return [{...active,bonuses:Object.fromEntries(['bonus_ac','bonus_weapon','bonus_weapon_attack','bonus_weapon_damage','bonus_spell_attack'].filter(key=>Number.isFinite(Number(data[key]))).map(key=>[key,Number(data[key])*mult]))}];
 });
}
export function itemOptionNumericBonuses(record,item,definitions=[],features=[]){
 const result={};for(const effect of itemOptionNumericEffects(record,item,definitions,features))
  for(const [key,value] of Object.entries(effect.bonuses))result[key]=(result[key]||0)+value;
 return result;
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

// Legacy API name retained for native/import parity tests.
export const infusionNumericBonuses=itemOptionNumericBonuses;
