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
const SKILLS=['animal handling','athletics','intimidation','nature','perception','survival'];


export function barbarian2014Supplements(record={},features=[]){
 const empty={actions:[],trackers:[],numeric_grants:[],conditional_modes:[],
   initiative_origin:'',spell_choices:[],proficiency_rows:[]};
 if(String(record.rules_version||'2014')==='2024')return empty;
 const member=classMembers(record).find(row=>norm(row.name)==='barbarian'&&
   (!row.source||norm(row.source)==='phb'));
 if(!member)return empty;
 const level=Math.max(0,Number(member.level)||0);
 const owned=(name,sub='')=>rows(features).find(f=>{
  if(norm(f.name)!==norm(name)||f.inactive||f.disabled||
     !String(f.origin_key||'').startsWith('class|phb|barbarian'))return false;
  const origin=String(f.origin_key||'');
  if(!sub)return !origin.includes('|subclass|');
  const source=origin.split('|subclass|')[1];
  return !!source&&path(source.split('|')[0])===path(sub)&&
    path(member.subclass||record.subclass)===path(sub)&&
    (!member.subclass_source||!f.subclass_source||norm(member.subclass_source)===norm(f.subclass_source));
 });
 const available=f=>!!f&&record.origin_enabled?.[f.origin_id]!==false&&
   record.trait_enabled?.[f.key]!==false&&
   !rows(record.proficiency_origins).some(o=>o?.id===f.origin_id&&o.disabled);
 const actions=[],trackers=[],numeric_grants=[],conditional_modes=[],proficiency_rows=[],spell_choices=[];
 const active=(name,sub='')=>{const f=owned(name,sub);return available(f)?f:null;};
 const fast=active('Fast Movement');
 const armored=rows(record.inventory).map(resolveOwnedItem).some(item=>rows(item?.equipped_slots).includes('body')&&
   String(item?.type||'').split('|')[0].toUpperCase()==='HA'&&
   Number(item?.quantity??1)>0);
 if(fast&&!armored)numeric_grants.push({id:'barbarian:2014:fast-movement',target:'speed',expression:'10',
   origin_id:fast.origin_id,origin_name:'Tratto · Fast Movement',automatic:true});
 const totem=active('Totem Spirit','Totem Warrior');
 if(totem){
  const animal=norm(record.origin_defense_choices?.[totem.origin_id]);
  if(animal==='elk'&&!!record.active_class_features?.rage&&!armored&&
     !rows(record.conditions).includes('unconscious'))
   numeric_grants.push({id:'barbarian:2014:totem-elk-speed',target:'speed',
    expression:'15',origin_id:totem.origin_id,origin_name:'Tratto · Totem Spirit (Elk)',automatic:true});
  if(animal==='eagle')
   actions.push({id:'barbarian:2014:totem-eagle-dash',
    name:'Totem Spirit · Aquila · Scatto',action_type:'bonus',type:'Capacità',
    description:'Durante l’Ira puoi effettuare Scatto come azione bonus. Gli attacchi di opportunità contro di te hanno svantaggio; applicalo manualmente.',
    origin_id:totem.origin_id,feature_id:totem.origin_id,feature_name:totem.name,automatic:true});
 }
 const danger=active('Danger Sense');
 if(danger)conditional_modes.push({id:'barbarian:2014:danger-sense',target:'save:dex',
   mode:'advantage',origin_id:danger.origin_id,origin_name:'Tratto · Danger Sense',
   granting_trait:'Danger Sense',condition_label:
   'Solo contro effetti che puoi vedere; non se sei accecato, assordato o incapacitato.'});
 const instinct=active('Feral Instinct');
 const knowledge=rows(features).filter(f=>norm(f.name)==='primal knowledge'&&
   String(f.origin_key||'').startsWith('class|phb|barbarian')&&
   !f.inactive&&!f.disabled&&Number(f.level||f.requirements?.level||3)<=level);
 for(const f of knowledge)if(available(f)&&f.id)proficiency_rows.push({
   id:f.id,name:f.name,source:f.source||'TCE',class_name:'Barbarian',class_source:'PHB',
   level:Number(f.level||3),skillProficiencies:[{choose:{from:SKILLS,count:1}}]});
 const aspect=active('Aspect of the Beast','Totem Warrior');
 if(aspect?.id&&record.trait_state_selection?.barbarian_totem_aspect==='barbarian_totem_aspect:tiger')
  proficiency_rows.push({id:aspect.id,name:aspect.name,source:aspect.source,
   class_name:'Barbarian',class_source:'PHB',
   subclass_short_name:aspect.subclass_short_name,
   subclass_source:aspect.subclass_source,subclass_feature:true,
   level:Number(aspect.level||6),
   skillProficiencies:[{choose:{from:['acrobatics','athletics','stealth','survival'],count:2}}]});
 const giant=active('Giant Power','Giant');
 if(giant)spell_choices.push({id:'barbarian:2014:giant-power:cantrip',
   origin_id:giant.origin_id,origin_name:giant.name,
   granting_trait:giant.name,spell_options:['phb2014_druidcraft','phb2014_thaumaturgy'],
   count:1,mode:'known',stage:'3',usage:'at_will',tracker_id:'',
   spellcasting_ability:'wis',spellcasting_ability_options:[]});
 return {actions,trackers,numeric_grants,conditional_modes,
   initiative_origin:instinct?.origin_id||'',spell_choices,proficiency_rows};
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
