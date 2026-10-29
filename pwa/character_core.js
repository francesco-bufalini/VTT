// Shared browser domain operations on native-compatible character records.
// Never computes tactical map geometry or persists UI widget state.
const array=value=>Array.isArray(value)?value:[];
const integer=(value,fallback=0)=>Number.isFinite(Number(value))?Math.trunc(Number(value)):fallback;
const zeroSlots=()=>Array(10).fill(0);

// Current imported monster catalogs include untyped Multiattack records.
// Convert once at ingress; runtime attack benefits read only the typed count.
// Ambiguous prose remains descriptive, with exactly the previous parser scope.
export function normalizeMonsterStatBlock(stat={}){
 let changed=false;
 const action=array(stat.action).map(row=>{
  if(!row||!/^multiattack$/i.test(String(row.name||'').trim()))return row;
  const direct=Number(row.attacks_per_action);
  if(Number.isSafeInteger(direct)&&direct>=2)return row;
  const match=JSON.stringify(row.entries||row.description||'').match(/\b(?:makes?|can make|effettua|può effettuare)\s+(?:up to\s+)?(\d+|one|two|three|four|five|six|uno|due|tre|quattro|cinque|sei)\s+(?:(?:melee|ranged|weapon|spell|arma)\s+)*attacks?\b/i);
  const words={one:1,two:2,three:3,four:4,five:5,six:6,uno:1,due:2,tre:3,quattro:4,cinque:5,sei:6};
  const count=match?(Number(match[1])||words[match[1].toLowerCase()]||0):0;
  if(count<2)return row;
  changed=true;return {...row,attacks_per_action:count};
 });
 return changed?{...stat,action}:stat;
}

/** Cumulative XP needed to reach each character level (D&D 5e, 2014/2024). */
export const XP_THRESHOLDS=Object.freeze([
 0,0,300,900,2700,6500,14000,23000,34000,48000,64000,
 85000,100000,120000,140000,165000,195000,225000,265000,305000,355000
]);
export function minimumXpForLevel(level){
 const n=Number(level);
 return Number.isInteger(n)&&n>=1?XP_THRESHOLDS[Math.min(n,20)]:0;
}
export function minimumXpForCreature(record={}){
 // Challenge rating never counts as a class level. A monster with class
 // levels uses the ordinary class XP thresholds; an unclassed creature
 // (including a bestiary monster) has no minimum XP requirement.
 const classes=array(record.classes).filter(row=>row&&String(row.name||'').trim());
 const total=classes.length?
  classes.reduce((sum,row)=>sum+Math.max(1,integer(row.level,1)),0):
  record.class?Math.max(1,integer(record.level,1)):0;
 return minimumXpForLevel(total);
}
export function canLevelUp(record={}){
 if(record.kind==='monster'||record.variant_rules_kind==='monster')return false;
 const classes=array(record.classes).filter(row=>row&&String(row.name||'').trim());
 const level=classes.length?classes.reduce((n,row)=>n+Math.max(1,integer(row.level,1)),0):
  record.class?Math.max(1,integer(record.level,1)):0;
 const xp=Number(record.xp);
 return level>=1&&level<20&&Number.isSafeInteger(xp)&&xp>=minimumXpForLevel(level+1);
}
export function experienceFloorPatch(record,changes={}){
 const updated={...record,...changes};
 const min=minimumXpForCreature(updated),xp=Number(updated.xp??0);
 return min>0&&(!Number.isSafeInteger(xp)||xp<min)?{xp:min}:{};
}

// Defaults mirror PlayerCharacterStore.create_character, not a separate
// simplified browser schema. Imported records are NEVER normalized with these.
export function initialCreature(kind,name,id,owner_id){
  if(!["character","monster"].includes(kind)||typeof name!=="string"||!name.trim()||
     !id||!owner_id)throw Error("Dati iniziali della creatura non validi.");
  const c={
    id,name,owner_id,kind,transfer_revision:0,
    default_miniature_id:"",current_miniature_id:"",size_name:"Medium",
    footprint:1,reach_feet:5,visual_front_quarter_turns:0,
    party_id:kind==="monster"?"":"Party",
    identity_factions:kind==="monster"?[]:[{value:"Party",active:true}],
    identity_hide_other_names:true,
    rules_version:"2014",player_name:"",classes:[],class:"",class_source:"",
    class_id:"",subclass:"",subclass_id:"",subclass_source:"",
    level:1,xp:0,proficiency_bonus:2,spellcasting_calculation:{},
    species:"",species_id:"",species_source:"",subrace:"",subrace_id:"",
    subrace_source:"",subtype:"",subtype_is_custom:false,background:"",
    background_source:"",backgrounds_catalog:[],action_variants_2014:[],alignment:"Completamente neutrale",sex:"",inspiration:false,
    abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10},
    saving_throw_proficiencies:[],skill_proficiencies:[],skill_expertise:[],
    armor_class:10,armor_class_base:10,armor_natural_formula:"",
    temporary_ac:0,initiative:0,initiative_base:0,attunement_max_base:3,
    max_hp:1,max_hp_base:1,current_hp:1,temporary_hp:0,
    variant_schema_version:1,variants:[],current_form_id:"",
    speed_base:30,speed:30,speed_is_custom:false,darkvision:0,exhaustion:0,
    hit_dice:"",hit_dice_spent:{},death_save_successes:0,death_save_failures:0,
    attacks:"",attack_ability:"str",attack_overrides:{},equipped_attack_id:"",
    equipped_inventory_index:-1,hand_main_special:"none",hand_off_special:"none",
    hand_grip_two_handed:false,two_weapon_fighting:false,fighting_styles:[],
    proficiency_choices:[],origin_ability_choices:[],advancement_choices:[],formula_bonuses:[],base_value_overrides:[],dice_bonuses:[],
    d20_reroll_grants:[],resource_trackers:[],resource_tracker_spent:{},
    resource_recovery_ready:{},resource_recovery_used:{},origin_spell_grants:[],
    origin_spell_configs:{},spellcasting_section_abilities:{},
    active_spell_context:{},conditions:[],concentrating_spell_id:"",
    damage_defense_overrides:{},condition_immunity_overrides:{},
    documents:[],inventory:[],weapons_catalog:[],armor_catalog:[],
    tools_catalog:[],languages_catalog:[],feats_catalog:[],class_features_catalog:[],
    species_traits_catalog:[],optional_features_catalog:[],inventory_mundane:[],
    inventory_magic:[],
    spellcasting_class:"",spellcasting_ability:"",spell_save_dc:0,
    spell_attack_bonus:0,spells:[],prepared_spells:[],spellbook_spells:[],
    spell_slots_total:zeroSlots(),spell_slots_spent:zeroSlots(),
    pact_slots_total:0,pact_slots_spent:0,pact_slot_level:1,
    spell_slots_visible:true,spell_slots_manual:false,spell_slots_automatic:false,
    pact_slots_visible:true,linked_token_sync_id:"",linked_token_name:"",
    background_personality:"",notes:"",appearance:"",personality_traits:"",
    ideals:"",bonds:"",flaws:"",additional_traits:"",
    faction:"",symbol:"",enemies:"",age:"",height:"",weight:"",eyes:"",
    skin:"",hair:"",ammunition:"",armor_proficiencies:"",
    weapon_proficiencies:"",tool_proficiencies:"",languages:"",
    feats:"",equipment:"",consumables:"",magic_items:"",
    class_features:"",racial_background_traits:"",limited_features:""
  };
  if(kind==="monster")c.stat_block={};
  return c;
}

// An optional adjustment when the effective CON modifier changes.
// Use the modifier difference once, not the raw ability-score difference.
export function constitutionHpAdjustment(record,previousModifier,nextModifier){
 const before=Number(previousModifier),after=Number(nextModifier);
 if(!Number.isInteger(before)||!Number.isInteger(after)||before<-30||before>30||after<-30||after>30)
   throw Error('Modificatore di Costituzione non valido.');
 const delta=after-before;
 if(!delta)return null;
 const maximum=Number(record.max_hp_base??record.max_hp??1);
 const current=Number(record.current_hp??0);
 if(!Number.isSafeInteger(maximum)||maximum<1||!Number.isSafeInteger(current)||current<0)
   throw Error('Punti ferita non validi.');
 return {max_hp_base:Math.max(1,maximum+delta),
   current_hp:Math.max(0,current+delta)};
}

export function changeTrackerUses(record,id,delta,trackers=record.resource_trackers){
  const row=array(trackers).find(t=>t&&t.id===id);
  if(!row||row.disabled)throw Error("Risorsa non disponibile.");
  const max=Math.max(0,integer(row.max));
  if(!Number.isInteger(delta)||![-1,1].includes(delta))throw Error("Variazione utilizzi non valida.");
  const spent={...(record.resource_tracker_spent||{})};
  const value=Math.max(0,Math.min(max,integer(spent[id])+delta));
  if(value===0)delete spent[id];else spent[id]=value;
  return {resource_tracker_spent:spent};
}

// Ability payments are atomic: never clamp an unaffordable cost into a partial payment.
export function spendTrackerUses(record,id,cost,trackers=record.resource_trackers){
  const row=array(trackers).find(t=>t&&t.id===id&&!t.disabled);
  if(!row)throw Error("Risorsa non disponibile.");
  if(!Number.isSafeInteger(cost)||cost<=0)throw Error("Costo utilizzi non valido.");
  const spent={...(record.resource_tracker_spent||{})};
  const used=Math.max(0,integer(spent[id]));
  if(cost>Math.max(0,integer(row.max))-used)throw Error("Risorsa insufficiente per usare la capacità.");
  spent[id]=used+cost;
  return {resource_tracker_spent:spent};
}


/**
 * Hit Dice remain a portable per-die-size counter. Older desktop exports have
 * no hit_dice_spent field: treat those pools as fully available, never discard
 * the native hit_dice string or the class-derived values.
 */
export function hitDicePools(record,calculated={}){
 const expression=String(calculated.stats?.hit_dice||record.hit_dice||'');
 const counts=new Map();
 for(const match of expression.matchAll(/(\d+)\s*d\s*(\d+)/gi)){
  const count=Number(match[1]),die=Number(match[2]);
  if(!Number.isSafeInteger(count)||count<1||count>1000||![4,6,8,10,12,20].includes(die))continue;
  counts.set(die,(counts.get(die)||0)+count);
 }
 return [...counts].sort(([a],[b])=>b-a).map(([die,total])=>{
  const value=Number(record.hit_dice_spent?.['d'+die]||0);
  const spent=Math.max(0,Math.min(total,Number.isFinite(value)?Math.trunc(value):0));
  return {die,total,spent,available:total-spent};
 });
}

