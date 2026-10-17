// Native-compatible inventory item instance helpers.
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
export function resolveOwnedItem(saved={}){
  const effective={...saved},overrides=saved?.instance_overrides;
  if(overrides&&typeof overrides==="object"&&!Array.isArray(overrides))
    for(const key of ITEM_INSTANCE_FIELDS)
      if(Object.hasOwn(overrides,key))effective[key]=structuredClone(overrides[key]);
  if(saved?.infusion?.requires_attunement===true)effective.req_attune=true;
  return effective;
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
    rows[index].quantity=Number(item.quantity)-1;
    const one=structuredClone(item);
    one.quantity=1;one.equipped_slots=[];one.equipped=false;one.attuned=false;
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

export function requiresAttunement(item={}){
  const v=item.req_attune??item.reqAttune??item.infusion?.requires_attunement??false;
  return v===true||(typeof v==="string"&&v.trim().length>0);
}
export const isCatalogItem=item=>!!String(item?.id||"")&&!String(item.id).startsWith("local_");
export function createOwnedItem(entry,id){
  if(!entry||typeof entry!=="object"||!String(entry.id||"")||!String(entry.name||""))throw Error("Oggetto senza ID o nome.");
  const result=structuredClone(entry);
  delete result._category;delete result._homebrew;
  Object.assign(result,{instance_id:id,quantity:1,equipped:false,equipped_slots:[],attuned:false,active:true,instance_overrides:{}});
  return result;
}
export function changeOwnedItem(inventory,index,key,value){
  if(!Number.isInteger(index)||index<0||index>=array(inventory).length)throw Error("Oggetto non trovato.");
  if(!["quantity","equipped","attuned","active","name","description"].includes(key))throw Error("Campo non modificabile.");
  const items=structuredClone(inventory),item=items[index],kind=itemKind(item);
  if(!item||typeof item!=="object"||Array.isArray(item))throw Error("Oggetto non valido.");
  if(key==="quantity"){
    const qty=Number(value);
    if(!Number.isInteger(qty)||qty<1||qty>99999||kind==="document")throw Error("Quantità non valida.");
    item.quantity=qty;
  }else if(key==="equipped"){
    if(["weapon","armor","shield","document"].includes(kind))throw Error("Equipaggia da Battaglia.");
    item.equipped=Boolean(value);
  }else if(key==="attuned"){
    if(!requiresAttunement(item))throw Error("Oggetto senza sintonia.");
    item.attuned=Boolean(value);
  }else if(key==="active")item.active=Boolean(value);
  else{
    if(isCatalogItem(item)||typeof value!=="string"||value.length>(key==="name"?160:12000)||
      (key==="name"&&!value.trim()))throw Error("Campo non modificabile.");
    item[key]=value;
  }
  return items;
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
export function equipSlot(inventory,slot,index){
  if(!["main","off","body"].includes(slot))throw Error("Slot equipaggiamento non valido.");
  const rows=structuredClone(Array.isArray(inventory)?inventory:[]);
  if(index!==-1&&(!Number.isInteger(index)||index<0||index>=rows.length||
    !validSlot(rows[index],slot)))throw Error("Oggetto incompatibile con lo slot.");
  const twoHanded=index>=0&&hasProperty(rows[index],"2H");
  for(const row of rows){
    const slots=Array.isArray(row.equipped_slots)?row.equipped_slots:[];
    row.equipped_slots=slots.filter(v=>v!==slot&&
      !(slot==="main"&&twoHanded&&v==="off")&&
      !(slot==="off"&&hasProperty(row,"2H")&&v==="main"));
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
  if(main&&hasProperty(main,"2H"))
    for(const row of rows)row.equipped_slots=row.equipped_slots.filter(v=>v!=="off");
  return rows;
}
