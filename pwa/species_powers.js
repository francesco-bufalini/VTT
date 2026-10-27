// Source-qualified racial powers. No ability is inferred from free-form prose.
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
const currentLevel=record=>rows(record.classes).length?
  rows(record.classes).reduce((n,member)=>n+Math.max(0,Number(member.level)||0),0):
  Math.max(1,Number(record.level)||1);
const permitted=(record,id)=>record.origin_enabled?.[id]!==false&&
  !rows(record.proficiency_origins).some(row=>row?.id===id&&row.disabled);

export function racialPowerSubraces(index={}) {
 return rows(index.races).flatMap(race=>rows(race.revelation?.subraces).map(form=>({
   id:form.id,name:form.name,source:race.source,
   raceName:race.name,raceSource:race.source,level:race.revelation.min_level,
   entries:[{name:form.name,level:race.revelation.min_level,entries:[form.description]}]
 })));
}
export function racialPowerProjection(record={},index={},features=[]) {
 const output={features:[],trackers:[],abilities:[],origin_spells:[],active_forms:[]};
 const race=rows(index.races).find(row=>norm(row.name)===norm(record.species)&&
   norm(row.source)===norm(record.species_source));
 if(!race||record.rules_version==='2024')return output;
 const owner=features.find(feature=>norm(feature.name)===norm(race.healing.trait)&&
   String(feature.origin_key||'').startsWith('species|')&&!feature.disabled&&!feature.inactive);
 const raceRoot='race|'+norm(race.source)+'|'+norm(race.name);
 if(owner&&permitted(record,owner.origin_id)&&permitted(record,raceRoot)) {
   const heal=race.healing;
   output.trackers.push({id:heal.tracker_id,name:heal.trait,max:heal.uses,
     recharge:heal.recharge,origin_id:owner.origin_id,origin_name:heal.trait,automatic:true});
   output.abilities.push({id:heal.id,name:heal.trait,feature_id:owner.origin_id,
     origin_id:owner.origin_id,origin_name:heal.trait,source:race.source,
     description:heal.description,action_type:heal.action_type,
     activation_mode:heal.action_type,action_kind:'ability',mode:'heal_dice',
     heal_dice:heal.roll,resource_cost:1,tracker_id:heal.tracker_id,
     target_mode:heal.target_mode,target_range_feet:heal.target_range_feet});
 }
 const revelation=race.revelation;
 const form=rows(revelation.subraces).find(row=>norm(row.name)===norm(record.subrace)&&
   norm(record.subrace_source)===norm(race.source));
 if(form&&currentLevel(record)>=Number(revelation.min_level||3)&&
   permitted(record,raceRoot)&&permitted(record,'subrace|'+norm(race.source)+'|'+norm(form.name))) {
   const originKey='subrace|'+norm(race.source)+'|'+norm(form.name);
   const featureId='feature:'+originKey+'|'+revelation.min_level+'|'+norm(form.name);
   const feature={name:form.name,origin_id:featureId,origin_key:originKey,
     level:revelation.min_level,requirements:{scope:'character',min_level:revelation.min_level},
     entries:[form.description],action_type:'bonus',action_kind:'Capacità'};
   output.features.push(feature);
   output.trackers.push({id:revelation.tracker_id,name:revelation.trait,
     max:revelation.uses,recharge:revelation.recharge,origin_id:featureId,
     origin_name:revelation.trait,automatic:true});
   output.origin_spells.push({
     id:'racial-power:'+norm(race.source)+':'+norm(race.name)+':'+norm(form.name),
     origin_id:featureId,origin_name:form.name,parent_origin:originKey,
     spell_id:form.spell_id,mode:'innate',payment_mode:'tracker',
     tracker_id:revelation.tracker_id,tracker_cost:1,cantrip:false,
     spellcasting_ability:form.spellcasting_ability||'',
     requires_spellcasting_ability:!!form.spellcasting_ability,
     casting_ability_not_required:!form.spellcasting_ability,
     active_key:'racial:celestial_revelation',
     duration_rounds:revelation.duration_rounds,
     aura_radius_feet:form.radius_feet,automatic:true,
     damage_type:form.damage_type,bonus_damage_once_per_turn:'proficiency'
   });
   output.active_forms.push({id:form.id,name:form.name,spell_id:form.spell_id,
     origin_id:featureId,tracker_id:revelation.tracker_id,
     active_key:'racial:celestial_revelation',duration_rounds:revelation.duration_rounds,
     fly_equals_walk:form.fly_equals_walk===true,damage_type:form.damage_type,
     bonus_damage_once_per_turn:'proficiency'});
 }
 return output;
}
export function healingHandsPatch(record={},calculated={},power={},rollDie=()=>1,target=null) {
 if(power.mode!=='heal_dice'||power.heal_dice?.count!=='proficiency'||
   !Number.isInteger(Number(power.heal_dice?.sides))||Number(power.heal_dice.sides)<2)
   throw Error('Capacità di cura non valida.');
 const tracker=rows(calculated.trackers).find(row=>row.id===power.tracker_id&&!row.disabled);
 const spent=Number(record.resource_tracker_spent?.[power.tracker_id]||0);
 if(!tracker||spent>=Number(tracker.max||0))throw Error('Healing Hands: utilizzi esauriti.');
 const proficiency=Number(calculated.stats?.proficiency||calculated.values?.proficiency||0);
 if(!Number.isInteger(proficiency)||proficiency<1||proficiency>9)throw Error('Bonus di competenza non valido.');
 const sides=Number(power.heal_dice.sides);
 const dice=Array.from({length:proficiency},()=>Number(rollDie(sides)));
 if(dice.some(n=>!Number.isInteger(n)||n<1||n>sides))throw Error('Tiro di cura non valido.');
 const total=dice.reduce((sum,n)=>sum+n,0);
 const patch={resource_tracker_spent:{...(record.resource_tracker_spent||{}),[tracker.id]:spent+1}};
 if(target==='self'){
   const max=Math.max(0,Number(calculated.stats?.max_hp)||0);
   patch.current_hp=Math.min(max,Math.max(0,Number(record.current_hp)||0)+total);
 }
 return {patch,dice,total,notation:proficiency+'d'+sides};
}

export function racialPowerSpellDefinitions(index={}) {
 return rows(index.races).flatMap(race=>rows(race.revelation?.subraces).map(form=>({
   id:form.spell_id,name:form.name,source:race.source,level:0,
   internal_grant:true,action_kind:'ability',classes:[],
   time:[{number:1,unit:'bonus'}],casting_time:'Bonus Action',
   range:'Self',range_feet:0,target_mode:'self_emanation',
   aoe_shape:'sphere',aoe_radius_feet:form.radius_feet,
   persistent:true,follow_caster:true,duration:'1 minute',
   condition_inflict:[],saving_throw:form.spellcasting_ability?['charisma']:[],
   description:form.description,damage_type:form.damage_type,
   bonus_damage_once_per_turn:'proficiency',
   area_damage_end_of_caster_turn:form.name==='Radiant Consumption',
   area_damage_formula:form.name==='Radiant Consumption'?'proficiency':''
 })));
}
