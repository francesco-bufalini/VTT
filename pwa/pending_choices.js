import {expandedSpellFeatOptions} from './feat_picker.js';
// Structured, still-unresolved character choices. Mirrors the native
// creature_pending_choices.gd and creature_proficiency_rules.gd contracts.
// Never infer a choice from prose or assign a privilege automatically.
import {selectedSources,grantedFields,fixedProficiencies,effectiveBackgrounds} from './structured_effects.js';
import {SKILLS} from './sheet_rules.js';
import {traitBenefitSources} from './trait_benefits.js';
import {contentForRules} from './source_edition.js';
import {originVariants,allocationChoiceRows,saveAllocationChoice,allocationVariants} from './ability_choice_rules.js';
import {selectedSpeciesDefenseRules} from './species_defenses.js';

const arr=x=>Array.isArray(x)?x:[];
const norm=x=>String(x??'').trim().toLowerCase();
const abilities=['str','dex','con','int','wis','cha'];
const kindNames={mixed:'Abilità o strumenti',skill:'Abilità',expertise:'Maestria',save:'Tiri salvezza',
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
 for(const row of arr(record.proficiency_choices))if(row?.kind===kind&&!row.custom)values.push(strip(row.key));
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
function mixedOptions(rule,record,index){
 const kinds=arr(rule?.choose?.fromKinds).filter(kind=>kind==='skill'||kind==='tool');
 const allowed=rule?.choose?.fromByKind||{};
 return unique(kinds.flatMap(kind=>optionPool(kind,record,index)
   .filter(key=>!Array.isArray(allowed[kind])||allowed[kind].map(strip).includes(key))
   .map(key=>kind+':'+key)));
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
 for(const rule of arr(source.source?.proficiencyChoices)){
  const choose=rule?.choose;
  if(!choose||!arr(choose.fromKinds).length)continue;
  entries.push({kind:'mixed',count:Math.max(1,Number(choose.count)||1),data:rule});
 }
 return entries;
}
// The next picker opens only when a completed choice *creates exactly one*
// previously nonexistent, still-unresolved choice. Ignore all older pending
// choices: a character may have several unrelated decisions left to make.
// This is derived from the typed choice snapshots, not from feature names.
export function singleNewPendingChoice(before=[],after=[],completed={}){
 const prior=arr(before),next=arr(after),id=String(completed?.id||'');
 if(!id||!prior.some(row=>row?.id===id))return null;
 const saved=next.find(row=>row?.id===id);
 if(saved&&Number(saved.remaining)>0)return null;
 const seen=new Set(prior.map(row=>row?.id).filter(Boolean));
 const fresh=next.filter(row=>row?.id&&!seen.has(row.id)&&Number(row.remaining)>0);
 return fresh.length===1?fresh[0]:null;
}

export function pendingCharacterChoices(record={},calculated={},catalogs={}){
 const result=[],index=catalogs.proficiencyGrants||{};
 for(const source of selectedSources(record,index,calculated.features??null)){
  if(!enabled(record,source.id))continue;
  for(const [i,req] of requirementEntries(source).entries()){
   const mixed=req.kind==='mixed';
   const options=(mixed?mixedOptions(req.data,record,index):
     optionPool(req.kind,record,index).filter(key=>allowedByRule(req.kind,req.data,key,record,index)&&
       !arr(source.choice_exclusions?.[req.kind]).includes(key)))
     .sort((a,b)=>a.localeCompare(b,'it'));
   const stored=mixed?arr(record.proficiency_choices).filter(row=>
     row?.origin_id===source.id&&['skill','tool'].includes(row.kind)&&!row.disabled):presentRows(record,source.id,req.kind);
   const valueOf=row=>mixed?row.kind+':'+strip(row.key):strip(row.key);
   const excluded=arr(source.choice_exclusions?.[req.kind]);
   const selected=unique(stored.map(valueOf).filter(key=>!excluded.includes(key)&&
     (stored.some(row=>row.custom&&valueOf(row)===key)||options.includes(key))));
   const custom_values=unique(stored.filter(row=>row.custom===true&&!excluded.includes(valueOf(row))&&(!mixed||row.kind==='tool'))
     .map(row=>strip(row.key)));
   const total=Math.max(1,Math.floor(req.count));
   result.push({id:'proficiency:'+source.id+':'+req.kind+':'+i,kind:'proficiency',
     origin_id:source.id,name:source.origin||source.source?.name||source.id,
     label:kindNames[req.kind]||req.kind,proficiency_kind:req.kind,
     count:total,selected,options,custom_values,
     ...(excluded.length?{excluded_options:excluded}:{}),
     custom_allowed:['tool','language','mixed'].includes(req.kind),
     remaining:Math.max(0,total-selected.length)});
  }
 }
 // Owned feats receive their own origin-level choices; single-stat legacy
 // selections remain editable and keep the old persisted feat field.
 const seen=new Set();
 for(const feat of arr(record.feats_catalog)){
  if(!feat?.name||feat.disabled)continue;
  const sid='feat|'+norm(feat.source)+'|'+norm(feat.name);
  if(seen.has(sid)||!enabled(record,sid))continue;
  seen.add(sid);
  const row=arr(catalogs.abilityGrants?.feat).find(x=>norm(x.name)===norm(feat.name)&&
    norm(x.source)===norm(feat.source));
  const variants=originVariants(catalogs.abilityGrants,'feat',row,feat.source);
  if(!variants.length)continue;
  const legacy=variants.length===1&&variants[0].parts.length===1?feat.ability_choice:'';
  result.push(...allocationChoiceRows(record,sid,feat.name,variants,legacy));
 }
 // Race, subrace and background score choices can be fixed or source-wide.
 for(const [group,name,source] of [
   ['race',record.species,record.species_source],
   ...(record.subrace?[['subrace',record.subrace,record.subrace_source]]:[]),
   ...effectiveBackgrounds(record).map(row=>['background',row.name,row.source])
 ]){
  if(!name||!source)continue;
  const matching=arr(catalogs.abilityGrants?.[group]).filter(row=>
    norm(row.name)===norm(name)&&norm(row.source)===norm(source)&&
    (group!=='subrace'||norm(row.raceName)===norm(record.species)&&
     (!row.raceSource||norm(row.raceSource)===norm(record.species_source))));
  // Source policies also apply when upstream omits an explicit race ability row.
  if(group==='race'&&!matching.length)matching.push({name,source});
  for(const row of matching){
   const sid=group+'|'+norm(row.source)+'|'+norm(row.name);
   if(!enabled(record,sid))continue;
   const fixed=row.ability&&typeof row.ability==='object'&&!Array.isArray(row.ability)?
     Object.entries(row.ability).filter(([key,val])=>abilities.includes(key)&&Number(val)>0):[];
   if(fixed.length)result.push({id:'ability-fixed:'+sid,kind:'ability_fixed',
     origin_id:sid,name:row.name,label:'Incrementi automatici',
     count:fixed.length,selected:fixed.map(([key])=>key),
     options:fixed.map(([key])=>key),amounts:Object.fromEntries(fixed),
     remaining:0});
   const variants=originVariants(catalogs.abilityGrants,group,row,source);
   result.push(...allocationChoiceRows(record,sid,row.name,variants));
  }
 }
 // The same resolved parent and subrace sources drive both the defense
 // calculation and its picker. Never offer an unrelated 5etools variant.
 for(const source of selectedSpeciesDefenseRules(record,catalogs.speciesDefenses)){
  if(!enabled(record,source.source_id)||!enabled(record,source.origin_key))continue;
  const chosen=record.origin_defense_choices?.[source.source_id]??
   record.origin_defense_choices?.[source.row.id]??
   record.origin_defense_choices?.[source.origin_key];
  for(const rule of source.choices){
   const feature=arr(calculated.features).find(f=>norm(f.name)===norm(rule.trait)&&
     f.origin_key===source.origin_key);
   if(feature&&(feature.disabled||feature.inactive||
     !enabled(record,feature.origin_id)||record.trait_enabled?.[feature.key]===false))continue;
   const options=arr(rule.from).filter(x=>typeof x==='string');
   const selected=typeof chosen==='string'&&options.includes(norm(chosen))?[norm(chosen)]:[];
   result.push({id:'defense:'+source.source_id+':'+rule.rank+':'+norm(rule.trait),
    kind:'defense',origin_id:feature?.origin_id||source.source_id,
    defense_source_id:source.source_id,name:'Tratto · '+rule.trait,
    label:rule.rank===1?'Resistenza ai danni':rule.rank===2?'Immunità ai danni':'Tipo di difesa',
    count:1,selected,options,remaining:selected.length?0:1});
  }
 }
 // Class-level Ability Score Improvement has an explicit 5etools feature ID.
 // Each occurrence can grant score allocation OR an individually owned feat.
 for(const feature of arr(calculated.features)){
  if(!feature?.origin_id||feature.disabled||feature.inactive||!enabled(record,feature.origin_id))continue;
  const rule=arr(catalogs.abilityGrants?.advancement_rules).find(r=>
    norm(r.feature_name)===norm(feature.name)&&arr(r.sources).some(source=>
    norm(source)===norm(feature.class_source||String(feature.origin_key||'').split('|')[1])));
  if(!rule)continue;
  const sid=feature.origin_id,owned=arr(record.advancement_choices).find(x=>x.origin_id===sid);
  const mode=owned?.mode;
  result.push({id:'advancement-mode:'+sid,kind:'advancement_mode',origin_id:sid,
    name:feature.name+' · livello '+feature.level,
    label:'Incremento caratteristiche o talento',count:1,
    selected:mode?[mode]:[],options:rule.feat_alternative?['ability','feat']:['ability'],
    option_labels:{ability:'Incrementa le caratteristiche',feat:'Scegli un talento'+(rule.feat_optional?' (regola opzionale)':'')},
    remaining:mode?0:1});
  if(mode==='ability')result.push(...allocationChoiceRows(record,sid,feature.name,
    allocationVariants(rule.ability_choices)));
  if(mode==='feat'){
   const baseAvailable=Object.entries(catalogs.originDetails?.feats||{}).map(([key])=>{
    const cut=key.lastIndexOf('|');return cut<0?null:
      {value:key.slice(cut+1)+'|'+key.slice(0,cut),name:key.slice(0,cut),source:key.slice(cut+1)};
   }).filter(Boolean).filter(f=>String(record.rules_version||'2014')==='2024'?
      f.source==='xphb'||f.source==='efa':contentForRules([f],record.rules_version).length>0)
     .sort((a,b)=>a.name.localeCompare(b.name));
   const available=expandedSpellFeatOptions(baseAvailable,catalogs.classMechanics?.additional_spells||[])
     .map(f=>({...f,value:f.value+(f.spell_variant?'|'+norm(f.spell_variant):'')}));
   const ownedFeat=arr(record.feats_catalog).find(f=>f?.granted_by===sid);
   const value=ownedFeat?norm(ownedFeat.source)+'|'+norm(ownedFeat.name)+(ownedFeat.spell_variant?'|'+norm(ownedFeat.spell_variant):''):'';
   result.push({id:'advancement-feat:'+sid,kind:'advancement_feat',origin_id:sid,
    name:feature.name+' · livello '+feature.level,label:'Talento concesso',
    count:1,selected:value?[value]:[],
    options:available.map(f=>f.value),option_labels:Object.fromEntries(available.map(f=>
      [f.value,(f.display_name||f.name)+' ('+f.source.toUpperCase()+')'])),
    remaining:value?0:1});
  }
 }
 // Casting stat selection is an owned benefit of the granting trait.
 const casterOwners=new Set();
 for(const grant of arr(calculated.origin_spells)){
  if(!grant?.origin_id||casterOwners.has(grant.origin_id)||!enabled(record,grant.origin_id))continue;
  if(!grant.tracker_id&&grant.cantrip!==true)continue;
  const options=arr(grant.spellcasting_ability_options).length?
    arr(grant.spellcasting_ability_options).filter(value=>abilities.includes(value)):
    (!grant.spellcasting_ability?abilities:[]);
  if(!options.length)continue;
  casterOwners.add(grant.origin_id);
  const current=record.spellcasting_section_abilities?.['origin:'+grant.origin_id]||'';
  const selected=options.includes(current)?[current]:[];
  result.push({id:'casting-ability:'+grant.origin_id,kind:'casting_ability',
    origin_id:grant.origin_id,name:grant.origin_name||grant.origin_id,
    label:'Caratteristica da incantatore',count:1,selected,options,
    remaining:selected.length?0:1});
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
// A choice picker may contain already-owned proficiencies from any source,
// including fixed grants and the current character's selected proficiencies.
export function knownProficiencyOptions(record={},calculated={},choice={},index={}){
 if(choice.kind!=='proficiency')return new Set();
 const all=new Set([...fixedProficiencies(record,index).keys(),
   ...arr(calculated.proficiencies)].map(norm));
 const kind=choice.proficiency_kind;
 if(kind==='mixed')return new Set(arr(choice.options).filter(key=>
   all.has(key)||(key.startsWith('skill:')&&all.has('expertise:'+key.slice(6)))));
 return new Set(arr(choice.options).filter(key=>
   all.has(kind+':'+key)||(kind==='skill'&&all.has('expertise:'+key))));
}
// Link pickers to the exact trait that granted them; never match by display name.
export function choicesForTrait(trait,record,choices=[]){
 const origins=traitBenefitSources(trait,record);
 return arr(choices).filter(choice=>origins.has(choice.origin_id));
}
export function savePendingChoice(record,choice,values=[]){
 if(!choice||!['ability','ability_mode','ability_fixed','advancement_mode','advancement_feat','proficiency','casting_ability','defense'].includes(choice.kind))throw Error('Scelta non valida.');
 if(choice.kind==='ability_fixed')throw Error('Gli incrementi fissi sono automatici.');
 const raw=unique(arr(values).map(value=>choice.kind==='advancement_feat'?norm(value):strip(value)));
 const prefix='__custom__:';
 const mixed=choice.proficiency_kind==='mixed';
 const custom=raw.filter(key=>key.startsWith(prefix)).map(key=>
   (mixed?'tool:':'')+key.slice(prefix.length));
 const regular=raw.filter(key=>!key.startsWith(prefix));
 const selected=unique([...regular,...custom]);
 if(selected.length>choice.count||
    regular.some(key=>!choice.options.includes(key))||
    (custom.length&&(!choice.custom_allowed||choice.kind!=='proficiency'))||
    custom.some(key=>!(mixed?key.slice(5):key)||(mixed?key.slice(5):key).length>80||
       /[<>{}\x00-\x1f]/.test(key)||choice.options.includes(key)||
       arr(choice.excluded_options).includes(key)||regular.includes(key)))
   throw Error('Selezione non consentita dal privilegio.');
 if(['advancement_mode','advancement_feat'].includes(choice.kind)){
  const previous=arr(record.advancement_choices).find(row=>row.origin_id===choice.origin_id);
  const advancements=arr(record.advancement_choices).filter(row=>row.origin_id!==choice.origin_id);
  const otherFeats=arr(record.feats_catalog).filter(row=>row?.granted_by!==choice.origin_id);
  if(choice.kind==='advancement_mode'){
   const mode=selected[0]||'';
   if(mode)advancements.push({origin_id:choice.origin_id,mode});
   return {advancement_choices:advancements,feats_catalog:mode==='feat'&&previous?.mode==='feat'?
     arr(record.feats_catalog):otherFeats,
     origin_ability_choices:arr(record.origin_ability_choices).filter(row=>row.origin_id!==choice.origin_id)};
  }
  if(selected.length){
   const [source,...parts]=selected[0].split('|');
   const variant=parts.length>1?parts.pop():'';
   const name=parts.join('|');
   if(!name||!source)throw Error('Talento non disponibile.');
   advancements.push({origin_id:choice.origin_id,mode:'feat'});
   otherFeats.push({id:'advancement:'+choice.origin_id,name,source:source.toUpperCase(),
     ...(variant?{spell_variant:variant}:{}),granted_by:choice.origin_id});
  }else advancements.push({origin_id:choice.origin_id,mode:'feat'});
  return {advancement_choices:advancements,feats_catalog:otherFeats};
 }
 if(choice.kind==='defense'){
  if(selected.length>1||selected.some(key=>!choice.options.includes(key))||
    !/^(race|subrace)\\|[^|]+\\|[^|]+$/.test(String(choice.defense_source_id||'')))
   throw Error('Tipo di danno non consentito dalla specie.');
  const current={...(record.origin_defense_choices||{})};
  if(selected.length)current[choice.defense_source_id]=selected[0];
  else delete current[choice.defense_source_id];
  return {origin_defense_choices:current};
 }
 if(choice.kind==='casting_ability'){
  if(selected.length!==1||!abilities.includes(selected[0])||
    !choice.options.includes(selected[0]))throw Error('Scegli una caratteristica da incantatore valida.');
  return {spellcasting_section_abilities:{...(record.spellcasting_section_abilities||{}),
    ['origin:'+choice.origin_id]:selected[0]}};
 }
 if(choice.kind==='ability_mode')return saveAllocationChoice(record,choice,selected);
 if(choice.kind==='ability'){
  if(choice.part!==undefined&&choice.variant!==undefined){
   if(choice.exclusive&&selected.some(ability=>arr(choice.used_elsewhere).includes(ability)))
    throw Error('Ogni incremento deve scegliere una caratteristica differente.');
   return saveAllocationChoice(record,choice,selected);
  }
  if(selected.length>1)throw Error('Puoi scegliere una sola caratteristica.');
  if(!choice.origin_id.startsWith('feat|')){
    if(!/^(race|subrace|background)\|/.test(choice.origin_id))throw Error('Origine non valida.');
    const rows=arr(record.origin_ability_choices).filter(row=>row?.origin_id!==choice.origin_id);
    if(selected.length)rows.push({origin_id:choice.origin_id,ability:selected[0]});
    return {origin_ability_choices:rows};
  }
  let updated=false;
  const feats=arr(record.feats_catalog).map(feat=>{
   const sid='feat|'+norm(feat?.source)+'|'+norm(feat?.name);
   if(sid!==choice.origin_id)return feat;
   updated=true;return {...feat,ability_choice:selected[0]||''};
  });
  if(!updated)throw Error('Talento non più disponibile.');
  return {feats_catalog:feats};
 }
 const rows=arr(record.proficiency_choices).filter(row=>{
   if(row?.origin_id!==choice.origin_id||row.automatic)return true;
   if(mixed)return !['skill','tool'].includes(row.kind)||
     !(choice.options.includes(row.kind+':'+strip(row.key))||row.custom===true);
   return row.kind!==choice.proficiency_kind||
     !(choice.options.includes(strip(row.key))||row.custom===true);
 });
 for(const key of selected){
   const colon=mixed?key.indexOf(':'):-1;
   const kind=mixed?key.slice(0,colon):choice.proficiency_kind;
   const proficiencyKey=mixed?key.slice(colon+1):key;
   if(mixed&&!['skill','tool'].includes(kind))throw Error('Categoria di competenza non valida.');
   rows.push({kind,key:proficiencyKey,origin_id:choice.origin_id,
     origin_name:choice.name,disabled:false,
     ...(custom.includes(key)?{custom:true}:{})});
 }
 return {proficiency_choices:rows};
}
// Remove only one owned feat, plus its own selected proficiency rows.
// Other feats, class grants and manually added proficiencies are preserved.
export function removeOwnedFeatPatch(record={},originKey=''){
 const feats=arr(record.feats_catalog);
 const asFeat=feat=>typeof feat==='string'?{name:feat}:feat;
 const index=feats.findIndex(raw=>{
   const feat=asFeat(raw);
   return !!feat?.name&&'feat|'+(feat.id||norm(feat.name)+'|'+norm(feat.source))===originKey;
 });
 if(index<0)throw Error('Talento non più presente nella scheda.');
 const feat=asFeat(feats[index]),sourceId='feat|'+norm(feat.source)+'|'+norm(feat.name);
 const origin_enabled={...(record.origin_enabled||{})};
 delete origin_enabled[sourceId];
 delete origin_enabled[originKey];
 return {feats_catalog:feats.filter((_,i)=>i!==index),
   proficiency_choices:arr(record.proficiency_choices).filter(row=>
     row?.origin_id!==sourceId&&row?.origin_id!==originKey),
   origin_enabled};
}
