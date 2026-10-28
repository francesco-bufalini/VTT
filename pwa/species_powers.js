// Source-qualified racial powers. No ability is inferred from free-form prose.
import {canReselectPower,selectionRestLabel} from './trait_state_rules.js';
import {dragonbornFtdProjection} from './dragonborn_ftd.js';
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
 const output=dragonbornFtdProjection(record,index,features);
 const race=rows(index.races).find(row=>norm(row.name)===norm(record.species)&&
   norm(row.source)===norm(record.species_source));
 if(!race||record.rules_version==='2024')return output;
 const owner=features.find(feature=>norm(feature.name)===norm(race.healing?.trait)&&
   String(feature.origin_key||'').startsWith('species|')&&!feature.disabled&&!feature.inactive);
 const raceRoot='race|'+norm(race.source)+'|'+norm(race.name);
 if(race.healing&&owner&&permitted(record,owner.origin_id)&&permitted(record,raceRoot)) {
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
 const featureFor=trait=>features.find(f=>norm(f.name)===norm(trait)&&
   String(f.origin_key||'').startsWith('species|')&&!f.disabled&&!f.inactive&&
   record.trait_enabled?.[f.key]!==false&&permitted(record,f.origin_id)&&
   permitted(record,f.origin_key)&&permitted(record,raceRoot));
 // Source-qualified per-subrace powers retain the owning subrace trait.
 const subraceFeatureFor=(trait,subrace)=>features.find(f=>norm(f.name)===norm(trait)&&
   norm(record.subrace)===norm(subrace)&&norm(record.subrace_source)===norm(race.source)&&
   f.origin_key==='subrace|'+norm(race.source)+'|'+norm(subrace)&&
   !f.disabled&&!f.inactive&&record.trait_enabled?.[f.key]!==false&&
   permitted(record,f.origin_id)&&permitted(record,f.origin_key)&&permitted(record,raceRoot));
 const maximum=uses=>uses==='proficiency'?2+Math.floor((currentLevel(record)-1)/4):
   Math.max(0,Number(uses)||0);
 for(const power of rows(race.active_conditions)){
   const powerOwner=featureFor(power.trait);
   if(!powerOwner||!power.id||!power.condition||!power.tracker_id)continue;
   output.trackers.push({id:power.tracker_id,name:power.trait,max:maximum(power.uses),
     recharge:power.recharge||'long_rest',origin_id:powerOwner.origin_id,
     origin_name:'Tratto · '+power.trait,automatic:true});
   output.abilities.push({id:power.id,name:power.name||power.trait,
     feature_id:powerOwner.origin_id,origin_id:powerOwner.origin_id,
     origin_name:'Tratto · '+power.trait,source:race.source,
     description:power.description||'',action_type:power.action_type||'bonus',
     activation_mode:power.action_type||'bonus',action_kind:'ability',
     mode:'temporary_condition',effect_condition:power.condition,
     persistent_key:power.persistent_key,duration_rounds:power.duration_rounds||1,
     ends_on:rows(power.ends_on),tracker_id:power.tracker_id,resource_cost:1});
 }
 // Keep the normal unlimited cantrip; the extra grant uses the existing
 // spell-casting pipeline with a separate tracker and bonus-action timing.
 for(const cast of rows(race.bonus_cantrips)){
   const castOwner=subraceFeatureFor(cast.trait,cast.subrace);
   if(!castOwner||!cast.tracker_id||!cast.spell_id)continue;
   output.trackers.push({id:cast.tracker_id,name:cast.trait+' · azione bonus',
     max:maximum(cast.uses),recharge:cast.recharge||'long_rest',
     origin_id:castOwner.origin_id,origin_name:'Tratto · '+cast.trait,automatic:true});
   output.origin_spells.push({id:cast.id,
     origin_id:'racial-bonus-cast:'+castOwner.origin_id,
     owner_origin_id:castOwner.origin_id,
     origin_parent_id:castOwner.origin_id,origin_parent_name:cast.trait,
     origin_name:cast.trait+' · azione bonus',granting_trait:cast.trait,
     spell_id:cast.spell_id,mode:'innate',payment_mode:'tracker',
     tracker_id:cast.tracker_id,tracker_cost:1,cantrip:true,
     casting_ability_not_required:true,cast_action_type:cast.action_type||'bonus',
     automatic:true});
 }
 // Each racial die bonus is owned by its individual trait. A tracker is
 // optional: an unlimited situational benefit must never fabricate a resource.
 for(const bonus of [...(race.roll_bonus?[race.roll_bonus]:[]),...rows(race.roll_bonuses)]){
   const bonusOwner=featureFor(bonus.trait);
   if(!bonusOwner||!bonus.dice||!rows(bonus.targets).length)continue;
   const trackerId=String(bonus.tracker_id||'');
   if(trackerId){
     output.trackers.push({id:trackerId,name:bonus.trait,
       max:bonus.uses==='proficiency'?2+Math.floor((currentLevel(record)-1)/4):Math.max(0,Number(bonus.uses)||0),
       recharge:bonus.recharge||'long_rest',origin_id:bonusOwner.origin_id,
       origin_name:'Tratto · '+bonus.trait,automatic:true});
   }
   output.roll_bonuses.push({id:bonus.id||'racial-roll:'+norm(race.name)+':'+norm(bonus.trait),
     origin_id:bonusOwner.origin_id,origin_name:'Tratto · '+bonus.trait,
     origin_parent_id:raceRoot,granting_trait:bonus.trait,
     name:bonus.name||bonus.trait,description:bonus.description||'',
     condition_label:bonus.condition_label||'',
     dice:bonus.dice,targets:bonus.targets,
     ...(trackerId?{tracker_id:trackerId,tracker_cost:Math.max(1,Number(bonus.tracker_cost)||1),
       strict_tracker:bonus.strict_tracker===true}:{}),
     automatic:true,optional:true});
 }
 // Racial actions are trait-owned, source-qualified and do not need a
 // tracker. An attack reference reuses an existing computed attack roll.
 for(const action of rows(race.actions)){
   const actionOwner=featureFor(action.trait);
   if(!actionOwner||!action.id||!action.action_type)continue;
   const roll=action.roll_attack;
   if(roll&&!(roll.kind==='attack'&&
     (typeof roll.trait==='string'&&roll.trait.trim()||
      typeof roll.id==='string'&&roll.id.trim())))continue;
   output.abilities.push({
     id:action.id,name:action.name||action.trait,feature_id:actionOwner.origin_id,
     origin_id:actionOwner.origin_id,origin_name:'Tratto · '+action.trait,
     source:race.source,description:action.description||'',
     action_type:action.action_type,activation_mode:action.action_type,
     action_kind:'ability',resource_cost:0,
     ...(roll?{roll_attack:{kind:'attack',
       ...(roll.id?{id:String(roll.id)}:{}),
       ...(roll.trait?{trait:String(roll.trait)}:{}),
       ...(roll.slot?{slot:String(roll.slot)}:{})}}:{})
   });
 }
 const teleport=race.teleport,teleportOwner=teleport&&featureFor(teleport.trait);
 if(teleportOwner&&teleport.spell_id&&teleport.tracker_id){
   output.trackers.push({id:teleport.tracker_id,name:teleport.trait,
     max:teleport.uses==='proficiency'?2+Math.floor((currentLevel(record)-1)/4):Number(teleport.uses)||0,
     recharge:teleport.recharge||'long_rest',origin_id:teleportOwner.origin_id,
     origin_name:'Tratto · '+teleport.trait,automatic:true});
   output.origin_spells.push({id:'racial-power:'+norm(race.source)+':'+norm(race.name)+':'+norm(teleport.trait),
     origin_id:teleportOwner.origin_id,origin_name:teleport.trait,granting_trait:teleport.trait,
     origin_parent_id:raceRoot,origin_parent_name:race.name,spell_id:teleport.spell_id,
     mode:'innate',payment_mode:'tracker',tracker_id:teleport.tracker_id,
     tracker_cost:1,cantrip:false,casting_ability_not_required:true,automatic:true});
 }
 const training=race.rest_training,trainingOwner=training&&featureFor(training.trait);
 if(trainingOwner&&training.group&&training.recovery){
   const picks=rows(training.picks).length?training.picks:[
     ...Array.from({length:training.skill_count||1},()=>({label:'Abilità',kinds:['skill']})),
     ...Array.from({length:training.weapon_tool_count||1},()=>({label:'Arma o strumento',kinds:['weapon','tool']}))
   ];
   output.rest_choices.push({group:training.group,trait:training.trait,recovery:training.recovery,
     kind:'training',root_id:raceRoot,origin_id:trainingOwner.origin_id,
     picks,description:training.description||''});
 }
 const season=race.season_choice,seasonOwner=season&&featureFor(season.trait);
 if(seasonOwner&&season.group&&rows(season.options).length)
   output.rest_choices.push({group:season.group,trait:season.trait,recovery:season.recovery,
     kind:'racial_option',root_id:raceRoot,origin_id:seasonOwner.origin_id,
     label:season.label||'Scelta',options:season.options,option_labels:season.option_labels||{},
     description:'Puoi scegliere o cambiare questa opzione al termine del riposo lungo.'});
 const revelation=race.revelation;
 const form=rows(revelation?.subraces).find(row=>norm(row.name)===norm(record.subrace)&&
   norm(record.subrace_source)===norm(race.source));
 if(form&&currentLevel(record)>=Number(revelation.min_level||3)&&
   permitted(record,raceRoot)&&permitted(record,'subrace|'+norm(race.source)+'|'+norm(form.name))) {
   const originKey='subrace|'+norm(race.source)+'|'+norm(form.name);
   const featureId='feature:'+originKey+'|'+revelation.min_level+'|'+norm(form.name);
   const feature={name:form.name,origin_id:featureId,origin_key:originKey,
     level:revelation.min_level,requirements:{scope:'character',min_level:revelation.min_level},
     entries:[form.description],bonuses:[],action_type:'bonus',action_kind:'Capacità'};
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
// End a trait-owned temporary condition without deleting a condition the
// character already had before the racial ability was activated.
export function endTemporaryConditionPatch(record={},key='racial:firbolg:hidden_step'){
 const current=record.active_class_features?.[key];
 if(!current||!current.effect_condition)return {};
 const active={...(record.active_class_features||{})};
 delete active[key];
 const patch={active_class_features:active};
 const stillGranted=Object.values(active).some(row=>row?.effect_condition===current.effect_condition);
 if(current.added_condition&&!stillGranted)
   patch.conditions=rows(record.conditions).filter(value=>norm(value)!==norm(current.effect_condition));
 return patch;
}
// Rest training uses Armor Model's reselection lifecycle and ordinary typed
// proficiency grants; it never writes a permanent racial proficiency.
// A source-defined set of proficiency slots: skill+weapon/tool or two weapon/tools.
export function restTrainingPatch(record={},choice={},selected=[],allowed={}){
 if(!choice.group||!choice.root_id||!choice.origin_id||!choice.trait||
   !rows(choice.picks).length)throw Error('Competenze temporanee non disponibili.');
 if(!canReselectPower(record,choice.group))
   throw Error('Puoi riselezionare le competenze dopo un '+selectionRestLabel(choice.recovery).toLowerCase()+'.');
 if(!Array.isArray(selected)||selected.length!==choice.picks.length)
   throw Error('Scegli tutte le competenze previste dal privilegio.');
 const picks=selected.map((value,i)=>{
   const [kind,...parts]=String(value||'').split(':'),key=parts.join(':').toLowerCase();
   if(!rows(choice.picks[i]?.kinds).includes(kind)||!key||
     !rows(allowed[kind]).includes(key))throw Error('Competenza non valida per questa scelta.');
   return {kind,key};
 });
 if(new Set(picks.map(row=>row.kind+':'+row.key)).size!==picks.length)
   throw Error('Non puoi selezionare due volte la stessa competenza.');
 if(picks.some(row=>rows(allowed.unavailable).includes(row.kind+':'+row.key)))
   throw Error('Puoi scegliere soltanto competenze che non possiedi già.');
 return {
   proficiency_choices:[
     ...rows(record.proficiency_choices).filter(row=>row?.rest_training_group!==choice.group),
     ...picks.map(row=>({...row,origin_id:choice.root_id,rest_training_group:choice.group,
       granting_feature_origin_id:choice.origin_id,
       origin_name:'Tratto · '+choice.trait}))
   ],
   trait_state_selection:{...(record.trait_state_selection||{}),[choice.group]:'selected'},
   rest_selection_available:{...(record.rest_selection_available||{}),[choice.group]:false}
 };
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

export function racialPowerSpellDefinitions(index={},record={},originDetails={}) {
 return rows(index.races).flatMap(race=>[
  ...(race.teleport?[{
    id:race.teleport.spell_id,name:race.teleport.trait,source:race.source,
    level:0,internal_grant:true,action_kind:'ability',classes:[],
    time:[{number:1,unit:race.teleport.action_type||'bonus'}],casting_time:'Bonus Action',
    range:'Self',range_feet:race.teleport.range_feet,target_mode:race.teleport.target_mode||'teleport_self',
    teleport_range_feet:race.teleport.range_feet,
    targeting_template_spell_id:race.teleport.targeting_template_spell_id||'',
    duration:'Instantaneous',description:race.teleport.description+
      (race.season_choice&&currentLevel(record)>=3&&norm(record.species)===norm(race.name)&&
       norm(record.species_source)===norm(race.source)?
        (()=>{const key=record.trait_state_selection?.[race.season_choice.group]||'';
          const source=originDetails?.races?.[norm(race.name)+'|'+norm(race.source)];
          const feature=rows(source?.entries).find(row=>norm(row?.name)===norm(race.teleport.trait));
          const seasonList=rows(feature?.entries).find(row=>row?.type==='list');
          const sourceEntry=rows(seasonList?.items).find(row=>norm(row?.name)===key)?.entry;
          // Prefer the original 5etools trait text when the offline source catalog
          // is available; the short data-defined copy is only a fallback.
          const description=String(sourceEntry||race.season_choice.descriptions?.[key]||'')
            .replace(/\{@(?:condition|damage|dice)\s+([^}|]+)[^}]*\}/gi,'$1');
          return description?'\nStagione: '+(race.season_choice.option_labels?.[key]||key)+'. '+description:
            '\nScegli una stagione per conoscere l’effetto aggiuntivo dal livello 3.';})():'')
  }]:[]),
  ...rows(race.revelation?.subraces).map(form=>({
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
 }))]);
}
