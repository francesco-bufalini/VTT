import {CLASS_NUMERIC_FEATURE_GRANTS} from './catalog/class_numeric_feature_grants.js';
import {removedBenefitIds} from './trait_benefit_editor.js';
import {monsterTraits} from './monster_traits.js';
import {normalizeMonsterStatBlock} from './character_core.js';
// Generic structured effects and fixed proficiency projection based on
// creature_structured_bonuses.gd and creature_proficiency_rules.gd.
// No mechanics are inferred from descriptions or HTML/prose.
const array=v=>Array.isArray(v)?v:[];
const norm=s=>String(s??"").trim().toLowerCase();
const match=(a,b)=>norm(a)===norm(b);
const validAmount=v=>typeof v==="number"&&Number.isFinite(v)||
  typeof v==="string"&&v.trim()!==""&&Number.isFinite(Number(v));
const identity=(group,row)=>group+"|"+norm(row.source)+"|"+norm(row.name);
const kinds=["weapon","armor","skill","expertise","save","tool","language"];
const fields={weapon:"weaponProficiencies",armor:"armorProficiencies",
  skill:"skillProficiencies",expertise:"expertise",tool:"toolProficiencies",
  language:"languageProficiencies",save:"saveProficiencies"};
const classMembers=record=>array(record.classes).length?array(record.classes):
  record.class?[{name:record.class,source:record.class_source||"",level:record.level||1}]:[];
// Treat older single-background characters as having a first background.
export function effectiveBackgrounds(record={}){
 const primary=record.background?[{name:record.background,id:record.background_id||'',source:record.background_source||''}]:[];
 const rows=[...primary,...array(record.backgrounds_catalog)].filter(row=>row?.name&&!row.disabled);
 const seen=new Set();
 return rows.filter(row=>{
  const key=norm(row.name)+'|'+norm(row.source);
  if(seen.has(key))return false;
  seen.add(key);return true;
 });
}
// Feature grants use the existing trait IDs, not a second class-wide source.
// A compact proficiency catalog can resolve these even without descriptions offline.
function proficiencyFeatures(record,index,features){
 return features??collectStructuredFeatures(record,{classFeatures:{
  class_features:array(index.classFeature),subclass_features:array(index.subclassFeature)}});
}
function proficiencyTraitActive(record,feature,grant={}){
 // Optional class features never grant languages until chosen explicitly.
 if(grant.language_grant_requires_opt_in&&
   record.origin_enabled?.[feature?.origin_id]!==true&&
   !array(record.optional_features_catalog).some(row=>!row?.disabled&&match(row.name,feature?.name)&&
     (!row.source||match(row.source,feature?.source))))return false;
 const parent=String(feature?.origin_key||''),base=parent.split('|').slice(0,3).join('|');
 return !!feature&&!feature.inactive&&!feature.disabled&&record.trait_enabled?.[feature.key]!==false&&
  ![feature.origin_id,parent,base].some(id=>id&&muted(record,id));
}
export function selectedSources(record,index={},features=null){
  const selected=[];
  const push=(group,source,origin,mode="starting")=>{
    if(!source?.name)return;
    const id=identity(group,source);
    if(!selected.some(x=>x.id===id)){
     // Custom Lineage grants darkvision OR a skill, never both.
     const effective=id==='race|tce|custom lineage'&&
       record.origin_sense_choices?.[id]==='darkvision'?
       {...source,skillProficiencies:[]}:source;
     selected.push({id,group,source:effective,origin,mode});
   }
  };
  for(const [group,field,sourceField] of [["race","species","species_source"]]){
    if(!record[field])continue;
    for(const source of array(index[group]).filter(x=>match(x.name,record[field])&&
        (group==="background"&&!record[sourceField]||match(x.source,record[sourceField]))))
      push(group,source,record[field]);
  }
  for(const background of effectiveBackgrounds(record))
    for(const source of array(index.background).filter(x=>match(x.name,background.name)&&
      (!background.source||match(x.source,background.source))))
      push("background",source,background.name);
  if(record.subrace)for(const source of array(index.subrace).filter(x=>
    match(x.raceName,record.species)&&match(x.name,record.subrace)&&
    match(x.source,record.subrace_source)&&
    match(x.raceSource,record.species_source)))
    push("subrace",source,record.subrace);
  // Some later subraces replace their parent's Languages grant rather than
  // augmenting it. Exclude the parent's fixed and chosen languages only;
  // unrelated proficiencies and other origins remain intact.
  if(selected.some(row=>row.group==="subrace"&&row.source.replaces_parent_languages&&
      !muted(record,row.id)))
    for(const parent of selected.filter(row=>row.group==="race"))
      parent.source={...parent.source,languageProficiencies:[],parent_languages_replaced:true};
  for(const feat of array(record.feats_catalog)){
    if(!feat||feat.disabled)continue;
    for(const source of array(index.feat).filter(x=>match(x.name,feat.name)&&
        match(x.source,feat.source)))push("feat",source,feat.name);
  }
  let first=true;
  for(const member of classMembers(record)){
    for(const source of array(index.class).filter(x=>match(x.name,member?.name)&&
        match(x.source,member.source)))
      push("class",source,member.name,first?"starting":"multiclass");
    first=false;
  }
  const owned=proficiencyFeatures(record,index,features);
  for(const group of ['classFeature','subclassFeature']){
    for(const row of array(index[group])){
      const feature=array(owned).find(f=>f.id===row.id&&match(f.class_name,row.class_name)&&
        match(f.class_source,row.class_source)&&(!f.source||match(f.source,row.source))&&
        (group!=='subclassFeature'||match(f.subclass_short_name,row.subclass_short_name)&&
          match(f.subclass_source,row.subclass_source)));
      if(!proficiencyTraitActive(record,feature,row))continue;
      // An optional replacement removes its predecessor only if explicitly selected.
      if(row.language_grant_replaced_by&&(
        array(record.optional_features_catalog).some(opt=>!opt?.disabled&&
          match(opt.name,row.language_grant_replaced_by))||
        array(owned).some(other=>match(other.name,row.language_grant_replaced_by)&&
          match(other.class_name,row.class_name)&&record.origin_enabled?.[other.origin_id]===true)))
        continue;
      selected.push({id:feature.origin_id,group,source:row,origin:'Tratto · '+feature.name,
        feature,mode:'feature'});
    }
  }
  // Replacement choices are conditional on another active grant. A feature's
  // own automatic grant (including an older saved copy) cannot trigger itself.
  const suppressed=removedBenefitIds(record),byId=new Map(selected.map(source=>[source.id,source]));
  const activeGrant=(sid,kind,key)=>!muted(record,sid)&&
    !suppressed.has('proficiency:'+(sid||'')+':'+kind+':'+norm(key))&&
    proficiencyOwnerActive(record,byId.has(sid)&&
      proficiencyFeatureOwner(record,byId.get(sid),kind,key,owned));
  const activeSaved=row=>row&&!row.disabled&&liveSource(record,row.origin_id||'')&&
    (!String(row.origin_id||'').startsWith('feature:class|')||byId.has(row.origin_id))&&
    activeGrant(row.origin_id,row.kind,row.key)&&featureStoredGrantAllowed(byId.get(row.origin_id),row)&&
    (!String(row.origin_id||'').startsWith('feature:class|')||
      array(owned).some(f=>f.origin_id===row.origin_id&&proficiencyTraitActive(record,f)));
  const activeFixed=(source,grant)=>activeGrant(source.id,grant.kind,grant.key)&&
    !array(record.proficiency_choices).some(saved=>saved.origin_id===source.id&&
      saved.kind===grant.kind&&norm(saved.key)===grant.key&&saved.disabled);
  for(const [i,source] of selected.entries()){
    for(const rule of array(source.source.proficiencyReplacements)){
      const kind=rule.kind,key=norm(rule.key),field=fields[kind];
      if(!field||!rule.choose)continue;
      const priorFixed=selected.slice(0,i).some(other=>fixedGrants(other).some(grant=>
        grant.kind===kind&&grant.key===key&&activeFixed(other,grant)));
      const priorSaved=array(record.proficiency_choices).some(saved=>saved?.origin_id!==source.id&&
        saved?.kind===kind&&norm(saved.key)===key&&activeSaved(saved));
      if(!priorFixed&&!priorSaved)continue;
      const data=array(source.source[field]).map(row=>{
        if(!row||typeof row!=='object'||Array.isArray(row))return row;
        return Object.fromEntries(Object.entries(row).filter(([name])=>norm(name.split('|')[0])!==key));
      }).filter(row=>row!==null&&(typeof row!=='object'||Object.keys(row).length));
      source.source={...source.source,[field]:[...data,rule.choose]};
      const unavailable=new Set([key]);
      for(const other of selected.filter(other=>other.id!==source.id))
        for(const grant of fixedGrants(other))if(grant.kind===kind&&activeFixed(other,grant))unavailable.add(grant.key);
      for(const saved of array(record.proficiency_choices))
        if(saved?.origin_id!==source.id&&saved?.kind===kind&&activeSaved(saved))unavailable.add(norm(saved.key));
      source.choice_exclusions={...source.choice_exclusions,[kind]:[...unavailable]};
    }
  }
  return selected;
}
export function grantedFields(source,kind){
  if(source.group==="class"){
    if(kind==="save")return source.mode==="starting"?source.source.savingThrows:[];
    const data=source.mode==="starting"?source.source.startingProficiencies:
      source.source.multiclassProficiencies;
    if(kind==="skill")return data?.skills??[];
    if(kind==="weapon")return data?.weaponProficiencies??data?.weapons??[];
    if(kind==="armor")return data?.armorProficiencies??data?.armor??[];
    if(kind==="tool")return data?.toolProficiencies??data?.tools??[];
    return [];
  }
  return source.source[fields[kind]]??[];
}
function grantLiteral(kind,raw){
  let key=norm(raw);
  if(key.startsWith("{@item ")&&key.endsWith("}"))
    key=key.slice(7,-1).split("|")[0].trim();
  else if(key.includes(" ")&&!["skill","language"].includes(kind)&&
      !["simple","martial","all"].includes(key))return "";
  if(key.startsWith("{@")||!key)return "";
  return key;
}
function fixedGrants(source){
  const result=[];
  for(const kind of kinds){
    const raw=grantedFields(source,kind);
    for(const row of array(raw)){
      if(typeof row==="string"){
        const key=grantLiteral(kind,row);
        if(key)result.push({kind,key});
      }else if(row&&typeof row==="object"&&!Array.isArray(row)){
        // Some 5etools class sources describe optional firearms proficiency as
        // {proficiency:"firearms",optional:true}. These are metadata fields,
        // not proficiency names ("weapon:optional" was previously leaked).
        if(typeof row.proficiency==="string"){
          const key=grantLiteral(kind,row.proficiency);
          if(key)result.push({kind,key});
        }
        for(const [name,value] of Object.entries(row)){
          if(["proficiency","optional"].includes(name))continue;
          if(value===true&&!("choose any anyArtisansTool anyGamingSet anyMusicalInstrument anyStandard anyExotic anyProficientSkill".split(" ")).includes(name))
            result.push({kind,key:norm(name.split("|")[0])});
        }
      }
    }
  }
  return result;
}
function muted(record,id){
  if(!id)return false;
  if(record.origin_enabled&&Object.hasOwn(record.origin_enabled,id)&&!record.origin_enabled[id])return true;
  return array(record.proficiency_origins).some(x=>x.id===id&&x.disabled);
}
function liveSource(record,id){
  if(!id)return true;
  const parts=String(id).split("|"),group=parts[0],
    source=parts[1]||"",name=parts.slice(2).join("|");
  if(group==="race")return match(record.species,name)&&match(record.species_source,source);
  if(group==="subrace")return match(record.subrace,name)&&match(record.subrace_source,source);
  if(group==="background")return effectiveBackgrounds(record).some(row=>match(row.name,name)&&
    (!source||!row.source||match(row.source,source)));
  if(group==="class")return classMembers(record).some(c=>match(c.name,name)&&match(c.source,source));
  if(group==="feat")return array(record.feats_catalog).some(f=>!f?.disabled&&(
    match(f.id,parts.slice(1).join("|"))||
    match(f.name,name)&&match(f.source,source)));
  if(id.startsWith("item:"))return array(record.inventory).some(row=>
    "item:"+row?.id===id&&Number(row.quantity??1)>0);
  return true; // Saved custom origins are not automatically invalidated by changing class.
}
// Typed ownership is separate from proficiency mechanics: an entire race
// can own many privileges, but each grant belongs to one concrete trait.
export function proficiencyFeatureOwner(record={},source={},kind="",key="",features=[]){
 const root=source?.source||{};
 const named=root.trait_proficiencies?.[kind+":"+norm(key)]||
   root.trait_proficiency_choices?.[kind];
 if(!named||!array(features).length)return null;
 let ownerKey="";
 if(source.group==="race")ownerKey="species|"+(record.species_id||norm(record.species))+"|"+norm(record.species_source);
 else if(source.group==="subrace")ownerKey="subrace|"+norm(record.subrace_source)+"|"+norm(record.subrace);
 else if(source.group==="feat"){
   const feat=array(record.feats_catalog).find(row=>match(row.name,root.name)&&match(row.source,root.source));
   if(feat)ownerKey="feat|"+(feat.id||norm(feat.name)+"|"+norm(feat.source));
 }
 if(!ownerKey)return null;
 const feature=array(features).find(row=>row.origin_key===ownerKey&&match(row.name,named));
 return feature?.origin_id?{id:feature.origin_id,name:"Tratto · "+feature.name,
   parent_id:source.id,feature}:null;
}
function proficiencyOwnerActive(record,owner){
 return !owner||(!owner.feature?.inactive&&!owner.feature?.disabled&&
   record.trait_enabled?.[owner.feature?.key]!==false&&!muted(record,owner.id)&&!muted(record,owner.feature?.origin_key));
}
// A saved conditional choice stays in the record, but grants nothing while
// its rule is unavailable. Manual benefits use their separate trait-editor IDs.
function featureStoredGrantAllowed(source,row){
 // Earlier catalogs had an upstream placeholder mistakenly materialized as a
 // language. Keep saved records intact, but never project this fake grant.
 if(row?.kind==='language'&&norm(row.key)==='other')return false;
 // Withdraw legacy saved choices when a subrace replaces racial Languages.
 if(source?.source?.parent_languages_replaced&&row.kind==='language')return false;
 if(source?.mode!=='feature')return true;
 if(fixedGrants(source).some(grant=>grant.kind===row.kind&&grant.key===norm(row.key)))return true;
 if(array(source.choice_exclusions?.[row.kind]).includes(norm(row.key)))return false;
 return array(grantedFields(source,row.kind)).some(data=>data&&typeof data==='object'&&
   Object.entries(data).some(([key,value])=>key==='choose'&&value||
     key.startsWith('any')&&Number(value)>0))||
   array(source.source.proficiencyChoices).some(rule=>array(rule.choose?.fromKinds).includes(row.kind));
}
export function fixedProficiencies(record,index={},features=null){
 const suppressed=removedBenefitIds(record);
 const excluded=(id,kind,key)=>suppressed.has("proficiency:"+id+":"+kind+":"+norm(key));
 const owned=proficiencyFeatures(record,index,features);
 const selected=selectedSources(record,index,owned),byId=new Map(selected.map(s=>[s.id,s]));
 const stored=array(record.proficiency_choices).filter(row=>{
  if(!row||row.disabled||muted(record,String(row.origin_id||""))||
     !liveSource(record,String(row.origin_id||"")))return false;
  if(row.granting_feature_origin_id&&!proficiencyTraitActive(record,
    array(owned).find(f=>f.origin_id===row.granting_feature_origin_id)))return false;
  if(String(row.origin_id||'').startsWith('feature:class|')&&
    (!byId.has(row.origin_id)||
      !array(owned).some(f=>f.origin_id===row.origin_id&&proficiencyTraitActive(record,f))))return false;
  const source=byId.get(row.origin_id);
  if(row.origin_id==='race|tce|custom lineage'&&row.kind==='skill'&&
    record.origin_sense_choices?.[row.origin_id]==='darkvision')return false;
  if(!featureStoredGrantAllowed(source,row))return false;
  return proficiencyOwnerActive(record,source&&
    proficiencyFeatureOwner(record,source,row.kind,row.key,features));
 });
 const result=new Map(),add=(kind,key)=>result.set(kind+":"+norm(key),true);
 for(const row of stored)if(kinds.includes(row.kind)&&row.key&&
   !excluded(row.origin_id||'',row.kind,row.key))add(row.kind,row.key);
 for(const source of selected){
  if(muted(record,source.id))continue;
  for(const grant of fixedGrants(source)){
   if(excluded(source.id,grant.kind,grant.key))continue;
   const owner=proficiencyFeatureOwner(record,source,grant.kind,grant.key,features);
   if(!proficiencyOwnerActive(record,owner))continue;
   const saved=array(record.proficiency_choices).find(row=>row.kind===grant.kind&&
     norm(row.key)===grant.key&&row.origin_id===source.id);
   if(saved?.disabled)continue;
   add(grant.kind,grant.key);
  }
 }
 return result;
}
// Expose the exact granted-by feature, but keep saved grants and suppression
// keyed to their existing parent IDs so old creature records still work.
export function proficiencyGrantOrigins(record={},index={},kind,key,features=null){
 const suppressed=removedBenefitIds(record),wanted=norm(key);
 const excluded=id=>suppressed.has('proficiency:'+id+':'+kind+':'+wanted);
 const owned=proficiencyFeatures(record,index,features);
 const sources=[],seen=new Set(),selected=selectedSources(record,index,owned);
 const byId=new Map(selected.map(source=>[source.id,source]));
 const add=(id,name,source)=>{
  const owner=source&&proficiencyFeatureOwner(record,source,kind,wanted,features);
  if(!proficiencyOwnerActive(record,owner))return;
  const resolvedId=owner?.id||id;
  if(!resolvedId||seen.has(resolvedId))return;
  seen.add(resolvedId);
  sources.push({id:resolvedId,name:owner?.name||name||id,
   ...(owner?{origin_parent_id:id}:{})});
 };
 for(const row of array(record.proficiency_choices))
  if(row&&!row.disabled&&row.kind===kind&&norm(row.key)===wanted&&
    !muted(record,row.origin_id)&&liveSource(record,row.origin_id)&&!excluded(row.origin_id)&&
    !(row.origin_id==='race|tce|custom lineage'&&row.kind==='skill'&&
      record.origin_sense_choices?.[row.origin_id]==='darkvision')&&
    featureStoredGrantAllowed(byId.get(row.origin_id),row)&&
    (!String(row.origin_id||'').startsWith('feature:class|')||
      byId.has(row.origin_id)&&
      array(owned).some(f=>f.origin_id===row.origin_id&&proficiencyTraitActive(record,f))))
    (()=>{
      if(row.granting_feature_origin_id){
        const feature=array(owned).find(f=>f.origin_id===row.granting_feature_origin_id);
        if(!proficiencyTraitActive(record,feature))return;
        if(!seen.has(feature.origin_id)){
          seen.add(feature.origin_id);
          sources.push({id:feature.origin_id,name:'Tratto · '+feature.name,
            origin_parent_id:row.origin_id});
        }
      }else add(row.origin_id,row.origin_name||byId.get(row.origin_id)?.origin||row.origin_id,
        byId.get(row.origin_id));
    })();
 for(const source of selected){
  if(muted(record,source.id)||excluded(source.id))continue;
  if(!fixedGrants(source).some(grant=>grant.kind===kind&&grant.key===wanted))continue;
  const override=array(record.proficiency_choices).find(row=>row.kind===kind&&
    norm(row.key)===wanted&&row.origin_id===source.id);
  if(!override?.disabled)add(source.id,source.origin||source.source?.name,source);
 }
 return sources;
}
export const automaticId=(sid,field,target,suffix="")=>
  "auto|"+sid+"|"+field+"|"+target+suffix;
export function numericGrant(sid,name,field,target,value,suffix="",allowModifier=false){
  if(!target||!validAmount(value)&&
    !(allowModifier&&typeof value==="string"&&/^(?:(?:str|dex|con|int|wis|cha)_mod|attuned_item_count)$/.test(value.trim().toLowerCase())))return null;
  return {id:automaticId(sid,field,target,suffix),
    origin_id:sid,origin_name:name,target,expression:String(value),
    automatic:true,disabled:false};
}
// Native CreatureFeatures.collect_features identity scheme. These are
// data-driven projections, not inferred mechanics from English descriptions.
export function collectStructuredFeatures(record,catalogs={}){
  if(record.stat_block)record={...record,stat_block:normalizeMonsterStatBlock(record.stat_block)};
  const results=[],seen=new Set();
  const attackRules=array(catalogs.featureRules?.attack_count_grants);
  // Partial class mechanics tables cannot grant slots without the full feature
  // catalog; explicit homebrew feature.benefits remain usable independently.
  const spellcastingRules=catalogs.classFeatures?array(catalogs.spellcastingBenefits?.grants):[];
  const subclassKey=value=>norm(value).replace(/^(?:college of |school of |circle of |way of |oath of |order of |the )/,'');
  const attackCount=(row,origin,level,className,classSource)=>{
   const direct=Number(row.attacks_per_action);
   if(Number.isSafeInteger(direct)&&direct>=2)return direct;
   if(origin.startsWith('monster|action'))return 0;
   const originSubclass=origin.includes('|subclass|')?
     origin.split('|subclass|')[1].split('|')[0]:'';
   const found=attackRules.find(rule=>match(rule.class_name,className)&&
     match(rule.class_source,classSource)&&match(rule.feature,row.name)&&
     level>=Number(rule.min_level||1)&&
     (!rule.subclass||originSubclass&&subclassKey(rule.subclass)===subclassKey(originSubclass)));
   return Number(found?.attacks_per_action)||0;
  };
  const members=classMembers(record),total=Number(record.level??members.reduce((n,c)=>n+Math.max(0,Number(c.level)||0),0)??1)||1;
  const classLevel=(name,source)=>members.filter(c=>match(c.name,name)&&(!source||!c.source||match(c.source,source)))
    .reduce((n,c)=>Math.max(n,Number(c.level)||0),0);
  function append(row,origin,level=1,scope="character",className="",classSource="",inactive=false){
    if(!row||typeof row!=="object"||!String(row.name||"").trim())return;
    const gate={scope,min_level:level,...(scope==="class"?{class_name:className,class_source:classSource}:{}),...(row.requirements||{})};
    const at=gate.scope==="class"?classLevel(gate.class_name||className,gate.class_source||classSource):total;
    if(at<Number(gate.min_level||0)||gate.max_level!==undefined&&gate.max_level!==""&&at>Number(gate.max_level))return;
    const id=String(row.id||"").trim()||origin+"|"+level+"|"+norm(row.name);
    const key=row.feature_key||origin+"|"+id;if(seen.has(key))return;seen.add(key);
    const attacksPerAction=attackCount(row,origin,level,className,classSource);
    // A spellcasting benefit belongs to its exact feature, never to its class
    // by default. The same lookup works for subclasses and homebrew benefits.
    const subParts=origin.includes('|subclass|')?origin.split('|subclass|')[1].split('|'):null;
    const spellRule=spellcastingRules.find(rule=>{
      const owner=rule.owner||{};
      return match(owner.class_name,className)&&
        (!owner.class_source||match(owner.class_source,classSource))&&
        match(owner.trait,row.name)&&
        (owner.subclass?!!subParts&&match(owner.subclass,subParts[0])&&
          (!owner.subclass_source||match(owner.subclass_source,subParts[1])):!subParts);
    });
    const benefits=[...array(row.benefits),
      ...(spellRule?.benefit&&!array(row.benefits).some(b=>b.type==='spell_selection')?[spellRule.benefit]:[])];
    results.push({...row,key,origin_key:origin,origin_id:"feature:"+key,
      ...(benefits.length?{benefits}:{}),
      level,requirements:gate,inactive:inactive||row.inactive===true,
      bonuses:array(row.bonuses),
      ...(attacksPerAction>=2?{attacks_per_action:attacksPerAction}:{}),
      action_type:row.action_type||row.activation_type||row.activation||row.time||"",
      action_kind:row.action_kind||"Capacità"});
  }
  if(record.kind==="monster"){
    for(const row of monsterTraits(record))append(row,row.origin_key,0);
  }else{
    const details=catalogs.originDetails||{};
    const lookup=(category,name,source)=>{
      const entries=details[category];if(!entries||!name)return null;
      if(Array.isArray(entries))return entries.find(r=>match(r.name,name)&&(!source||match(r.source,source)))||null;
      const candidate=entries[norm(name)+"|"+norm(source)];if(candidate)return candidate;
      if(source)return null;
      const matching=Object.entries(entries).filter(([key])=>key.startsWith(norm(name)+"|"));
      return matching.length===1?matching[0][1]:null;
    };
    if(record.species){
      const full=record.subrace&&lookup("races",record.species+" ("+record.subrace+")",record.subrace_source);
      const ftdDragonborn=match(record.species,"Dragonborn")&&match(record.species_source,"PHB")&&
        match(record.subrace_source,"FTD")&&["chromatic","metallic","gem"].includes(norm(record.subrace));
      // Fizban's dragonborn are complete race replacements. A flattened 5etools
      // entry must own its traits as the chosen FTD subrace, never the PHB parent.
      const race=full||lookup("races",record.species,record.species_source);
      const origin=ftdDragonborn?"subrace|ftd|"+norm(record.subrace):
        "species|"+(record.species_id||norm(record.species))+"|"+norm(record.species_source);
      for(const [i,row] of array(ftdDragonborn?full?.entries:race?.entries).entries()){
        if(row&&typeof row==="object")append({...row,name:row.name||"Altri tratti · "+(i+1)},origin,
          Number(row.level||row.requirements?.min_level||1));
      }
    }
    for(const selection of effectiveBackgrounds(record)){
      const background=lookup("backgrounds",selection.name,selection.source);
      const origin="background|"+norm(background?.source||selection.source)+"|"+norm(selection.name);
      for(const row of array(background?.entries))
        if(row?.name&&(row.entries!==undefined||row.entry!==undefined))
          append({...row,entries:row.entries??row.entry},origin,1);
    }
    for(const feat of array(record.feats_catalog)){
      if(!feat?.name)continue;
      const info=lookup("feats",feat.name,feat.source);
      const origin="feat|"+String(feat.id||norm(feat.name)+"|"+norm(feat.source));
      const sections=Array.isArray(info?.feature_sections)?info.feature_sections:
        Array.isArray(feat.feature_sections)?feat.feature_sections:null;
      const entries=sections||info?.entries||feat.entries||[];
      array(entries).forEach((row,i)=>{
        if(row?.name&&(sections||row.entries!==undefined||row.entry!==undefined))
          append({...row,...(!sections&&!row.id?{id:"section-"+i}:{})},origin,
            Number(row.requirements?.min_level??row.min_level??1),"character","","",Boolean(feat.disabled));
      });
    }
  }
  const featureIndex=catalogs.classFeatures||{
    class_features:array(catalogs.classMechanics?.resource_features).filter(f=>!f.subclass_name&&!f.subclass_short_name),
    subclass_features:array(catalogs.classMechanics?.resource_features).filter(f=>f.subclass_name||f.subclass_short_name)
  };
  const selectedEdition=record.rules_version==="2024"?"XPHB":"PHB";
  for(const member of members){
    if(!member?.name||match(member.name,"Mostro"))continue;
    const name=member.name,source=String(member.source||record.class_source||selectedEdition);
    const level=Math.max(0,Number(member.level)||0),base="class|"+norm(source)+"|"+norm(name);
    for(const row of [...array(featureIndex.class_features),...array(member.features)]){
      if(row?.class_name&&!match(row.class_name,name))continue;
      if(row?.class_source&&!match(row.class_source,source))continue;
      const at=Number(row?.level??1);
      if(at>=1&&at<=level)append(row,base,at,"class",name,source);
    }
    const primary=match(member.name,record.class)&&match(source,record.class_source||selectedEdition);
    const sub=member.subclass||(primary?record.subclass:'');
    if(!sub)continue;
    const subsource=String(member.subclass_source||(primary?record.subclass_source:'')||"");
    const origin=base+"|subclass|"+norm(sub)+"|"+norm(subsource);
    for(const row of [...array(featureIndex.subclass_features),...array(member.subclass_features)]){
      if(row?.class_name&&!match(row.class_name,name))continue;
      if(row?.class_source&&!match(row.class_source,source))continue;
      if((row?.subclass_name||row?.subclass_short_name)&&
        !match(row.subclass_name,sub)&&!match(row.subclass_short_name,sub))continue;
      if(subsource&&row?.subclass_source&&!match(row.subclass_source,subsource))continue;
      const at=Number(row?.level??1);
      if(at>=1&&at<=level)append(row,origin,at,"class",name,source);
    }
  }
  // Invocations and other selected optional class traits are individual owned
  // benefits, not permanent class-level grants. Only project choices which
  // explicitly declare an attack-count grant in the structured catalogue.
  for(const optional of array(record.optional_features_catalog)){
    if(!optional?.name)continue;
    const rule=attackRules.find(grant=>match(grant.feature,optional.name)&&
      members.some(member=>match(member.name,grant.class_name)&&
        match(member.source||record.class_source||selectedEdition,grant.class_source)&&
        Number(member.level||0)>=Number(grant.min_level||1)));
    const amount=Number(optional.attacks_per_action||rule?.attacks_per_action);
    if(!Number.isSafeInteger(amount)||amount<2)continue;
    const origin=optional.origin_id||'optional|'+norm(optional.source)+'|'+norm(optional.name);
    // Use the same stable key as the optional-trait card in trait_projection.
    append({...optional,id:'0|'+norm(optional.name),attacks_per_action:amount},
      origin,0,'character','','',optional.disabled===true);
  }
  return results;
}
export function structuredFeatureGrants(record,catalogs={},features=collectStructuredFeatures(record,catalogs)){
  const result=[];
  for(const feature of features){
    if(!feature||feature.inactive)continue;
    // Source-qualified catalog grants; no class or feature names are interpreted here.
    for(const rule of CLASS_NUMERIC_FEATURE_GRANTS){
      const classSource=feature.class_source||String(feature.origin_key||'').split('|')[1];
      const owner=feature.class_name||feature.requirements?.class_name||String(feature.origin_key||'').split('|')[2];
      if(!match(owner,rule.class_name)||!match(classSource,rule.class_source)||
         !match(feature.name,rule.feature))continue;
      if(rule.max_class_level){
        const member=classMembers(record).find(c=>match(c.name,rule.class_name)&&match(c.source,rule.class_source));
        if(Number(member?.level||0)>rule.max_class_level)continue;
      }
      const value=rule.formula??rule.value;
      for(const target of array(rule.targets)){
        const grant=numericGrant(feature.origin_id,'Tratto · '+feature.name,rule.group,target,value,'',true);
        if(grant)result.push(grant);
      }
    }
    for(const row of array(feature.bonuses)){
      if(!row||typeof row!=="object")continue;
      const target=String(row.target||"");
      const grant=numericGrant(feature.origin_id,"Tratto · "+feature.name,
        "bonuses",target,row.expression,"|"+target,true);
      if(grant)result.push({...grant,requirements:feature.requirements,
        parent_origin:feature.origin_key});
    }
  }
  return result;
}
export function structuredOrigins(record,index={}){
  return selectedSources(record,index).map(row=>({id:row.id,
    active:!muted(record,row.id),group:row.group,name:row.origin,
    mode:row.mode}));
}
