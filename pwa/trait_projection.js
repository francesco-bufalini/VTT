import {effectiveBackgrounds} from './structured_effects.js';
// Read-only portable counterpart of CreatureFeatures.collect_features in the desktop.
// Do not infer mechanics from descriptions: this projection only decides which
// owned/level-available traits the PWA lists. Structured effects remain separate.
import {localClasses} from './sheet_rules.js';
import {activeInfusions,infusionInstanceOrigin,itemKind,requiresAttunement,resolveOwnedItem,inventoryAttunementCounts} from './item_controls.js';
import {traitIsActive} from './trait_benefit_editor.js';
import {conditionOptions,conditionDescriptionHtml,exhaustionLevel,exhaustionConditionRows} from './condition_catalog.js';

const arr=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
const same=(a,b)=>norm(a)===norm(b);
const levelOf=value=>Math.max(0,Math.trunc(Number(value)||0));
const CATEGORIES=['stati','razza','background','classi','talenti','incantesimi','oggetti','mostro','altro'];
export const TRAIT_CATEGORIES={
 stati:'STATI ATTIVI',razza:'RAZZA E SOTTORAZZA',background:'BACKGROUND',classi:'CLASSI E SOTTOCLASSI',
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
   localClasses(record).reduce((total,c)=>total+levelOf(c.level),0)||levelOf(record.level)||1;
 return current>=threshold&&current<=maximum;
}
function sourceDisabled(record,id){
 return record.origin_enabled?.[id]===false||
   arr(record.proficiency_origins).some(row=>row?.id===id&&row.disabled);
}

// Dependency injection keeps the rules testable without IndexedDB, HTTP or Godot.
export async function collectTraitRows(record={},calculated={},providers={}){
 const {entries=async()=>[],detail=async(_category,row)=>row,isDocument=()=>false,
  conditionLabel=id=>String(id).replaceAll('_',' '),conditionCatalog=null,spells=[]}=providers;
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
  const compatibleOrigins=new Set([norm(origin_key)]);
  if(category==='razza'&&origin_key.startsWith('species|')&&record.species)
   compatibleOrigins.add('race|'+norm(record.species_source)+'|'+norm(record.species));
  if(category==='razza'&&origin_key.startsWith('subrace|')&&record.subrace)
   compatibleOrigins.add('subrace|'+norm(record.subrace_source)+'|'+norm(record.subrace));
  const projected=arr(calculated.features).find(row=>same(row.name,name)&&
   compatibleOrigins.has(norm(row.origin_key))&&levelOf(row.level)===at);
  const id=projected?.origin_id||entry.feature_origin||'';
  const trait={name,entries:entry.entries??entry.entry??entry.description??'',
   source:entry.source||'',category,origin,origin_key,level:at,rank,
   item_quantity:Math.max(1,Number(entry.item_quantity)||1),
   item_active_quantity:Math.max(0,Number(entry.item_active_quantity)||0),
   item_requires_attunement:entry.item_requires_attunement===true,
   item_id:String(entry.item_id||''),item_inventory_indices:arr(entry.item_inventory_indices),
   item_base_origin:String(entry.item_base_origin||''),
   infusion_origin_id:String(entry.infusion_origin_id||''),
   feature_origin:id,key:origin_key+'|'+(entry.id||at+'|'+norm(name)),
   // Keep explicit activation metadata even for a standalone feat, item or
   // monster trait that has no separate calculated feature record.
   action_type:projected?.action_type||entry.action_type||entry.activation_type||entry.activation||'',
   activation_requirements:projected?.activation_requirements||entry.activation_requirements||'',
   resource_name:projected?.resource_name||entry.resource_name||''};
  // A calculated disabled flag is not a user decision. Treat privileges as
  // enabled by default; only an explicit owner/trait override can dim them.
  rows.push({...trait,inactive:Boolean(inactive||!traitIsActive(record,trait)||
    sourceDisabled(record,origin_key))});
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
 if(record.kind==='monster'||record.variant_rules_kind==='monster'){
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
  const baseRace=await lookup('races',record.species,record.species_source,record.species_id);
  const race=baseRace||selected;
  if(race){
   const key='species|'+(record.species_id||norm(record.species))+'|'+norm(record.species_source);
   const options={category:'razza',origin:'Specie · '+record.species,origin_key:key,level:1};
   // Species and subrace own distinct feature lists and grant origins.
   // Never place subrace-only features into the base species tier.
   const story=(arr(baseRace?.fluff).length?baseRace.fluff:null)??
    (arr(selected?.fluff).length?selected.fluff:null)??
    baseRace?.description??selected?.description??baseRace?.entries??'';
   add({name:'Descrizione · '+record.species,entries:story,source:baseRace?.source||race.source},
    {...options,rank:0});
   if(baseRace)named(baseRace,options,{includeUnnamed:true,requireGates:true});
   if(record.subrace){
    const subopts={...options,origin:'Sottorazza · '+record.subrace,
     origin_key:'subrace|'+norm(record.subrace_source)+'|'+norm(record.subrace)};
    // The base lore is already displayed above; the subrace overview
    // contains only its own lore and its own structured benefits.
    const substory=(arr(selected?.fluff).length?selected.fluff:null)??
     selected?.description??'';
    add({name:'Descrizione · '+record.subrace,entries:substory,
     source:selected?.source||record.subrace_source||''},{...subopts,rank:0});
    if(selected)named(selected,subopts,{includeUnnamed:true,requireGates:true});
   }
  }
 }
 for(const selection of effectiveBackgrounds(record)){
  const background=await lookup('backgrounds',selection.name,selection.source,selection.id);
  if(background){
   const options={category:'background',origin:'Background · '+selection.name,
    origin_key:'background|'+norm(background.source||selection.source)+'|'+norm(selection.name),level:1};
   add({name:'Descrizione · '+selection.name,entries:background.entries??background.description??'',source:background.source}, {...options,rank:0});
   named(background,options);
   if(!arr(background.entries).some(e=>e&&typeof e==='object'&&e.name))
    add({name:'Tratti del background · '+selection.name,entries:background.entries||background.description,source:background.source}, {...options,rank:2});
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
 for(const raw of arr(record.feats_catalog)){
  const feat=typeof raw==='string'?{name:raw}:raw;
  if(!feat?.name)continue;
  const info=await lookup('feats',feat.name,feat.source,feat.id)||feat;
  const granting=feat.granted_by?arr(calculated.features).find(row=>row.origin_id===feat.granted_by):null;
  const otherOrigin=feat.granted_by?arr(calculated.origins).find(row=>row.id===feat.granted_by):null;
  const from=granting?granting.name+' (livello '+granting.level+')':
    feat.granting_origin_name||otherOrigin?.name||'';
  const owner=from?' · da '+from:'';
  const displayName=feat.name+(feat.spell_variant?' · '+String(feat.spell_variant).replace(/ Spells$/i,''):'');
  const options={category:'talenti',origin:'Talento · '+displayName+owner,
   origin_key:'feat|'+(feat.id||norm(feat.name)+'|'+norm(feat.source)),level:1,inactive:!!feat.disabled};
  add({name:displayName,entries:info.entries??info.description??'',source:feat.source,
   action_type:feat.action_type||info.action_type||info.activation||''},{...options,rank:0});
  const sections=arr(info.feature_sections).length?info.feature_sections:info.entries;
  arr(sections).forEach(section=>{
   if(!section?.name||(!section.entries&&!section.entry))return;
   const at=levelOf(section.requirements?.min_level??section.min_level??1);
   if(available(record,section,at))
    add(section,{...options,level:at,rank:2});
  });
 }
 // Non-infusion optional privileges (maneuvers, invocations, metamagic) are
 // still actual traits. Learned infusions are choices belonging to Infuse Item:
 // their benefits appear only on the enchanted inventory copy, never as a
 // separate "Privilegio opzionale" card.
 const infusionDefinitions=arr(calculated.infusion_catalog);
 const isInfusionOption=option=>Boolean(option&&(
  String(option.id||'').startsWith('infusion|tce|')||
  infusionDefinitions.some(def=>def.id===option.id||
    same(def.name,option.name)&&same(option.source||'TCE',def.source||'TCE'))));
 for(const optional of arr(record.optional_features_catalog)){
  if(!optional?.name||isInfusionOption(optional))continue;
  const ownId=optional.origin_id||'optional|'+norm(optional.source)+'|'+norm(optional.name);
  const details=await lookup('optional_features',optional.name,optional.source)||optional;
  add({name:optional.name,entries:details.entries??details.description??optional.entries??'',
    source:optional.source||details.source||'',feature_origin:ownId,
    action_type:optional.action_type||details.action_type||details.activation||'',
    resource_name:optional.resource_name||details.resource_name||''},
    {category:'altro',origin:'Privilegio opzionale · '+optional.name,
     origin_key:ownId,level:0,rank:2,inactive:!!optional.disabled});
 }
 for(const origin of arr(record.proficiency_origins)){
  if(origin?.group!=='spell'||!String(origin.id||'').startsWith('spell:'))continue;
  const spellId=String(origin.id).slice(6);
  const spells=await load('spells');
  const spell=spells.find(s=>s.id===spellId);
  if(spell)add(spell,{category:'incantesimi',origin:'Incantesimo · '+spell.name,
   origin_key:origin.id,level:1,inactive:!!origin.disabled});
 }
 // Ordinary copies of a catalog item share one trait. Infused copies are
 // separate physical instances: the infusion is part of that object's card,
 // not a second item, an optional-feature card, or a fabricated active state.
 const groupedItems=new Map();
 const attunements=calculated.attunements?.counts||inventoryAttunementCounts(record.inventory,
  calculated.values?.attunement_max??record.attunement_max_base??3);
 const effectiveInventory=arr(record.inventory).map((item,i)=>requiresAttunement(resolveOwnedItem(item))?
  {...item,attuned_count:attunements[i]||0,attuned:attunements[i]>0}:item);
 const activeByIndex=new Map(activeInfusions({...record,inventory:effectiveInventory},
  infusionDefinitions,calculated.features||[]).map(applied=>[applied.index,applied]));
 for(const [index,item] of arr(record.inventory).entries()){
  if(!item?.id||Number(item.quantity??1)<=0||isDocument(item))continue;
  const effective=resolveOwnedItem(item),needsAttunement=requiresAttunement(effective);
  const kind=itemKind(effective),slotted=['weapon','armor','shield'].includes(kind);
  const slots=arr(item.equipped_slots);
  const eligible=item.active!==false&&item.disabled!==true&&
    (!needsAttunement||attunements[index]>0);
  const inSlot=kind==='armor'?slots.includes('body'):
    slots.includes('main')||slots.includes('off');
  const active=eligible&&(!slotted||inSlot);
  const qty=Math.max(1,Math.floor(Number(item.quantity)||1)),id=String(item.id);
  const infusion=item.infusion?.id?item.infusion:null;
  const infusionName=infusion?
    infusionDefinitions.find(def=>def.id===infusion.id)?.name||infusion.name||'Infusione':'';
  const instanceOrigin=infusion?infusionInstanceOrigin(item,index):'';
  const groupKey=infusion?id+'|'+instanceOrigin:id;
  const group=groupedItems.get(groupKey)||{item,quantity:0,activeQuantity:0,
   slotted,needsAttunement:false,indices:[],infusionName,infusionOrigin:''};
  group.indices.push(index);
  group.needsAttunement||=needsAttunement;
  group.quantity+=qty;
  if(active){
   group.activeQuantity+=needsAttunement?attunements[index]:slotted?Math.min(qty,Math.max(1,slots.length)):qty;
   group.item=item;
  }
  // Only verified active infusions can attribute mechanical grants. An
  // unattuned copy retains the combined title but has no infusion benefits.
  if(activeByIndex.has(index))group.infusionOrigin=activeByIndex.get(index).id;
  groupedItems.set(groupKey,group);
 }
 for(const [groupKey,group] of groupedItems){
  const item=group.item,id=String(item.id);
  const info=await lookup('items',item.name||id,item.source||'',id)||item;
  if(isDocument(info))continue;
  const name=item.name||info.name||id,infused=Boolean(group.infusionName);
  const displayName=infused?name+' - '+group.infusionName:name;
  const originKey='item:'+groupKey;
  const options={category:'oggetti',origin:'Oggetto · '+displayName,
   origin_key:originKey,level:0,inactive:group.activeQuantity===0};
  const itemDescription=info.entries??info.description??item.entries??item.description??'';
  let description=itemDescription;
  if(infused){
   const infusionDetail=await lookup('optional_features',group.infusionName,item.infusion?.source||'TCE');
   const infusionDescription=infusionDetail?.entries??infusionDetail?.description??'';
   if(infusionDescription)
    description=[...arr(itemDescription).length?arr(itemDescription):itemDescription?[itemDescription]:[],
      ...arr(infusionDescription).length?arr(infusionDescription):[infusionDescription]];
  }
  add({name:displayName,entries:description,source:info.source||item.source,
   item_id:id,item_inventory_indices:group.indices,
   item_base_origin:'item:'+id,infusion_origin_id:group.infusionOrigin,
   item_quantity:group.quantity,item_active_quantity:group.activeQuantity,
   item_requires_attunement:group.needsAttunement,
   action_type:item.action_type||info.action_type||info.activation||''}, {...options,rank:0});
 }
 // Persistent effects share stable state-trait keys with the States cards.
 // These are read-only projections: native numeric/mechanical state is unchanged.
 const stateTrait=(id,name,description,extra={})=>{
  if(!id||rows.some(row=>row.key==='state|'+id))return;
  rows.push({name:String(name||id),entries:description||'',
   ...(extra.description_html?{description_html:extra.description_html}:{}),
   source:extra.source||'',category:'stati',origin:'Stato · '+String(name||id),
   origin_key:'state|'+id,key:'state|'+id,level:0,rank:0,
   feature_origin:String(extra.origin_id||''),state_id:extra.state_id||'',
   state_key:extra.state_key||'',condition_id:extra.condition_id||'',
   spell_id:extra.spell_id||'',infusion_id:extra.infusion_id||'',
   inactive:false,readonly:true});
 };
 const availableConditions=conditionOptions(conditionCatalog,record.rules_version,record.conditions||[]);
 const definitions=new Map(availableConditions.map(row=>[row.id,row]));
 for(const condition of arr(record.conditions)){
  if(!condition||condition==='exhaustion'||/^exhaustion:[1-6]$/.test(condition))continue;
  const definition=definitions.get(String(condition))||
    {id:String(condition),name:conditionLabel(condition),category:'conditions'};
  stateTrait('condition:'+condition,definition.label||conditionLabel(condition),
   definition.entries??definition.description??'Descrizione non disponibile nel catalogo locale.',{
    condition_id:String(condition),state_key:'condition:'+condition,
    description_html:conditionDescriptionHtml(definition)});
 }
 const exhaustion=exhaustionLevel(record);
 if(exhaustion){
  const row=exhaustionConditionRows(record.rules_version,definitions.get('exhaustion'))[exhaustion-1];
  stateTrait('condition:'+row.id,row.label,row.entries,{
   condition_id:row.id,state_key:'condition:'+row.id,
   description_html:conditionDescriptionHtml(row)});
 }
 const appliedSpells=arr(record.proficiency_origins).filter(origin=>
  origin?.group==='spell'&&String(origin.id||'').startsWith('spell:')&&
  !origin.disabled&&record.origin_enabled?.[origin.id]!==false);
 const effectiveSpells=new Map([
   ...arr(spells),...(appliedSpells.length?arr(await load('spells')):[])
  ].filter(row=>row?.id).map(row=>[String(row.id),row]));
 for(const origin of appliedSpells){
  const id=String(origin.id),spellId=id.slice(6),spell=effectiveSpells.get(spellId);
  stateTrait(id,String(spell?.name||origin.name||spellId),
   spell?.entries??spell?.entry??spell?.description??
    origin.description??'Descrizione dell’incantesimo non disponibile nel catalogo locale.',{
    origin_id:id,spell_id:spellId,state_key:id,source:spell?.source||''});
 }
 const activeFeatures=record.active_class_features||{};
 const effects=new Map(arr(calculated.active_feature_effects).filter(effect=>effect?.key)
  .map(effect=>[String(effect.key),effect]));
 for(const [key,active] of Object.entries(activeFeatures)){
  if(!active)continue;
  const effect=effects.get(key);
  const originId=String(active.origin_id||effect?.origin_id||'');
  const backing=rows.find(row=>row.category!=='stati'&&(
    originId&&row.feature_origin===originId||row.name===active.name));
  const feature=arr(calculated.features).find(row=>
    originId&&String(row.origin_id||'')===originId||row.name===active.name);
  const description=backing?.entries||feature?.entries||feature?.description||
    active.description||effect?.summary||'Descrizione della capacità non disponibile.';
  stateTrait(key,active.name||effect?.name||key,description,{
   origin_id:originId,state_key:key,
   state_id:key.startsWith('trait_state:')?key.slice('trait_state:'.length):''});
 }
 // Projected persistent effects may exist without a saved class-ability toggle.
 for(const effect of arr(calculated.active_feature_effects)){
  if(!effect?.effective)continue;
  const key=String(effect.key||effect.origin_id||'');
  stateTrait(key,effect.name,effect.summary,{
   origin_id:effect.origin_id,state_key:key,
   state_id:key.startsWith('trait_state:')?key.slice('trait_state:'.length):''});
 }
 // Keep explicitly calculated traits if a catalog is unavailable offline, and
 // cover portable grants absent from a descriptive index without duplicating.
 for(const feature of arr(calculated.features)){
  const originKey=String(feature.origin_key||'altro');
  // Do not resurrect item-only structured features for unequipped inventory,
  // and do not replace the full item description with partial effect text.
  if(originKey.startsWith('item:')||
    originKey.startsWith('optional|')&&isInfusionOption(feature))continue;
  const category=originKey.startsWith('class|')?'classi':
   originKey.startsWith('species|')||originKey.startsWith('race|')||
   originKey.startsWith('subrace|')?'razza':
   originKey.startsWith('background|')?'background':
   originKey.startsWith('feat|')?'talenti':
   originKey.startsWith('monster|')?'mostro':'altro';
  const normalizedKey=category==='razza'&&
    originKey==='race|'+norm(record.species_source)+'|'+norm(record.species)?
     'species|'+(record.species_id||norm(record.species))+'|'+norm(record.species_source):
     originKey;
  const origin=rows.find(r=>r.origin_key===normalizedKey)?.origin||
   arr(calculated.origins).find(o=>o.id===originKey)?.name||originKey.replaceAll('|',' · ');
  add(feature,{category,origin,origin_key:normalizedKey,level:feature.level||0,
   rank:2});
 }
 // Proficiencies remain benefits on their actual granting trait.
 // Origin-level grants belong to the existing class/species/background/feat
 // overview and feature-level grants to the matching concrete feature.
 // Manual proficiencies without a named origin are shown in Altre competenze.
 // Old trait_enabled["proficiency:<id>"] values are legacy metadata, not a
 // reason to recreate a separate and duplicated "Competenze" trait.
 rows.sort((a,b)=>
  CATEGORIES.indexOf(a.category)-CATEGORIES.indexOf(b.category)||
  (a.category==='razza'&&b.category==='razza'?
   Number(a.origin_key.startsWith('subrace|'))-Number(b.origin_key.startsWith('subrace|')):0)||
  a.origin.localeCompare(b.origin,'it',{sensitivity:'base',numeric:true})||
  a.level-b.level||a.rank-b.rank||
  a.name.localeCompare(b.name,'it',{sensitivity:'base',numeric:true}));
 return rows;
}

// Origin is the primary group, not level: each class/subclass owns a single
// visible section containing its own ordered level headings.
export function groupTraitRows(rows){
 const groups=[];
 for(const row of rows){
  let category=groups.find(group=>group.id===row.category);
  if(!category){
   category={id:row.category,title:TRAIT_CATEGORIES[row.category]||TRAIT_CATEGORIES.altro,origins:[]};
   groups.push(category);
  }
  let origin=category.origins.find(group=>group.key===row.origin_key);
  if(!origin){
   origin={key:row.origin_key,title:row.origin,levels:[]};
   category.origins.push(origin);
  }
  const level=['classi','razza'].includes(row.category)?row.level:-1;
  let tier=origin.levels.find(group=>group.level===level);
  if(!tier){tier={level,rows:[]};origin.levels.push(tier);}
  tier.rows.push(row);
 }
 return groups;
}

/**
 * Attach real calculated spell grants to the most specific visible owned
 * privilege. Never infer grants by scanning localized rule descriptions.
 * Race/background catalog descriptions can use a different origin ID than
 * the structured 5etools grant; in that case use their matching origin group.
 */
export function withGrantedSpellPreviews(rows=[],grants=[],spells=[]){
 const result=rows.map(row=>({...row,granted_spells:[]}));
 const catalogue=new Map(arr(spells).map(spell=>[String(spell.id),spell]));
 for(const grant of arr(grants)){
  if(!grant?.spell_id||grant.disabled)continue;
  const originId=String(grant.origin_id||'');
  const originName=norm(grant.origin_name);
  const explicitTrait=norm(grant.granting_trait);
  const parentName=norm(grant.origin_parent_name);
  // Never collapse a typed grant to a race/class overview if the named
  // granting trait is unavailable due to level gating or lazy loading.
  const ownedRows=explicitTrait?result.map((row,index)=>({row,index})):[];
  const explicitOwner=explicitTrait?(originId.startsWith('feature:')?
   ownedRows.find(({row})=>String(row.feature_origin||'')===originId):
   ownedRows.find(({row})=>norm(row.name)===explicitTrait&&
     (!parentName||norm(String(row.origin||'').split(' · ').pop())===parentName))):null;
  if(explicitTrait&&!explicitOwner)continue;
  const candidates=result.map((row,index)=>({row,index})).filter(({row})=>{
   const ownedId=String(row.origin_key||'');
   const display=norm(String(row.origin||'').split(' · ').pop());
   if(explicitTrait&&norm(row.name)===explicitTrait&&
     (!parentName||display===parentName))return true;
   return (originId&&
       (String(row.feature_origin||'')===originId||ownedId===originId||
         originId==='feature:trait:'+row.key))||
     (originName&&display===originName);
  });
  if(!candidates.length)continue;
  const selected=explicitOwner||candidates.find(({row})=>explicitTrait&&norm(row.name)===explicitTrait&&
    (!parentName||norm(String(row.origin||'').split(' · ').pop())===parentName))||
   candidates.find(({row})=>originId&&String(row.feature_origin||'')===originId)||
   candidates.find(({row})=>originName&&norm(row.name)===originName)||
   candidates.find(({row})=>/spellcasting|incantesim|magic|magia|legacy|eredità/i.test(row.name)&&
     !/^Descrizione ·/.test(row.name))||
   candidates.find(({row})=>/^Descrizione ·/.test(row.name))||
   candidates[0];
  const spell=catalogue.get(String(grant.spell_id));
  const id=String(grant.spell_id);
  if(selected.row.granted_spells.some(item=>item.id===id))continue;
  const rawLevel=spell?.level,level=rawLevel==null?null:Number(rawLevel);
  selected.row.granted_spells.push({id,origin_id:originId,name:String(spell?.name||grant.spell_name||id),
    level:Number.isInteger(level)&&level>=0&&level<=9?level:null});
 }
 for(const row of result)row.granted_spells.sort((a,b)=>(a.level??10)-(b.level??10)||
  a.name.localeCompare(b.name,'it',{sensitivity:'base'}));
 return result;
}
