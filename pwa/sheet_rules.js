import {variantOwns} from './creature_variants.js';
import {removedBenefitIds} from './trait_benefit_editor.js';
import {calculateSenses} from './sense_rules.js';
import {speciesDefenseEntries,speciesDefenseFeatures} from './species_defenses.js';
import {classDefenseEntries} from './class_defenses.js';
import {speciesRollModeEntries,speciesRollModeFeatures,speciesRollModeTrackers} from './species_roll_modes.js';
import {racialBonusFeatures,racialBonusEntries,racialBonusTrackers,racialAutomaticBonusGrants} from './species_conditional_bonuses.js';
import {originVariants,effectiveAllocations,allocationVariants} from './ability_choice_rules.js';
import {attackCountBenefits,attacksPerActionFromBenefits} from './attack_count_benefits.js';
import {collectEffectExtensions} from './effect_extensions.js';
import {armorStrengthWaivers,armorRuleEffects} from './armor_rules.js';
// Browser-only counterpart of creature_rules.gd / creature_bonus_rules.gd.
// It never sends a character sheet over the network. Numeric 5etools inputs
// are bundled with the PWA and loaded even when the native desktop is closed.
import {itemKind,requiresAttunement,itemAttunementCount,inventoryAttunementCounts,itemBenefitCopies,hasProperty,resolveOwnedItem,infusionNumericBonuses,activeInfusions,armorDexterityBonus,infusionInstanceOrigin} from "./item_controls.js";
import {automaticId,numericGrant,collectStructuredFeatures,structuredFeatureGrants,fixedProficiencies,effectiveBackgrounds,proficiencyGrantOrigins} from "./structured_effects.js";
import {structuredSpellGrants,featureTableSpellGrants,supplementalFeatureSpellGrants,supplementalSpeciesSpellFeatures,expandedOriginClassSpellIds,expandedOriginSpellFeatures} from './spell_selection.js';
import {racialPowerProjection,racialPowerSpellDefinitions} from './species_powers.js';
import {dragonbornFtdResistances} from './dragonborn_ftd.js';
import {supplementalClassSpells,supplementalItemBonuses} from './rule_supplements.js';
import {modifyFeatureTrackers,classFeatureDamage,classFeatureEffects,classFeatureActive,featureEnabled} from './feature_mechanics.js';

import {traitStateActions,activeTraitStates,traitStateAttacks,traitStateTrackers,traitStateNumericGrants,traitStateOptionalDice,traitStateEffects,traitStateRollModes} from './trait_state_rules.js';
import {featureItemGrants,racialItemGrantFeatures} from './feature_item_grants.js';
import {activeExhaustionEffects,exhaustionAdjustedValue,exhaustionIsDead} from './exhaustion_rules.js';

export const ABILITIES=["str","dex","con","int","wis","cha"];
export const SKILLS=[
 ["acrobatics","Acrobazia","dex"],["animal handling","Addestrare Animali","wis"],
 ["arcana","Arcano","int"],["athletics","Atletica","str"],
 ["deception","Inganno","cha"],["history","Storia","int"],
 ["insight","Intuizione","wis"],["intimidation","Intimidire","cha"],
 ["investigation","Indagare","int"],["medicine","Medicina","wis"],
 ["nature","Natura","int"],["perception","Percezione","wis"],
 ["performance","Intrattenere","cha"],["persuasion","Persuasione","cha"],
 ["religion","Religione","int"],["sleight of hand","Rapidità di Mano","dex"],
 ["stealth","Furtività","dex"],["survival","Sopravvivenza","wis"]
];
const fullSlots=[
 [0,0,0,0,0,0,0,0,0,0],[0,2,0,0,0,0,0,0,0,0],
 [0,3,0,0,0,0,0,0,0,0],[0,4,2,0,0,0,0,0,0,0],
 [0,4,3,0,0,0,0,0,0,0],[0,4,3,2,0,0,0,0,0,0],
 [0,4,3,3,0,0,0,0,0,0],[0,4,3,3,1,0,0,0,0,0],
 [0,4,3,3,2,0,0,0,0,0],[0,4,3,3,3,1,0,0,0,0],
 [0,4,3,3,3,2,0,0,0,0],[0,4,3,3,3,2,1,0,0,0],
 [0,4,3,3,3,2,1,0,0,0],[0,4,3,3,3,2,1,1,0,0],
 [0,4,3,3,3,2,1,1,0,0],[0,4,3,3,3,2,1,1,1,0],
 [0,4,3,3,3,2,1,1,1,0],[0,4,3,3,3,2,1,1,1,1],
 [0,4,3,3,3,3,1,1,1,1],[0,4,3,3,3,3,2,1,1,1],
 [0,4,3,3,3,3,2,2,1,1]
];
const int=(v,otherwise=0)=>Number.isFinite(Number(v))?Math.trunc(Number(v)):otherwise;
const clamp=(n,min,max)=>Math.min(max,Math.max(min,n));
const mod=n=>Math.floor((n-10)/2);
const godotRound=n=>Math.sign(n)*Math.floor(Math.abs(n)+0.5);
const arr=v=>Array.isArray(v)?v:[];
const norm=value=>String(value??"").trim().toLowerCase();
const same=(a,b)=>String(a??"").trim().toLowerCase()===String(b??"").trim().toLowerCase();
const key=(row)=>String(row?.name||"").toLowerCase()+"|"+String(row?.source||"").toLowerCase();

export function localClasses(record={}){
  const classes=arr(record.classes).filter(c=>c&&typeof c==="object"&&String(c.name||"").trim());
  return classes.length?classes:[...(record.class?[{name:record.class,source:record.class_source||"",level:record.level??1,
    subclass:record.subclass||"",subclass_source:record.subclass_source||""}]:[])];
}
export function classLevel(record,name,source=""){
  const classes=localClasses(record);
  const row=classes.find(c=>same(c.name,name)&&(!source||!c.source||same(c.source,source)));
  return Math.max(0,int(row?.level));
}
export function requirementsAllow(record,row){
  const gate=row?.requirements&&typeof row.requirements==="object"&&!Array.isArray(row.requirements)?row.requirements:{};
  const lvl=gate.scope==="class"?
    classLevel(record,gate.class_name,gate.class_source):int(record.level,1);
  const lo=Math.max(0,int(gate.min_level??row?.min_level,0));
  return lvl>=lo&&(gate.max_level===undefined||lvl<=int(gate.max_level));
}
export function parseArithmetic(expression,variable,{round=godotRound}={}){
  const raw=String(expression??"").trim().toLowerCase();
  if(!raw||/\d*d\d+\b/.test(raw)||!/^[a-z0-9_ .+*/()-]+$/.test(raw))
    throw Error("Formula aritmetica non valida");
  const tokens=raw.match(/(?:\d+(?:\.\d*)?|\.\d+)|[a-z_][a-z_0-9]*|[()+*/-]/g)||[];
  if(tokens.join("").toLowerCase()!==raw.replace(/\s+/g,""))throw Error("Espressione non valida");
  let i=0;
  const atom=()=>{
    const t=tokens[i++];
    if(t==="+"||t==="-")return (t==="-"?-1:1)*atom();
    if(t==="("){const value=expr();if(tokens[i++]!==")")throw Error("Parentesi incompleta");return value;}
    if(t&&/^(?:\d|\.\d)/.test(t)&&Number.isFinite(Number(t)))return Number(t);
    if(t&&/^[a-z_]/.test(t))return Number(variable(t));
    throw Error("Termine non valido");
  };
  const product=()=>{
    let value=atom();
    while(tokens[i]==="*"||tokens[i]==="/"){
      const op=tokens[i++],rhs=atom();
      if(op==="/"&&rhs===0)throw Error("Divisione per zero");
      value=op==="*"?value*rhs:value/rhs;
    }
    return value;
  };
  const expr=()=>{
    let value=product();
    while(tokens[i]==="+"||tokens[i]==="-"){
      const op=tokens[i++],rhs=product();value=op==="+"?value+rhs:value-rhs;
    }
    return value;
  };
  const value=expr();
  if(i!==tokens.length||!Number.isFinite(value))throw Error("Formula non calcolabile");
  return round(value);
}
function symbolTarget(value){
  if(ABILITIES.some(a=>value===a+"_score"))return "ability:"+value.slice(0,3);
  if(ABILITIES.some(a=>value===a+"_mod"))return "ability_mod:"+value.slice(0,3);
  if(value.startsWith("save_")&&ABILITIES.includes(value.slice(5)))return "save:"+value.slice(5);
  if(value.startsWith("skill_"))return "skill:"+value.slice(6).replaceAll("_"," ");
  return ({
    proficiency:"proficiency",prof:"proficiency",initiative:"initiative",ac:"ac",speed:"speed",
    climb_speed:"speed:climb",swim_speed:"speed:swim",fly_speed:"speed:fly",
    burrow_speed:"speed:burrow",max_hp:"hp",
    passive_perception:"passive_perception",passive_investigation:"passive_skill:investigation",level:"level"
  })[value]||null;
}
export function formulaValue(expression,calculated){
 return parseArithmetic(expression,name=>{
  const target=symbolTarget(name);
  if(!target||!Number.isFinite(calculated?.values?.[target]))throw Error('Variabile non disponibile: '+name);
  return calculated.values[target];
 });
}
export function validBonusDice(value){
 const match=String(value).toLowerCase().replaceAll(' ','').match(/^([1-9][0-9]*)d(4|6|8|10|12|20|100)([+-][0-9]+)?$/);
 return !!match&&Number(match[1])<=100;
}
export function applicableDiceBonuses(record,target,spells=[],calculated=null){
 const attunements=calculated?.attunements?.counts||inventoryAttunementCounts(record.inventory,
  calculated?.values?.attunement_max??record.attunement_max_base??3);
 record={...record,inventory:arr(record.inventory).map((item,i)=>
  requiresAttunement(resolveOwnedItem(item))?{...item,attuned_count:attunements[i]||0}:item)};
 const scope=target==='initiative'||/^(ability_check:|ability_mod:|skill:)/.test(target)?'ability_check':target.startsWith('save:')?'saving_throw':/^(attack_hit:|casting_hit:)/.test(target)||target==='spell_attack'?'attack_roll':target.startsWith('attack_damage:')||target==='spell_damage'?'damage_roll':'';
 if(!scope)return [];
 const enabled=id=>!id||record.origin_enabled?.[id]!==false&&!arr(record.proficiency_origins).some(o=>o.id===id&&o.disabled);
 const fits=row=>[target,scope].includes(row.target)||
   row.target==='skill_check'&&target.startsWith('skill:')||
   row.target==='tool_check'&&/^(?:ability_check:|ability_mod:)/.test(target)||
   row.target==='any_d20'&&scope!=='damage_roll'||
   // Attack-hit damage only. A spell's saving-throw damage is not an attack roll.
   row.target==='attack_damage'&&target.startsWith('attack_damage:')||
   row.target==='spell_attack'&&(target==='spell_attack'||target.startsWith('casting_hit:'));
 // Damage bonuses are selected manually; the sheet does not assume a hit or
 // infer a once-per-turn state from dice rolled outside the application.
 const damageAttack=target.startsWith('attack_damage:')?
   arr(calculated?.attacks).find(attack=>'attack_damage:'+attack.id===target):null;
 const racial=arr(calculated?.racial_roll_bonuses).filter(row=>!row.disabled&&!row.automatic_apply&&
   !(row.exclude_initiative&&target==='initiative')&&
   (validBonusDice(row.dice)||Number.isSafeInteger(row.flat_bonus)&&row.flat_bonus>0||
    Number(row.proficiency_multiplier)===2||row.flat_proficiency===true||
    row.weapon_damage_die===true)&&
   (arr(row.targets).some(key=>fits({target:key}))||fits(row))&&
   (!row.weapon_requirement||row.weapon_requirement!=='equipped_weapon'||
    !!damageAttack&&String(damageAttack.id).startsWith('item:'))&&
   (!row.melee_weapon_attack||!!damageAttack&&damageAttack.melee===true&&
    /^(?:item:|natural:)/.test(String(damageAttack.id)))).map(row=>{
     if(row.flat_proficiency)return {...row,target,
       flat_bonus:Math.max(0,Number(calculated?.values?.proficiency)||0)};
     if(row.weapon_damage_die){
       const die=String(damageAttack?.damage_base_formula||damageAttack?.damage||'')
         .match(/(?:^|[^\d])\d+d(4|6|8|10|12)(?!\d)/i);
       return die?{...row,target,dice:'1d'+die[1]}:null;
     }
     if(!row.proficiency_multiplier)return {...row,target};
     const skill=target.startsWith('skill:')?target.slice(6):'';
     const owned=arr(calculated?.proficiencies);
     const rank=skill?(owned.includes('expertise:'+skill)?2:owned.includes('skill:'+skill)?1:0):0;
     const amount=Math.max(0,Math.trunc((Number(row.proficiency_multiplier)-rank)*(Number(calculated?.values?.proficiency)||0)));
     return {...row,target,flat_bonus:amount};
   }).filter(row=>row&&(validBonusDice(row.dice)||
     Number.isSafeInteger(row.flat_bonus)&&row.flat_bonus>0));
 const rows=[...arr(record.dice_bonuses),...racial].filter(row=>row&&!row.disabled&&
   (validBonusDice(row.dice)||Number.isSafeInteger(row.flat_bonus)&&row.flat_bonus>0)&&fits(row))
   .flatMap(row=>{
    const id=String(row.origin_id||'');
    const fromItem=id.startsWith('item:')||id.startsWith('feature:trait:item:');
    if(!fromItem)return enabled(id)?[row]:[];
    const copies=arr(record.inventory).reduce((sum,saved)=>{
     const item=resolveOwnedItem(saved),itemKey='item:'+String(item.id||'');
     return (id===itemKey||id.startsWith('feature:trait:'+itemKey+'|'))&&itemActive(item,record)?
       sum+itemBenefitCopies(item):sum;
    },0);
    if(!copies)return [];
    if(copies===1)return [row];
    // A duplicate magic item grants its optional dice as many times as owned.
    const match=/^([1-9]\d*)d(4|6|8|10|12|20|100)([+-]\d+)?$/i.exec(String(row.dice).replace(/\s+/g,''));
    if(!match)return [row];
    const dice=Number(match[1])*copies,constant=Number(match[3]||0)*copies;
    if(dice>100)return [row]; // More than 100 dice cannot fit in one roll.
    return [{...row,dice:dice+'d'+match[2]+(constant?(constant>0?'+':'')+constant:''),multiplier:copies}];
   });
 for(const origin of arr(record.proficiency_origins)){
  if(origin?.group!=='spell'||!String(origin.id).startsWith('spell:')||!enabled(origin.id))continue;
  const id=origin.id.slice(6),spell=spells.find(s=>s.id===id),context=record.active_spell_context?.[id];
  if(!spell||!validBonusDice(context?.bonus_dice)||!arr(spell.roll_bonus_targets).some(key=>fits({target:key})))continue;
  rows.push({id:'spell_roll:'+id,origin_id:origin.id,origin_name:spell.name+' · '+(context.caster_name||''),dice:context.bonus_dice,automatic:true,consumes_spell:spell.consume_effect_on_roll?id:''});
 }
 return rows;
}
function fixedAbilities(row){
  const options=arr(row.ability).length?row.ability:[row.ability];
  if(options.some(o=>!o||typeof o!=="object"))return {};
  const intersection={};
  for(const stat of ABILITIES){
    if(options.every(o=>typeof o[stat]==="number"&&o[stat]===options[0][stat]))
      intersection[stat]=options[0][stat];
  }
  return intersection;
}
// Explicit 5etools allocations share a typed, source-qualified evaluator.
function selectedAbilityChoices(record,row,sid,index,group,legacy=''){
 return effectiveAllocations(record,sid,originVariants(index,group,row,row.source),legacy);
}
function indexRows(record,index,warnings){
  const rows=[];
  // Some source-specific subraces replace the entire parental ASI (e.g.
  // FTD Dragonborn, Eberron dragonmarks), rather than stacking onto it.
  const subraceASI=arr(index.subrace).find(r=>same(r.name,record.subrace)&&
    same(r.raceName,record.species)&&same(r.source,record.subrace_source));
  const replacesParentASI=!!subraceASI&&(
    subraceASI.replaces_parent_ability===true||
    Object.values(subraceASI.ability||{}).reduce((total,v)=>
      total+Math.max(0,Number(v)||0),0)>=3||
    same(record.species,'Human')&&/mark of/i.test(record.subrace||''));
  const append=(sid,name,amounts)=>{
    for(const [ability,value] of Object.entries(amounts)){
      const grant=numericGrant(sid,name,"ability","ability:"+ability,value);
      if(grant)rows.push(grant);
    }
  };
  const categories=[["race","species","species_source"]];
  for(const [group,field,sourceField] of categories){
    if(group==='race'&&replacesParentASI)continue;
    const value=record[field];
    if(!value)continue;
    const options=arr(index[group]).filter(r=>same(r.name,value)&&(!record[sourceField]||same(r.source,record[sourceField])));
    // A source-wide 5etools rule can grant ASIs even without an explicit
    // 'ability' field on the race itself (e.g. MPMM lineage creation).
    if(!options.length&&record[sourceField]&&index.source_ability_choices?.[String(record[sourceField]).toUpperCase()])
      options.push({name:value,source:record[sourceField]});
    if(!options.length){warnings.add("Bonus "+group+" non presenti nell’indice offline");continue;}
    if(!record[sourceField]&&new Set(options.map(r=>key(r))).size>1){
      warnings.add("Specifica la fonte di "+value+" per i bonus razziali");
      continue;
    }
    for(const row of options){
      const sid=group+"|"+String(row.source||"").toLowerCase()+"|"+String(row.name||"").toLowerCase();
      append(sid,row.name,fixedAbilities(row));
      for(const choice of selectedAbilityChoices(record,row,sid,index,group)){
        const grant=numericGrant(sid,row.name,"ability_choice","ability:"+choice.ability,choice.amount);
        if(grant)rows.push(grant);
      }
    }
  }
  for(const background of effectiveBackgrounds(record)){
    const options=arr(index.background).filter(row=>same(row.name,background.name)&&
      (!background.source||same(row.source,background.source)));
    if(!options.length){warnings.add("Bonus background non presenti nell’indice offline");continue;}
    for(const row of options){
      const sid="background|"+String(row.source||"").toLowerCase()+"|"+String(row.name||"").toLowerCase();
      append(sid,row.name,fixedAbilities(row));
      for(const choice of selectedAbilityChoices(record,row,sid,index,"background")){
        const grant=numericGrant(sid,row.name,"ability_choice","ability:"+choice.ability,choice.amount);
        if(grant)rows.push(grant);
      }
    }
  }
  if(record.subrace){
    const matches=arr(index.subrace).filter(r=>same(r.name,record.subrace)&&same(r.raceName,record.species)&&
      (!record.subrace_source||same(r.source,record.subrace_source)));
    if(matches.length===1){
      const r=matches[0],sid="subrace|"+String(r.source).toLowerCase()+"|"+String(r.name).toLowerCase();
      const subraceFixed=fixedAbilities(r);
      if(!replacesParentASI){
        const parent=arr(index.race).find(row=>same(row.name,record.species)&&
          same(row.source,record.species_source));
        for(const [stat,amount] of Object.entries(subraceFixed))
          if(Number(parent?.ability?.[stat])===amount)delete subraceFixed[stat];
      }
      append(sid,r.name,subraceFixed);
      for(const choice of selectedAbilityChoices(record,r,sid,index,"subrace")){
        const grant=numericGrant(sid,r.name,"ability_choice","ability:"+choice.ability,choice.amount);
        if(grant)rows.push(grant);
      }
    }else warnings.add("La sottorazza richiede un riferimento di fonte univoco");
  }
  for(const feat of arr(record.feats_catalog)){
    const matches=arr(index.feat).filter(r=>same(r.name,feat.name)&&same(r.source,feat.source));
    for(const row of matches){
      const sid="feat|"+String(row.source).toLowerCase()+"|"+String(row.name).toLowerCase();
      append(sid,row.name,fixedAbilities(row));
      for(const choice of selectedAbilityChoices(record,row,sid,index,"feat",feat.ability_choice)){
        const grant=numericGrant(sid,row.name,"ability_choice","ability:"+choice.ability,choice.amount);
        if(grant)rows.push(grant);
      }
    }
    // 2014 feat effects absent from 5etools ability-choice fields. The same
    // origin-gated formula pipeline handles both flat and level-scaled grants.
    const numeric=arr(index.feat_numeric_bonuses).find(rule=>
      same(rule.name,feat.name)&&same(rule.source,feat.source));
    const sid='feat|'+String(feat.source||'').toLowerCase()+'|'+String(feat.name||'').toLowerCase();
    for(const bonus of arr(numeric?.bonuses)){
      const target=String(bonus?.target||'').trim(),expression=String(bonus?.expression||'').trim();
      if(!target||!expression)continue;
      rows.push({id:automaticId(sid,'feat_numeric',target),origin_id:sid,
        origin_name:'Talento · '+feat.name,target,expression,automatic:true,disabled:false});
    }
  }
  return rows;
}
function itemActive(item,record={}){
  if(item.requirements&&!requirementsAllow(record,item))return false;
  if(int(item.quantity,1)<=0||item.active===false)return false;
  if(requiresAttunement(item)&&!itemAttunementCount(item))return false;
  const slots=arr(item.equipped_slots),kind=itemKind(item);
  if(kind==="armor")return slots.includes("body");
  if(["weapon","shield"].includes(kind))return slots.includes("main")||slots.includes("off");
  // Non-slotted inventory is always carried and grants its benefits without
  // a legacy "equipped" checkbox; attunement and explicit suspension remain gates.
  return true;
}
function numericField(o,snake,camel){const val=o?.[snake]??o?.[camel];return val===undefined||val===null?"":String(val);}
function itemRows(record,warnings,infusionCatalog=[],features=[],itemGrants=[]){
  const rows=[],seen=new Set(),seenAttacks=new Set();
  for(const [index,saved] of arr(record.inventory).entries()){
    const item=resolveOwnedItem(saved);
    if(!item||!item.id||!itemActive(item,record))continue;
    const sid="item:"+item.id,kind=itemKind(item),slots=arr(item.equipped_slots);
    const ordinary=!["weapon","armor","shield"].includes(kind);
    // Stacks represent independent item instances, not one shared bonus.
    // Preserve the original automatic ID for the first stack, and give later
    // stacks their own IDs so removals and explanations stay stable.
    const suffix=ordinary&&seen.has(sid)?"|stack:"+index:"";
    const copies=itemBenefitCopies(item);
    // Optional catalog supplements are typed grants, not parsed from item prose.
    // Existing per-item numeric fields always override fallback data.
    const rule=arr(itemGrants).find(entry=>arr(entry.names).some(name=>same(name,item.name))&&
      (!arr(entry.sources).length||arr(entry.sources).some(source=>same(source,item.source))));
    const supplemental=rule?.bonuses||{};
    const infusion=infusionNumericBonuses(record,item,infusionCatalog,features);
    const infusionName="Infusione · "+String(item.infusion?.name||"Artefice");
    const add=(target,field,snake,camel)=>{
      const raw=item?.[snake]??item?.[camel]??supplemental[target];
      const grant=numericGrant(sid,"Oggetto · "+(item.name||item.id),field,target,raw,suffix);
      if(grant){grant.multiplier=copies;rows.push(grant);}
    };
    if(["armor","shield"].includes(kind)&&!seen.has(sid))
      add("ac","bonus_ac","bonus_ac","bonusAc");
    if(kind==="weapon"){
      const targets=[];
      if(slots.includes("main"))targets.push("item:"+item.id,"item:throw:main:"+item.id);
      if(slots.includes("off"))targets.push("item:off:"+item.id,"item:throw:off:"+item.id);
      for(const attack of targets){
        if(seenAttacks.has(sid+"|"+attack))continue;
        seenAttacks.add(sid+"|"+attack);
        for(const [field,snake,camel,target] of [
          ["bonus_weapon","bonus_weapon","bonusWeapon","attack_hit:"+attack],
          ["bonus_weapon","bonus_weapon","bonusWeapon","attack_damage:"+attack],
          ["bonus_weapon_attack","bonus_weapon_attack","bonusWeaponAttack","attack_hit:"+attack],
          ["bonus_weapon_damage","bonus_weapon_damage","bonusWeaponDamage","attack_damage:"+attack]
        ])add(target,field,snake,camel);
        if(Number.isFinite(infusion.bonus_weapon)){
          for(const type of ["attack_hit:","attack_damage:"]){
            const grant=numericGrant(infusionInstanceOrigin(saved,index),infusionName,"infusion:"+item.infusion.id,type+attack,infusion.bonus_weapon);
            if(grant)rows.push(grant);
          }
        }
      }
    }
    // General infusion grants are per active item, while weapon grants
    // above follow the actual equipped hand and thrown-attack identities.
    if(infusion.bonus_ac!==undefined&&["armor","shield"].includes(kind)){
      const grant=numericGrant(infusionInstanceOrigin(saved,index),infusionName,"infusion:"+item.infusion.id,"ac",infusion.bonus_ac);
      if(grant)rows.push(grant);
    }
    if(infusion.bonus_spell_attack!==undefined){
      const grant=numericGrant(infusionInstanceOrigin(saved,index),infusionName,"infusion:"+item.infusion.id,"spell_attack",infusion.bonus_spell_attack);
      if(grant)rows.push(grant);
    }
    if(seen.has(sid)&&!ordinary)continue;
    seen.add(sid);
    add("saving_throw","bonus_saving_throw","bonus_saving_throw","bonusSavingThrow");
    add("ability_check","bonus_ability_check","bonus_ability_check","bonusAbilityCheck");
    add("passive_perception","bonus_passive_perception","bonus_passive_perception","bonusPassivePerception");
    for(const [field,camel,target] of [
      ["bonus_spell_attack","bonusSpellAttack","spell_attack"],
      ["bonus_spell_save_dc","bonusSpellSaveDc","spell_dc"],
      ["bonus_spell_damage","bonusSpellDamage","spell_damage"],
      ["bonus_proficiency_bonus","bonusProficiencyBonus","proficiency"],
      ["bonus_saving_throw_concentration","bonusSavingThrowConcentration","save_concentration"]
    ])add(target,field,field,camel);
    const abilities=item.bonus_ability??item.bonusAbility;
    if(abilities&&typeof abilities==="object")
      for(const [stat,value] of Object.entries(abilities))
        if(ABILITIES.includes(stat)){
          const grant=numericGrant(sid,"Oggetto · "+(item.name||item.id),
            "ability","ability:"+stat,value,suffix);
          if(grant){grant.multiplier=copies;rows.push(grant);}
        }
  }
  return rows;
}
function hasProficiency(record,type,id,computed){
  if(computed)return computed.has(type+":"+String(id).toLowerCase());
  const rows=arr(record.proficiency_choices);
  const matches=rows.filter(row=>row?.kind===type&&same(row.key,id));
  if(matches.length)return matches.some(row=>!row.disabled&&
    !arr(record.proficiency_origins).some(origin=>origin.id===row.origin_id&&origin.disabled));
  const fields={skill:"skill_proficiencies",expertise:"skill_expertise",save:"saving_throw_proficiencies"};
  const legacy=record[fields[type]];
  // Native restores legacy ranks only while the new origin choice model is absent.
  const migrate=!Object.hasOwn(record,"proficiency_choices")||
    (rows.length===0&&!Object.hasOwn(record,"proficiency_origins"));
  return migrate&&arr(legacy).some(value=>same(value,id));
}
function crNumber(raw){
  const value=typeof raw==="object"&&raw!==null?raw.cr:raw;
  if(typeof value==="string"&&value.includes("/")){
    const [a,b]=value.split("/").map(Number);return b>0?a/b:0;
  }
  return Math.max(0,Number(value)||0);
}
function classHitDice(record,classes,catalog){
  let first=true,total=0;const parts=[];
  for(const cls of classes){
    const options=arr(catalog.classes).filter(r=>same(r.name,cls.name));
    let chosen=options.find(r=>same(r.source,cls.source));
    if(!chosen){
      // Native ClassMechanics.class_row() prefers PHB, XPHB, TCE in this order.
      chosen=["PHB","XPHB","TCE"].map(book=>options.find(r=>same(r.source,book)))
        .find(Boolean)||options[0];
    }
    if(!chosen){return {available:false,reason:"Classe non inclusa nei dadi vita locali: "+cls.name};}
    const hd=int(chosen.hit_die),count=clamp(int(cls.level,1),1,20);
    const subtotal={die:hd,count,name:cls.name};parts.push(subtotal);
    if(hd<=0)return {available:false,reason:"Dado vita non noto per "+cls.name};
  }
  return {available:true,parts};
}
export function classMechanicsRow(catalog,name,source=''){
 const rows=arr(catalog?.classes).filter(r=>same(r.name,name));
 return rows.find(r=>same(r.source,source))||['PHB','XPHB','TCE'].map(book=>rows.find(r=>same(r.source,book))).find(Boolean)||rows[0];
}
// Port of ClassSpellSelection.classes(): actual table data, per-class limits,
// separate cantrip capacity and class spellcasting ability, including 2024.
export function castingClasses(record,catalog,abilityModifiers={}){
 return localClasses(record).flatMap(member=>{
  const source=member.source||(record.rules_version==='2024'?'XPHB':'PHB');
  const row=classMechanicsRow(catalog,member.name,source),data=row?.spellcasting;
  if(!data||!Object.keys(data).length)return [];
  const level=clamp(int(member.level,1),1,20),id='class|'+source.toLowerCase()+'|'+member.name.toLowerCase();
  const ability=({wizard:'int',artificer:'int',cleric:'wis',druid:'wis',ranger:'wis',paladin:'cha',bard:'cha',sorcerer:'cha',warlock:'cha'})[member.name.toLowerCase()]||'int';
  let limit=-1,mode='Conosciuti';
  if(Array.isArray(data.preparedSpellsProgression)){limit=int(data.preparedSpellsProgression[level-1]);mode='Preparati';}
  else if(data.preparedSpells){
   const expr=data.preparedSpells.replace(/<\$([a-z_]+)\$>/g,(_,key)=>key);
   try{limit=Math.max(1,parseArithmetic(expr,key=>key==='level'?level:abilityModifiers[key.slice(0,3)]??mod(int(record.abilities?.[key.slice(0,3)],10)),{round:Math.floor}));}catch{limit=-1;}
   mode='Preparati';
  }else if(Array.isArray(data.spellsKnownProgression))limit=int(data.spellsKnownProgression[level-1]);
  const progression=spellProgression(record,[member]);
  const maxLevel=Math.max(progression.pact_total?progression.pact_level:0,...progression.slots.map((n,i)=>n>0?i:0));
  if(!maxLevel)limit=0;
  return [{id,name:member.name,source,level,mode,limit,cantrips:int(data.cantripProgression?.[level-1]),max_level:maxLevel,book:same(member.name,'wizard'),ability}];
 });
}
function subclassKey(value){
 return String(value||'').toLowerCase().trim().replace(/^(?:school of |circle of |oath of |college of |domain of |way of the |way of |the )/,'').replace(/ (?:domain|school)$/,'');
}
// Same stable tracker IDs and recovery events as StructuredResourceTrackers.
// Source-qualified feat mechanics are ordinary typed tracker/roll/action grants.
// No talent names appear in the runtime projection logic.
export function featMechanicGrants(record={},index={}){
 const result={trackers:[],roll_modes:[],roll_bonuses:[],movement_rules:[],spell_imprints:[],actions:[]};
 for(const feat of arr(record.feats_catalog)){
  if(!feat?.name||feat.disabled)continue;
  const rule=arr(index.feat_mechanics).find(row=>same(row.name,feat.name)&&same(row.source,feat.source));
  if(!rule)continue;
  const origin_id='feat|'+norm(feat.source)+'|'+norm(feat.name);
  for(const raw of arr(rule.trackers))result.trackers.push({...raw,origin_id,
    origin_name:'Talento · '+feat.name,automatic:true});
  for(const raw of arr(rule.roll_modes))result.roll_modes.push({...raw,origin_id,
    origin_name:'Talento · '+feat.name,feat_name:feat.name});
  for(const raw of arr(rule.roll_bonuses))result.roll_bonuses.push({...raw,origin_id,
    origin_name:'Talento · '+feat.name,feat_name:feat.name});
  for(const raw of arr(rule.movement_rules))result.movement_rules.push({...raw,origin_id,
    origin_name:'Talento · '+feat.name,feat_name:feat.name});
  for(const raw of arr(rule.spell_imprints))result.spell_imprints.push({...raw,origin_id,
    origin_name:feat.name,feat_name:feat.name});
  for(const raw of arr(rule.actions))result.actions.push({...raw,origin_id,
    origin_name:'Talento · '+feat.name,origin_key:origin_id,automatic:true,
    cost:Math.max(0,Number(raw.resource_cost)||0),time:raw.action_type||raw.activation||'reaction'});
 }
 return result;
}
export function resourceTrackers(record,catalog,resolve=()=>0){
 const rows=new Map();
 const features=[];
 const append=(row,origin,level=0,member=null)=>{
  if(!row?.name)return;
  features.push({...row,key:origin+'|'+(row.id||origin+'|'+level+'|'+row.name.toLowerCase()),origin_key:origin,parent_origin:member?'class|'+String(member.source||'').toLowerCase()+'|'+member.name.toLowerCase():''});
 };
 for(const member of localClasses(record))for(const row of arr(catalog?.resource_features)){
  if(!same(row.class_name,member.name)||member.source&&!same(row.class_source,member.source)||int(row.level)<1||int(row.level)>int(member.level))continue;
  const origin='class|'+String(member.source||'').toLowerCase()+'|'+member.name.toLowerCase();
  if(row.subclass_name||row.subclass_short_name){
   if(!same(row.subclass_name,member.subclass)&&!same(row.subclass_short_name,member.subclass)||member.subclass_source&&!same(row.subclass_source,member.subclass_source))continue;
   append(row,origin+'|subclass|'+String(member.subclass||'').toLowerCase()+'|'+String(member.subclass_source||'').toLowerCase(),int(row.level),member);
  }else append(row,origin,int(row.level),member);
 }
 if(record.kind==='monster')for(const section of ['trait','action','bonus','reaction','legendary','mythic'])for(const feature of arr(record.stat_block?.[section]))append(feature,'monster|'+section);
 const add=row=>{if(row.id&&!rows.has(row.id))rows.set(row.id,row);};
 for(const member of localClasses(record)){
  const level=int(member.level),base=classMechanicsRow(catalog,member.name,member.source);
  if(!base||level<1||level>20)continue;
  const prefix='class:'+member.name.toLowerCase()+':'+base.source.toLowerCase()+':';
  const makeId=name=>prefix+name.toLowerCase().replaceAll(' ','_');
  for(const column of arr(base.columns)){
   const max=column.levels?.[level-1];
   if(column.kind==='resource'&&typeof max==='number'&&max>0)
    add({id:makeId(column.name),name:column.name,max:int(max),origin_name:column.origin_feature||column.name,origin_feature_key:column.origin_feature_key||'',origin_class:member.name,origin_class_source:base.source,recharge:'manual',automatic:true});
  }
  for(const group of arr(catalog?.resource_overrides).filter(r=>same(r.class,member.name)&&same(r.source,base.source))){
   for(const resource of arr(group.resources)){
    if(resource.subclass&&subclassKey(resource.subclass)!==subclassKey(member.subclass||record.subclass))continue;
    const steps=arr(resource.steps).filter(s=>requirementsAllow(record,{requirements:{scope:'class',class_name:member.name,class_source:base.source,min_level:int(s.level),...s.requirements}})).sort((a,b)=>int(b.requirements?.min_level??b.level)-int(a.requirements?.min_level??a.level));
    const step=steps[0];if(!step)continue;
    const columnName=resource.column||resource.name,column=arr(base.columns).find(c=>c.name===columnName);
    if(column&&(typeof column.levels?.[level-1]!=='number'||column.levels[level-1]<=0))continue;
    const id=makeId(columnName);
    if(rows.has(id)){rows.get(id).recharge=step.reset||'manual';continue;}
    try{
     const max=Math.max(int(resource.minimum),parseArithmetic(step.value,resolve));
     if(max>0)add({id,name:resource.name,max,max_formula:String(step.value),origin_name:resource.origin_feature||resource.name,origin_feature_key:resource.origin_feature_key||'',origin_class:member.name,origin_class_source:base.source,origin_subclass:resource.subclass||'',origin_subclass_source:resource.subclass?(resource.source||member.subclass_source||''):'',recharge:step.reset||'manual',automatic:true});
    }catch{ /* An unsupported formula cannot invent a resource maximum. */ }
   }
  }
 }
 if(record.kind==='monster'){
  const stat=record.stat_block||{};
  if(int(stat.legendaryActions)>0)add({id:'legendary_actions',name:'Azioni leggendarie',max:int(stat.legendaryActions),recharge:'turn',automatic:true});
  for(const section of ['trait','action','bonus','reaction','legendary','mythic'])arr(stat[section]).forEach((feature,i)=>{
   const m=String(feature?.name||'').match(/\{@recharge(?: ([1-6]))?\}/);
   if(m)add({id:'recharge:'+section+':'+i,name:feature.name.replace(m[0],'').trim(),max:1,recharge:'d6',recharge_min:int(m[1],6),automatic:true});
  });
  const clean=name=>String(name||'').replace(/\{@recharge(?: [1-6])?\}|\(recharge [1-6](?:-[1-6])?\)/i,'').trim();
  const supplement=arr(catalog?.monster_resources).find(row=>same(row.source,stat.source??record.source)&&same(row.name,stat.name??record.base_name));
  for(const resource of arr(supplement?.resources)){
   if(int(resource.max)<=0||!['d6','turn','short_rest','long_rest'].includes(resource.recharge))continue;
   if(resource.legendary_pool){if(arr(stat.legendary).length)add({id:'legendary_actions',name:'Azioni leggendarie',max:int(resource.max),recharge:'turn',automatic:true});continue;}
   if(!['trait','action','bonus','reaction','legendary','mythic'].includes(resource.section))continue;
   const matches=arr(stat[resource.section]).map((feature,i)=>({feature,i})).filter(({feature})=>same(clean(feature?.name),clean(resource.name)));
   if(matches.length!==1)continue;
   const {feature,i}=matches[0];if(rows.has('recharge:'+resource.section+':'+i))continue;
   add({id:'fightclub:'+resource.section+':'+i,name:clean(feature.name),max:int(resource.max),recharge:resource.recharge,...(resource.recharge==='d6'?{recharge_min:int(resource.recharge_min,6)}:{}),automatic:true});
  }
 }
 for(const row of rows.values()){
  const ref=String(row.origin_feature_key||'').replace(/^feature:/,''),wanted=String(row.origin_name||row.name).trim().toLowerCase();
  const matches=ref?features.filter(f=>f.key===ref):features.filter(f=>{
   if(row.origin_class){
    if(!same(f.class_name,row.origin_class)||!same(f.class_source,row.origin_class_source))return false;
    const subclassParts=String(f.origin_key||'').split('|subclass|');
    if((subclassParts.length>1)!==!!row.origin_subclass)return false;
    if(row.origin_subclass){
     const [name,source]=subclassParts[1].split('|');
     // Older characters omit the selected subclass source in their saved
     // origin key; fall back to the source-qualified catalog feature itself.
     const actualSource=source||f.subclass_source||'';
     if(subclassKey(name)!==subclassKey(row.origin_subclass)||
       row.origin_subclass_source&&actualSource&&!same(actualSource,row.origin_subclass_source))return false;
    }
   }
   const name=f.name.trim().toLowerCase();return name===wanted||name.startsWith(wanted+' {')||name.startsWith(wanted+' (');
  });
  const exact=matches.filter(f=>f.name.trim().toLowerCase()===wanted);
  const feature=exact.length===1?exact[0]:matches.length===1?matches[0]:null;
  // A class table only supplies capacity. Without its granting class trait,
  // the class does not independently produce an actionable resource.
  if(row.origin_class&&!feature){
    row.disabled=true;
    row.origin_id='';
    continue;
  }
  row.origin_id=feature?'feature:'+feature.key:'tracker:auto:'+row.id; // non-class (monster) counters only
  row.origin_name=feature?'Tratto · '+feature.name:row.origin_name||row.name;
  if(feature?.parent_origin)row.parent_origin=feature.parent_origin;
  if(feature)row.disabled=feature.inactive||feature.disabled||record.origin_enabled?.[row.origin_id]===false||
   record.origin_enabled?.[feature.origin_key]===false||arr(record.proficiency_origins).some(o=>
    o?.disabled&&[row.origin_id,feature.origin_key,feature.parent_origin].includes(o.id));
 }
 for(const row of arr(record.resource_trackers)){
  if(!row||!requirementsAllow(record,row))continue;
  let max=Math.max(0,int(row.max));
  let formula_error='';
  if(row.max_formula)try{max=Math.max(0,int(row.min_max),parseArithmetic(row.max_formula,resolve));}catch(error){formula_error=error.message;}
  if(row.id&&row.name)add({...row,max,formula_error,automatic:false});
 }
 return modifyFeatureTrackers(record,[...rows.values()].filter(row=>!row.disabled&&!arr(record.proficiency_origins).some(o=>o?.id===row.origin_id&&o.disabled)&&record.origin_enabled?.[row.origin_id]!==false),catalog?.feature_rules||{});
}
// CreatureAttackData / CreatureItemRules projection: each equipped hand keeps
// its native stable attack ID. Published monster totals already include PB.
export function attackCalculations(record,abilities,proficiency,proficiencies=[],bonus=()=>0,featureContext={}){
 const out=[],inventory=arr(record.inventory).map(resolveOwnedItem),trained=new Set(proficiencies);
 const occupied=slot=>inventory.find(row=>int(row?.quantity,1)>0&&arr(row?.equipped_slots).includes(slot));
 const main=occupied('main'),physicalOff=occupied('off');
 // Preserve the one-handed damage until the stored offhand is actually clear.
 const offBlocked=Boolean(main&&(hasProperty(main,'2H')||
   record.hand_grip_two_handed&&hasProperty(main,'V'))&&record.hand_off_with_two_handed!==true);
 const off=offBlocked?null:physicalOff;
 const dual=arr(record.feats_catalog).some(f=>!f?.disabled&&same(f.name,'Dual Wielder'));
 const offAllowed=main&&off&&itemKind(main)==='weapon'&&itemKind(off)==='weapon'&&
   (String(record.rules_version)==='2024'?hasProperty(main,'L')&&(hasProperty(off,'L')||dual&&String(off.type).split('|')[0]!=='R'):
    String(main.type).split('|')[0]!=='R'&&String(off.type).split('|')[0]!=='R'&&(hasProperty(main,'L')&&hasProperty(off,'L')||dual));
 const style=record.two_weapon_fighting||['fighting_styles','proficiency_choices','proficiency_origins','selected_features','feats_catalog','trait_choices'].some(field=>arr(record[field]).some(row=>{
   if(row?.disabled)return false;
   const label=typeof row==='string'?row:[row?.name||row?.label||row?.key||'',...['fighting_style','fightingStyle','selected_style','selected','choice'].map(k=>typeof row?.[k]!=='boolean'?row?.[k]||'':'')].join(' ');
   return label.toLowerCase().includes('two-weapon fighting');
 }));
 const sign=n=>n>0?' + '+n:n<0?' − '+Math.abs(n):'';
 const append=(attack,ability,proficient,damage,baseHit=null)=>{
  const settings=record.attack_overrides?.[attack.id]||{};
  const modifier=abilities[ability]?.modifier??0;
  const hit=(baseHit??(modifier+(proficient?proficiency:0)))+bonus('attack_hit:'+attack.id);
  let damageMod=baseHit!==null||attack.damage_ability_modifier===false?0:modifier;
  if(attack.slot==='off'&&offAllowed&&!style)damageMod=Math.min(0,damageMod);
  const damageAbilityModifier=damageMod;
  const featureDamage=classFeatureDamage(record,featureContext,attack,ability);
  const damageExtraModifier=bonus('attack_damage:'+attack.id)+featureDamage;
  damageMod+=damageExtraModifier;
  const range=clamp(int(settings.range_feet,attack.range_feet)+bonus('attack_range:'+attack.id),5,1000);
  const longRange=attack.melee||!attack.long_range_feet?0:clamp(int(settings.long_range_feet,attack.long_range_feet)+bonus('attack_long_range:'+attack.id),5,5000);
  const usedBase=featureContext.damageBase?featureContext.damageBase(attack.id,damage):damage;
  out.push({...attack,ability,proficient,hit,damage:usedBase?usedBase+sign(damageMod):'Come da bestiario',
    damage_base_formula:usedBase||'',damage_ability_modifier:damageAbilityModifier,
    damage_extra_modifier:damageExtraModifier,range_feet:range,long_range_feet:longRange,
    explanation:baseHit!==null?'Bestiario '+baseHit+' · competenza già inclusa':'Caratteristica '+modifier+' + competenza '+(proficient?proficiency:0)+' + bonus '+bonus('attack_hit:'+attack.id),
    feature_damage:featureDamage,damage_explanation:featureDamage?'Ira +'+featureDamage:'',
    offhand_bonus:attack.slot==='off'||attack.slot==='shield'&&attack.hand==='off'});
 };
 for(const weapon of traitStateAttacks(record,featureContext.features,featureContext.traitStates))append(weapon,weapon.ability,true,weapon.damage);
 for(const section of ['action','bonus','reaction','legendary','mythic'])arr(record.stat_block?.[section]).forEach((action,i)=>{
  if(!action?.name)return;
  const text=JSON.stringify(action.entries||[]),hit=text.match(/\{@hit\s*([+-]?\d+)\}/)||text.match(/([+-]\d+)\s+to\s+hit/i);
  if(!hit&&!/\{@atk |weapon attack:|spell attack:/i.test(text))return;
  const ranged=/ranged|\{@atk r[ws]\}/i.test(text),reach=int(text.match(/reach\s*(\d+)\s*(?:ft|feet)/i)?.[1],5);
  const range=text.match(/range\s*(\d+)(?:\/(\d+))?/i),damage=text.match(/\{@damage\s*([^}]+)\}/)?.[1]||text.match(/\d+d\d+(?:\s*[+-]\s*\d+)*/)?.[0]||'';
  append({id:'monster:'+section+':'+i,name:action.name,melee:!ranged||/melee or ranged/i.test(text),range_feet:ranged?int(range?.[1],5):reach,long_range_feet:ranged?int(range?.[2]):0},ranged?'dex':'str',true,damage,int(hit?.[1]));
 });
 for(const slot of ['main','off']){
  const item=slot==='off'?off:main;if(!item||itemKind(item)!=='weapon')continue;
  const ranged=String(item.type||'').split('|')[0].toUpperCase()==='R';
  const ranges=String(item.range||'').split('/').map(Number),reach=hasProperty(item,'R')?10:5;
  const proficient=trained.has('weapon:'+String(item.name).toLowerCase())||trained.has('weapon:'+String(item.weapon_category).toLowerCase())||trained.has('weapon:all');
  // By default, the selected ability only overrides Finesse weapons.
  // When the scope toggle is off, it applies to every equipped weapon.
  const chosen=['str','dex','con','int','wis','cha'].includes(record.attack_ability)?
    record.attack_ability:'str';
  const ability=record.attack_ability_finesse_only===false?chosen:
    hasProperty(item,'F')?chosen:ranged?'dex':'str';
  let damage=item.damage||'';
  if(slot==='main'&&!physicalOff&&hasProperty(item,'V')&&record.hand_grip_two_handed&&item.versatile_damage)damage=item.versatile_damage;
  const size=item.instance_overrides?.weapon_size||record.size_name||'Medium',factor=({Large:2,Huge:3,Gargantuan:4})[size]||1;
  if(factor>1)damage=damage.replace(/^(\s*)(\d+)d(\d+)/,(_,space,count,die)=>space+(Number(count)*factor)+'d'+die);
  const attack={id:'item:'+(slot==='off'?'off:':'')+item.id,name:item.name+(slot==='off'?' · secondaria':''),slot,melee:!ranged,range_feet:ranged?Math.max(5,ranges[0]||0):reach,long_range_feet:ranged?ranges[1]||0:0,damage_type:item.damage_type||''};
  append(attack,ability,proficient,damage);
  if(!ranged&&hasProperty(item,'T')&&ranges[0]>0)append({...attack,id:'item:throw:'+slot+':'+item.id,name:attack.name+' · lancio',melee:false,range_feet:ranges[0],long_range_feet:ranges[1]||0},ability,proficient,damage);
 }
 // A shield can be used as an improvised weapon when actually equipped.
 // Keep its own stable attack ID for dice, modifiers and the Actions tab.
 for(const slot of ['main','off']){
  const shield=slot==='off'?off:main;
  if(!shield||itemKind(shield)!=='shield')continue;
  append({id:'shield:improvised:'+slot+':'+shield.id,
    name:(shield.name||'Scudo')+' · arma improvvisata'+(slot==='off'?' · secondaria':''),slot:'shield',hand:slot,
    melee:true,range_feet:5,long_range_feet:0,damage_type:'contundente'},
    'str',trained.has('weapon:improvised'),'1d4');
 }
 // Unarmed strikes are always possible: never require a fictitious equipped weapon.
 // The off hand adds a separate bonus-action row only while free and unlocked.
 const unarmed=(slot)=>{
  const id=slot==='off'?'unarmed:off':'unarmed';
  append({id,name:"Colpo senz’armi"+(slot==='off'?' · secondaria':''),slot,
    melee:true,range_feet:5,long_range_feet:0,damage_type:'contundente'},'str',true,'1');
  // The default 2014 strike has a minimum of 1 damage. A typed replacement
  // such as 1d4 is a damage *die*, not a flat 1 plus another 1d4.
  if(out[out.length-1].damage_base_formula==='1')
    out[out.length-1].damage=String(Math.max(1,1+(abilities.str?.modifier??0)+
      bonus('attack_damage:'+id)+classFeatureDamage(record,featureContext,{},'str')));
 };
 unarmed('main');
 if(!off&&!offBlocked)unarmed('off');
 // Natural strikes are typed, source-qualified 5etools mechanics generated at
 // catalog sync time. A natural weapon requires no equipped item or free hand.
 // Their own trait remains the origin for disabling and inspecting benefits.
 const naturalCatalog=arr(featureContext.speciesAttacks?.races);
 const ownRace=naturalCatalog.find(row=>record.species_id&&row.id===record.species_id)||
   naturalCatalog.find(row=>same(row.name,record.species)&&
     record.species_source&&same(row.source,record.species_source));
 if(record.kind!=='monster'&&ownRace){
   const origin='species|'+(record.species_id||String(record.species||'').toLowerCase())+
     '|'+String(ownRace.source||'').toLowerCase();
   const legacy='race|'+String(ownRace.source||'').toLowerCase()+'|'+
     String(ownRace.name||'').toLowerCase();
   const paused=id=>record.origin_enabled?.[id]===false||
     arr(record.proficiency_origins).some(r=>r?.id===id&&r.disabled);
   if(!paused(origin)&&!paused(legacy))for(const natural of arr(ownRace.attacks)){
     const trait=arr(featureContext.features).find(row=>same(row.name,natural.trait)&&
       row.origin_key===origin);
     const traitId=trait?.origin_id||'feature:'+origin+'|1|'+String(natural.trait).toLowerCase();
     if(trait?.disabled||trait?.inactive||paused(traitId))continue;
     const id='natural:'+String(ownRace.id||ownRace.name).toLowerCase()+':'+
       String(natural.trait).toLowerCase().replace(/[^a-z0-9]+/g,'-');
     const type=({slashing:'taglienti',piercing:'perforanti',bludgeoning:'contundenti'})[natural.damage_type]||natural.damage_type;
     append({id,name:natural.trait,slot:'natural',melee:true,range_feet:5,long_range_feet:0,
       damage_type:type,damage_ability_modifier:natural.damage_ability_modifier!==false,
       origin_id:traitId,origin_name:'Tratto · '+natural.trait,
       description:'Attacco naturale concesso dal tratto '+natural.trait+'.'},
       natural.ability||'str',true,natural.damage);
   }
 }
 // Explicit improvised attacks remain selectable without affecting unarmed strikes.
 for(const slot of ['main','off']){
  if(record['hand_'+slot+'_special']!=='improvised'||slot==='off'&&(off||offBlocked))continue;
  const id=slot==='off'?'improvised:off':'improvised';
  append({id,name:'Arma improvvisata'+(slot==='off'?' · secondaria':''),slot,
    melee:true,range_feet:5,long_range_feet:0,damage_type:'contundente'},
    'str',trained.has('weapon:improvised'),'1d4');
 }
 return out;
}
export function spellProgression(record,classes){
  const edition=String(record.rules_version||"2014"),sources=[];let warlock=0;
  const warnings=[];
  for(const cls of classes){
    const name=String(cls.name||"").toLowerCase(),level=clamp(int(cls.level,1),1,20);
    if(name==="warlock")warlock+=level;
    else if(["bard","cleric","druid","sorcerer","wizard"].includes(name))sources.push(["full",level]);
    else if(name==="artificer")sources.push(["half_up",level]);
    else if(["paladin","ranger"].includes(name)){
      if(level>=2||edition==="2024")sources.push(["half",level]);
    }else if(["fighter","rogue"].includes(name)){
      warnings.push("Le sottoclassi magiche di "+cls.name+" richiedono regole specifiche");
    }
  }
  const multiclass=sources.length>1;
  const caster=clamp(sources.reduce((sum,[kind,lvl])=>sum+(kind==="full"?lvl:
    kind==="half_up"||!multiclass||edition==="2024"?Math.ceil(lvl/2):Math.floor(lvl/2)),0),0,20);
  return {slots:[...fullSlots[caster]],pact_total:warlock===0?0:warlock===1?1:warlock<11?2:warlock<17?3:4,
    pact_level:warlock?Math.min(5,Math.ceil(warlock/2)):1,caster_level:caster,warnings};
}
export function calculateSheet(record={},catalogs={}){
  let effective=record;
  // Imported or externally edited stacks can exceed the current capacity.
  // Bound their effective benefits without rewriting the owner's saved data.
  for(let pass=0;pass<8;pass++){
    const calculated=calculateSheetValues(effective,catalogs);
    const maximum=Math.max(0,Math.floor(Number(calculated.values.attunement_max)||0));
    const counts=inventoryAttunementCounts(effective.inventory,maximum);
    if(counts.every((count,i)=>count===itemAttunementCount(arr(effective.inventory)[i])))
      return {...calculated,attunements:{counts,maximum,used:counts.reduce((sum,n)=>sum+n,0)}};
    effective={...effective,inventory:arr(effective.inventory).map((item,i)=>
      requiresAttunement(resolveOwnedItem(item))?{...item,attuned_count:counts[i],attuned:counts[i]>0}:item)};
  }
  const inventory=arr(effective.inventory).map(item=>requiresAttunement(resolveOwnedItem(item))?
    {...item,attuned_count:0,attuned:false}:item);
  const result=calculateSheetValues({...effective,inventory},catalogs);
  result.warnings.push('Sintonie sospese: il massimo dipende dalle stesse sintonie.');
  result.complete=false;
  return {...result,attunements:{counts:inventory.map(()=>0),maximum:Math.max(0,Math.floor(result.values.attunement_max||0)),used:0}};
}
function calculateSheetValues(record={},catalogs={}){
  if(record.variant_rules_kind==='monster')record={...record,kind:'monster'};
  const suppressed=removedBenefitIds(record);
  // Suppress legacy/manual grants in the calculation as well as in the popup.
  // The original catalog grants remain untouched and recoverable.
  record={...record,
   formula_bonuses:arr(record.formula_bonuses).filter(r=>!suppressed.has('bonus:'+r.id)),
   dice_bonuses:arr(record.dice_bonuses).filter(r=>!suppressed.has('dice:'+String(r.id||[r.origin_id,r.target,r.dice].join('|')))),
   damage_defense_entries:arr(record.damage_defense_entries).filter(r=>!suppressed.has('defense:'+String(r.origin_id||'')+':'+r.rank+':'+String(r.key||'').toLowerCase())),
   resource_trackers:arr(record.resource_trackers).filter(r=>!suppressed.has('tracker:'+r.id)),
   origin_spell_grants:arr(record.origin_spell_grants).filter(r=>!suppressed.has('spell:'+r.origin_id+':'+r.spell_id)),
   effect_extensions:arr(record.effect_extensions).filter(r=>!suppressed.has('effect_extension:'+r.id)),
   action_grants:arr(record.action_grants).filter(r=>!suppressed.has('action:'+r.id))
  };
  const warnings=new Set(),index=catalogs.abilityGrants,classesCatalog=catalogs.classMechanics;
  const featMovement=featMechanicGrants(record,index).movement_rules;
  if(!index)warnings.add("Indice delle origini non caricato: i bonus automatici sono incompleti");
  if(!classesCatalog)warnings.add("Catalogo classi non caricato: dadi vita automatici non disponibili");
  if(catalogs.speciesAttacks?.load_error)warnings.add("Catalogo attacchi naturali non disponibile: gli attacchi della specie sono incompleti");
  const classes=localClasses(record),kind=record.kind==="monster"?"monster":"character";
  const exhaustion_effects=activeExhaustionEffects(record,catalogs.exhaustionRules||{});
  if(kind==='character'&&!variantOwns(record,'movement')){
    const races=arr(classesCatalog?.races);
    const race=races.find(row=>record.species_id&&row.id===record.species_id)||races.find(row=>same(row.name,record.species)&&same(row.source,record.species_source));
    const subrace=record.subrace?arr(classesCatalog?.subraces).find(row=>
      same(row.raceName,record.species)&&same(row.name,record.subrace)&&
      same(row.source,record.subrace_source)&&same(row.raceSource,record.species_source)):null;
    // Bridge the still-packaged native references until regeneration copies
    // subtype movement to the canonical subrace record.
    const nativeSource=record.subrace&&subrace?.speed===undefined?races.find(row=>
      same(row.name,record.species+' ('+record.subrace+')')&&
      same(row.source,record.subrace_source)):null;
    const speed=subrace?.speed??nativeSource?.speed??race?.speed;
    if(speed!==undefined)record={...record,species_speed:speed};
  }
  const level=classes.reduce((sum,c)=>sum+Math.max(0,int(c.level)),0);
  const activeItemCopies=new Map(),alwaysCarriedSources=new Set();
  for(const saved of arr(record.inventory)){
    const item=resolveOwnedItem(saved);
    if(!item?.id||!itemActive(item,record))continue;
    const kind=itemKind(item),amount=itemBenefitCopies(item);
    const key="item:"+item.id;
    activeItemCopies.set(key,(activeItemCopies.get(key)||0)+amount);
    if(!["weapon","armor","shield"].includes(kind))alwaysCarriedSources.add(key);
  }
  // The benefit editor stores custom item grants under feature:trait:item:<id>|...
  // while catalog grants use item:<id>. Both must inherit the same copy count.
  const itemSourceOf=origin=>{
    const sid=String(origin||'');
    if(sid.startsWith('item:'))return sid;
    if(sid.startsWith('feature:trait:item:'))
      return [...activeItemCopies.keys()].find(id=>sid.startsWith('feature:trait:'+id+'|'))||'';
    return '';
  };
  const manual=arr(record.formula_bonuses).filter(r=>r&&!r.automatic&&!String(r.id||"").startsWith("auto|"))
    .map(r=>r.target==='max_hp'?{...r,target:'hp'}:r.target==='spell_hit'?{...r,target:'spell_attack'}:r);
  const features=collectStructuredFeatures(record,catalogs);
  features.push(...racialBonusFeatures(record,catalogs.speciesConditionalBonuses||{},features));
  const racialPowers=racialPowerProjection(record,catalogs.speciesPowers||{},features);
  features.push(...racialPowers.features);
  const dragonbornFlight=racialPowers.abilities.find(power=>power.mode==='temporary_flight'&&
    record.active_class_features?.[power.persistent_key]?.origin_id===power.persistent_origin_id);
  const celestialForm=racialPowers.active_forms.find(form=>
    record.active_class_features?.[form.active_key]?.spell_id===form.spell_id);
  features.push(...speciesDefenseFeatures(record,catalogs.speciesDefenses,features));
  features.push(...speciesRollModeFeatures(record,catalogs.speciesRollModes,features));
  features.push(...supplementalSpeciesSpellFeatures(record,catalogs.spellGrantRules,features));
  features.push(...racialItemGrantFeatures(record,features,catalogs.featureItemGrants||[]));
  features.push(...expandedOriginSpellFeatures(record,classesCatalog?.additional_spells,features));
  const racialRollModes=speciesRollModeEntries(record,catalogs.speciesRollModes,features,suppressed);
  const racialBonusRows=racialBonusEntries(record,catalogs.speciesConditionalBonuses||{},features,suppressed);
  const damage_defense_entries=[...arr(record.damage_defense_entries),
    ...speciesDefenseEntries(record,catalogs.speciesDefenses,features,suppressed),
    ...classDefenseEntries(record,features,suppressed),
    ...dragonbornFtdResistances(record,catalogs.speciesPowers,features).filter(row=>
      !suppressed.has(row.benefit_id)&&sourceEnabled(row))];
  const grantingCastingTrait=member=>{
    // Partial/offline catalog tables must not impersonate a real feature grant.
    if(!catalogs.classFeatures)return null;
    const source=member.source||(record.rules_version==='2024'?'XPHB':'PHB');
    const origin='class|'+String(source).toLowerCase()+'|'+String(member.name||'').toLowerCase();
    return features.find(feature=>feature.origin_key===origin&&
      ['spellcasting','pact magic'].includes(String(feature.name||'').toLowerCase())&&
      featureEnabled(record,feature));
  };
  // Each class advancement belongs to its own level-specific ASI feature.
  const advancements=features.flatMap(feature=>{
    if(!featureEnabled(record,feature))return [];
    const policy=arr(index?.advancement_rules).find(rule=>
      same(rule.feature_name,feature.name)&&arr(rule.sources).some(source=>
      same(source,feature.class_source||String(feature.origin_key||'').split('|')[1])));
    if(!policy)return [];
    const owned=arr(record.advancement_choices).find(row=>row.origin_id===feature.origin_id);
    if(owned?.mode!=='ability')return [];
    return effectiveAllocations(record,feature.origin_id,allocationVariants(policy.ability_choices))
      .map(({ability,amount})=>numericGrant(feature.origin_id,
        'Tratto · '+feature.name,'advancement','ability:'+ability,amount)).filter(Boolean);
  });
  const automatic=[...(index?indexRows(record,index,warnings):[]),
    ...advancements,...itemRows(record,warnings,index?.artificer_infusions||[],features,catalogs.itemGrants),...structuredFeatureGrants(record,catalogs,features),...traitStateNumericGrants(record,features,catalogs.traitStates||[]),...racialAutomaticBonusGrants(racialBonusRows)];
  const disabled=new Set(arr(record.formula_bonuses).filter(r=>r?.disabled&&
    (r.automatic||String(r.id||"").startsWith("auto|"))).map(r=>r.id));
  const grants=[...manual,...automatic.filter(r=>!disabled.has(r.id)&&!suppressed.has('bonus:'+r.id))];
  // Base formula replacements are not additive bonuses. Every rule has a
  // stable origin, target and operation and reuses the normal source gates.
  const nativeBases=index?.base_value_overrides||{};
  const baseRows=[];
  const baseAdd=(rule,origin_id,origin_name)=>{
    for(const [ordinal,raw] of arr(rule?.overrides).entries()){
      if(!raw?.target||!raw?.expression)continue;
      const id=automaticId(origin_id,'base_value',raw.target,String(ordinal));
      const trait=String(rule.granting_trait||'');
      const owner=trait?features.find(f=>same(f.name,trait)&&
        (f.origin_key===origin_id||origin_id.startsWith('race|')&&
          f.origin_key==='species|'+(record.species_id||norm(record.species))+'|'+norm(record.species_source))):null;
      baseRows.push({...raw,id,origin_id:owner?.origin_id||origin_id,
        origin_name:owner?'Tratto · '+owner.name:origin_name,
        origin_parent_id:origin_id,origin_parent_name:rule.name||'',
        granting_trait:trait,automatic:true});
    }
  };
  for(const feat of arr(record.feats_catalog)){
    if(!feat?.name||feat.disabled)continue;
    const rule=arr(nativeBases.feats).find(row=>same(row.name,feat.name)&&same(row.source,feat.source));
    if(rule)baseAdd(rule,'feat|'+norm(feat.source)+'|'+norm(feat.name),'Talento · '+feat.name);
  }
  for(const rule of arr(nativeBases.species)){
    if(!same(record.species,rule.name)||!same(record.species_source,rule.source))continue;
    baseAdd(rule,'race|'+norm(rule.source)+'|'+norm(rule.name),'Specie · '+rule.name);
  }
  for(const optional of [
    ...arr(record.optional_features_catalog),
    ...arr(record.fighting_styles).filter(row=>typeof row==='string'||row?.name).map(row=>
      typeof row==='string'?{name:row,source:'TCE'}:row)
  ]){
    if(!optional?.name||optional.disabled)continue;
    const source=optional.source||'TCE';
    const rule=arr(nativeBases.optional_features).find(row=>same(row.name,optional.name)&&same(row.source,source));
    if(rule)baseAdd(rule,'optional|'+norm(source)+'|'+norm(optional.name),'Stile · '+optional.name);
  }
  for(const feature of features){
    if(!featureEnabled(record,feature))continue;
    const rule=arr(nativeBases.features).find(row=>same(row.name,feature.name)&&
      same(row.class_name,feature.class_name||feature.requirements?.class_name||
        String(feature.origin_key||'').split('|')[2])&&
      same(row.class_source,feature.class_source||String(feature.origin_key||'').split('|')[1]));
    if(rule)baseAdd(rule,feature.origin_id,'Tratto · '+feature.name);
  }
  for(const saved of arr(record.inventory)){
    const item=resolveOwnedItem(saved);
    if(!item?.id||!itemActive(item,record))continue;
    const rule=arr(nativeBases.items).find(row=>same(row.name,item.name)&&
      (same(row.source,item.source)||!item.source&&String(record.rules_version||'2014')==='2014'));
    if(rule)baseAdd(rule,'item:'+item.id,'Oggetto · '+item.name);
  }
  const excludedBases=new Set(arr(record.base_value_overrides).filter(row=>row?.automatic&&row.disabled).map(row=>row.id));
  const baseOverrides=[
    ...arr(record.base_value_overrides).filter(row=>!row?.automatic&&!String(row?.id||'').startsWith('auto|')),
    ...baseRows.filter(row=>!excludedBases.has(row.id)&&!suppressed.has('base_override:'+row.id))
  ];
  const baseFor=target=>baseOverrides.filter(row=>row?.target===target&&!row.disabled&&
    requirementsAllow(record,row)&&sourceEnabled(row)&&
    (!row.parent_origin||sourceEnabled({origin_id:row.parent_origin})))
    .sort((a,b)=>(Number(b.priority)||0)-(Number(a.priority)||0)||
      String(a.id||'').localeCompare(String(b.id||'')));
  const appliedBaseOverrides=new Map();
  const baseAllowed=row=>{
    const rules=row?.requirements||{};
    if((row.no_shield||rules.no_shield)&&shieldBonus>0)return false;
    if((row.no_armor||rules.no_armor)&&armor)return false;
    if((row.no_weapon_or_shield||rules.no_weapon_or_shield)&&arr(record.inventory).some(saved=>{
      const item=resolveOwnedItem(saved);
      return int(item.quantity,1)>0&&['weapon','shield'].includes(itemKind(item))&&
        arr(item.equipped_slots).some(slot=>slot==='main'||slot==='off');
    }))return false;
    return true;
  };
  const overrideNumeric=(target,base,resolve,stack,mode,filter=()=>true)=>{
    const applicable=baseFor(target).filter(row=>row.mode===mode&&baseAllowed(row)&&filter(row));
    const values=[];
    for(const row of applicable){
      try{
        const value=parseArithmetic(row.expression,name=>resolveSymbol(name,resolve,stack));
        if(Number.isFinite(value))values.push({row,value});
      }catch(error){warnings.add('Sostituzione base ignorata per '+target+': '+error.message);}
    }
    if(!values.length)return base;
    const chosen=mode==='replace'?values[0]:values.reduce((a,b)=>b.value>a.value?b:a);
    if(mode==='replace'||chosen.value>base)
      appliedBaseOverrides.set(target,{...chosen.row,resolved_value:chosen.value});
    return mode==='replace'?chosen.value:Math.max(base,chosen.value);
  };
  if(arr(record.feats_catalog).length&&!index)warnings.add("Talenti strutturati non calcolati");
  if(classes.length&&!catalogs.classFeatures)warnings.add("Indice dei privilegi di classe non disponibile");
  if(record.additional_traits||arr(record.stat_block?.trait).length)
    warnings.add("Tratti personalizzati: verificare i bonus non strutturati");
  // Disabled sources are handled by their identities and the parent-feature hierarchy.
  const proficiencies=fixedProficiencies(record,catalogs.proficiencyGrants,features);
  if(!catalogs.proficiencyGrants)
    warnings.add("Competenze automatiche da origini non disponibili senza il catalogo");
  const inventory=arr(record.inventory).map(resolveOwnedItem);
  const equipped=slot=>inventory.find(it=>int(it?.quantity,1)>0&&arr(it?.equipped_slots).includes(slot));
  const currentArmor=equipped("body");
  const armor=currentArmor&&itemKind(currentArmor)==="armor"?currentArmor:null;
  const armorIndex=arr(record.inventory).findIndex(item=>
    arr(item?.equipped_slots).includes('body')&&itemKind(resolveOwnedItem(item))==='armor');
  const armorForRules=armor?{...armor,inventory_index:armorIndex}:null;
  // Item-targeted Arcane Armor extensions must be resolved before speed.
  const activeArmorStates=activeTraitStates(record,features,catalogs.traitStates||[]).map(row=>row.id);
  const equippedExtensions=collectEffectExtensions(record,catalogs.effectExtensions||[],
    features,index?.artificer_infusions||[],activeArmorStates).filter(row=>sourceEnabled(row));
  const strengthWaivers=armorStrengthWaivers(record,equippedExtensions);
  const speciesRule=arr(catalogs.speciesAttacks?.races).find(row=>
    record.species_id&&row.id===record.species_id)||
    arr(catalogs.speciesAttacks?.races).find(row=>same(row.name,record.species)&&
      record.species_source&&same(row.source,record.species_source));
  const shield=[equipped("main"),equipped("off")].filter(it=>it&&itemKind(it)==="shield");
  const shieldBonus=shield.reduce((max,it)=>Math.max(max,Math.max(0,int(it.ac,2))),0);
  const simpleSpeed=()=>typeof record.species_speed==="number"?Math.max(0,int(record.species_speed)):
    record.species_speed?.walk!==undefined?Math.max(0,int(record.species_speed.walk?.number??record.species_speed.walk?.value??record.species_speed.walk,30)):
    Math.max(0,int(record.speed_base??record.speed,30));
  if(kind==="character"&&record.species&&!record.species_speed)
    warnings.add("Velocità della specie non disponibile nello snapshot locale");
  if(kind==="character"&&record.species&&!record.species_source&&index)
    warnings.add("Le fonti delle specie senza edizione esplicita possono essere ambigue");
  const proficiencyBase=()=>{
    if(kind!=="monster"&&!Object.hasOwn(record,"stat_block"))
      return 2+Math.floor((clamp(level,1,20)-1)/4);
    const cr=crNumber(record.stat_block?.cr)+level;
    return 2+Math.max(0,Math.floor((Math.min(cr,30)-1)/4));
  };
  const targetBase=(target,resolve,stack)=>{
    const [prefix,key]=target.split(":");
    if(prefix==="ability"&&ABILITIES.includes(key))return int(record.abilities?.[key],10);
    if(prefix==="ability_mod"&&ABILITIES.includes(key))return mod(resolve("ability:"+key,stack));
    if(target==="level")return int(record.level,1);
    if(target==="attunement_max")return Math.max(0,int(record.attunement_max_base,3));
    if(target==="proficiency")return proficiencyBase();
    if(target==="initiative")return resolve("ability_mod:dex",stack)+sumGrants("ability_check",stack)+sumGrants("initiative",stack);
    if(prefix==="ability_check"&&ABILITIES.includes(key))
      return resolve("ability_mod:"+key,stack)+sumGrants("ability_check",stack);
    if(target==="ac"){
      if(!armor){
        const base=kind==="monster"?monsterArmor(record.stat_block):int(record.armor_class_base,10);
        const fallback=kind==="character"&&base===10?"10 + dex_mod":String(base);
        let natural=base;
        try{natural=parseArithmetic(record.armor_natural_formula||fallback,
          name=>resolveSymbol(name,resolve,stack));}catch{warnings.add("Formula CA naturale non valida");}
        // Class, species and feat AC formulas all use the same typed,
        // individually disableable source-qualified alternatives.
        natural=overrideNumeric('ac_unarmored',natural,resolve,stack,'alternative');
        return natural+shieldBonus;
      }
      const dex=resolve("ability_mod:dex",stack);
      const equippedAc=int(armor.ac,10)+armorDexterityBonus(armor,dex);
      // Some natural armors explicitly remain selectable when wearing inferior
      // armor (Loxodon, Locathah, Lizardfolk). Tortle armor grants no benefit.
      const tortleBase=overrideNumeric('ac_unarmored',0,resolve,stack,'alternative',
        row=>row.ignore_armor===true);
      if(tortleBase>0)return tortleBase+shieldBonus;
      return overrideNumeric('ac_unarmored',equippedAc,resolve,stack,'alternative',
        row=>row.allow_armor===true)+shieldBonus;
    }
    if(target==="speed")return Math.max(0,simpleSpeed()-
      armorRuleEffects(record,armorForRules,resolve('ability:str',stack),strengthWaivers).speed_penalty);
    if(prefix==="speed"){
      const from=kind==="monster"?record.stat_block?.speed:record.species_speed;
      const source=record.movement_speeds?.[key]??from?.[key];
      const raw=typeof source==="object"&&source!==null?source.number??source.value:source;
      // A typed 5etools speed of true means "equal to walking speed",
      // not a speed of 1 foot (e.g. MPMM Aarakocra flight).
      const copiesWalk=raw===true&&["fly","swim","climb","burrow"].includes(key);
      const base=copiesWalk?resolve("speed",stack):
        Math.max(0,int(typeof raw==="string"?raw.split(" ")[0]:raw));
      if(key==='fly'&&(celestialForm?.fly_equals_walk||dragonbornFlight))
        return Math.max(base,resolve('speed',stack));
      if(key==="fly"&&speciesRule?.flight_no_medium_heavy_armor&&armor&&
        ['MA','HA'].includes(String(armor.type||"").split('|')[0].toUpperCase()))return 0;
      // All creatures can climb and swim by spending an extra foot of
      // movement per foot traveled. A declared movement speed wins over
      // that default; a specific climbing-cost waiver can improve it.
      const defaultBase=(key==='climb'||key==='swim')?resolve('speed',stack)/2:0;
      const specified=base>0;
      const effective=specified?base:defaultBase;
      const adjusted=key==='climb'&&featMovement.some(rule=>
        rule.mode==='climb_at_walking_cost'&&sourceEnabled(rule))?
        Math.max(effective,resolve('speed',stack)):effective;
      return specified&&String(record.rules_version)==="2024"&&!copiesWalk?
        adjusted+sumGrants("speed",stack):adjusted;
    }
    if(target==="hp")return int(record.max_hp_base??record.max_hp,1);
    if(target==="second_max")return int(record.second_form_max_hp);
    if(prefix==="save"&&ABILITIES.includes(key)){
      const legacy=record.stat_block?.save?.[key];
      if(kind==="monster"&&!hasProficiency(record,"save",key,proficiencies)&&legacy!==undefined&&
        /^[-+]?\d+$/.test(String(legacy)))return int(legacy)+sumGrants("saving_throw",stack);
      return resolve("ability_mod:"+key,stack)+(hasProficiency(record,"save",key,proficiencies)?resolve("proficiency",stack):0)+sumGrants("saving_throw",stack);
    }
    if(prefix==="skill"){
      const skill=SKILLS.find(row=>row[0]===key);
      if(!skill)return 0;
      let rank=hasProficiency(record,"expertise",key,proficiencies)?2:hasProficiency(record,"skill",key,proficiencies)?1:0;
      if(kind==="monster"&&!record.skill_ranks_custom){
        const old=record.stat_block?.skill?.[key];
        if(old!==undefined&&/^[-+]?\d+$/.test(String(old))){
          const difference=int(old)-mod(int(record.abilities?.[skill[2]],10));
          if(difference===resolve("proficiency",stack)*2)rank=Math.max(rank,2);
          else if(difference===resolve("proficiency",stack))rank=Math.max(rank,1);
        }
      }
      return resolve("ability_mod:"+skill[2],stack)+rank*resolve("proficiency",stack)+sumGrants("ability_check",stack);
    }
    if(target==="passive_perception")return 10+resolve("skill:perception",stack);
    if(prefix==="passive_skill"&&SKILLS.some(([id])=>id===key))
      return 10+resolve("skill:"+key,stack);
    return 0;
  };
  function monsterArmor(stat={}){
    if(Array.isArray(stat?.ac)){
      for(const row of stat.ac){if(typeof row==="number")return Math.max(0,int(row));
        if(row&&typeof row==="object"&&row.ac!==undefined)return Math.max(0,int(row.ac,10));}
    }
    return Math.max(0,int(stat?.ac,10));
  }
  function resolveSymbol(name,resolve,stack){
    const target=symbolTarget(name);if(!target)throw Error("Variabile sconosciuta: "+name);
    return resolve(target,stack);
  }
  function sourceEnabled(row){
    const sid=String(row?.origin_id||"");
    const parent=String(row?.origin_parent_id||"");
    if(parent&&parent!==sid&&(record.origin_enabled?.[parent]===false||
      arr(record.proficiency_origins).some(origin=>origin?.id===parent&&origin.disabled)))return false;
    if(sid.startsWith('item:')||sid.startsWith('feature:trait:item:')){
      const owner=itemSourceOf(sid);
      if(!owner)return false;
      if(alwaysCarriedSources.has(owner))return record.origin_enabled?.[sid]!==false&&
        !arr(record.proficiency_origins).some(origin=>origin?.id===sid&&origin.disabled);
    }
    if(!sid)return true;
    const saved=arr(record.proficiency_origins).find(x=>x?.id===sid);
    if(saved?.disabled)return false;
    if(record.origin_enabled?.[sid]===false)return false;
    if(row.parent_origin){
      if(record.origin_enabled&&Object.hasOwn(record.origin_enabled,row.parent_origin)&&
          !record.origin_enabled[row.parent_origin])return false;
      if(arr(record.proficiency_origins).some(x=>x.id===row.parent_origin&&x.disabled))
        return false;
      if(row.parent_origin.startsWith("feat|")){
        const featKey=row.parent_origin.slice(5);
        if(!arr(record.feats_catalog).some(x=>!x.disabled&&
          (String(x.id||"")===featKey||
           norm(x.name)+"|"+norm(x.source)===featKey)))return false;
      }
      if(row.parent_origin.startsWith("class|")){
        const chunks=row.parent_origin.split("|"),source=chunks[1],name=chunks[2];
        if(!localClasses(record).some(x=>same(x.name,name)&&
           (!source||!x.source||same(x.source,source))))return false;
      }
    }
    if(sid.startsWith("feature:")||sid.startsWith('tracker:auto:'))return true;
    // A generated infusion is a separate, verifiable equipment origin, not
    // an unknown manual bonus or an unconditional class privilege.
    if(sid.startsWith("infusion:"))return activeInfusions(record,index?.artificer_infusions||[],features)
      .some(infused=>infused.id===sid&&itemActive(resolveOwnedItem(infused.item),record));
    if(sid.startsWith("item:"))
      return inventory.some(it=>"item:"+it.id===sid&&itemActive(it,record));
    const fragments=sid.split("|"),group=fragments[0],
      source=fragments[1]||"",name=fragments.slice(2).join("|");
    if(group==="race")return same(record.species,name)&&
      (!source||!record.species_source||same(record.species_source,source));
    if(group==="subrace")return same(record.subrace,name)&&
      (!source||!record.subrace_source||same(record.subrace_source,source));
    if(group==="background")return effectiveBackgrounds(record).some(b=>same(b.name,name)&&
      (!source||!b.source||same(b.source,source)));
    if(group==="feat")return arr(record.feats_catalog).some(x=>!x.disabled&&
      same(x.name,name)&&(!source||same(x.source,source)));
    if(group==="optional")return [
      ...arr(record.optional_features_catalog),
      ...arr(record.fighting_styles).map(x=>typeof x==='string'?{name:x,source:'TCE'}:x)
    ].some(x=>x?.name&&!x.disabled&&same(x.name,name)&&(!source||same(x.source||'TCE',source)));
    if(group==="class")return localClasses(record).some(x=>
      same(x.name,name)&&(!source||!x.source||same(x.source,source)));
    // Native custom origins can explicitly exist in saved proficiency_origins.
    if(saved&&!saved.disabled)return true;
    warnings.add("Bonus di origine non verificabile: "+sid);
    return false;
  }
  const dependencies=expression=>[...String(expression||'').toLowerCase().matchAll(/[a-z_][a-z0-9_]*/g)].map(m=>symbolTarget(m[0])).filter(Boolean);
  const nativeDependencies=target=>{
    if(target.startsWith('ability_mod:'))return ['ability:'+target.slice(12)];
    if(target==='initiative')return ['ability_mod:dex'];
    if(target.startsWith('save:'))return ['ability_mod:'+target.slice(5),'proficiency'];
    if(target.startsWith('skill:'))return ['ability_mod:'+(SKILLS.find(([id])=>id===target.slice(6))?.[2]||'wis'),'proficiency'];
    if(target==='passive_perception')return ['skill:perception'];
    if(target.startsWith('passive_skill:'))return ['skill:'+target.slice('passive_skill:'.length)];
    if(target==='ac'&&inventory.some(it=>arr(it.equipped_slots).includes('body')&&['LA','MA'].includes(String(it.type).split('|')[0])))return ['ability_mod:dex'];
    if(target.startsWith('speed:')&&record.rules_version==='2024'&&int(record.movement_speeds?.[target.slice(6)]??record.species_speed?.[target.slice(6)])>0)return ['speed'];
    return [];
  };
  const reaches=(current,wanted,visited=new Set())=>{
    if(current===wanted)return true;
    if(visited.has(current))return false;
    visited.add(current);
    const refs=[...nativeDependencies(current),...grants.filter(r=>r.target===current&&!r.disabled&&sourceEnabled(r)).flatMap(r=>dependencies(r.expression))];
    return refs.some(ref=>reaches(ref,wanted,visited));
  };
  const cycleCache=new Map();
  const explanations={},components={},rollComponents={};
  function sumGrants(target,stack){
    let total=0;
    for(const row of grants){
      if(row?.target!==target||row.disabled||!requirementsAllow(record,row)||!sourceEnabled(row))continue;
      try{
        if(!cycleCache.has(row))cycleCache.set(row,dependencies(row.expression).some(ref=>reaches(ref,target)));
        if(cycleCache.get(row))throw Error('Dipendenza circolare: '+target);
        const value=parseArithmetic(row.expression??"0",name=>resolveSymbol(name,resolve,stack));
        const owner=itemSourceOf(row.origin_id);
        const repeats=row.automatic?Math.max(1,Number(row.multiplier)||1):
          owner?(activeItemCopies.get(owner)||0):1;
        const effective=value*repeats;
        total+=effective;
        if(!components[target])components[target]=new Map();
        components[target].set(row.id||row,(row.origin_name||'Bonus')+': '+row.expression+
          (repeats>1?' ×'+repeats:'')+' = '+effective);
        if(!rollComponents[target])rollComponents[target]=new Map();
        rollComponents[target].set(row.id||row,{id:row.id||'',origin_id:row.origin_id||'',
          origin_name:row.origin_name||'Bonus',expression:String(row.expression??'0'),
          ...(row.dice_notation?{dice_notation:String(row.dice_notation)}:{}),value:effective,multiplier:repeats});
      }catch(error){warnings.add("Bonus ignorato per "+target+": "+error.message);}
    }
    return total;
  }
  const memo=new Map();
  function resolve(target,stack=new Set()){
    if(stack.has(target))throw Error("Dipendenza circolare: "+target);
    if(memo.has(target))return memo.get(target);
    const next=new Set(stack);next.add(target);
    const base=overrideNumeric(target,targetBase(target,resolve,next),resolve,next,'replace');
    const value=base+sumGrants(target,next);
    const total=exhaustionAdjustedValue(overrideNumeric(target,value,resolve,next,'minimum'),target,exhaustion_effects);
    if(!Number.isFinite(total))throw Error("Valore non finito per "+target);
    memo.set(target,total);return total;
  }
  function safe(target){
    try{return resolve(target);}catch(error){warnings.add(error.message);return null;}
  }
  const armor_effects=armorRuleEffects(record,armorForRules,safe('ability:str'),strengthWaivers);
  const abilities=Object.fromEntries(ABILITIES.map(a=>[a,{score:safe("ability:"+a),
    modifier:safe("ability_mod:"+a)}]));
  safe("attunement_max");
  for(const ability of ABILITIES)safe("ability_check:"+ability);
  const saves=Object.fromEntries(ABILITIES.map(a=>[a,safe("save:"+a)]));
  const skills=Object.fromEntries(SKILLS.map(([id])=>[id,safe("skill:"+id)]));
  // Actual spell capacity also comes from an enabled Spellcasting/Pact Magic
  // trait. Class levels only determine its progression once granted.
  // A class table defines progression, never the entitlement to cast.
  // If class-feature metadata is missing offline, fail closed instead of
  // granting class slots from class and level alone.
  const spellcastingMembers=classes.filter(member=>grantingCastingTrait(member));
  if(classes.length&&!catalogs.classFeatures)
    warnings.add('Catalogo tratti di classe non disponibile: slot di classe sospesi');
  const progression=spellProgression(record,spellcastingMembers);
  progression.warnings.forEach(w=>warnings.add(w));
  const saved=arr(record.spell_slots_total);
  const hasLegacy=saved.some(x=>int(x)>0);
  const useSaved=record.spell_slots_manual||(!record.spell_slots_automatic&&hasLegacy);
  const slots=Array.from({length:9},(_,i)=>{
    const level=i+1,total=Math.max(0,(useSaved?int(saved[level]):progression.slots[level])+
      (safe("slot:"+level)??0)+Math.max(0,int(record.created_spell_slots?.[level]))),spent=Math.max(0,int(record.spell_slots_spent?.[level]));
    return {level,base:Math.max(0,useSaved?int(saved[level]):progression.slots[level]),total,spent:Math.min(spent,total)};
  });
  const pactTotal=Math.max(0,(useSaved?int(record.pact_slots_total):progression.pact_total)+
    (safe("pact_slot")??0));
  const dice=classesCatalog?classHitDice(record,classes,classesCatalog):{available:false};
  let automaticHP={available:false};
  if(dice.available&&dice.parts.length){
    let first=true,total=0;
    const con=abilities.con?.modifier??mod(int(record.abilities?.con,10));
    for(const {die,count} of dice.parts){
      for(let i=0;i<count;i++){total+=Math.max(1,(first?die:Math.max(1,Math.floor((die+2)/2)))+con);first=false;}
    }
    automaticHP={available:true,value:total};
  }
  if(kind==='monster'&&!classes.length){
    const hp=record.stat_block?.hp;
    if(typeof hp==='number'||Number.isFinite(Number(hp?.average)))
      automaticHP={available:true,value:Math.max(1,int(typeof hp==='number'?hp:hp.average))};
  }
  // Unknown class/feature effects are reported, not silently guessed or persisted.
  const speeds={walk:safe("speed")};
  for(const v of ["climb","swim","fly","burrow"])speeds[v]=safe("speed:"+v);
  for(const slot of slots)memo.set('slot:'+slot.level,slot.total);
  memo.set('pact_slot',pactTotal);
  for(const target of ['level','ac','initiative','hp','second_max','passive_perception','passive_skill:investigation'])safe(target);
  // Racial expanded lists belong to a real spellcasting class and never
  // grant free, known or permanently prepared spells of their own.
  const expandedSpellIds=expandedOriginClassSpellIds(record,classesCatalog?.additional_spells,features);
  // Class spell entries retain the owning structured trait, not the class.
  const spellClasses=castingClasses(record,classesCatalog,Object.fromEntries(ABILITIES.map(a=>[a,abilities[a].modifier])))
    .map(member=>{
      const trait=grantingCastingTrait(member);
      return {...member,granting_trait_id:trait?.origin_id||'',
        granting_trait_name:trait?.name||'',
        ...(expandedSpellIds.length?{expanded_spell_ids:expandedSpellIds}: {})};
    }).filter(member=>!!member.granting_trait_id);
  for(const a of ABILITIES){
    memo.set('casting_dc:'+a,8+(safe('proficiency')??0)+(abilities[a].modifier??0)+(safe('spell_dc')??0));
    memo.set('casting_hit:'+a,(safe('proficiency')??0)+(abilities[a].modifier??0)+(safe('spell_attack')??0));
  }
  const featMechanics=featMechanicGrants(record,index);
  const featureSpells=arr(classesCatalog?.feature_spells);
  const additional=structuredSpellGrants(record,[...arr(classesCatalog?.additional_spells),...featureSpells],catalogs.spells||[],features,catalogs.spellGrantRules||[],catalogs.speciesPowers?.races||[],safe('proficiency'));
  // Permanently prepared subclass spells are attached to their actual feature,
  // not to the class itself; the same source identity powers UI and calculations.
  const classCasting=castingClasses(record,classesCatalog,Object.fromEntries(ABILITIES.map(a=>[a,abilities[a].modifier])));
  additional.grants.push(...featureTableSpellGrants(record,features,catalogs.spells||[],classCasting,featureSpells),
    ...supplementalFeatureSpellGrants(record,features,catalogs.spells||[],
      catalogs.featureSpellGrants||[],classCasting,featureSpells));
  for(const warning of additional.warnings)warnings.add(warning);
  // Feats use the same expression evaluator as other typed trackers.
  // The proficiency-sized pool must reflect level changes without modifying saves.
  const featTrackers=featMechanics.trackers.map(row=>{
    if(!row.max_formula)return row;
    try{return {...row,max:Math.max(0,parseArithmetic(row.max_formula,
      name=>resolveSymbol(name,resolve,new Set())))};}
    catch(error){warnings.add('Formula tracker talento '+row.name+': '+error.message);return {...row,max:0};}
  });
  const trackerMap=new Map();
  for(const row of [...resourceTrackers(record,{...classesCatalog,feature_rules:catalogs.featureRules},name=>resolveSymbol(name,resolve,new Set())),...additional.trackers,...featTrackers,...racialPowers.trackers,...speciesRollModeTrackers(record,racialRollModes,safe('proficiency')??2),...racialBonusTrackers(racialBonusRows,safe('proficiency')??2)])
    if(!trackerMap.has(row.id)&&sourceEnabled(row)&&!suppressed.has('tracker:'+row.id))trackerMap.set(row.id,row);
  for(const stateTracker of traitStateTrackers(record,features,catalogs.traitStates||[]))
    trackerMap.set(stateTracker.id,stateTracker);
  const trackers=[...trackerMap.values()].map(row=>{
    if(row.formula_error)warnings.add('Formula tracker '+row.name+': '+row.formula_error+' · mantenuto il massimo base');
    const maximum=Math.max(0,row.max+(safe('tracker:'+row.id)??0));
    return {...row,max:maximum,spent:clamp(Math.max(int(record.resource_tracker_spent?.[row.id]),
      ...arr(row.legacy_ids).map(id=>int(record.resource_tracker_spent?.[id]))),0,maximum)};
  });
  for(const tracker of trackers)memo.set('tracker:'+tracker.id,tracker.max);
  const resolvedDamageBase=(id,damage)=>{
    const specific=baseFor('attack_damage_base:'+id);
    const fallback=id.startsWith('unarmed:')?baseFor('attack_damage_base:unarmed'):[];
    const candidates=[...specific,...fallback].filter(row=>
      ['replace','alternative'].includes(row.mode)&&baseAllowed(row));
    const average=formula=>{
      const match=String(formula).replace(/\s+/g,'').match(/^(?:(\d+)d(4|6|8|10|12|20|100)|(\d+))([+-]\d+)?$/i);
      if(!match)return null;
      return match[3]!==undefined?Number(match[3])+Number(match[4]||0):
        Number(match[1])*(Number(match[2])+1)/2+Number(match[4]||0);
    };
    let result=String(damage||''),selected=null,score=average(result)??-Infinity;
    for(const rule of candidates){
      const formula=String(rule.expression||'').replace(/\s+/g,'');
      const value=average(formula);
      if(value===null){warnings.add('Formula del danno base ignorata: '+formula);continue;}
      // A replacement becomes the base; additional optional formulas only
      // supersede it when their expected die result is higher.
      if(rule.mode==='replace'){
        if(!selected||selected.mode==='replace'&&
          (Number(rule.priority)||0)>(Number(selected.priority)||0)){
          selected=rule;result=formula;score=value;
        }
      }else if(value>score){
        selected=rule;result=formula;score=value;
      }
    }
    if(selected)appliedBaseOverrides.set('attack_damage_base:'+id,
      {...selected,enabled_target:'attack_damage_base:'+id});
    return result;
  };
  const featureContext={damageBase:resolvedDamageBase,speciesAttacks:catalogs.speciesAttacks,features:features.map(f=>({...f,disabled:f.inactive||!sourceEnabled({origin_id:f.origin_id,parent_origin:f.origin_key})})),traitStates:catalogs.traitStates||[],trait_state_catalog:catalogs.traitStates||[],active_trait_state_ids:activeTraitStates(record,features,catalogs.traitStates||[]).map(row=>row.id)};
  const attacks=attackCalculations(record,abilities,safe('proficiency')??0,[...proficiencies.keys()],target=>safe(target)??0,featureContext);
  const attack_count_benefits=attackCountBenefits(record,featureContext.features);
  const effect_extensions=equippedExtensions;
  const originMap=new Map();
  const addOrigin=(id,name)=>{if(id&&!originMap.has(id))originMap.set(id,{id,name,disabled:arr(record.proficiency_origins).some(o=>o?.id===id&&o.disabled)||record.origin_enabled?.[id]===false});};
  for(const cls of classes)addOrigin('class|'+String(cls.source||'').toLowerCase()+'|'+cls.name.toLowerCase(),cls.name);
  for(const [group,field] of [['race','species'],['subrace','subrace']])if(record[field])addOrigin(group+'|'+String(record[field+'_source']||'').toLowerCase()+'|'+String(record[field]).toLowerCase(),record[field]);
  for(const background of effectiveBackgrounds(record))
    addOrigin('background|'+String(background.source||'').toLowerCase()+'|'+String(background.name).toLowerCase(),background.name);
  for(const feat of arr(record.feats_catalog))if(feat?.name)addOrigin('feat|'+String(feat.source||'').toLowerCase()+'|'+feat.name.toLowerCase(),feat.name);
  for(const origin of arr(record.proficiency_origins))addOrigin(origin.id,origin.name||origin.label||origin.id);
  for(const tracker of trackers)addOrigin(tracker.origin_id,tracker.origin_name||tracker.name);
  for(const feature of features)addOrigin(feature.origin_id,"Tratto · "+feature.name);
  const originSpellMap=new Map();
  const spellOwnerLive=row=>{
    if(String(row.source_choice_id||'').startsWith('feature:class|')&&
      !additional.choices.some(choice=>choice.id===row.source_choice_id))return false;
    const trait=features.find(feature=>feature.origin_id===(row.owner_origin_id||row.origin_id));
    return !trait||(!trait.inactive&&!trait.disabled&&
      record.trait_enabled?.[trait.key]!==false);
  };
  for(const row of [...additional.saved_grants,...additional.grants,...racialPowers.origin_spells])if(row?.origin_id&&row.spell_id&&!suppressed.has('spell:'+row.origin_id+':'+row.spell_id)&&!row.disabled&&requirementsAllow(record,row)&&sourceEnabled(row)&&spellOwnerLive(row)){
    const key=row.origin_id+'|'+row.spell_id;
    if(!originSpellMap.has(key)){
      const id=row.id||key,config=record.origin_spell_configs?.[id]||{},resolved={...row,id};
      for(const field of ['payment_mode','tracker_id','spellcasting_ability','tracker_cost','slot_alternative'])
        if(Object.hasOwn(config,field))resolved[field]=config[field];
      if(row.casting_ability_from_source)resolved.spellcasting_ability=row.spellcasting_ability;
      // The owner-level casting choice is shared by all spells granted by
      // this trait and is validated against its structured eligibility list.
      const chosen=record.spellcasting_section_abilities?.['origin:'+row.origin_id];
      if(arr(resolved.spellcasting_ability_options).includes(chosen))
        resolved.spellcasting_ability=chosen;
      // An origin-granted cantrip is at-will by default, regardless of the
      // "known" storage group. Explicit limited-use cantrip trackers remain
      // chargeable; a cantrip never consumes a spell slot.
      const originSpellDefinition=arr(catalogs.spells).find(spell=>spell.id===resolved.spell_id);
      if(originSpellDefinition?.level===0||resolved.cantrip===true)
        resolved.cantrip=true;
      if(resolved.cantrip===true&&resolved.payment_mode!=='tracker')
        resolved.payment_mode='free';
      if(!['tracker','slot','free'].includes(resolved.payment_mode))
        resolved.payment_mode=resolved.tracker_id?'tracker':
          resolved.cantrip===true?'free':
          ['known','prepared'].includes(resolved.mode)?'slot':'free';
      // The alternate slot path is meaningful only for an active tracker.
      if(resolved.payment_mode!=='tracker'||!resolved.tracker_id)
        resolved.slot_alternative=false;
      originSpellMap.set(key,resolved);
    }
  }
  const originSpells=[...originSpellMap.values()];
  const originChoices=additional.choices.map(choice=>{
    const selected=additional.saved_grants.filter(g=>g?.source_choice_id===choice.id&&!g.disabled);
    return {...choice,selected,remaining:Math.max(0,choice.count-selected.length)};
  });
  for(const row of [...originSpells,...originChoices])addOrigin(row.origin_id,row.origin_name||row.origin_id);
  for(const attack of attacks){
    memo.set('attack_hit:'+attack.id,attack.hit);
    memo.set('attack_range:'+attack.id,attack.range_feet);
    memo.set('attack_long_range:'+attack.id,attack.long_range_feet);
  }
  for(const target of memo.keys()){
    const total=memo.get(target),parts=[...(components[target]?.values()||[])];
    explanations[target]=target+': '+total+(parts.length?' · '+parts.join(' · '):' · Nessun bonus aggiuntivo');
  }
  const senses=calculateSenses(record,features,catalogs.senseGrants||{},sourceEnabled);
  return {source:"local",schema:1,abilities,saves,skills,senses,
    values:Object.fromEntries(memo),explanations,
    roll_components:Object.fromEntries(Object.entries(rollComponents).map(([target,rows])=>[target,[...rows.values()]])),
    proficiencies:[...proficiencies.keys()],
    // Preserve origins for every structured proficiency kind (including
    // weapons, armor, tools and languages), not only d20-linked skills/saves.
    proficiency_sources:Object.fromEntries([...proficiencies.keys()]
      .map(key=>{const [kind,...parts]=key.split(':');return [key,
        proficiencyGrantOrigins(record,catalogs.proficiencyGrants,kind,parts.join(':'),features)];})),
    casting_classes:spellClasses,trackers,attacks,damage_defense_entries,
    feature_item_grants:featureItemGrants(record,features,catalogs.featureItemGrants||catalogs.classMechanics?.feature_item_grants||[]),
    trait_state_roll_modes:traitStateRollModes(record,features,catalogs.traitStates||[]),
    racial_abilities:racialPowers.abilities,racial_passive_notes:racialPowers.passive_notes||[],celestial_forms:racialPowers.active_forms,
    racial_rest_choices:racialPowers.rest_choices,
    racial_roll_bonuses:[...racialPowers.roll_bonuses,...racialBonusRows.filter(row=>!row.automatic_apply)],
    racial_roll_modes:racialRollModes,
    racial_spell_definitions:racialPowerSpellDefinitions(catalogs.speciesPowers||{},record,catalogs.originDetails||{}),
    active_celestial_form:celestialForm||null,
    active_racial_damage_bonus:celestialForm?{
      origin_id:celestialForm.origin_id,source:celestialForm.name,
      damage_type:celestialForm.damage_type,
      amount:safe('proficiency'),once_per_turn:true}:null,
    attack_count_benefits,attacks_per_action:attacksPerActionFromBenefits(attack_count_benefits),
    effect_extensions,armor_effects,armor_strength_waivers:strengthWaivers,
    item_damage_resistances:effect_extensions.filter(row=>row.operation==='resistance'&&row.target_kind==='item')
      .map(row=>({damage_type:row.value,origin_id:row.origin_id,origin_name:row.origin_name,
        target_id:row.target_id,target_instance_id:row.target_instance_id,
        target_inventory_index:row.target_inventory_index})),
    feature_rules:catalogs.featureRules||{},
    base_value_overrides:baseOverrides.filter(row=>sourceEnabled(row)&&requirementsAllow(record,row)&&!row.disabled),
    base_override_applied:Object.fromEntries(appliedBaseOverrides),
    feat_roll_modes:featMechanics.roll_modes.filter(row=>sourceEnabled(row)),
    feat_roll_bonuses:featMechanics.roll_bonuses.filter(row=>sourceEnabled(row)),
    feat_actions:featMechanics.actions.filter(row=>sourceEnabled(row)),
    spell_imprint_rules:[...featMechanics.spell_imprints,...arr(record.spell_imprint_grants)].filter(row=>sourceEnabled(row)),
    feat_movement_rules:featMovement.filter(row=>sourceEnabled(row)),
    active_feature_effects:[...classFeatureEffects(record,featureContext),...traitStateEffects(record,features,catalogs.traitStates||[])],
    active_trait_state_ids:activeTraitStates(record,features,catalogs.traitStates||[]).map(row=>row.id),
    state_actions:traitStateActions(record,features,catalogs.traitStates||[]),
    trait_state_optional_dice:traitStateOptionalDice(record,features,catalogs.traitStates||[]),
    trait_state_catalog:catalogs.traitStates||[],
    exhaustion_effects,exhaustion_dead:exhaustionIsDead(exhaustion_effects),
    roll_bonus_rules:catalogs.rollBonusRules||[],
    feature_damage_resistances:classFeatureActive(record,featureContext,'rage')?['bludgeoning','piercing','slashing']:[],
    features:features.map(f=>({...f,disabled:f.inactive||!sourceEnabled({origin_id:f.origin_id,parent_origin:f.origin_key})})),
    origins:[...originMap.values()],origin_spells:originSpells,origin_choices:originChoices,
    origin_spell_variant_choices:additional.variant_choices,
    automatic_bonuses:automatic.filter(row=>!suppressed.has('bonus:'+row.id)&&requirementsAllow(record,row)&&sourceEnabled(row)).map(row=>({...row,disabled:disabled.has(row.id)})),
    bonuses:grants.filter(r=>!r.disabled&&requirementsAllow(record,r)&&sourceEnabled(r)),
    stats:{level,proficiency:safe("proficiency"),initiative:safe("initiative"),
      armor_class:safe("ac"),max_hp:safe("hp"),passive_perception:safe("passive_perception"),
      passive_investigation:safe("passive_skill:investigation"),
      speeds,hovering:!!dragonbornFlight,automatic_hp:automaticHP,hit_dice:dice.available?dice.parts.map(p=>p.count+'d'+p.die+' ('+p.name+')').join(', '):record.hit_dice||'',
      jumps:{long:Math.max(0,abilities.str.score??0),high:Math.max(0,3+(abilities.str.modifier??0))}},
    spell_slots:slots,pact_slots:{base:Math.max(0,useSaved?int(record.pact_slots_total):progression.pact_total),total:pactTotal,spent:Math.max(0,Math.min(pactTotal,int(record.pact_slots_spent))),
      level:useSaved?int(record.pact_slot_level,1):progression.pact_level},
    warnings:[...warnings],complete:warnings.size===0};
}
let catalogPromise;
export function loadRuleCatalogs(){
  if(!catalogPromise)catalogPromise=Promise.all([
    fetch("/catalog/ability_grants.json").then(r=>{if(!r.ok)throw Error("Indice abilità non caricato");return r.json();}),
    fetch("/catalog/class_mechanics.json").then(r=>{if(!r.ok)throw Error("Regole classi non caricate");return r.json();}),
    fetch("/catalog/proficiency_grants.json").then(r=>{if(!r.ok)throw Error("Competenze delle origini non caricate");return r.json();}),
    // Numeric rules do not block on the entire spell compendium.
    // Already visible spell references are supplied by the PWA on demand.
    Promise.resolve([]),
    fetch('/catalog/feature_timing_recovery_rules.json').then(r=>{if(!r.ok)throw Error('Regole privilegi non disponibili');return r.json();}).then(data=>data?.version===1&&Array.isArray(data.actions)&&Array.isArray(data.recoveries)?data:null),
    fetch('/catalog/trait_states.json').then(r=>{if(!r.ok)throw Error('Privilegi di stato non disponibili');return r.json();})
      .then(data=>data?.version===1&&Array.isArray(data.states)?
       {states:data.states,exhaustion:data.exhaustion||{}}:{states:[],exhaustion:{}}),
    fetch('/catalog/roll_bonus_rules.json').then(r=>{if(!r.ok)throw Error('Regole dei bonus ai tiri non disponibili');return r.json();})
      .then(data=>data?.version===1&&Array.isArray(data.features)?data.features:[]),
    fetch('/catalog/classes.json').then(r=>{if(!r.ok)throw Error('Indice privilegi non disponibile');return r.json();})
      .then(data=>data?.version===1&&Array.isArray(data.class_features)&&Array.isArray(data.subclass_features)?data:null).catch(()=>null),
    // This catalog is supplemental. A missing/stale native host must not also
    // suppress all fixed racial ability and proficiency grants in the sheet.
    fetch('/catalog/species_attacks.json').then(r=>{if(!r.ok)throw Error('HTTP '+r.status);return r.json();})
      .then(data=>data?.version===1&&Array.isArray(data.races)?data:{races:[],load_error:true})
      .catch(error=>{console.warn('VTT: catalogo attacchi delle specie non disponibile',error);return {races:[],load_error:true};}),
    Promise.all(['/catalog/features.json','/catalog/backgrounds.json'].map(path=>
      fetch(path).then(r=>r.ok?r.json():{}).catch(()=>({})))).then(([features,backgrounds])=>({
        races:features.races||{},feats:features.feats||{},backgrounds:backgrounds.backgrounds||{}
      })),
    fetch('/catalog/effect_extensions.json').then(r=>{if(!r.ok)throw Error('Estensioni effetti non disponibili');return r.json();})
      .then(data=>data?.version===1&&Array.isArray(data.extensions)?data.extensions:[]),
    fetch('/catalog/species_powers.json').then(r=>r.ok?r.json():{})
      .then(data=>data?.version===1&&Array.isArray(data.races)?data:{races:[]}).catch(()=>({races:[]})),
    fetch('/catalog/species_conditional_bonuses.json').then(r=>r.ok?r.json():{})
      .then(data=>data?.version===1&&Array.isArray(data.races)?data:{races:[]}).catch(()=>({races:[]})),
    fetch('/catalog/spell_grant_rules.json').then(r=>r.ok?r.json():{})
      .then(data=>data?.version===1&&Array.isArray(data.rules)?data.rules:[])
      .catch(()=>[]),
    fetch('/catalog/species_defenses.json').then(r=>{if(!r.ok)throw Error('Difese delle specie non disponibili');return r.json();})
      .then(data=>data?.version===1&&Array.isArray(data.races)?data:{races:[],load_error:true})
      .catch(error=>{console.warn('VTT: catalogo difese delle specie non disponibile',error);return {races:[],load_error:true};}),
    fetch('/catalog/species_roll_modes.json').then(r=>{if(!r.ok)throw Error('Modificatori ai tiri delle specie non disponibili');return r.json();})
      .then(data=>data?.version===1&&Array.isArray(data.races)?data:{races:[],load_error:true})
      .catch(error=>{console.warn('VTT: vantaggi razziali condizionali non disponibili',error);return {races:[],load_error:true};}),
    fetch('/catalog/sense_grants.json').then(r=>r.ok?r.json():{}).then(data=>data?.version===1?data:{}).catch(()=>({})),
    fetch('/catalog/feature_item_grants.json').then(r=>r.ok?r.json():{}).then(data=>data?.version===1&&Array.isArray(data.grants)?data.grants:[]).catch(()=>[])
  ]).then(([abilityGrants,classMechanics,proficiencyGrants,spells,featureRules,traitStates,rollBonusRules,classFeatures,speciesAttacks,originDetails,effectExtensions,speciesPowers,speciesConditionalBonuses,spellGrantRules,speciesDefenses,speciesRollModes,senseGrants,featureItemGrants])=>({
    abilityGrants,classMechanics:{...classMechanics,feature_item_grants:featureItemGrants},featureItemGrants,
    proficiencyGrants,speciesAttacks,speciesDefenses,speciesRollModes,senseGrants,featureRules:featureRules||{},
    traitStates:traitStates.states,exhaustionRules:traitStates.exhaustion,rollBonusRules,classFeatures,effectExtensions,
    featureSpellGrants:supplementalClassSpells,itemGrants:supplementalItemBonuses,originDetails,spellGrantRules,speciesPowers,speciesConditionalBonuses,
    spells:[...new Map([...spells,...arr(classMechanics.legacy_spells)].map(s=>[s.id,s])).values()]}))
    .catch(error=>{catalogPromise=null;throw error;});
  return catalogPromise;
}
export function clearLocalRuleCatalogCache(){catalogPromise=null;}
