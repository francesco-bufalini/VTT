// Matches vtt/document_homebrew.gd: documents are homebrew definitions
// referenced by ordinary owned inventory copies, not freeform item metadata.
export const DOCUMENT_PREFIX="homebrew:vttdoc:documents:";
export const MAX_DOCUMENT_TITLE=160;
export const MAX_DOCUMENT_BODY=3500;

export function isDocument(item={}){
  return item?.category==="documents"||String(item?.id||"").includes(":documents:");
}
export function documentStyle(value){
  return value==="lettera"?"lettera":"pergamena";
}
export function editDocumentDefinition(definition,title,body){
  if(!definition||typeof definition!=="object"||Array.isArray(definition)||
    !String(definition.id||"").includes(":documents:"))
    throw Error("Definizione documento non valida.");
  if(typeof title!=="string"||typeof body!=="string")
    throw Error("Titolo e testo non validi.");
  if(title.trim().length>MAX_DOCUMENT_TITLE||body.length>MAX_DOCUMENT_BODY)
    throw Error("Limite documento: 160 caratteri per il titolo, 3500 per il testo.");
  const name=title.trim()||"Senza titolo";
  return {...structuredClone(definition),name,data:{
    ...structuredClone(definition.data||{}),description:body}};
}
export function createDocumentDefinition(localId,title="Nuovo documento",body=""){
  if(typeof localId!=="string"||!/^doc_[a-z0-9_-]{1,59}$/.test(localId))
    throw Error("Identificativo documento non valido.");
  return editDocumentDefinition({
    id:DOCUMENT_PREFIX+localId,category:"documents",name:"Nuovo documento",
    source:"VTTDOC",data:{description:""}
  },title,body);
}
export function createOwnedDocument(definition,instanceId,addedAt=Math.floor(Date.now()/1000)){
  if(!isDocument(definition)||!String(definition?.id||"").startsWith(DOCUMENT_PREFIX)||
    typeof instanceId!=="string"||!instanceId.startsWith("owned_doc_"))
    throw Error("Definizione o copia documento non valida.");
  return {
    id:definition.id,name:definition.name,source:definition.source||"VTTDOC",
    category:"documents",quantity:1,equipped_slots:[],instance_overrides:{},
    added_at:addedAt,display_style:"pergamena",instance_id:instanceId
  };
}
export function documentInfo(item,definition){
  const value=definition&&isDocument(definition)?definition:item||{};
  return {title:String(value.name||item?.name||"Senza titolo"),
    body:String(value.data?.description??value.description??value.text??item?.description??""),
    style:documentStyle(item?.display_style),addedAt:Number(item?.added_at)||0};
}
