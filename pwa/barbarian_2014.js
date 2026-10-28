// Source-qualified, data-driven supplements for the 2014 Barbarian.
// Only an owned, enabled 5etools feature may grant an action or mechanical effect.
// These helpers do not interpret rulebook prose or assume an in-app hit/damage roll.
import {resolveOwnedItem} from './item_controls.js';
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value||'').trim().toLowerCase();
const path=value=>norm(value).replace(/^path of (?:the )?/,'').replace(/^the /,'');
const classMembers=record=>rows(record.classes).length?record.classes:
  record.class?[{name:record.class,source:record.class_source,subclass:record.subclass,
    subclass_source:record.subclass_source,level:record.level}]:[];
import {BARBARIAN_2014_GRANTS} from './catalog/barbarian_2014_rules.js';

export function barbarian2014Supplements(record={},features=[]){
 const empty={actions:[],trackers:[],numeric_grants:[],conditional_modes:[],
   initiative_origin:'',spell_choices:[],proficiency_rows:[]};
 if(String(record.rules_version||'2014')==='2024')return empty;
 const member=classMembers(record).find(row=>norm(row.name)==='barbarian'&&
   (!row.source||norm(row.source)==='phb'));
 if(!member)return empty;
 const level=Math.max(0,Number(member.level)||0);
 const available=feature=>!!feature&&!feature.inactive&&!feature.disabled&&
   record.origin_enabled?.[feature.origin_id]!==false&&
   record.trait_enabled?.[feature.key]!==false&&
   !rows(record.proficiency_origins).some(o=>o?.id===feature.origin_id&&o.disabled);
 const matches=(feature,rule)=>{
   if(norm(feature?.name)!==norm(rule.feature)||
      !String(feature.origin_key||'').startsWith('class|phb|barbarian'))return false;
   const origin=String(feature.origin_key||'');
   if(!rule.subclass)return !origin.includes('|subclass|');
   const source=origin.split('|subclass|')[1];
   return !!source&&path(source.split('|')[0])===path(rule.subclass)&&
     path(member.subclass||record.subclass)===path(rule.subclass)&&
     (!member.subclass_source||!feature.subclass_source||
       norm(member.subclass_source)===norm(feature.subclass_source));
 };
 const armored=rows(record.inventory).map(resolveOwnedItem).some(item=>
   rows(item?.equipped_slots).includes('body')&&
   String(item?.type||'').split('|')[0].toUpperCase()==='HA'&&
   Number(item?.quantity??1)>0);
 const requirements={no_heavy_armor:!armored,
   rage:!!record.active_class_features?.rage,
   conscious:!rows(record.conditions).includes('unconscious')};
 const result={...empty};
 for(const rule of BARBARIAN_2014_GRANTS){
   const matching=rows(features).filter(feature=>matches(feature,rule)&&available(feature));
   if(!matching.length||(rule.requires||[]).some(name=>!requirements[name]))continue;
   for(const feature of rule.repeat_per_feature?matching:[matching[0]]){
     if(rule.defense_choice&&norm(record.origin_defense_choices?.[feature.origin_id])!==rule.defense_choice)continue;
     if(rule.state_choice&&record.trait_state_selection?.[rule.state_choice.group]!==rule.state_choice.value)continue;
     if(rule.kind==='numeric')result.numeric_grants.push({id:rule.id,target:rule.target,
       expression:rule.expression,origin_id:feature.origin_id,
       origin_name:'Tratto · '+feature.name+(rule.origin_suffix||''),automatic:true});
     else if(rule.kind==='action')result.actions.push({id:rule.id,name:rule.name,
       action_type:rule.action_type,type:'Capacità',description:rule.description,
       origin_id:feature.origin_id,feature_id:feature.origin_id,
       feature_name:feature.name,automatic:true});
     else if(rule.kind==='roll_mode')result.conditional_modes.push({id:rule.id,
       target:rule.target,mode:rule.mode,origin_id:feature.origin_id,
       origin_name:'Tratto · '+feature.name,granting_trait:feature.name,
       condition_label:rule.condition_label});
     else if(rule.kind==='initiative')result.initiative_origin=feature.origin_id;
     else if(rule.kind==='proficiency'&&feature.id&&
       Number(feature.level||feature.requirements?.level||rule.min_feature_level||3)<=level)
       result.proficiency_rows.push({id:feature.id,name:feature.name,
         source:feature.source||rule.source_fallback,class_name:'Barbarian',class_source:'PHB',
         ...(rule.subclass?{subclass_short_name:feature.subclass_short_name,
           subclass_source:feature.subclass_source,subclass_feature:true}:{}),
         level:Number(feature.level||(rule.subclass?6:rule.min_feature_level||3)),
         skillProficiencies:[{choose:rule.choose}]});
     else if(rule.kind==='spell_choice')result.spell_choices.push({id:rule.id,
       origin_id:feature.origin_id,origin_name:feature.name,
       granting_trait:feature.name,spell_options:rule.spell_options,
       count:rule.count,mode:rule.mode,stage:rule.stage,usage:rule.usage,
       tracker_id:rule.tracker_id,spellcasting_ability:rule.spellcasting_ability,
       spellcasting_ability_options:rule.spellcasting_ability_options});
   }
 }
 return result;
}


export function barbarian2014ProficiencyCatalog(index={},supplements={}){
 if(!supplements.proficiency_rows?.length)return index;
 const ownClass=rows(index.classFeature),ownSubclass=rows(index.subclassFeature);
 const classes=supplements.proficiency_rows.filter(row=>!row.subclass_feature);
 const subclasses=supplements.proficiency_rows.filter(row=>row.subclass_feature);
 return {...index,
  classFeature:[...ownClass,...classes.filter(row=>!ownClass.some(other=>other.id===row.id))],
  subclassFeature:[...ownSubclass,...subclasses.filter(row=>!ownSubclass.some(other=>other.id===row.id))]};
}
