// Offline structured class-feature mechanics shared by the PWA sheet and actions.
// No regex matching feature prose; no network access in the evaluation path.
import {resolveOwnedItem} from './item_controls.js';
const rows=value=>Array.isArray(value)?value:[];
const low=value=>String(value||'').trim().toLowerCase();
const subclass=value=>low(value).replace(/^(?:circle of |way of |oath of |school of )/,'').replace(/^the /,'');
// Same explicit operations as vtt/class_feature_activation.gd. Descriptions
// never determine effects, payments or eligibility.
export const CLASS_FEATURE_RULES=[
 ['armor_guardian','Artificer','Armor Model','Modello armatura · Guardiano','','free','armor_model'],
 ['armor_infiltrator','Artificer','Armor Model','Modello armatura · Infiltratore','','free','armor_model'],
 ["magical_tinkering", "Artificer", "Magical Tinkering", "Congegni magici", "", "action", "context"],
 ["flash_of_genius", "Artificer", "Flash of Genius", "Lampo di genio", "Flash of Genius", "reaction", "context"],
 ["defensive_field", "Artificer", "Defensive Field", "Campo difensivo", "Defensive Field", "bonus", "temporary_hp"],
 ["experimental_elixir", "Artificer", "Experimental Elixir", "Elisir sperimentale", "Experimental Elixir", "action", "context"],
 ["eldritch_cannon", "Artificer", "Eldritch Cannon", "Cannone arcano", "Eldritch Cannon", "action", "context"],
 ["command_cannon", "Artificer", "Eldritch Cannon", "Attiva cannone arcano", "", "bonus", "context"],
 ["command_defender", "Artificer", "Steel Defender", "Comanda difensore d'acciaio", "", "bonus", "context"],
 ["arcane_jolt", "Artificer", "Arcane Jolt", "Scossa arcana", "Arcane Jolt", "free", "context"],
 ["restorative_reagents", "Artificer", "Restorative Reagents", "Reagenti ristoratori · ristorare inferiore", "Restorative Reagents", "action", "context"],
 ["chemical_mastery_heal", "Artificer", "Chemical Mastery", "Maestria chimica · guarigione", "Chemical Mastery (Heal)", "action", "context"],
 ["chemical_mastery_restore", "Artificer", "Chemical Mastery", "Maestria chimica · ristorare superiore", "Chemical Mastery (Greater Restoration)", "action", "context"],
 ["perfected_guardian", "Artificer", "Guardian", "Armatura perfezionata · guardiano", "Perfected Armor", "reaction", "context"],
 ["spell_storing_item", "Artificer", "Spell-Storing Item", "Oggetto accumula incantesimi", "", "action", "context"],
 ["soul_of_artifice", "Artificer", "Soul of Artifice", "Anima dell'artefice", "", "reaction", "context"],
 ['rage','Barbarian','Rage','Ira','Rages','bonus','toggle'],
 ['reckless_attack','Barbarian','Reckless Attack','Attacco irruento','','free','toggle'],
 ['second_wind','Fighter','Second Wind','Recuperare energie','Second Wind','bonus','heal_roll'],
 ['action_surge','Fighter','Action Surge',"Impeto d'azione",'Action Surge','free','context'],
 ['lay_on_hands','Paladin','Lay on Hands','Imposizione delle mani','Lay on Hands','action','heal_pool'],
 ['divine_sense','Paladin','Divine Sense','Percezione del divino','Divine Sense','action','context'],
 ['turn_undead','Cleric','Turn Undead','Scacciare non morti','Channel Divinity','action','context'],
 ['channel_divinity','Paladin','Channel Divinity','Incanalare divinità','Channel Divinity','action','context'],
 ['font_of_magic','Sorcerer','Font of Magic','Fonte di magia','Sorcery Points','bonus','conversion'],
 ['innate_sorcery','Sorcerer','Innate Sorcery','Stregoneria innata','Innate Sorcery','bonus','toggle'],
 ['arcane_recovery','Wizard','Arcane Recovery','Recupero arcano','Arcane Recovery','free','recovery'],
 ['flurry_of_blows','Monk','Ki','Raffica di colpi','Ki Points','bonus','context'],
 ['patient_defense','Monk','Ki','Difesa paziente','Ki Points','bonus','toggle'],
 ['step_of_the_wind','Monk','Ki','Passo del vento','Ki Points','bonus','toggle'],
 ['stunning_strike','Monk','Stunning Strike','Colpo stordente','Ki Points','free','context'],
 ['uncanny_dodge','Rogue','Uncanny Dodge','Schivata prodigiosa','','reaction','context'],
 ['deflect_missiles','Monk','Deflect Missiles','Deviare proiettili','','reaction','context'],
 ['deflect_attacks','Monk','Deflect Attacks','Deviare attacchi','','reaction','context']
];
const METAMAGIC_COSTS={'Careful Spell':1,'Distant Spell':1,'Empowered Spell':1,'Extended Spell':1,
 'Heightened Spell':3,'Quickened Spell':2,'Subtle Spell':1,'Twinned Spell':1,'Seeking Spell':2,'Transmuted Spell':1};
export function metamagicOptions(record){
 return rows(record.optional_features_catalog).filter(f=>f&&!f.disabled&&Object.hasOwn(METAMAGIC_COSTS,f.name)&&
  !disabledOrigin(record,f.origin_id)).map(f=>({...f,
   cost:record.rules_version==='2024'&&f.name==='Heightened Spell'?2:record.rules_version==='2024'&&f.name==='Seeking Spell'?1:METAMAGIC_COSTS[f.name],
   origin_id:f.origin_id||'optional-feature:'+low(f.source)+'|'+low(f.name)}));
}
const disabledOrigin=(record,id)=>record.origin_enabled?.[id]===false||
 rows(record.proficiency_origins).some(o=>o?.id===id&&o.disabled);
export function featureEnabled(record,feature){
 const parent=String(feature?.origin_key||'');
 const base=parent.startsWith('class|')?parent.split('|').slice(0,3).join('|'):parent;
 return !!feature&&!feature.inactive&&!feature.disabled&&
  ![feature.origin_id,parent,base].some(id=>id&&disabledOrigin(record,id));
}
export function classFeatureEntries(record={},calculated={}){
 const revised=record.rules_version==='2024',output=[];
 for(const [key,owner,sourceName,label,baseResource,baseTime,mode] of CLASS_FEATURE_RULES){
  const parent=revised&&sourceName==='Ki'?'Monk’s Focus':sourceName;
  const feature=rows(calculated.features).find(f=>featureEnabled(record,f)&&
   low(f.name).replaceAll("'",'’')===low(parent)&&String(f.origin_key||'').startsWith('class|')&&
   low(f.requirements?.class_name||f.class_name||String(f.origin_key).split('|')[2])===low(owner));
  if(!feature)continue;
  if(owner==='Artificer'&&low(feature.class_source||String(feature.origin_key).split('|')[1])!=='tce')continue;
  if(key==='defensive_field'&&(!rows(record.inventory).map(resolveOwnedItem).some(i=>Number(i.quantity??1)>0&&rows(i.equipped_slots).includes('body')&&['LA','MA','HA'].includes(String(i.type).split('|')[0]))||(record.artificer_armor_model||'guardian')!=='guardian'))continue;
  let resource=revised&&baseResource==='Ki Points'?'Focus Points':baseResource;
  if(revised&&key==='divine_sense')resource='Channel Divinity';
  const tracker=rows(calculated.trackers).find(t=>!t.disabled&&low(t.name)===low(resource)&&
   (!t.origin_class||low(t.origin_class)===low(owner)));
  output.push({id:'class_feature:'+key,class_feature_id:key,name:label,
   time:revised&&key==='lay_on_hands'?'bonus':baseTime,type:'Capacità',
   mode,description:feature.entries??feature.description??'',class_name:owner,
   resource_name:resource,tracker:tracker?.name||resource,tracker_id:tracker?.id||'',
   cost:revised&&['patient_defense','step_of_the_wind'].includes(key)?0:resource?1:0,
   origin:'personal',origin_id:feature.origin_id,feature_id:feature.origin_id,
   feature_name:feature.name,origin_name:'Tratto · '+feature.name,
   active:mode==='toggle'&&!!record.active_class_features?.[key]});
 }
 for(const option of metamagicOptions(record)){
  const tracker=rows(calculated.trackers).find(t=>!t.disabled&&low(t.name)==='sorcery points'&&low(t.origin_class)==='sorcerer');
  output.push({id:'metamagic:'+option.name,class_feature_id:'metamagic:'+option.name,name:option.name,
   time:'free',type:'Capacità',mode:['Empowered Spell','Seeking Spell'].includes(option.name)?'metamagic_roll':'metamagic',
   description:option.entries??option.description??'',class_name:'Sorcerer',resource_name:'Sorcery Points',
   tracker:tracker?.name||'Sorcery Points',tracker_id:tracker?.id||'',cost:option.cost,origin:'personal',
   origin_id:option.origin_id,feature_id:option.origin_id,feature_name:option.name});
 }
 return output;
}
export function classFeatureLevel(record,name){
 const member=rows(record.classes).find(c=>low(c.name)===low(name));
 return Math.max(0,Number(member?.level??(low(record.class)===low(name)?record.level:0))||0);
}
export function classFeatureActive(record,calculated,key){
 if(!record.active_class_features?.[key]||!classFeatureEntries(record,calculated).some(a=>a.class_feature_id===key))return false;
 if(key==='rage'&&(rows(record.inventory).map(resolveOwnedItem).some(i=>Number(i.quantity??1)>0&&
  rows(i.equipped_slots).includes('body')&&String(i.type||'').split('|')[0]==='HA')||
  rows(record.conditions).includes('unconscious')||record.rules_version==='2024'&&rows(record.conditions).includes('incapacitated')))return false;
 return true;
}
export function classFeatureDamage(record,calculated,attack,ability){
 const ranged=attack.thrown||attack.weapon_kind==='R'||attack.melee===false;
 if(ability!=='str'||!classFeatureActive(record,calculated,'rage')||record.rules_version!=='2024'&&ranged)return 0;
 const level=classFeatureLevel(record,'Barbarian');
 return level>=16?4:level>=9?3:2;
}
export function classFeatureRollAdvantage(record,calculated,target){
 if(target==='save:dex'&&classFeatureActive(record,calculated,'patient_defense')&&
  !rows(record.conditions).includes('incapacitated')&&(record.rules_version!=='2024'||record.active_class_features.patient_defense.enhanced))return true;
 if(classFeatureActive(record,calculated,'rage')&&['ability_mod:str','save:str','skill:athletics'].includes(target))return true;
 if(target.startsWith('attack_hit:')){
  const attack=rows(calculated.attacks).find(a=>'attack_hit:'+a.id===target);
  return !!attack&&attack.ability==='str'&&classFeatureActive(record,calculated,'reckless_attack')&&
   (record.rules_version==='2024'||!attack.thrown&&attack.weapon_kind!=='R'&&attack.melee!==false);
 }
 if(target.startsWith('casting_hit:')&&classFeatureActive(record,calculated,'innate_sorcery')){
  const sources=rows(calculated.casting_classes).filter(c=>c.ability===target.slice('casting_hit:'.length));
  return sources.length===1&&low(sources[0].name)==='sorcerer';
 }
 return false;
}
export function classFeatureEffects(record,calculated){
 return Object.entries(record.active_class_features||{}).map(([key,state])=>{
  const action=classFeatureEntries(record,calculated).find(a=>a.class_feature_id===key);
  const effective=classFeatureActive(record,calculated,key);
  const summaries={rage:'Danni con attacchi di Forza validi +'+classFeatureDamage(record,calculated,{},'str')+
   '; vantaggio a prove e TS di Forza; resistenza a contundenti, perforanti e taglienti; lancio incantesimi bloccato.',
   reckless_attack:'Vantaggio agli attacchi di Forza previsti dal privilegio.',
   patient_defense:record.rules_version==='2024'&&!state.enhanced?'Disimpegno gratuito.':'Schivata e vantaggio ai TS di Destrezza quando previsto.',
   step_of_the_wind:'Passo del vento'+(state.enhanced?' potenziato':'')+'; usa il movimento e le condizioni descritti dal tratto.',
   innate_sorcery:'Incantesimi da Stregone: CD +1 e vantaggio agli attacchi magici.'};
  return {key,name:action?.name||state?.name||key,origin_id:action?.origin_id||state?.origin_id||'',
   effective,summary:summaries[key]||'',enhanced:!!state?.enhanced};
 });
}
// Produce one atomic patch. Invalid/stale actions never spend a use.
export function classFeatureActivationPatch(record,calculated,id,options={}){
 const action=classFeatureEntries(record,calculated).find(a=>a.id===id||a.class_feature_id===id);
 if(!action)throw Error('Privilegio non disponibile.');
 if(action.mode==='metamagic')throw Error('Scegli la Metamagia nella finestra di lancio.');
 const key=action.class_feature_id,active={...(record.active_class_features||{})};
 if(action.mode==='armor_model')return {artificer_armor_model:key==='armor_guardian'?'guardian':'infiltrator'};
 if(action.mode==='toggle'&&active[key]){delete active[key];return {active_class_features:active};}
 if(key==='rage'&&!classFeatureActive({...record,active_class_features:{...active,rage:{}}},calculated,key))
  throw Error('Ira non disponibile con armatura pesante o incapacità.');
 const tracker=rows(calculated.trackers).find(t=>t.id===action.tracker_id&&!t.disabled);
 const spent={...(record.resource_tracker_spent||{})};
 const remaining=tracker?Math.max(0,tracker.max-Number(spent[tracker.id]||0)):0;
 let cost=action.cost,patch={};
 const integer=(value)=>Number.isSafeInteger(Number(value))?Number(value):NaN;
 if(action.mode==='metamagic_roll'){
  const count=action.name==='Seeking Spell'?1:integer(options.count);
  const sides=action.name==='Seeking Spell'?20:integer(options.sides);
  if(!(count>=1&&count<=Math.max(1,Number(calculated.values['ability_mod:cha'])||0))||![4,6,8,10,12,20,100].includes(sides))
   throw Error('Seleziona i dadi da sostituire entro il modificatore di Carisma.');
 }else if(action.mode==='heal_pool'){
  cost=integer(options.amount??1);if(!(cost>=1))throw Error('Quantità di cura non valida.');
  if(options.apply_to_self!==false)patch.current_hp=Math.min(calculated.values.hp,Number(record.current_hp||0)+cost);
 }else if(action.mode==='temporary_hp'){
  patch.temporary_hp=Math.max(Number(record.temporary_hp)||0,classFeatureLevel(record,'Artificer'));
 }else if(action.mode==='heal_roll'){
  const roll=integer(options.roll);if(!(roll>=1&&roll<=10))throw Error('Tiro d10 non valido.');
  patch.current_hp=Math.min(calculated.values.hp,Number(record.current_hp||0)+roll+classFeatureLevel(record,'Fighter'));
 }else if(action.mode==='conversion'){
  const level=integer(options.level);if(!(level>=1&&level<=5))throw Error('Livello slot non valido.');
  if(!tracker)throw Error('Punti stregoneria non disponibili.');
  if(options.create_slot!==false){
   if(record.rules_version==='2024'&&classFeatureLevel(record,'Sorcerer')<level*2-1)throw Error('Livello da Stregone insufficiente.');
   cost=[0,2,3,5,6,7][level];
   const created=Array.from({length:10},(_,i)=>Number(record.created_spell_slots?.[i]||0));
   created[level]++;patch.created_spell_slots=created;
  }else{
   const total=Number(calculated.spell_slots?.find(s=>s.level===level)?.total||0);
   const slots=Array.from({length:10},(_,i)=>Number(record.spell_slots_spent?.[i]||0));
   if(slots[level]>=total)throw Error('Slot non disponibile.');
   if(Number(spent[tracker.id]||0)<level)throw Error('I punti recuperati supererebbero il massimo.');
   spent[tracker.id]=Number(spent[tracker.id]||0)-level;slots[level]++;
   return {resource_tracker_spent:spent,spell_slots_spent:slots};
  }
 }else if(action.mode==='recovery'){
  const levels=rows(options.levels);if(levels.length!==5)throw Error('Scegli gli slot da recuperare.');
  const slots=Array.from({length:10},(_,i)=>Number(record.spell_slots_spent?.[i]||0));
  let total=0;
  for(let level=1;level<=5;level++){
   const count=integer(levels[level-1]);if(!(count>=0&&count<=slots[level]))throw Error('Slot da recuperare non validi.');
   total+=level*count;slots[level]-=count;
  }
  if(!total||total>Math.ceil(classFeatureLevel(record,'Wizard')/2))throw Error('Troppi livelli di slot da recuperare.');
  patch.spell_slots_spent=slots;
 }
 if(record.rules_version==='2024'&&['patient_defense','step_of_the_wind'].includes(key))cost=options.enhanced?1:0;
 if(action.resource_name&&cost>0){
  if(!tracker||remaining<cost)throw Error('Risorsa insufficiente.');
  spent[tracker.id]=Number(spent[tracker.id]||0)+cost;patch.resource_tracker_spent=spent;
 }
 if(!['temporary_hp','heal_pool','heal_roll','conversion','recovery','metamagic_roll'].includes(action.mode)){
  active[key]={name:action.name,origin_id:action.origin_id,rules_version:record.rules_version||'2014',enhanced:!!options.enhanced};
  patch.active_class_features=active;
 }
 if(key==='rage'){patch.conditions=rows(record.conditions).filter(c=>c!=='concentrating');patch.concentrating_spell_id='';}
 return patch;
}
// Same per-cast validations and changes as vtt/spell_metamagic.gd.
export function metamagicPlan(record,spell,slotLevel,calculated){
 const selection=spell.metamagic||{},names=rows(selection.names),known=metamagicOptions(record);
 if(names.length>1||new Set(names).size!==names.length)throw Error('Non puoi combinare queste opzioni di Metamagia.');
 const modified=structuredClone(spell),elements=['acid','cold','fire','lightning','poison','thunder'];
 let cost=0;
 const revised=record.rules_version==='2024';
 for(const name of names){
  const option=known.find(o=>o.name===name);
  if(!option)throw Error('Opzione di Metamagia non disponibile.');
  if(['Empowered Spell','Seeking Spell'].includes(name))throw Error('Questa Metamagia si usa dopo il tiro: apri il privilegio nelle Risorse.');
  cost+=name==='Twinned Spell'&&!revised?Math.max(1,slotLevel):option.cost;
  if(name==='Distant Spell'){
   const range=typeof spell.range==='object'?spell.range?.distance?.type:spell.range;
   let feet=Number(spell.range_feet??spell.range?.distance?.amount??0);
   if(low(range).includes('touch'))feet=30;else if(feet>=5)feet*=2;else throw Error('Incantesimo Distante richiede gittata o contatto.');
   modified.range_feet=Math.min(100000,feet);modified.range=modified.range_feet+' feet';
  }else if(name==='Quickened Spell'){
   const raw=Array.isArray(spell.time)?spell.time[0]:spell.casting_time??spell.time;
   const time=typeof raw==='object'?raw?.unit:raw;
   if(!['action','1 action','1 azione'].includes(low(time)))throw Error('Incantesimo Rapido richiede tempo di lancio di un’azione.');
   modified.casting_time='Bonus Action';modified.time='bonus';
  }else if(name==='Subtle Spell'){
   const raw=spell.components;
   const material=typeof raw==='object'?(typeof raw.m==='object'?raw.m.text:String(raw.m||'')):
    String(raw||'').includes('M')?String(raw).slice(String(raw).indexOf('M')):'';
   const costly=typeof raw?.m==='object'&&(raw.m.cost||raw.m.consume)||/gp|consum/i.test(material);
   modified.components=revised&&!costly?'':material;
  }else if(name==='Extended Spell'){
   const seconds=durationSeconds(spell.duration);
   if(seconds<60)throw Error('Incantesimo Esteso richiede durata di almeno un minuto.');
   modified.requires_concentration=spell.requires_concentration||rows(spell.duration).some(d=>d?.concentration)||/concentration/i.test(String(spell.duration));
   modified.duration=Math.min(86400,seconds*2)+' seconds';modified.metamagic_duration_seconds=Math.min(86400,seconds*2);
  }else if(name==='Twinned Spell'){
   if(!selection.eligible_targeting)throw Error('Conferma i requisiti di bersaglio per questa edizione.');
   if(revised){
    if(slotLevel<1||slotLevel>=9)throw Error('Incantesimo Raddoppiato richiede uno slot inferiore al 9°.');
    modified.metamagic_effective_level=slotLevel+1;
    modified.base_target_clicks=Number(spell.base_target_clicks||1)+Math.max(1,Number(spell.target_clicks_per_slot_above_base||1));
   }else{
    const range=Number(spell.range_feet??spell.range?.distance?.amount??0);
    if(spell.aoe_shape||spell.range?.type==='cone'||spell.range?.type==='radius'||range<=0)throw Error('Un incantesimo ad area o Personale non può essere raddoppiato.');
    modified.base_target_clicks=2;modified.target_clicks_per_slot_above_base=0;
   }
   modified.target_mode='token_then_multi_token';modified.allow_repeat_targets=false;
  }else if(name==='Transmuted Spell'){
   if(!selection.eligible_damage||!elements.includes(selection.damage_type))throw Error('Conferma il danno elementale e scegli il nuovo tipo.');
   modified.metamagic_damage_type=selection.damage_type;modified.damage_type=selection.damage_type;
  }else if(name==='Careful Spell')modified.metamagic_careful=true;
  else if(name==='Heightened Spell')modified.metamagic_save_disadvantage=true;
 }
 const tracker=rows(calculated.trackers).find(t=>!t.disabled&&low(t.name)==='sorcery points'&&low(t.origin_class)==='sorcerer');
 if(cost&&(!tracker||tracker.max-Number(record.resource_tracker_spent?.[tracker.id]||0)<cost))throw Error('Punti stregoneria insufficienti.');
 return {spell:modified,cost,tracker,selection};
}
function durationSeconds(raw){
 if(Array.isArray(raw))return raw.map(durationSeconds).find(n=>n>0)||0;
 if(raw&&typeof raw==='object'){const d=raw.duration||raw;return Number(d.amount||0)*({round:6,minute:60,hour:3600,day:86400}[d.type]||0);}
 const found=/(\d+) (round|minute|hour|day|second)/i.exec(String(raw));
 return found?Number(found[1])*({round:6,minute:60,hour:3600,day:86400,second:1}[low(found[2])]||0):0;
}
export function wildShapePatch(record,calculated,profile,maximum=0){
 const feature=rows(calculated.features).find(f=>low(f.name)==='wild shape'&&featureEnabled(record,f)&&
  String(f.origin_key||'').startsWith('class|')&&String(f.origin_key).split('|')[2]==='druid');
 if(!feature||record.active_class_features?.wild_shape)throw Error('Forma selvatica non disponibile o già attiva.');
 const tracker=rows(calculated.trackers).find(t=>!t.disabled&&low(t.name)==='wild shape'&&low(t.origin_class)==='druid');
 if(!tracker||tracker.max-Number(record.resource_tracker_spent?.[tracker.id]||0)<1)throw Error('Utilizzi di Forma selvatica esauriti.');
 const original=record.current_miniature_id||record.default_miniature_id;
 if(!original)throw Error('Scegli prima la miniatura di base della creatura.');
 if(!profile?.id||!Number.isSafeInteger(Number(maximum))||Number(maximum)<0||Number(maximum)>99999)throw Error('Forma o punti ferita non validi.');
 return {current_miniature_id:profile.id,second_form_hp:Number(maximum),second_form_max_hp:Number(maximum),
  resource_tracker_spent:{...(record.resource_tracker_spent||{}),[tracker.id]:Number(record.resource_tracker_spent?.[tracker.id]||0)+1},
  active_class_features:{...(record.active_class_features||{}),wild_shape:{name:'Forma selvatica',origin_id:feature.origin_id,
   previous_miniature_id:original,rules_version:record.rules_version||'2014'}}};
}
export function endWildShapePatch(record){
 const active={...(record.active_class_features||{})},form=active.wild_shape;
 if(!form)throw Error('Forma selvatica non attiva.');
 const original=form.previous_miniature_id||record.default_miniature_id;
 if(!original)throw Error('Aspetto originale non disponibile.');
 delete active.wild_shape;
 return {current_miniature_id:original,second_form_hp:0,second_form_max_hp:0,active_class_features:active};
}
export function featureMember(record,rule){
 const edition=record?.rules_version==='2024'?'XPHB':'PHB';
 const classes=rows(record?.classes).length?record.classes:
  record?.class?[{name:record.class,source:record.class_source,level:record.level,subclass:record.subclass}]:[];
 return classes.find(c=>{
  const source=String(c.source||edition).toUpperCase();
  // The legacy top-level subclass belongs only to the primary class. Never
  // borrow it for another class when a multiclass entry has no subclass.
  const primary=low(c.name)===low(record.class)&&
    source===String(record.class_source||edition).toUpperCase();
  const selectedSubclass=c.subclass||(primary?record.subclass:'');
  return low(c.name)===low(rule.class_name)&&
    source===String(rule.class_source||'').toUpperCase()&&
    Number(c.level||0)>=Number(rule.min_level||1)&&
    (!rule.subclass||subclass(selectedSubclass)===subclass(rule.subclass));
 })||null;
}
function trackerFor(member,rule,trackers){
 const prefix='class:'+low(rule.class_name)+':'+low(rule.class_source)+':';
 return rows(trackers).find(t=>String(t.id||'').startsWith(prefix)&&
   low(t.name)===low(rule.resource_name||rule.tracker_name))||null;
}
// Respect native feature origin switches before selecting action overrides.
// In particular, disabling Combat Wild Shape must restore the base Wild Shape
// timing, not leave the subclass bonus action enabled.
export function featureActionEntries(record,trackers,catalog={},features=[]){
 const selected=new Map();
 const disabled=id=>record?.origin_enabled?.[id]===false||
   rows(record?.proficiency_origins).some(o=>o?.id===id&&o.disabled);
 for(const rule of rows(catalog.actions)){
  if(!rule.action_id)continue;
  const member=featureMember(record,rule);
  if(!member)continue;
  const classOrigin='class|'+low(rule.class_source||member.source)+'|'+low(rule.class_name);
  if(disabled(classOrigin))continue;
  const matches=rows(features).filter(f=>low(f.name)===low(rule.feature)&&
    (String(f.origin_key||'')===classOrigin||String(f.origin_key||'').startsWith(classOrigin+'|')));
  if(!matches.some(f=>!f.disabled&&!f.inactive&&!disabled(f.origin_id)&&!disabled(f.origin_key)))continue;
  if(rule.subclass){
   const subclassOrigins=rows(features).filter(f=>String(f.origin_key||'').startsWith(classOrigin+'|subclass|')&&
    low(f.name)===low(rule.feature));
   if(subclassOrigins.length&&!subclassOrigins.some(f=>!f.disabled))continue;
   const selectedSubclass=member.subclass||(low(member.name)===low(record?.class)?record.subclass:'');
   const subSource=member.subclass_source||'';
   const specific='|subclass|'+low(selectedSubclass)+'|'+low(subSource);
   if(disabled(classOrigin+specific))continue;
  }
  const old=selected.get(rule.action_id);
  if(!old||Number(rule.priority||0)>Number(old.priority||0))selected.set(rule.action_id,rule);
 }
 return [...selected.values()].map(rule=>{
  const tracker=trackerFor(featureMember(record,rule),rule,trackers);
  const source='class|'+low(rule.class_source)+'|'+low(rule.class_name);
  const feature=rows(features).find(f=>low(f.name)===low(rule.feature)&&
    (String(f.origin_key||'')===source||String(f.origin_key||'').startsWith(source+'|'))&&!f.disabled);
  return {name:rule.name,time:rule.activation,type:'Capacità',description:rule.detail||'',
   tracker:tracker?.name||rule.tracker_name||'',tracker_id:tracker?.id||'',
   cost:tracker?1:0,origin:'personal',origin_id:feature?.origin_id||source,
   action_id:'',rule_action_id:rule.action_id,rule_id:rule.id,feature:rule.feature};
 });
}
export function modifyFeatureTrackers(record,trackers,catalog={}){
 for(const rule of rows(catalog.recoveries)){
  const member=featureMember(record,rule);if(!member)continue;
  const row=trackerFor(member,rule,trackers);if(!row)continue;
  if(rule.mode==='full'){
   if(rule.event==='short_rest'||row.recharge!=='short_rest')row.recharge=rule.event;
  }else if(['partial','optional_partial'].includes(rule.mode)){
   row.partial_recoveries??=[];
   if(!row.partial_recoveries.some(r=>r.id===rule.id))row.partial_recoveries.push(rule);
  }
 }
 return trackers;
}
export function optionalRecoveryPatch(record,ruleId,trackers){
 if(!record?.resource_recovery_ready?.[ruleId]||record?.resource_recovery_used?.[ruleId])return null;
 for(const row of rows(trackers))for(const rule of rows(row.partial_recoveries)){
  if(rule.id!==ruleId||rule.mode!=='optional_partial')continue;
  const member=featureMember(record,rule);if(!member)continue;
  const amount=rule.formula==='half_class_level_floor'?Math.floor(Number(member.level||0)/2):Math.max(0,Number(rule.amount)||0);
  const spent={...(record.resource_tracker_spent||{})};
  spent[row.id]=Math.max(0,Number(spent[row.id]||0)-amount);
  if(!spent[row.id])delete spent[row.id];
  const ready={...record.resource_recovery_ready};delete ready[ruleId];
  return {resource_tracker_spent:spent,resource_recovery_ready:ready,
   resource_recovery_used:{...record.resource_recovery_used,[ruleId]:true}};
 }
 return null;
}

// Curated TCE consumables; the two browser projections share these definitions.
export function artificerResources(level,intelligence,proficiency,selectedSubclass){
 const extra=[['Flash of Genius',7,Math.max(1,intelligence),''],['Defensive Field',3,proficiency,'Armorer'],
  ['Experimental Elixir',3,level>=15?3:level>=6?2:1,'Alchemist'],
  ['Restorative Reagents',9,Math.max(1,intelligence),'Alchemist'],
  ['Chemical Mastery (Heal)',15,1,'Alchemist','Chemical Mastery'],
  ['Chemical Mastery (Greater Restoration)',15,1,'Alchemist','Chemical Mastery'],
  ['Eldritch Cannon',3,1,'Artillerist'],['Arcane Jolt',9,Math.max(1,intelligence),'Battle Smith'],
  ['Perfected Armor',15,proficiency,'Armorer','Guardian']];
 return extra.filter(([,gate,,sub])=>level>=gate&&(!sub||low(sub)===low(selectedSubclass)))
  .map(([name,,max,sub,origin])=>({name,max,subclass:sub,origin:origin||name}));
}

export function armorerWeapons(record,features=[]){
 if(!rows(record.inventory).map(resolveOwnedItem).some(i=>Number(i.quantity??1)>0&&rows(i.equipped_slots).includes('body')&&['LA','MA','HA'].includes(String(i.type).split('|')[0])))return [];
 const guardian=(record.artificer_armor_model||'guardian')==='guardian';
 const name=guardian?'Thunder Gauntlets':'Lightning Launcher';
 const trait=features.find(f=>f.name===name&&featureEnabled(record,f)&&low(f.class_name||f.requirements?.class_name)==='artificer'&&low(f.class_source||String(f.origin_key).split('|')[1])==='tce');
 if(!trait)return [];
 return [{id:'class_feature:'+(guardian?'thunder_gauntlets':'lightning_launcher'),name,
  origin_id:trait.origin_id,source:'class_feature',proficient:true,melee:guardian,
  damage:guardian?'1d8':'1d6',damage_type:guardian?'T':'L',
  ability:record.attack_ability==='int'?'int':guardian?'str':'dex',range_feet:guardian?5:90,long_range_feet:guardian?0:300}];
}
