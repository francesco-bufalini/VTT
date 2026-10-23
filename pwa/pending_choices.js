// Structured, still-unresolved character choices. Mirrors the native
// creature_pending_choices.gd and creature_proficiency_rules.gd contracts.
// Never infer a choice from prose or assign a privilege automatically.
import {selectedSources,grantedFields,fixedProficiencies} from './structured_effects.js';
import {SKILLS} from './sheet_rules.js';
import {traitBenefitSources} from './trait_benefits.js';

const arr=x=>Array.isArray(x)?x:[];
const norm=x=>String(x??'').trim().toLowerCase();
const abilities=['str','dex','con','int','wis','cha'];
const kindNames={skill:'Abilità',expertise:'Maestria',save:'Tiri salvezza',
  weapon:'Armi',armor:'Armature',tool:'Strumenti',language:'Lingue'};
const kindFields=['weapon','armor','skill','expertise','save','tool','language'];
const artisanTools=['alchemist\'s supplies','brewer\'s supplies','calligrapher\'s supplies',
  'carpenter\'s tools','cartographer\'s tools','cobbler\'s tools','cook\'s utensils',
  'glassblower\'s tools','jeweler\'s tools','leatherworker\'s tools','mason\'s tools',
  'painter\'s supplies','potter\'s tools','smith\'s tools','tinker\'s tools',
  'weaver\'s tools','woodcarver\'s tools'];
const gamingSets=['dice set','dragonchess set','playing card set','three-dragon ante set'];
const instruments=['bagpipes','drum','dulcimer','flute','lute','lyre','horn','pan flute',
  'shawm','viol'];
const commonLanguages=['common','dwarvish','elvish','giant','gnomish','goblin',
  'halfling','orc','abyssal','celestial','draconic','deep speech','infernal',
  'primordial','sylvan','undercommon','aquan','auran','ignan','terran'];
const secretLanguages=new Set(['druidic','thieves\' cant']);
const exoticLanguages=new Set(['abyssal','celestial','draconic','deep speech','infernal',
  'primordial','sylvan','undercommon']);
const rareLanguages=new Set(['aquan','auran','ignan','terran']);
const martialWeapons=['battleaxe','flail','glaive','greataxe','greatsword','halberd',
  'lance','longsword','maul','morningstar','pike','rapier','scimitar','shortsword',
  'trident','war pick','warhammer','whip','blowgun','hand crossbow',
  'heavy crossbow','longbow','net'];
const strip=x=>norm(x).replace(/^\{@item\s+/,'').replace(/\}$/, '').split('|')[0].trim();
const enabled=(record,id)=>record.origin_enabled?.[id]!==false&&
  !arr(record.proficiency_origins).some(row=>row?.id===id&&row.disabled);
const presentRows=(record,id,kind)=>arr(record.proficiency_choices).filter(row=>
  row?.origin_id===id&&row.kind===kind&&!row.disabled);
const unique=values=>[...new Set(values.filter(Boolean))];

// The native picker combines the canonical catalogs with explicit "from"
// values. Supplement its small vocabularies for unrestricted 5etools choices.
function optionPool(kind,record,index){
 const values=kind==='skill'||kind==='expertise'?SKILLS.map(x=>x[0]):
   kind==='save'?abilities:kind==='language'?commonLanguages:
   kind==='tool'?[...artisanTools,...gamingSets,...instruments,
     'thieves\' tools','disguise kit','forgery kit','herbalism kit',
     'navigator\'s tools','poisoner\'s kit']:
   kind==='armor'?['light','medium','heavy','shield']:
   ['simple','martial','all',...martialWeapons];
 for(const source of selectedSources(record,index)){
  for(const raw of arr(grantedFields(source,kind))){
   if(typeof raw==='string'){
    if(!raw.includes(' of your choice')&&!raw.startsWith('one '))values.push(strip(raw));
   }else if(raw&&typeof raw==='object'){
    for(const [key,value] of Object.entries(raw)){
     if(value===true)values.push(strip(key));
     if(key==='choose')for(const item of arr(value?.from))values.push(strip(item));
    }
   }
  }
 }
 for(const row of arr(record.proficiency_choices))if(row?.kind===kind)values.push(strip(row.key));
 return unique(values.map(strip));
}
function allowedByRule(kind,data,key,record,index){
 const choose=data?.choose;
 if(choose&&typeof choose==='object'){
  const from=arr(choose.from).map(strip);
  if(from.length)return from.includes(key);
  if(choose.fromFilter){
   const filter=norm(choose.fromFilter);
   return kind==='weapon'&&filter.includes('type=martial weapon')&&martialWeapons.includes(key);
  }
  if(choose.any!==undefined)return kind!=='weapon'||!['simple','martial','all'].includes(key);
 }
 if(data?.any!==undefined)return kind!=='weapon'||!['simple','martial','all'].includes(key);
 if(data?.anyProficientSkill!==undefined)return kind==='skill'||kind==='expertise'?
   fixedProficiencies(record,index).has('skill:'+key):false;
 if(data?.anyArtisansTool!==undefined)return artisanTools.includes(key);
 if(data?.anyGamingSet!==undefined)return gamingSets.includes(key);
 if(data?.anyMusicalInstrument!==undefined)return instruments.includes(key);
 if(data?.anyStandard!==undefined)return kind==='language'&&!secretLanguages.has(key);
 if(data?.anyExotic!==undefined)return kind==='language'&&(exoticLanguages.has(key)||rareLanguages.has(key));
 return false;
}
function requirementEntries(source){
 const entries=[];
 for(const kind of kindFields){
  for(const data of arr(grantedFields(source,kind))){
   if(!data||typeof data!=='object'||Array.isArray(data))continue;
   const choose=data.choose;
   if(choose&&typeof choose==='object'&&Object.keys(choose).length){
    entries.push({kind,count:Math.max(1,Number(choose.count)||1),data});
   }
   for(const field of ['any','anyArtisansTool','anyGamingSet','anyMusicalInstrument',
     'anyStandard','anyExotic','anyProficientSkill']){
    if(data[field]!==undefined)
      entries.push({kind,count:Math.max(1,Number(data[field])||1),data:{[field]:data[field]}});
   }
  }
 }
 return entries;
}
export function pendingCharacterChoices(record={},calculated={},catalogs={}){
 const result=[],index=catalogs.proficiencyGrants||{};
 for(const source of selectedSources(record,index)){
  if(!enabled(record,source.id))continue;
  for(const [i,req] of requirementEntries(source).entries()){
   const options=optionPool(req.kind,record,index)
     .filter(key=>allowedByRule(req.kind,req.data,key,record,index))
     .sort((a,b)=>a.localeCompare(b,'it'));
   const selected=unique(presentRows(record,source.id,req.kind)
     .map(row=>strip(row.key)).filter(key=>allowedByRule(req.kind,req.data,key,record,index)));
   const total=Math.max(1,Math.floor(req.count));
   result.push({id:'proficiency:'+source.id+':'+req.kind+':'+i,kind:'proficiency',
     origin_id:source.id,name:source.origin||source.source?.name||source.id,
     label:kindNames[req.kind]||req.kind,proficiency_kind:req.kind,
     count:total,selected,options,remaining:Math.max(0,total-selected.length)});
  }
 }
 // The native code recognizes exactly one 5etools one-score choice per feat.
 const seen=new Set();
 for(const feat of arr(record.feats_catalog)){
  if(!feat||feat.disabled||!feat.name)continue;
  const sid='feat|'+norm(feat.source)+'|'+norm(feat.name);
  if(seen.has(sid)||!enabled(record,sid))continue;
  const indexed=arr(catalogs.abilityGrants?.feat).find(row=>
    norm(row.name)===norm(feat.name)&&String(row.source||'')===String(feat.source||''));
  const variants=arr(indexed?.ability_choices);
  if(variants.length!==1||!variants[0]?.choose)continue;
  const choice=variants[0].choose;
  const options=unique(arr(choice.from).map(norm).filter(x=>abilities.includes(x)));
  if((Number(choice.count)||1)!==1||!options.length||Number(choice.amount??1)<=0)continue;
  seen.add(sid);
  const selected=unique(arr(record.feats_catalog).filter(row=>
    norm(row?.name)===norm(feat.name)&&norm(row?.source)===norm(feat.source))
    .map(row=>norm(row.ability_choice)).filter(x=>options.includes(x)));
  result.push({id:'ability:'+sid,kind:'ability',origin_id:sid,name:feat.name,
    label:'Caratteristica (+'+Number(choice.amount??1)+')',count:1,
    selected,options,remaining:selected.length?0:1});
 }
 for(const choice of arr(calculated.origin_choices)){
  if(!choice?.id||!enabled(record,choice.origin_id))continue;
  const feature=arr(calculated.features).find(row=>row.origin_id===choice.origin_id);
  if(feature&&(feature.disabled||feature.inactive||!enabled(record,feature.origin_key)))continue;
  result.push({id:'spell:'+choice.id,kind:'spell',origin_id:choice.origin_id,
    name:choice.origin_name||choice.origin_id,label:'Incantesimi / capacità magiche',
    count:Math.max(1,Number(choice.count)||1),selected:arr(choice.selected)
      .map(row=>row.spell_id),options:[],remaining:Math.max(0,Number(choice.remaining)||0),
    source_choice_id:choice.id});
 }
 return result;
}
// Link pickers to the exact trait that granted them; never match by display name.
export function choicesForTrait(trait,record,choices=[]){
 const origins=traitBenefitSources(trait,record);
 return arr(choices).filter(choice=>origins.has(choice.origin_id));
}
export function savePendingChoice(record,choice,values=[]){
 if(!choice||!['ability','proficiency'].includes(choice.kind))throw Error('Scelta non valida.');
 const selected=unique(arr(values).map(strip));
 if(selected.length>choice.count||selected.some(key=>!choice.options.includes(key)))
   throw Error('Selezione non consentita dal privilegio.');
 if(choice.kind==='ability'){
  if(selected.length>1)throw Error('Puoi scegliere una sola caratteristica.');
  let updated=false;
  const feats=arr(record.feats_catalog).map(feat=>{
   const sid='feat|'+norm(feat?.source)+'|'+norm(feat?.name);
   if(sid!==choice.origin_id)return feat;
   updated=true;return {...feat,ability_choice:selected[0]||''};
  });
  if(!updated)throw Error('Talento non più disponibile.');
  return {feats_catalog:feats};
 }
 const rows=arr(record.proficiency_choices).filter(row=>!(
   row?.origin_id===choice.origin_id&&row.kind===choice.proficiency_kind&&
   choice.options.includes(strip(row.key))&&!row.automatic));
 for(const key of selected)rows.push({kind:choice.proficiency_kind,key,
   origin_id:choice.origin_id,origin_name:choice.name,disabled:false});
 return {proficiency_choices:rows};
}
