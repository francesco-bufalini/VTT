// Native StructuredResourceTrackers/class_resource_overrides rules in browser.
// Numeric 5etools class columns + a bundled, source-qualified FightClub
// supplement; never infer resources or recharge modes from feature prose.
import {artificerResources} from './feature_mechanics.js';
import {localClasses,parseArithmetic} from "./sheet_rules.js";
const arr=v=>Array.isArray(v)?v:[];
const norm=v=>String(v??"").trim().toLowerCase();
const subclassKey=v=>{
 let name=norm(v);
 for(const prefix of ["school of ","circle of ","oath of ","college of ","domain of ","way of the ","way of ","the "])
  if(name.startsWith(prefix))name=name.slice(prefix.length);
 for(const suffix of [" domain"," school"])if(name.endsWith(suffix))name=name.slice(0,-suffix.length);
 return name;
};
const integer=v=>Number.isFinite(Number(v))?Math.trunc(Number(v)):0;
const classId=(name,source,column)=>
  "class:"+norm(name)+":"+norm(source)+":"+norm(column).replaceAll(" ","_");
function maximum(value,record,classLevel,minimum,modifiers){
 if(typeof value==="number"&&Number.isFinite(value))
  return {max:Math.max(minimum,Math.trunc(value)),max_formula:""};
 const expression=String(value??"").trim().toLowerCase();
 if(!expression)return null;
 if(/^\d+$/.test(expression))return {max:Math.max(minimum,Number(expression)),max_formula:""};
 if(!/^[0-9a-z_ .+*/()-]+$/.test(expression))return null;
 try{
  const resolve=name=>{
   if(/^(str|dex|con|int|wis|cha)_mod$/.test(name)){
    const stat=name.slice(0,3);
    const mod=modifiers?.[stat];
    return Number.isFinite(Number(mod))?Number(mod):
      Math.floor((Number(record.abilities?.[stat]??10)-10)/2);
   }
   if(name==="proficiency")return 2+Math.floor((Math.max(1,integer(record.level||classLevel))-1)/4);
   if(name==="level")return integer(record.level||classLevel);
   throw Error("Simbolo sconosciuto: "+name);
  };
  return {max:Math.max(minimum,parseArithmetic(expression,resolve)),max_formula:expression};
 }catch{return null;}
}

let cachedOverrides;
export function loadClassResourceOverrides(){
 if(!cachedOverrides)cachedOverrides=fetch("/catalog/class_resource_overrides.json").then(r=>{
  if(!r.ok)throw Error("Progressioni delle risorse non disponibili offline.");
  return r.json();
 }).catch(error=>{cachedOverrides=null;throw error;});
 return cachedOverrides;
}

export function classResourceTrackers(record,classCatalog={},overrides={},modifiers={}){
 const result=new Map();
 for(const member of localClasses(record)){
  const name=String(member.name||"").trim();
  const source=String(member.source||"")||(record.rules_version==="2024"?"XPHB":"PHB");
  const level=integer(member.level);
  if(level<1||level>20)continue;
  const definition=arr(classCatalog.classes).find(row=>norm(row.name)===norm(name)&&norm(row.source)===norm(source));
  const resolvedSource=String(definition?.source||source);
  const columns=arr(definition?.columns);
  for(const column of columns){
   if(column.kind!=="resource")continue;
   const value=arr(column.levels)[level-1];
   if(typeof value!=="number"||!Number.isFinite(value)||value<=0)continue;
   const id=classId(name,resolvedSource,column.name);
   result.set(id,{id,name:String(column.name),max:Math.trunc(value),
    origin:String(column.origin_feature||column.name),origin_class:name,
    origin_class_source:resolvedSource,recharge:"manual",automatic:true});
  }
  if(norm(name)==='artificer'&&resolvedSource==='TCE'){
   const intelligence=Math.max(1,Number(modifiers?.int??Math.floor((Number(record.abilities?.int??10)-10)/2)));
   const pb=2+Math.floor((Math.max(1,integer(record.level||level))-1)/4);
   for(const resource of artificerResources(level,intelligence,pb,member.subclass||record.subclass)){
    const id=classId(name,resolvedSource,resource.name);
    result.set(id,{id,...resource,recharge:'long_rest',origin_class:name,
      origin_class_source:resolvedSource,origin_subclass:resource.subclass,automatic:true});
   }
  }
  const group=arr(overrides.classes).find(row=>norm(row.class)===norm(name)&&norm(row.source)===norm(resolvedSource));
  for(const entry of arr(group?.resources)){
   if(entry.subclass&&subclassKey(entry.subclass)!==
     subclassKey(member.subclass||record.subclass))continue;
   const steps=arr(entry.steps).filter(s=>Number(s?.level)<=level)
     .sort((a,b)=>Number(b.level)-Number(a.level));
   if(!steps.length)continue;
   const step=steps[0];
   const computed=maximum(step.value,record,level,integer(entry.minimum),modifiers);
   if(!computed||computed.max<=0)continue;
   const columnName=String(entry.column||entry.name||"");
   if(!columnName)continue;
   const native=columns.find(col=>norm(col.name)===norm(columnName));
   if(native){
    const value=arr(native.levels)[level-1];
    // 'unlimited' and empty class-table values must not become finite.
    if(typeof value!=="number"||value<=0)continue;
   }
   const id=classId(name,resolvedSource,columnName);
   const existing=result.get(id);
   if(existing)existing.recharge=String(step.reset||"manual");
   else result.set(id,{id,name:String(entry.name||columnName),max:computed.max,
    max_formula:computed.max_formula,recharge:String(step.reset||"manual"),
    origin:String(entry.origin_feature||columnName),
    origin_class:name,origin_class_source:resolvedSource,
    origin_subclass:String(entry.subclass||""),automatic:true});
  }
 }
 // Saved resources remain user-owned and keep their own IDs/usage counters.
 for(const row of arr(record.resource_trackers)){
  if(!row||typeof row!=="object"||!row.id||!row.name||row.disabled||
     result.has(String(row.id)))continue;
  // Unknown formula is left at the explicit saved max; never evaluated as JS.
  let max=Math.max(0,integer(row.max));
  const calculated=row.max_formula?
    maximum(row.max_formula,record,integer(record.level),0,modifiers):null;
  if(calculated)max=calculated.max;
  result.set(String(row.id),{...structuredClone(row),max,automatic:false});
 }
 return [...result.values()];
}
