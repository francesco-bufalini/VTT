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
