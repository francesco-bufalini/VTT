// Read-only portable counterpart of CreatureFeatures.collect_features in the desktop.
// Do not infer mechanics from descriptions: this projection only decides which
// owned/level-available traits the PWA lists. Structured effects remain separate.
import {localClasses} from './sheet_rules.js';

const arr=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
const same=(a,b)=>norm(a)===norm(b);
const levelOf=value=>Math.max(0,Math.trunc(Number(value)||0));
const CATEGORIES=['razza','background','classi','talenti','incantesimi','oggetti','mostro','altro'];
export const TRAIT_CATEGORIES={
 razza:'RAZZA E SOTTORAZZA',background:'BACKGROUND',classi:'CLASSI E SOTTOCLASSI',
 talenti:'TALENTI',incantesimi:'INCANTESIMI ATTIVI',oggetti:'OGGETTI',
 mostro:'TRATTI DEL MOSTRO',altro:'ALTRI TRATTI'
};

function available(record,entry,level=1,classMember=null){
 const gate=entry?.requirements||{};
 const threshold=levelOf(gate.min_level??entry?.min_level??entry?.level??level);
 const maximum=gate.max_level==null?Infinity:levelOf(gate.max_level);
 const current=gate.scope==='class'&&gate.class_name?
   levelOf(localClasses(record).find(c=>same(c.name,gate.class_name)&&
     (!gate.class_source||same(c.source,gate.class_source)))?.level):
   classMember?levelOf(classMember.level):
   localClasses(record).reduce((total,c)=>total+levelOf(c.level),0)||levelOf(record.level);
 return current>=threshold&&current<=maximum;
}
function sourceDisabled(record,id){
 return record.origin_enabled?.[id]===false||
   arr(record.proficiency_origins).some(row=>row?.id===id&&row.disabled);
}

// Dependency injection keeps the rules testable without IndexedDB, HTTP or Godot.
export async function collectTraitRows(record={},calculated={},providers={}){
 const {entries=async()=>[],detail=async(_category,row)=>row,isDocument=()=>false}=providers;
 const rows=[],loaded=new Map(),used=new Set();
 const load=async category=>{
  if(!loaded.has(category))loaded.set(category,Promise.resolve().then(()=>entries(category)).catch(()=>[]));
  return arr(await loaded.get(category));
 };
 const lookup=async(category,name,source='',id='')=>{
  if(!name)return null;
  const matches=(await load(category)).filter(row=>
   (id&&row.id===id)||(same(row.name,name)&&(!source||same(row.source,source))));
  const selected=matches.find(row=>id&&row.id===id)||
    matches.find(row=>same(row.name,name)&&source&&same(row.source,source))||
    (matches.length===1?matches[0]:null);
  if(!selected)return null;
  try{return await detail(category,selected);}catch{return selected;}
 };
 const add=(entry,{category='altro',origin='Altro',origin_key='',level=1,rank=2,inactive=false}={})=>{
  const name=String(entry?.name||'').trim();
  if(!name)return;
  const at=levelOf(level),key=[origin_key,norm(name),at].join('|');
  if(used.has(key))return;
  used.add(key);
  const projected=arr(calculated.features).find(row=>same(row.name,name)&&
   same(row.origin_key,origin_key)&&levelOf(row.level)===at);
  const id=projected?.origin_id||'';
  rows.push({name,entries:entry.entries??entry.entry??entry.description??'',
   source:entry.source||'',category,origin,origin_key,level:at,rank,
   inactive:inactive||!!projected?.disabled||sourceDisabled(record,origin_key)||
     (id&&sourceDisabled(record,id)),
   // Only existing structured traits can be toggled; catalog text is read-only.
   feature_origin:id, key:origin_key+'|'+(entry.id||at+'|'+norm(name))});
 };
 const named=(entry,options,{includeUnnamed=false,requireGates=false}={})=>{
  arr(entry?.entries).forEach((part,index)=>{
   if(typeof part==='string'){
    if(includeUnnamed&&part.trim())add({name:'Tratto · '+(index+1),entries:part}, {...options,rank:1});
   }else if(part&&typeof part==='object'){
    if(requireGates&&!available(record,part,options.level))return;
    const name=part.name||(includeUnnamed?'Altri tratti · '+(index+1):'');
    if(name&&(part.entries!==undefined||part.entry!==undefined||includeUnnamed))
     add({...part,name}, {...options,level:levelOf(part.level??part.requirements?.min_level??options.level),rank:options.rank??2});
   }
  });
 };
 if(record.kind==='monster'){
  const sectionNames={trait:'Tratti',action:'Azioni',bonus:'Azioni bonus',
   reaction:'Reazioni',legendary:'Azioni leggendarie',mythic:'Azioni mitiche',
   lairActions:'Azioni della tana'};
  for(const [section,label] of Object.entries(sectionNames))
   arr(record.stat_block?.[section]).forEach((entry,i)=>add(
    typeof entry==='string'?{name:label+' · '+(i+1),entries:entry}:
     {...entry,name:entry?.name||label+' · '+(i+1)},
    {category:'mostro',origin:'Mostro · '+label,origin_key:'monster|'+section,level:0,rank:0}));
 }else if(record.species){
  const selected=record.subrace?
   await lookup('races',record.species+' ('+record.subrace+')',record.subrace_source):null;
  const race=selected||await lookup('races',record.species,record.species_source,record.species_id);
  if(race){
   const key='species|'+(record.species_id||norm(record.species))+'|'+norm(record.species_source);
   const options={category:'razza',origin:'Specie · '+record.species,origin_key:key,level:1};
   add({name:'Descrizione · '+record.species,entries:race.entries??race.description??'',source:race.source},
    {...options,rank:0});
   named(race,options,{includeUnnamed:true});
  }
 }
 if(record.background){
  const background=await lookup('backgrounds',record.background,record.background_source,record.background_id);
  if(background){
   const options={category:'background',origin:'Background · '+record.background,
    origin_key:'background|'+norm(background.source||record.background_source)+'|'+norm(record.background),level:1};
   add({name:'Descrizione · '+record.background,entries:background.entries??background.description??'',source:background.source}, {...options,rank:0});
   named(background,options);
   if(!arr(background.entries).some(e=>e&&typeof e==='object'&&e.name))
    add({name:'Tratti del background · '+record.background,entries:background.entries||background.description,source:background.source},
     {...options,rank:2});
  }
 }
 const classes=localClasses(record).filter(c=>c?.name&&norm(c.name)!=='mostro');
 if(classes.length){
  const classFeatures=await load('class_features'),subFeatures=await load('subclass_features');
  for(const member of classes){
   const book=member.source||record.class_source||(record.rules_version==='2024'?'XPHB':'PHB');
   const base='class|'+norm(book)+'|'+norm(member.name);
   const options={category:'classi',origin:'Classe · '+member.name,origin_key:base,level:1};
   const description=await lookup('classes',member.name,book);
   if(description){
    add({name:'Descrizione · '+member.name,entries:description.entries??description.description??'',source:book},{...options,rank:0});
    named(description,options);
   }
   for(const feature of [...classFeatures,...arr(member.features)]){
    if(!same(feature.class_name||feature.className||member.name,member.name)||
       feature.class_source&&!same(feature.class_source,book))continue;
    const at=levelOf(feature.level||1);
    if(at<1||at>levelOf(member.level)||!available(record,feature,at,member))continue;
    add(feature,{...options,level:at,rank:2});
   }
   if(!member.subclass)continue;
   const subbook=member.subclass_source||'';
   const subkey=base+'|subclass|'+norm(member.subclass)+'|'+norm(subbook);
   const subopts={...options,origin:'Sottoclasse · '+member.name+' / '+member.subclass,origin_key:subkey};
   const sub=await lookup('subclasses',member.subclass,subbook);
   if(sub)add({name:'Descrizione · '+member.subclass,entries:sub.entries??sub.description??'',source:subbook},
    {...subopts,rank:0});
   for(const feature of [...subFeatures,...arr(member.subclass_features)]){
    if(!same(feature.class_name||feature.className||member.name,member.name)||
       feature.class_source&&!same(feature.class_source,book)||
       (feature.subclass_name||feature.subclass_short_name||feature.subclassName)&&
        ![feature.subclass_name,feature.subclass_short_name,feature.subclassName].some(n=>same(n,member.subclass))||
       subbook&&feature.subclass_source&&!same(feature.subclass_source,subbook))continue;
    const at=levelOf(feature.level||1);
    if(at<1||at>levelOf(member.level)||!available(record,feature,at,member))continue;
    add(feature,{...subopts,level:at,rank:2});
   }
  }
 }
 for(const feat of arr(record.feats_catalog)){
  if(!feat?.name)continue;
  const info=await lookup('feats',feat.name,feat.source,feat.id)||feat;
  const options={category:'talenti',origin:'Talento · '+feat.name,
   origin_key:'feat|'+(feat.id||norm(feat.name)+'|'+norm(feat.source)),level:1,inactive:!!feat.disabled};
  add({name:feat.name,entries:info.entries??info.description??'',source:feat.source},{...options,rank:0});
  const sections=arr(info.feature_sections).length?info.feature_sections:info.entries;
  arr(sections).forEach(section=>{
   if(!section?.name||(!section.entries&&!section.entry))return;
   const at=levelOf(section.requirements?.min_level??section.min_level??1);
   if(available(record,section,at))
    add(section,{...options,level:at,rank:2});
  });
 }
 for(const origin of arr(record.proficiency_origins)){
  if(origin?.group!=='spell'||!String(origin.id||'').startsWith('spell:'))continue;
  const spellId=String(origin.id).slice(6);
  const spells=await load('spells');
  const spell=spells.find(s=>s.id===spellId);
  if(spell)add(spell,{category:'incantesimi',origin:'Incantesimo · '+spell.name,
   origin_key:origin.id,level:1,inactive:!!origin.disabled});
 }
 const items=new Map();
 for(const item of arr(record.inventory)){
  if(!item?.id||Number(item.quantity??1)<=0||isDocument(item))continue;
  const id=String(item.id),old=items.get(id);
  if(old)old.quantity+=Number(item.quantity??1);
  else items.set(id,{item,quantity:Number(item.quantity??1)});
 }
 for(const [id,{item,quantity}] of items){
  const info=await lookup('items',item.name||id,item.source||'',id)||item;
  if(isDocument(info))continue;
  const options={category:'oggetti',origin:'Oggetto · '+(item.name||info.name||id),
   origin_key:'item:'+id,level:0,inactive:item.disabled===true};
  add({name:'Descrizione · '+(item.name||info.name||id)+(quantity>1?' ×'+quantity:''),
   entries:info.entries??info.description??item.description??'',source:info.source},{...options,rank:0});
  named(info,options,{requireGates:true});
 }
 // Keep explicitly calculated traits if a catalog is unavailable offline, and
 // cover portable grants absent from a descriptive index without duplicating.
 for(const feature of arr(calculated.features)){
  const originKey=String(feature.origin_key||'altro');
  const category=originKey.startsWith('class|')?'classi':
   originKey.startsWith('species|')||originKey.startsWith('race|')?'razza':
   originKey.startsWith('background|')?'background':
   originKey.startsWith('feat|')?'talenti':
   originKey.startsWith('monster|')?'mostro':'altro';
  const origin=rows.find(r=>r.origin_key===originKey)?.origin||
   arr(calculated.origins).find(o=>o.id===originKey)?.name||originKey.replaceAll('|',' · ');
  add(feature,{category,origin,origin_key:originKey,level:feature.level||0,
   rank:2,inactive:!!feature.disabled});
 }
 rows.sort((a,b)=>
  CATEGORIES.indexOf(a.category)-CATEGORIES.indexOf(b.category)||
  a.level-b.level||a.rank-b.rank||
  a.origin.localeCompare(b.origin,'it',{sensitivity:'base',numeric:true})||
  a.name.localeCompare(b.name,'it',{sensitivity:'base',numeric:true}));
 return rows;
}

export function groupTraitRows(rows){
 const groups=[];
 for(const row of rows){
  let category=groups.find(group=>group.id===row.category);
  if(!category){category={id:row.category,title:TRAIT_CATEGORIES[row.category]||TRAIT_CATEGORIES.altro,levels:[]};groups.push(category);}
  const level=row.category==='classi'?row.level:-1;
  let tier=category.levels.find(group=>group.level===level);
  if(!tier){tier={level,origins:[]};category.levels.push(tier);}
  let origin=tier.origins.find(group=>group.key===row.origin_key);
  if(!origin){origin={key:row.origin_key,title:row.origin,rows:[]};tier.origins.push(origin);}
  origin.rows.push(row);
 }
 return groups;
}
