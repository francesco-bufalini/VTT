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
