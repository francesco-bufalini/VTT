// Shared browser domain operations on native-compatible character records.
// Never computes tactical map geometry or persists UI widget state.
const array=value=>Array.isArray(value)?value:[];
const integer=(value,fallback=0)=>Number.isFinite(Number(value))?Math.trunc(Number(value)):fallback;
const zeroSlots=()=>Array(10).fill(0);

// Compatibility belongs at record ingress. Keep old fields for native export,
// but project one canonical choice list; an explicit empty list with origins
// means the player removed the grants and must never resurrect legacy ranks.
export function normalizeCreatureRecord(record={}, {inheritedOrigins=false,classMechanics}={}){
 let result=record;
 // Preserve old saved species identities. Canonical subtype metadata supplies
 // their movement at ingress, without recreating flattened races in the engine.
 if(!record.subrace&&classMechanics){
  const subtype=array(classMechanics.subraces).find(row=>
   record.species_id&&row.id===record.species_id||
   row.legacy_name&&String(row.legacy_name).toLowerCase()===String(record.species||'').toLowerCase()&&
    String(row.source||'').toLowerCase()===String(record.species_source||'').toLowerCase());
  if(subtype?.speed!==undefined&&record.species_speed!==subtype.speed)
   result={...result,species_speed:subtype.speed};
 }
 const migrate=!Object.hasOwn(record,'proficiency_choices')||
   (!array(record.proficiency_choices).length&&!inheritedOrigins&&!Object.hasOwn(record,'proficiency_origins'));
 if(migrate){
  const choices=[['skill','skill_proficiencies'],['expertise','skill_expertise'],
   ['save','saving_throw_proficiencies']].flatMap(([kind,field])=>
    array(record[field]).map(key=>({kind,key,origin_id:'',origin_name:'',disabled:false})));
  if(choices.length)result={...result,proficiency_choices:choices};
 }
 if(record.stat_block){
  const stat=normalizeMonsterStatBlock(record.stat_block);
  if(stat!==record.stat_block)result={...result,stat_block:stat};
 }
 if(array(record.variants).length){
  const variants=record.variants.map(variant=>{
   const values=normalizeCreatureRecord(variant.values,{classMechanics,
    inheritedOrigins:inheritedOrigins||Object.hasOwn(record,'proficiency_origins')});
   return values===variant.values?variant:{...variant,values};
  });
  if(variants.some((variant,i)=>variant!==record.variants[i]))result={...result,variants};
 }
 return result;
}
// Old/imported monster catalogs still include untyped Multiattack records.
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
 // Monster challenge rating is not character level. An unclassed character
 // can keep custom XP without being assigned a class progression.
 if(record.kind==='monster')return 0;
 const classes=array(record.classes).filter(row=>row&&String(row.name||'').trim());
 const total=classes.length?
  classes.reduce((sum,row)=>sum+Math.max(1,integer(row.level,1)),0):
  record.class?Math.max(1,integer(record.level,1)):0;
 return minimumXpForLevel(total);
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
    footprint:1,reach_feet:5,visual_front_quarter_turns:0,party_id:"",
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
    resource_trackers:[],resource_tracker_spent:{},
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

// Same recovery contract as StructuredResourceTrackers.spent_after_recovery.
// Short rest restores pact magic; long rest restores both types of spell slot.
// Does not invent recovery for HP, hit dice, or manual/dice-recharge resources.
export function recoveryPatch(record,event,trackers=record.resource_trackers){
  if(!["short_rest","long_rest","turn"].includes(event))throw Error("Evento di recupero non valido.");
  const spent={...(record.resource_tracker_spent||{})};
  for(const row of array(trackers)){
    if(!row?.id||row.disabled)continue;
    const mode=String(row.recharge||"manual");
    if(mode===event||(event==="long_rest"&&mode==="short_rest"))delete spent[row.id];
  }
  const patch={resource_tracker_spent:spent};
  if(event==="short_rest"||event==="long_rest")patch.pact_slots_spent=0;
  if(event==="long_rest")patch.spell_slots_spent=zeroSlots();
  return patch;
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

