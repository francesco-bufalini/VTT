import {speciesTraitDescription} from './species_trait_text.js';
// Rules for the 2021 Fizban dragonborn variants. The PHB dragonborn is replaced,
// never inherited, even when an older character stores FTD as a subrace.
const norm=v=>String(v??'').trim().toLowerCase();
const rows=v=>Array.isArray(v)?v:[];
export function dragonbornFtdProfile(record={},catalog={}){
 if(record.rules_version==='2024')return null;
 let variant='',origin_id='',origin_key='';
 const flattened=String(record.species||'').match(/^Dragonborn \((Chromatic|Metallic|Gem)\)$/i);
 if(flattened&&norm(record.species_source)==='ftd'){
  variant=flattened[1].toLowerCase();
  origin_id='race|ftd|'+norm(record.species);
  origin_key='species|'+(record.species_id||norm(record.species))+'|ftd';
 }else if(norm(record.species)==='dragonborn'&&norm(record.species_source)==='phb'&&
          norm(record.subrace_source)==='ftd'&&
          ['chromatic','metallic','gem'].includes(norm(record.subrace))){
  variant=norm(record.subrace);
  origin_id='subrace|ftd|'+variant;
  origin_key=origin_id;
 }else return null;
 const definition=rows(catalog.races).find(row=>norm(row.name)==='dragonborn ('+variant+')'&&norm(row.source)==='ftd');
 if(!definition?.draconic_ancestries?.length)return null;
 // For new FTD species, ancestry is their color subrace. Retain a saved
 // ancestry only for previously created flattened characters without a color.
 const selected=norm(flattened&&norm(record.subrace_source)==='ftd'?
   record.subrace:record.origin_draconic_ancestry?.[origin_id]);
 const ancestry=rows(definition.draconic_ancestries).find(row=>norm(row.name)===selected)||null;
 return {variant,origin_id,origin_key,definition,ancestry,selected:ancestry?selected:''};
}
export function dragonbornFtdChoice(record={},catalog={}){
 const p=dragonbornFtdProfile(record,catalog);
 if(!p||norm(record.species_source)==='ftd')return null;
 return {id:'ancestry:'+p.origin_id,kind:'draconic_ancestry',origin_id:p.origin_id,
  name:'Dragonborn · '+p.variant[0].toUpperCase()+p.variant.slice(1),
  label:'Ascendenza draconica',count:1,
  options:p.definition.draconic_ancestries.map(row=>row.name.toLowerCase()),
  option_labels:Object.fromEntries(p.definition.draconic_ancestries.map(row=>
   [row.name.toLowerCase(),row.name+' · '+row.damage_type])),
  selected:p.selected?[p.selected]:[],remaining:p.selected?0:1};
}
export function dragonbornFtdSaveChoice(record,choice,selected=[]){
 // Validate against the immutable source-qualified options provided by the live choice,
 // not against data saved on a character.
 const matching=norm(record.species_source)==='ftd'&&
   choice.origin_id==='race|ftd|'+norm(record.species)||
   norm(record.species)==='dragonborn'&&norm(record.species_source)==='phb'&&
   choice.origin_id==='subrace|ftd|'+norm(record.subrace)&&norm(record.subrace_source)==='ftd';
 if(!matching||choice?.kind!=='draconic_ancestry'||!/^((subrace\|ftd\|(chromatic|metallic|gem))|(race\|ftd\|dragonborn \((chromatic|metallic|gem)\)))$/.test(choice.origin_id||'')||
   selected.length>1||selected.some(name=>!rows(choice.options).includes(name)))throw Error('Ascendenza draconica non valida.');
 const values={...(record.origin_draconic_ancestry||{})};
 if(selected.length)values[choice.origin_id]=selected[0];
 else delete values[choice.origin_id];
 return {origin_draconic_ancestry:values};
}
export function dragonbornFtdResistances(record={},catalog={},features=[]){
 const p=dragonbornFtdProfile(record,catalog);
 if(!p?.ancestry)return [];
 if(record.origin_enabled?.[p.origin_id]===false)return [];
 const owner=name=>rows(features).find(f=>norm(f.name)===norm(name)&&f.origin_key===p.origin_key);
 const allowed=name=>{
  const f=owner(name);
  return !!f&&!f.inactive&&!f.disabled&&record.origin_enabled?.[f.origin_id]!==false&&record.trait_enabled?.[f.key]!==false;
 };
 const output=allowed('Draconic Resistance')?[{rank:1,key:p.ancestry.damage_type,trait:'Draconic Resistance',
  origin_id:owner('Draconic Resistance').origin_id,origin_parent_id:p.origin_id,
  origin_parent_name:p.definition.name,origin_name:'Tratto · Draconic Resistance',
  granting_trait:'Draconic Resistance',
  benefit_id:'defense:'+p.origin_id+':1:'+p.ancestry.damage_type,
  automatic:true}]:[];
 if(p.variant==='chromatic'&&allowed('Chromatic Warding')&&
    record.active_class_features?.['racial:dragonborn_ftd:warding']?.origin_id===p.origin_id)
  output.push({rank:2,key:p.ancestry.damage_type,trait:'Chromatic Warding',
   origin_id:owner('Chromatic Warding').origin_id,origin_parent_id:p.origin_id,
   origin_parent_name:p.definition.name,origin_name:'Tratto · Chromatic Warding',
   granting_trait:'Chromatic Warding',
   benefit_id:'defense:'+p.origin_id+':2:'+p.ancestry.damage_type,automatic:true});
 return output;
}
export function dragonbornFtdProjection(record={},catalog={},knownFeatures=[],originDetails={}){
 const output={features:[],trackers:[],abilities:[],origin_spells:[],active_forms:[],rest_choices:[],roll_bonuses:[]};
 const p=dragonbornFtdProfile(record,catalog);
 if(!p||record.origin_enabled?.[p.origin_id]===false||
   rows(record.proficiency_origins).some(x=>x.id===p.origin_id&&x.disabled))return output;
 const level=rows(record.classes).length?rows(record.classes).reduce((n,x)=>n+Math.max(0,Number(x.level)||0),0):Math.max(1,Number(record.level)||1);
 const proficiency=2+Math.floor((Math.max(1,level)-1)/4);
 const descriptionFor=(trait,option='')=>speciesTraitDescription(
   originDetails,p.definition.name,p.definition.source,trait,{option});
 const featureFor=(name,minLevel=1)=>{
  if(level<minLevel)return null;
  const original=rows(knownFeatures).find(f=>norm(f.name)===norm(name)&&f.origin_key===p.origin_key);
  const id=original?.origin_id||'feature:'+p.origin_key+'|'+minLevel+'|'+norm(name);
  const key=original?.key||p.origin_key+'|'+minLevel+'|'+norm(name);
  if(original?.inactive||original?.disabled||record.origin_enabled?.[id]===false||record.trait_enabled?.[key]===false)return null;
  if(!original)output.features.push({name,origin_key:p.origin_key,origin_id:id,key,
   level:minLevel,source:'FTD',requirements:{scope:'character',min_level:minLevel},
   entries:[name+' · '+p.definition.name],bonuses:[],action_kind:'Capacità'});
  return id;
 };
 // Expose missing source traits without relying on free-form text parsing.
 featureFor('Draconic Ancestry');
 featureFor('Draconic Resistance');
 const breath=p.ancestry&&featureFor('Breath Weapon');
 if(breath){
  const rule=p.definition.breath_weapon;
  const dice=(level>=17?4:level>=11?3:level>=5?2:1)+'d10';
  const tracker_id='race:ftd:dragonborn:'+p.variant+':breath';
  output.trackers.push({id:tracker_id,name:'Breath Weapon',max:proficiency,
   recharge:'long_rest',origin_id:breath,origin_name:'Breath Weapon',automatic:true});
  output.abilities.push({id:tracker_id,name:'Breath Weapon',source:'FTD',
   feature_id:breath,origin_id:breath,origin_name:'Tratto · Breath Weapon',
   description:descriptionFor('Breath Weapon'),
   action_type:'action',activation_mode:'action',mode:'save_area',
   attack_replacement:true,resource_cost:1,tracker_id,
   area_shape:rule.shape,area_length_feet:rule.length_feet||0,
   area_width_feet:rule.width_feet||0,area_radius_feet:rule.radius_feet||0,
   damage_formula:dice,damage_type:p.ancestry.damage_type,
   save_ability:'dex',save_base:'constitution',half_on_save:true});
 }
 const special=p.definition.special,owner=special&&featureFor(special.trait,special.min_level||5);
 if(owner&&(p.ancestry||special.mode==='choice_area')){
  const tracker_id='race:ftd:dragonborn:'+p.variant+':special';
  output.trackers.push({id:tracker_id,name:special.trait,max:1,recharge:'long_rest',
   origin_id:owner,origin_name:special.trait,automatic:true});
  output.abilities.push({id:tracker_id,name:special.trait,source:'FTD',
   feature_id:owner,origin_id:owner,origin_name:'Tratto · '+special.trait,
   description:descriptionFor(special.trait),action_type:special.action_type,
   activation_mode:special.action_type,mode:special.mode,
   attack_replacement:special.mode==='choice_area',
   resource_cost:1,tracker_id,duration_rounds:special.duration_rounds||0,
   persistent_key:special.persistent_key||'',persistent_origin_id:p.origin_id,
   damage_type:p.ancestry?.damage_type||'',options:rows(special.options).map(option=>({...option,
     description:descriptionFor(special.trait,option.name)})),
   area_shape:special.shape||'',area_radius_feet:special.radius_feet||0,
   save_base:'constitution',half_on_save:false});
 }
 return output;
}
