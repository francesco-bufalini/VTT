// Action availability is projected from the same local creature and calculated
// resources as the battle/magic sheets. No server or prose-regex rule inference.
import {SKILLS} from './sheet_rules.js';
import {featureActionEntries,classFeatureEntries} from './feature_mechanics.js';
import {attackCountBenefits,attacksPerActionFromBenefits} from './attack_count_benefits.js';
import {offhandActionEligibility} from './offhand_rules.js';
import {equipmentRequirementMatches} from './item_controls.js';
import {render5etoolsInline} from './5etools_inline.js';
import {monsterActions,monsterBasicRules,monsterTraits,monsterActionOptions as projectedMonsterActionOptions} from './monster_traits.js';
export {offhandActionEligibility};

let supplementsCache=null;
let generalActionsCache=null;
let variantsCache=[];
export const actionVariants=()=>variantsCache;
export async function loadGeneralActionSupplements(){
 if(generalActionsCache)return generalActionsCache;
 const response=await fetch('/catalog/combat_actions_5etools.json',{cache:'no-store'});
 if(!response.ok)throw Error('Catalogo azioni 5etools non disponibile');
 const payload=await response.json();
 if(payload?.version!==1||!Array.isArray(payload.actions))throw Error('Catalogo azioni 5etools non valido');
 // Extra actions also exist in the native supplement catalog. The canonical
 // catalog owns variant gating, so never duplicate or auto-enable its rules.
 const known=new Set(payload.actions.map(row=>String(row.edition)+'|'+String(row.id)));
 let extras=[];
 try{
  const response=await fetch('/catalog/combat_action_supplements_5etools.json',{cache:'no-store'});
  if(response.ok){
   const extra=await response.json();
   if(extra?.version===1&&Array.isArray(extra.entries))
    extras=extra.entries.filter(row=>!row.optional&&!known.has(String(row.edition)+'|'+String(row.id)));
  }
 }catch{ /* Core actions and the variant picker remain usable offline. */ }
 generalActionsCache=[...payload.actions,...extras];
 variantsCache=Array.isArray(payload.variants)?payload.variants:[];
 return generalActionsCache;
}
export async function loadFeatureActionOverrides(){
 if(supplementsCache)return supplementsCache;
 const response=await fetch('/catalog/action_feature_overrides.json',{cache:'no-store'});
 if(!response.ok)throw Error('Catalogo azioni di classe non disponibile');
 const payload=await response.json();
 if(payload?.version!==1||!Array.isArray(payload.entries))throw Error('Catalogo azioni di classe non valido');
 supplementsCache=payload.entries;
 return supplementsCache;
}

/* The actual 98 SVG icons generated for VTT. Manifest.json is canonical
   and the four matching SVG sprites are shared with the Godot client. */
const GOLD_ICON_GROUPS=[["action","bonus","free","movement","reaction","sword","help","shove","prone","stealth","eye","object","speech","target","shield","book","spark","flag","skill","hand","acrobatics","animal_handling","arcana","armor","athletics"],["attack_bonus","bardic_inspiration","break_concentration","buff","check","coins","concentration","condition","cross","dash","debuff","deception","decrease","details","disengage","dodge","filter","fire","flight","grapple","healing","help_alt","hide","history","ice"],["increase","information","infusion","insight","interact","intimidation","inventory","investigation","invisibility","key","lightning","lock","magic_item","maneuver","map","mark_enemy","medicine","misty_step","nature","necromancy","opportunity_attack","perception","persuasion","poison","potion"],["proficiency","prone_alt","reaction_trigger","ready","religion","reset","rest_long","rest_short","save_throw","scroll","search","settings","sleight_of_hand","speed","spell_cast","spell_slot","stealth_check","summon","survival","talk","teleport","weapon","wild_shape"]];
const GOLD_ICON_INDEX=new Map(GOLD_ICON_GROUPS.flatMap((keys,group)=>
 keys.map((key,index)=>[key,{group,index,count:keys.length}])));
const HEADER_GLYPHS={action:"weapon",bonus:"flight",free:"sleight_of_hand",movement:"dash",reaction:"reaction_trigger"};
export function actionGlyph(key){
 const {group,index}=GOLD_ICON_INDEX.get(key)||GOLD_ICON_INDEX.get("weapon");
 return '<span class="vtt-action-glyph vtt-action-glyph--pack-'+group+
   ' vtt-action-glyph--slot-'+index+'" aria-hidden="true"></span>';
}
export function actionGlyphKey(item){
 const name=String(item.name||'').toLocaleLowerCase('it');
 const type=String(item.type||'');
 const actionId=String(item.action_id||'');
 if(actionId==='grapple'||name.includes('afferrar')||name.includes('grapple'))return 'grapple';
 if(actionId==='prone'||name.includes('prono')||name.includes('atterrar'))return 'prone_alt';
 if(actionId==='shove'||name.includes('spinger'))return 'shove';
 if(actionId==='help'||name.includes('aiutar'))return 'help_alt';
 if(name.includes('forma selvatica')||name.includes('wild shape'))return 'wild_shape';
 if(name.includes('ispirazione bardica')||name.includes('bardic inspiration'))return 'bardic_inspiration';
 if(name==='ira'||name.includes('rage')||name.includes('furia'))return 'fire';
 if(name.includes('nebbios')||name.includes('teletrasport'))return 'misty_step';
 if(name.includes('interrompere concentrazione'))return 'break_concentration';
 if(name.includes('concentrazione'))return 'concentration';
 if(name.includes('riposo'))return 'rest_short';
 if(name.includes('guarig')||name.includes('curar')||name.includes('energia'))return 'healing';
 if(name.includes('incantesim')||name==='magia'||type==='Incantesimo')return 'spell_cast';
 if(name.includes('rapidità di mano'))return 'sleight_of_hand';
 if(name.includes('furtiv')||name.includes('nascond'))return 'stealth_check';
 if(name.includes('opportunit'))return 'opportunity_attack';
 if(name.includes('disarm'))return 'maneuver';
 if(name.includes('due armi')||name.includes('attacc')||name.includes('pugnale')||
    name.includes('spada')||name.includes('sword')||name.includes('arco')||name.includes('bow'))return 'weapon';
 if(name.includes('oggetto')||name.includes('utilizz'))return 'interact';
 if(name.includes('scudo'))return 'armor';
 if(name.includes('pozion'))return 'potion';
 if(name.includes('parlare')||name.includes('comunicar'))return 'talk';
 if(name.includes('influenz'))return 'persuasion';
 if(name.includes('schivar'))return 'dodge';
 if(name.includes('disimpegn'))return 'disengage';
 if(name.includes('cercar')||name.includes('indagar'))return 'search';
 if(name.includes('studiar')||name.includes('arcano'))return 'arcana';
 if(name.includes('marcare'))return 'mark_enemy';
 if(name.includes('preparar'))return 'ready';
 if(name.includes('scatt')||name.includes('muov')||item.time==='movement')return 'dash';
 return ({Attacco:'weapon',Incantesimo:'spell_cast',Capacità:'proficiency'})[type]||'action';
}
function skillGlyphKey(skill){
 return ({
  'stealth':'stealth_check','sleight of hand':'sleight_of_hand',
  insight:'insight',perception:'perception',investigation:'investigation',
  athletics:'athletics',acrobatics:'acrobatics',arcana:'arcana',
  'animal handling':'animal_handling',medicine:'medicine',survival:'survival',
  nature:'nature',persuasion:'persuasion',deception:'deception',
  intimidation:'intimidation',religion:'religion',history:'history'
 })[skill]||'skill';
}

const arr=value=>Array.isArray(value)?value:[];
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','\'':'&#39;'}[c]));
const details=value=>typeof value==='string'?value:Array.isArray(value)?value.map(details).filter(Boolean).join('\n'):value&&typeof value==='object'?details(value.entries??value.entry??value.text??value.description??''):'';
// 5eTools models mutually exclusive choices as named list items within one
// rechargeable action. The action, not its individual options, owns the resource.
export function monsterActionOptions(feature={}){
 return projectedMonsterActionOptions(feature);
}
const specified=v=>v!==null&&v!==undefined&&(typeof v!=='string'||v.trim()!=='')&&(!Array.isArray(v)||v.length>0);
function timing(value){
 if(Array.isArray(value))return value.some(v=>timing(v)==='bonus')?'bonus':timing(value[0]);
 if(value&&typeof value==='object')return timing(value.unit??value.type??value.action_type??value.activation_type??value.time);
 const s=String(value||'').toLowerCase();
 if(['legendary','legendary_resistance','lair'].includes(s))return s;
 if(s.includes('reaction')||s.includes('reazione'))return 'reaction';
 if(s.includes('bonus'))return 'bonus';
 if(s.includes('free')||s.includes('gratuit')||s.includes('interact'))return 'free';
 if(s.includes('move')||s.includes('movimento'))return 'movement';
 return 'action';
}
function castingTime(spell){
 const time=arr(spell.time)[0]??spell.casting_time??spell.time??'action';
 const value=typeof time==='object'?String(time.number||1)+' '+String(time.unit||'azione'):String(time);
 return value;
}
// The attack-action multiplier is shared by the legacy action list and the
// mobile battle heading, so the same active traits control both views.
export function attacksPerAction(record={},calculated={}){
 const benefits=Array.isArray(calculated.attack_count_benefits)?
   calculated.attack_count_benefits:attackCountBenefits(record,calculated.features);
 return attacksPerActionFromBenefits(benefits);
}
export function actionEntries(record={},calculated={},spells=[],featureOverrides=[],generalActions=generalActionsCache||[],enabledVariants=[]){
 const out=[];
 const edition=record.rules_version==='2024'?'2024':'2014';
 for(const rule of arr(generalActions)){
  if(rule.edition!==edition||rule.variant_id&&!enabledVariants.includes(rule.variant_id)&&
    !(rule.variant_id==='healing_surges_dmg'&&enabledVariants.includes('healing_surges_bonus_dmg')))continue;
  let times=arr(rule.timings);
  const alternate=times.includes('action')&&times.includes('bonus');
  if(alternate)times=['bonus'];
  if(rule.id==='healing_surge'&&enabledVariants.includes('healing_surges_bonus_dmg'))times=['bonus'];
  for(const time of times)out.push({id:rule.id,name:rule.name,time,type:rule.parent_action==='attack'?'Attacco':'Generale',
   description:rule.description,tracker:rule.tracker||'',cost:0,origin:'general',optional:!!rule.variant_id,
   action_id:rule.action_id||'',skill_ids:arr(rule.skills),parent_action:rule.parent_action||'',
   source_label:rule.source+(rule.page?', p. '+rule.page:''),source_url:rule.source_url,
   alternate_action:alternate,catalog_id:rule.id});
 }
 const trackers=new Map(arr(calculated.trackers).map(row=>[String(row.id),row]));
 const add=(name,time,type,description,tracker='',cost=0,extra={})=>out.push({name:String(name||type),time:timing(time),type:String(type),description:details(description),tracker:String(tracker||''),cost,origin:'personal',...extra});
 const tracked=(id)=>trackers.get(String(id))?.name||'';
 for(const row of featureActionEntries(record,arr(calculated.trackers),calculated.feature_rules||{},arr(calculated.features))){
  const rule=arr(calculated.feature_rules?.actions).find(r=>r.id===row.rule_id);
  const base=out.find(r=>r.id===rule?.action_id);
  if(base){
   base.origin='personal';
   base.alternate_action=base.time==='action'&&timing(row.time)==='bonus';
   base.action_change_origin=row.origin_id;
   base.action_change_feature=row.feature;
   base.original_time=base.time;
   base.time=timing(row.time);
  }
  else out.push({...row,id:rule?.action_id||row.rule_id,time:timing(row.time)});
 }
 const already=new Set();
 // Local combat calculations preserve equipped weapon slots, hit, damage,
 // reach and monster section in stable attack identifiers.
 for(const attack of arr(calculated.attacks)){
  if(!attack?.id||already.has(attack.id))continue;
  already.add(attack.id);
  const section=String(attack.id).split(':')[1];
  const time=String(attack.id).startsWith('monster:')?(section==='bonus'||section==='reaction'?section:'action'):attack.offhand_bonus?'bonus':'action';
  const hit=attack.hit!==null&&attack.hit!==undefined&&attack.hit!==''&&Number.isFinite(Number(attack.hit))?
   'Colpire: '+(Number(attack.hit)>=0?'+':'')+attack.hit+'. ':'';
  add(attack.name,time,'Attacco',hit+(attack.damage?'Danni: '+attack.damage+'. ':'')+(attack.damage_explanation?attack.damage_explanation+'. ':'')+'Portata/gittata: '+(attack.range_feet??5)+' ft.'+
   (arr(attack.on_hit_effects).length?' Effetti sul colpo: '+arr(attack.on_hit_effects).map(effect=>effect.description).filter(Boolean).join(' · '):''),'',0,{id:attack.id,attack_id:attack.id,parent_action:time==='bonus'?'two_weapon':time==='action'?'attack':''});
 }
 // Fallback for older schemas without the local computed attack projection.
 for(const attack of arr(record.attacks))if(attack?.name&&!already.has(String(attack.id))){
  already.add(String(attack.id));add(attack.name,attack.action_type||'action','Attacco',attack.description||attack.damage||'',tracked(attack.tracker_id));
 }
 for(const action of monsterActions(record,calculated.trackers)){
  if(action.parent_action_id){
   const parentIndex=out.findIndex(row=>row.id===action.parent_action_id);
   if(parentIndex>=0)out.splice(parentIndex,1);
  }
  const existing=out.find(row=>row.id===action.id);
  if(existing)Object.assign(existing,action,{type:existing.type,tracker:tracked(action.tracker_id)});
  else add(action.name,action.time,'Capacità',action.description,tracked(action.tracker_id),action.cost,action);
 }
 // Named monster abilities and attacks share the same typed recharge pool.
 // A 5eTools list of options is projected under its parent, never as extra uses.
 for(const section of ['action','bonus','reaction']){
  arr(record.stat_block?.[section]).forEach((feature,i)=>{
   const id='monster:'+section+':'+i;
   if(!feature?.name)return;
   if(out.some(row=>row.parent_action_id===id))return;
   const candidates=[feature.tracker_id,feature.vtt_resource?.id,
     'recharge:'+section+':'+i,'fightclub:'+section+':'+i];
   const trackerId=candidates.find(key=>key&&trackers.has(String(key)))||'';
   const rechargeable=/\{@recharge(?: [1-6])?\}/i.test(String(feature.name))||
     feature.vtt_resource?.recharge==='d6'||!!trackerId&&
     ['d6','short_rest','long_rest'].includes(trackers.get(String(trackerId))?.recharge);
   const options=rechargeable?monsterActionOptions(feature):[];
   if(/^(?:multiattack|multiattacco)$/i.test(String(feature.name).trim()))return;
   if(already.has(id)||out.some(row=>row.id===id)){
    const existing=out.find(row=>row.id===id);
    if(existing&&options.length)Object.assign(existing,{options:existing.options?.length?existing.options:options,tracker_id:String(trackerId),
      tracker:tracked(trackerId)});
    return;
   }
   const name=options.length?String(feature.name).replace(/\s*\{@recharge(?: [1-6])?\}/gi,''):feature.name;
   add(name,section,'Capacità',feature.entries||feature.description||'',
       tracked(trackerId),Number(feature.tracker_cost)||0,
       {id,tracker_id:String(trackerId),options});
  });
 }
 // Explicit typed grants only. Passive traits are not automatically actions.
 const abilitySeen=new Set();
 for(const feature of [...arr(calculated.selection_record?.action_grants||record.action_grants),...arr(calculated.actions),...arr(calculated.feat_actions),...arr(calculated.features),...arr(record.selected_features),...arr(record.feats_catalog)]){
  if(!feature||feature.disabled||feature.inactive||feature.origin_id&&record.origin_enabled?.[feature.origin_id]===false)continue;
  const activation=feature.action_type??feature.activation??feature.activation_type??feature.time;
  if(!specified(activation))continue;
  const identity=String(feature.key||feature.id||'')+'|'+String(feature.name||feature.title||'');
  if(abilitySeen.has(identity))continue;
  abilitySeen.add(identity);
  const available=equipmentRequirementMatches(calculated.selection_record||record,
    feature.requirements||{},'',null,calculated.equipped_items);
  add(feature.name||feature.title,activation,feature.type||feature.action_kind||'Capacità',
      feature.description||feature.entries||feature.text||'',tracked(feature.tracker_id),Number(feature.tracker_cost??(feature.tracker_id?1:0))||0,{id:String(feature.key||feature.id||feature.name||feature.title),tracker_id:String(feature.tracker_id||''),origin_id:String(feature.origin_id||feature.origin_key||''),
       available:available&&feature.disabled!==true,unavailable_reason:feature.unavailable_reason||(available?'':'Equipaggiamento richiesto non presente.'),
       ...(feature.dice?{dice:feature.dice}:{}),
       ...(feature.attack_selector?{attack_selector:feature.attack_selector}:{}),
       ...(feature.action_id?{action_id:feature.action_id}:{}),
       alternate_action:Array.isArray(activation)&&activation.some(t=>timing(t)==='action')&&activation.some(t=>timing(t)==='bonus')});
 }
 // Exact 5etools class/feature/source/level supplements, not prose analysis.
 const members=arr(record.classes).length?arr(record.classes):
   record.class?[{name:record.class,source:record.class_source,level:record.level||1}]:[];
 const selectedEdition=record.rules_version==='2024'?'XPHB':'PHB';
 for(const rule of arr(featureOverrides)){
  if(rule.feature_name==='Cunning Action')continue; // Superseded by structured alternative activations.
  const classMember=members.find(m=>String(m?.name||'').toLowerCase()===String(rule.class_name||'').toLowerCase()&&
    String(m?.source||selectedEdition).toUpperCase()===String(rule.book||'').toUpperCase()&&
    Number(m?.level||0)>=Number(rule.min_level||1));
  if(!classMember)continue;
  const classOrigin='class|'+String(rule.book||'').toLowerCase()+'|'+String(rule.class_name||'').toLowerCase();
  if(record.origin_enabled?.[classOrigin]===false||arr(record.proficiency_origins).some(o=>o?.id===classOrigin&&o.disabled))continue;
  const resource=arr(calculated.trackers).find(t=>String(t.name).toLowerCase()===String(rule.resource_name||'').toLowerCase()&&
    (!t.origin_class||String(t.origin_class).toLowerCase()===String(rule.class_name||'').toLowerCase()));
  // Do not grant missing or disabled features solely from class/level.
  const collected=arr(calculated.features).filter(f=>String(f.origin_key||'').startsWith(classOrigin));
  const grantingFeature=collected.find(f=>String(f.name||'').toLowerCase()===
      String(rule.feature_name||'').toLowerCase()&&!f.inactive&&!f.disabled);
  if(!grantingFeature)continue;
  // Prefer the native activation (including persistent conditions) when present.
  // Otherwise keep a typed, class-owned grant with its actual resource.
  if(nativeClassFeatureActions(record,calculated).some(row=>
      row.origin_id===grantingFeature.origin_id||
      String(row.name).toLowerCase()===String(rule.display_name||rule.feature_name).toLowerCase()))continue;
  add(rule.display_name||rule.feature_name,rule.activation,'Capacità',rule.description||'',
      resource?.name||rule.resource_name||'',Number(rule.resource_cost??(resource?1:0))||0,
      {id:'class_override:'+rule.class_name+':'+(rule.display_name||rule.feature_name)+':'+rule.book,
       tracker_id:String(resource?.id||''),origin_id:grantingFeature.origin_id,
       feature_id:grantingFeature.origin_id,feature_name:grantingFeature.name});
 }
 // Native class abilities with no typed activation in their 5etools entry.
 for(const row of nativeClassFeatureActions(record,calculated)){
  if(out.some(existing=>existing.origin==='personal'&&
      String(existing.name).toLowerCase()===String(row.name).toLowerCase()))continue;
  out.push(row);
 }
 // Extra Attack modifies the Attack action; it is not a separate action.
 const attackAction=out.find(row=>row.id==='attack');
 if(attackAction){
  const amount=attacksPerAction(record,calculated);
  if(amount>1){
   attackAction.attack_count=amount;
   attackAction.description+='\nAttacchi per azione: '+amount+'.';
  }
 }
 // Origin-spell grants are already resolved by the local rules engine,
 // including custom payment mode, disabled origins and level requirements.
 for(const grant of arr(calculated.origin_spells)){
  if(grant?.disabled)continue;
  const definition=spells.find(row=>row.id===grant.spell_id);
  if(!definition||definition.internal_grant!==true)continue;
  const mode=grant.payment_mode||(grant.tracker_id?'tracker':'free');
  const tracker=mode==='tracker'?tracked(grant.tracker_id):mode==='slot'?'Slot incantesimo':'Nessuna risorsa';
  const internal=definition.internal_grant===true;
  add(definition.name||grant.spell_id,definition.time??definition.casting_time??'action',
      internal?'Capacità':'Incantesimo',
      (internal?'':'Tempo di lancio: '+castingTime(definition)+'.\n')+details(definition.entries??definition.description??''),
      tracker,mode==='tracker'?Math.max(1,Number(grant.tracker_cost)||1):0,
      {spell_id:String(grant.spell_id),grant_id:String(grant.id),spell_mode:mode,tracker_id:mode==='tracker'?String(grant.tracker_id||''):''});
 }
 const normalized=[];
 for(const row of out){
  if(row.type==='Incantesimo')continue;
  const same=normalized.find(old=>(old.id||old.name)===(row.id||row.name)&&old.tracker_id===row.tracker_id&&
   (old.time===row.time||[old.time,row.time].every(t=>['action','bonus'].includes(t))));
  if(!same){normalized.push(row);continue;}
  if(same.time!==row.time){same.time='bonus';same.alternate_action=true;}
 }
 return normalized;
}
// Retain the public projection API; execution and eligibility share one rule set.
export function nativeClassFeatureActions(record={},calculated={}){
 return [...classFeatureEntries(record,calculated).filter(row=>!row.roll_only),
  ...arr(calculated.feat_actions),...arr(calculated.state_actions)]
  .map(row=>({...row,description:details(row.description)}));
}
export function diceGlyph(){return '<span class="action-dice" aria-hidden="true"></span>';}
// Compact battle sections use the same action projection as the Actions tab.
// Keep attack buttons separate from description disclosures to avoid accidental dice rolls.
const BATTLE_TIMINGS=[['action','Azione'],['bonus','Azione bonus'],['reaction','Reazione'],['free','Azione gratuita'],['movement','Movimento'],['legendary','Azione leggendaria'],['legendary_resistance','Resistenza leggendaria'],['lair','Azioni di tana']];
const MOVEMENT_ACTION_IDS=new Set(['movement','stealth_movement','dash','disengage','drop_prone','climb_large','overrun','tumble','escape_grapple','stand_up','crawl','jump','mount','dismount','difficult_terrain']);
const WEAPON_ROLL_ACTION_IDS=new Set(['disarm','opportunity']);
const rollModifier=value=>value!==null&&value!==undefined&&value!==''&&Number.isFinite(Number(value))?Number(value):null;
const rollSign=value=>value<0?'−'+Math.abs(value):'+'+value;
const rollFormula=value=>'1d20 '+(value<0?'− '+Math.abs(value):'+ '+value);
const BATTLE_EFFECTS={
 grapple:['condition','Afferrato','condition'],
 prone:['condition','Prono','prone_alt'],
 shove:['movement','Spinto di 5 ft','shove'],
 shove_aside:['movement','Spinto lateralmente','shove'],
 disarm:['other','Oggetto lasciato cadere','disengage'],
 drop_prone:['condition','Prono','prone_alt'],
 escape_grapple:['condition','Interrompe Afferrato, se riesce','grapple'],
 disengage:['movement','Nessun attacco di opportunità durante lo spostamento','disengage'],
 dash:['movement','Movimento aggiuntivo pari alla velocità','dash'],
 movement:['movement','Spostamento entro la velocità','dash'],
 stealth_movement:['movement','Spostamento furtivo','stealth_check'],
 tumble:['movement','Passaggio nello spazio di un avversario','acrobatics'],
 overrun:['movement','Attraversa lo spazio di un avversario','athletics'],
 climb_large:['movement','Arrampicata su una creatura grande','athletics'],
 stand_up:['movement','Termina Prono','prone_alt'],
 crawl:['movement','Spostamento strisciando','dash'],
 jump:['movement','Salto','dash'],
 mount:['movement','Sale in sella','dash'],
 dismount:['movement','Scende dalla cavalcatura','dash'],
 difficult_terrain:['movement','Movimento su terreno difficile','dash']
};
const DAMAGE_GLYPHS={
 fire:'fire',fuoco:'fire',cold:'ice',freddo:'ice',lightning:'lightning',fulmine:'lightning',
 poison:'poison',veleno:'poison',necrotic:'necromancy',necrotico:'necromancy',
 radiant:'spark',radioso:'spark',acid:'poison',acido:'poison',psychic:'arcana',psichico:'arcana',
 thunder:'lightning',tuono:'lightning'
};
const supportedDamage=formula=>/^\s*(?:\d+d(?:4|6|8|10|12|20|100)|\d+)(?:\s*[+-]\s*(?:\d+d(?:4|6|8|10|12|20|100)|\d+))*\s*$/i.test(String(formula||''));
function battleEffectMarkup(item,attack){
 const effects=[];
 if(attack?.damage)effects.push(
  {kind:'damage',label:String(attack.damage).trim(),type:String(attack.damage_type||'').trim(),
   glyph:DAMAGE_GLYPHS[String(attack.damage_type||'').toLowerCase()]||'weapon'});
 else for(const bonus of arr(item.action_damage))if(bonus?.formula)effects.push(
  {kind:'damage',label:String(bonus.formula).trim(),type:String(bonus.damage_type||'').trim(),
   glyph:DAMAGE_GLYPHS[String(bonus.damage_type||'').toLowerCase()]||'weapon'});
 const fallback=BATTLE_EFFECTS[item.action_ref]||BATTLE_EFFECTS[item.action_id]||BATTLE_EFFECTS[item.id];
 if(!attack&&fallback)effects.push({kind:fallback[0],label:fallback[1],glyph:fallback[2]});
 else if(!attack&&!fallback&&item.class_feature_id==='step_of_the_wind')
  effects.push({kind:'movement',label:'Scattare o Disimpegnarsi',glyph:'dash'});
 return effects.map(resolved=>{
  const label=resolved.kind==='damage'?'Danni':resolved.kind==='condition'?'Condizione':'Effetto';
  const detail=resolved.label+(resolved.type?' · '+resolved.type:'');
  const glyph=actionGlyph(resolved.glyph);
  const canRoll=resolved.kind==='damage'&&supportedDamage(resolved.label)&&/\d+d\d+/i.test(resolved.label);
  return '<div class="play-battle-effect" data-effect-kind="'+esc(resolved.kind)+'">'+
   '<span class="play-battle-effect-kind">'+esc(label)+'</span>'+
   '<span class="play-battle-effect-value">'+glyph+'<strong>'+esc(detail)+'</strong></span>'+
   (canRoll?'<button type="button" class="play-battle-effect-roll" data-act="battle-damage-roll" data-damage-formula="'+
    esc(resolved.label)+'" data-damage-type="'+esc(resolved.type||'')+'" data-damage-attack-id="'+esc(attack?.id||'')+'" data-damage-action-id="'+esc(!attack?item.id||'':'')+'" data-damage-label="'+esc(item.name)+
    '" aria-label="Tira danni: '+esc(item.name)+'">'+diceGlyph()+'</button>':'')+
   '</div>';
 }).join('');
}
// A computed attack's melee flag, not its name or source, selects the glyph.
export function attackRowGlyphKey(attack={}){
 return attack.melee===false?'target':'sword';
}
// Expanded attack details come from the source that grants them.
function attackSourceDescription(record,calculated,attack){
 const id=String(attack?.id||''),inventory=arr(record.inventory);
 // A generic unarmed strike must never inherit the description of a held weapon.
 if(id.startsWith('item:')||id.startsWith('shield:improvised:')){
  const instance=String(attack.equipped_item_id||'');
  const item=inventory.find(row=>instance&&
   (String(row.instance_id||'')===instance||String(row.id||'')===instance))||
   inventory.find(row=>arr(row.equipped_slots).includes(attack.slot==='off'?'off':'main')&&
    String(row.id||'')===id.split(':').at(-1));
  const description=details(item?.description||item?.entries||item?.text);
  if(description)return description;
 }
 const monster=/^monster:(action|bonus|reaction|legendary|mythic):(\d+)$/.exec(id);
 if(monster){
  const entry=arr(record.stat_block?.[monster[1]])[Number(monster[2])];
  const description=details(entry?.entries||entry?.description||entry?.text);
  if(description)return description;
 }
 const origin=String(attack.origin_id||'');
 const feature=arr(calculated.features).find(row=>origin&&
  (row.origin_id===origin||row.origin_key===origin||'feature:'+row.key===origin))||
  arr(calculated.features).find(row=>attack.slot==='natural'&&row.name===attack.name);
 const trait=details(feature?.entries||feature?.description||feature?.text);
 if(trait)return trait;
 const manual=arr(record.attacks).find(row=>String(row.id||'')===id);
 return details(manual?.description||manual?.entries||attack.description);
}
function battleAttackRow(item,calculated,attacksById,descriptions,record={}){
 const attack=attacksById.get(String(item.attack_id||item.id||''));
 const rolls=[];
 const addRoll=(target,label,kind,value)=>{
  const modifier=rollModifier(value);
  if(modifier!==null)rolls.push({target,label,kind,modifier});
 };
 const choices=[...attacksById.values()];
 // Opportunity Attack is a rules action, not an automatically selected main-hand hit.
 // Abstract attack actions use the unarmed strike's reach, not an invented
 // main-hand weapon selection. Concrete attacks keep their own reach/range.
 const attackAction=item.type==='Attacco'||item.attack_selector==='melee'||
  ['attack','opportunity','two_weapon'].includes(String(item.id||''));
 const unarmed=attacksById.get('unarmed')||
  {id:'unarmed',name:'Colpo senz’armi',melee:true,range_feet:5};
 const selectedAttack=attack||(attackAction?unarmed:null);
 // A typed shove action uses the existing map-targeting combat action.
 // It is not inferred from whether the character has used Dash.
 const actionName=item.name;
 if(item.check_target){
  const key=String(item.check_target),stat=key.split(':')[1];
  const bonus=key.startsWith('skill:')?calculated.skills?.[key.slice(6)]:
   calculated.abilities?.[stat]?.modifier;
  addRoll(key,actionName,item.check_label||actionName,calculated.values?.[key]??bonus);
 }
 if(attack){
  addRoll('attack_hit:'+attack.id,'Tiro per colpire · '+actionName,
   attack.melee?'Mischia':'Distanza',calculated.values?.['attack_hit:'+attack.id]??attack.hit);
 }
 // A feat or feature may grant a new action timing for any melee attack.
 // It does not create another weapon, change the attack damage, or require a
 // Dash result to have been registered in the app.
 if(item.attack_selector==='melee'){
  for(const available of choices.filter(row=>row.melee===true&&!row.disabled)){
   addRoll('attack_hit:'+available.id,'Tiro per colpire · '+available.name,
    available.name,calculated.values?.['attack_hit:'+available.id]??available.hit);
  }
 }
 if(item.skill_ids?.length){
  for(const skill of [...new Set(item.skill_ids)]){
   const label=SKILLS.find(([id])=>id===skill)?.[1]||skill;
   addRoll('skill:'+skill,label,label,
    calculated.values?.['skill:'+skill]??calculated.skills?.[skill]);
  }
 }
 if(!attack&&!item.skill_ids?.length&&item.id==='disarm'){
  const weapon=choices.find(row=>row.slot==='main')||choices[0];
  if(weapon)addRoll('attack_hit:'+weapon.id,'Tiro per colpire · '+actionName,
   weapon.melee?'Mischia':'Distanza',calculated.values?.['attack_hit:'+weapon.id]??weapon.hit);
 }
 const offhand=attack&&(attack.slot==='off'||String(attack.id).startsWith('shield:improvised:off:'));
 const description=item.id==='improvised'?item.description||'Attacco con un oggetto equipaggiato impugnato come arma improvvisata.':
  attack?(attackSourceDescription(record,calculated,attack)||item.description||
   (offhand?descriptions.off:descriptions.main)):item.description||'';
 const rangeFeet=Number(selectedAttack?.range_feet);
 const longRangeFeet=Number(selectedAttack?.long_range_feet);
 const rangeLabel=Number.isFinite(rangeFeet)&&rangeFeet>0?
  (selectedAttack.melee?'Portata ':'Gittata ')+rangeFeet+
   (!selectedAttack.melee&&Number.isFinite(longRangeFeet)&&longRangeFeet>rangeFeet?'/'+longRangeFeet:'')+' ft':'';
 const mapButton=rangeLabel&&selectedAttack?.id?
  '<button type="button" class="play-battle-attack-map" data-act="battle-attack-map" data-map-attack-id="'+esc(selectedAttack.id)+
  '" aria-label="Mostra la gittata di '+esc(actionName)+' sulla mappa" title="Gittata sulla mappa">'+actionGlyph('map')+'</button>':'';
 const icon=actionGlyph(item.check_target?(item.skill_code?skillGlyphKey(item.skill_code):'proficiency'):
  attack?attackRowGlyphKey(attack):actionGlyphKey(item));
 const source=item.source_url?'<a href="'+esc(item.source_url)+'" target="_blank" rel="noopener">'+esc(item.source_label||'Fonte')+'</a>':'';
 const target=item.action_id?'<button type="button" class="btn small" data-act="combat-action" data-mode="'+esc(item.action_id)+'">Seleziona bersaglio</button>':'';
 const tracker=(calculated.trackers||[]).find(row=>String(row.id)===String(item.tracker_id||'')&&item.tracker_id);
 const remaining=tracker?Math.max(0,Number(tracker.max||0)-Number(tracker.spent||0)):0;
 const resources=tracker&&item.monster_action?'<div class="action-resource-control"><button type="button" class="btn small" data-act="monster-action-use" data-monster-action-id="'+esc(item.id)+'"'+(remaining<item.cost||tracker.disabled?' disabled':'')+' aria-label="Usa '+esc(actionName)+'">Usa</button><span>'+remaining+' / '+esc(tracker.max)+'</span></div>':tracker?'<div class="action-resource-control"><button type="button" class="btn small" data-act="tracker-more" data-tracker-id="'+esc(tracker.id)+'"'+(remaining<=0||tracker.disabled?' disabled':'')+'>−</button><span>'+remaining+' / '+esc(tracker.max)+'</span><button type="button" class="btn small" data-act="tracker-less" data-tracker-id="'+esc(tracker.id)+'"'+(Number(tracker.spent||0)<=0||tracker.disabled?' disabled':'')+'>+</button></div>':
  item.tracker?'<span class="action-economy-tracker">'+esc(item.tracker)+'</span>':'';
 const optionMarkup=monsterActionOptionsMarkup(item);
 if(item.id==='spell_cast')return '<article class="play-battle-attack-entry play-battle-action-direct" data-attack-id="spell_cast">'+
  '<button type="button" class="play-battle-attack-direct-button" data-act="action-open-spells">'+icon+
  '<span class="play-battle-attack-copy"><strong>'+esc(actionName)+'</strong></span></button></article>';
 return '<article class="play-battle-attack-entry'+(item.available===false?' play-battle-attack-unavailable':'')+
  '" data-attack-id="'+esc(item.id==='improvised'?'improvised':item.attack_id||item.id||'')+'">'+
  '<div class="play-battle-attack-line">'+
  (item.check_target?
   '<div class="play-battle-attack-details"><div class="play-battle-check-heading">'+icon+
   '<span class="play-battle-attack-copy"><strong>'+esc(actionName)+'</strong></span></div></div>':
   '<details class="play-battle-attack-details"><summary>'+icon+
   '<span class="play-battle-attack-copy"><strong>'+esc(actionName)+'</strong>'+
    (rangeLabel?'<small class="play-battle-attack-range">'+esc(rangeLabel)+'</small>':'')+
    (item.available===false&&item.unavailable_reason?'<small class="play-battle-unavailable-reason">'+esc(item.unavailable_reason)+'</small>':'')+'</span>'+
   (Number(item.attack_count)>1?'<span class="play-battle-attacks-per-action" title="Attacchi per azione" aria-label="'+esc(item.attack_count)+' attacchi per azione">×'+esc(item.attack_count)+'</span>':'')+
   (item.alternate_action?'<span class="action-alternate" title="Utilizzabile anche con un’azione">A</span>':'')+
   '</summary><div class="play-battle-attack-expanded"><p>'+render5etoolsInline(description||'Dettagli non disponibili.')+'</p>'+
   source+target+resources+optionMarkup+
   (String(item.id||'').startsWith('activated:')&&!item.descriptive_only?'<button type="button" class="btn small" data-act="battle-use-ability" data-ability-id="'+esc(item.id)+'">Usa</button>':'')+
   '</div></details>')+
  (rolls.length||mapButton?'<div class="play-battle-attack-rolls"'+(rolls.length>1?' data-multiple-rolls="true"':'')+'>'+rolls.map((row,index)=>
   '<div class="play-battle-attack-roll-line"><span class="play-battle-roll-formula">'+
   esc(rollFormula(row.modifier))+' · '+esc(row.kind)+'</span>'+
   (index===0?mapButton:'')+
   '<button type="button" class="play-battle-attack-roll" data-act="sheet-roll" data-target="'+esc(row.target)+
   '" data-label="'+esc(row.label)+'" aria-label="'+esc(row.label)+'">'+
   '<b>'+esc(rollSign(row.modifier))+'</b>'+diceGlyph()+'</button></div>').join('')+
   (!rolls.length&&mapButton?'<div class="play-battle-attack-roll-line">'+mapButton+'</div>':'')+
   '</div>':'')+
  '</div>'+battleEffectMarkup({...item,name:actionName,
   action_damage:attack?[]:arr(calculated.action_damage_bonuses).filter(row=>
    String(row.action_id)===String(item.id||''))},attack)+'</article>';
}

const classOrigin=row=>String(row?.origin_id||'').startsWith('class|')||
 String(row?.origin_id||'').startsWith('feature:class|')||
 String(row?.id||'').startsWith('class_feature:')||!!row?.class_feature_id;
// Reusable typed abilities route to the ordinary d20 attack popup; they
// do not duplicate hit, damage, advantage or provenance calculations.
export function abilityAttackRoll(ability={},calculated={}){
 const ref=ability.roll_attack;
 if(ref?.kind!=='attack')return null;
 const attacks=arr(calculated.attacks);
 const byId=ref.id?attacks.find(attack=>String(attack.id)===String(ref.id)):null;
 const byTrait=ref.trait?attacks.find(attack=>
   String(attack.name||'').trim().toLowerCase()===String(ref.trait).trim().toLowerCase()&&
   (!ref.slot||attack.slot===ref.slot)):null;
 const attack=byId||byTrait;
 return attack?.id&&Number.isFinite(Number(calculated.values?.['attack_hit:'+attack.id]))?
   {target:'attack_hit:'+attack.id,label:String(ability.name||'Capacità')+' · '+String(attack.name||'Attacco')}:
   null;
}
export function battleAbilityEntries(record={},calculated={},entries=[],activated=[]){
 const result=entries.filter(row=>row.origin==='personal'&&row.type==='Capacità'&&(classOrigin(row)||row.monster_action));
 const seen=new Set(result.map(row=>String(row.name||'').trim().toLocaleLowerCase('it')));
 // Targeted feat actions participate in the standard Battle/Resources
 // pipeline, with exactly the same tracker and target selection as powers.
 for(const ability of arr(calculated.feat_actions)){
  if(!ability?.id||!ability.target_mode&&!ability.mode)continue;
  const identity=String(ability.name||'').trim().toLocaleLowerCase('it');
  if(!identity||seen.has(identity))continue;
  const tracker=arr(calculated.trackers).find(row=>row.id===ability.tracker_id&&!row.disabled);
  if(ability.resource_cost>0&&!tracker)continue;
  result.push({...ability,id:ability.id,name:ability.name,origin:'personal',
   type:'Capacità',time:ability.action_type||'contextual',
   tracker:tracker?.name||'',tracker_id:tracker?.id||'',cost:Math.max(0,Number(ability.resource_cost)||0)});
  seen.add(identity);
 }
 for(const ability of activated){
  if(!String(ability.origin||'').startsWith('Classe ·')&&
     !String(ability.origin||'').startsWith('Specie ·')&&
     !String(ability.feature_id||'').startsWith('feature:class|')&&
     !String(ability.feature_id||'').startsWith('feature:species|'))continue;
  const raw=String(ability.action_type||ability.activation_mode||'').trim().toLowerCase();
  if(!raw||raw==='passive')continue;
  if(ability.id==='vtt_wild_shape'&&result.some(row=>row.rule_action_id==='wild_shape'||row.id==='wild_shape'))continue;
  const name=String(ability.name||'').trim().toLocaleLowerCase('it');
  if(!name||seen.has(name))continue;
  result.push({id:'activated:'+ability.id,ability_id:ability.id,name:ability.name,
   description:ability.description||'',descriptive_only:ability.descriptive_only===true,
   time:raw==='contextual'?'contextual':timing(raw),type:'Capacità',
   origin:'personal',origin_id:ability.feature_id||ability.origin_id||'',
   tracker_id:String(ability.tracker_id||''),tracker:ability.tracker_name||ability.resource_name||'',
   cost:Math.max(0,Number(ability.resource_cost??(ability.tracker_id?1:0))||0),
   target_mode:ability.target_mode||'',target_range_feet:ability.target_range_feet||0,
   exclude_self:ability.exclude_self===true,
   // Preserve typed mechanics for reusable racial area and temporary effects.
   mode:ability.mode||'',persistent_key:ability.persistent_key||'',
   effect_condition:ability.effect_condition||'',ends_on:arr(ability.ends_on),
   persistent_origin_id:ability.persistent_origin_id||'',
   duration_rounds:ability.duration_rounds||0,
   attack_replacement:ability.attack_replacement===true,
   area_shape:ability.area_shape||'',area_length_feet:ability.area_length_feet||0,
   area_width_feet:ability.area_width_feet||0,area_radius_feet:ability.area_radius_feet||0,
   damage_formula:ability.damage_formula||'',damage_type:ability.damage_type||'',
   save_ability:ability.save_ability||'',save_base:ability.save_base||'',
   half_on_save:ability.half_on_save===true,options:arr(ability.options),
   ...(ability.action_ref?{action_ref:ability.action_ref}:{}),
   ...(ability.roll_attack?{roll_attack:ability.roll_attack}:{}),
   ...(ability.companion_command?{companion_command:true}:{}),
   ...(ability.roll_effect?{roll_effect:ability.roll_effect}:{}),
   ...(ability.temp_hp?{temp_hp:ability.temp_hp}:{})});
  seen.add(name);
 }
 return result;
}
// The canonical 18 skills are grouped by their governing ability. Each group
// starts with an untrained ability check, without adding a fictitious proficiency.
export function battleSkillChecksPanel(calculated={}){
 const abilities=[['str','Forza'],['dex','Destrezza'],['con','Costituzione'],
  ['int','Intelligenza'],['wis','Saggezza'],['cha','Carisma']];
 const emptyAttacks=new Map(),descriptions={main:'',off:''};
 return abilities.map(([ability,label])=>{
  const choices=[
   {id:'ability_check:'+ability,name:'Prova di '+label,check_target:'ability_check:'+ability,check_label:label},
   ...SKILLS.filter(row=>row[2]===ability).map(([id,name])=>({
    id:'skill:'+id,name,check_target:'skill:'+id,check_label:name,skill_code:id}))
  ];
  return '<details class="play-battle-action-group" data-action-ability="'+esc(ability)+'">'+
   '<summary class="play-battle-action-heading">'+actionGlyph('proficiency')+
   '<span>'+esc(label)+'</span><span class="play-badge">'+choices.length+'</span></summary>'+
   '<div class="play-battle-action-rows">'+choices.map(row=>battleAttackRow(row,calculated,emptyAttacks,descriptions)).join('')+
   '</div></details>';
 }).join('');
}

// Spell actions open the very same spell/casting dialog as the Magia tab.
// Keep prose out of the action list; its detailed facts are shown in the dialog.
// The bonus attack is available only for a real two-weapon loadout.
// An empty off hand (including an unarmed off-hand entry) does not qualify.
// Light-weapon eligibility is independent of Dual Wielder: the feat grants
// its own privilege, while the basic-rule row stays locked if not Light.
export function offhandActionAvailable(record={},calculated={}){
 return offhandActionEligibility(record,calculated).available;
}

export function battleActionPanels(record,calculated,spells=[],featureOverrides=[],generalActions=generalActionsCache||[],enabledVariants=[],activatedAbilities=[]){
 const entries=actionEntries(record,calculated,spells,featureOverrides,generalActions,enabledVariants);
 const count=attacksPerAction(record,calculated);
 const descriptions={
  main:entries.find(row=>row.id==='attack')?.description||'Attaccare con un’arma o con un colpo senz’armi.',
  off:entries.find(row=>row.id==='two_weapon')?.description||'Effettuare un attacco con l’arma nella mano secondaria.'
 };
 const attacksById=new Map(arr(calculated.attacks).filter(row=>row?.id).map(row=>[String(row.id),row]));
 const classAbilities=battleAbilityEntries(record,calculated,entries,activatedAbilities);
 const classIds=new Set(classAbilities.filter(row=>!String(row.id||'').startsWith('activated:')));
 const offhandEligibility=offhandActionEligibility(record,calculated);
 const haveOffhand=offhandEligibility.available;
 const haveMelee=[...attacksById.values()].some(row=>row.melee);
 const hasSlots=arr(calculated.spell_slots).some(s=>Number(s.total)>0)||
   Number(calculated.pact_slots?.total)>0;
 const baseRules=[
  {id:'attack',name:'Azione di attacco',time:'action',type:'Generale',
   description:descriptions.main,attack_count:count},
  {id:'opportunity',name:'Attacco di opportunità',time:'reaction',type:'Generale',
   description:'Attacco in mischia effettuato come reazione.',available:haveMelee},
  {id:'two_weapon',name:'Attacco con arma secondaria',time:'bonus',type:'Generale',
   description:descriptions.off,available:offhandEligibility.base_available,
   unavailable_reason:offhandEligibility.base_reason},
  {id:'spell_cast',name:'Lanciare un incantesimo',time:'action',type:'Generale',
   description:'Lancia un incantesimo attraverso uno slot disponibile.',available:hasSlots},
  {id:'ability_checks',name:'Prova abilità',time:'action',type:'Generale',
   description:'Effettuare una prova di caratteristica o di abilità.',available:true}
 ];
 const baseById=new Map(baseRules.map(row=>[row.id,row]));
 for(const row of monsterBasicRules(record,calculated))baseById.set(row.id,row);
 const grants=arr(calculated.attack_count_benefits).filter(row=>Number(row.attacks_per_action)===count);
 const grant=grants[0];
 const grantingTrait=arr(calculated.features).find(row=>row.origin_id===grant?.origin_id)||
  (record.kind==='monster'?monsterTraits(record).find(row=>row.monster_role==='multiattack')||monsterTraits(record)[0]:null);
 baseById.get('attack').grant_description=details(grantingTrait?.entries)||grant?.origin_name||descriptions.main;
 const opportunity=entries.find(row=>row.id==='opportunity');
 if(opportunity)baseById.set('opportunity',{...opportunity,...baseById.get('opportunity')});
 const offhand=entries.find(row=>row.id==='two_weapon');
 if(offhand)baseById.set('two_weapon',{...offhand,...baseById.get('two_weapon')});
 const normalAttack=entries.find(row=>row.id==='attack');
 if(normalAttack)baseById.set('attack',{...normalAttack,...baseById.get('attack')});
 const allBase=[...baseById.values()];
 const actionsBase=allBase.map(row=>row.id==='two_weapon'?
  {...row,available:haveOffhand,unavailable_reason:offhandEligibility.reason}:
  row.id==='attack'?{...row,attack_count:1}:row);
 // All physical attack choices are a flat list, irrespective of action cost.
 // Their action economy is defined in "Azioni", not repeated here.
 // Combine all actually available improvised attacks into one generic choice.
 // Keep the underlying computed attack for its exact dice and modifiers.
 const improvised=attack=>{
  const id=String(attack?.id||'');
  return id==='improvised'||id.startsWith('improvised:')||
   id.startsWith('shield:improvised:')||attack?.improvised===true||
   /\b(?:improvvisat|improvised)/i.test(String(attack?.name||''));
 };
 const realImprovised=[...attacksById.values()].filter(improvised);
 const weapon=entries.filter(row=>row.type==='Attacco'&&
  !['attack','opportunity','two_weapon','unarmed:off'].includes(row.id)&&
  row.parent_action!=='two_weapon'&&
  !realImprovised.some(attack=>String(row.attack_id||row.id)===String(attack.id)));
 if(realImprovised.length){
  weapon.push({id:'improvised',attack_id:realImprovised[0].id,name:'Arma improvvisata',
   time:'action',type:'Attacco',origin:'general',parent_action:'attack',
   description:'Utilizza uno scudo o un oggetto impugnato come arma improvvisata.'});
 }
 const shownWeapon=new Set(weapon.map(row=>String(row.attack_id||row.id||'')));
 if(!shownWeapon.has('unarmed')){
  const known=attacksById.get('unarmed');
  weapon.push({id:'unarmed',attack_id:'unarmed',name:known?.name||'Colpo senz’armi',
   time:'action',type:'Attacco',origin:'general',parent_action:'attack'});
 }
 const weaponPriority=row=>{
  const attack=attacksById.get(String(row.attack_id||row.id||''));
  if(row.id==='unarmed')return 3;
  if(attack?.slot==='main')return 0;
  if(attack?.slot==='off'||attack?.slot==='shield')return 1;
  return 2;
 };
 // Privilege, monster and equipped attacks precede general attacks.
 // Unarmed Strike is always first in the final group of basic attacks.
 // A monster:<section>:<index> is special only when it actually exists in
 // the stat block; never infer an origin from the displayed attack name.
 // Damage and equipment priority only apply within the same tier.
 const dealsDamage=row=>{
  const attack=attacksById.get(String(row.attack_id||row.id||''));
  const formula=String(attack?.damage||row.damage||'').trim();
  return /\d+(?:d\d+)?/i.test(formula)||/\b(?:danni|damage)\s*:/i.test(String(row.description||''));
 };
 const attackTier=row=>{
  if(row.id==='unarmed')return 2;
  if(row.id==='improvised'||row.origin==='general'||row.catalog_id&&row.parent_action==='attack')return 3;
  const attack=attacksById.get(String(row.attack_id||row.id||''));
  const source=/^monster:(action|bonus|reaction|legendary|mythic):(\d+)$/.exec(String(attack?.id||''));
  const statBlockAttack=source&&arr(record.stat_block?.[source[1]])[Number(source[2])];
  return attack?.origin_id||row.origin_id||attack?.feature_id||row.feature_id||statBlockAttack?0:1;
 };
 weapon.sort((a,b)=>attackTier(a)-attackTier(b)||
  Number(dealsDamage(b))-Number(dealsDamage(a))||
  weaponPriority(a)-weaponPriority(b));
 // Always place Grapple directly below Unarmed Strike in the flat list.
 const unarmedAt=weapon.findIndex(row=>row.id==='unarmed');
 const grappleAt=weapon.findIndex(row=>row.id==='grapple');
 if(unarmedAt>=0&&grappleAt>=0){
  const [grapple]=weapon.splice(grappleAt,1);
  weapon.splice(weapon.findIndex(row=>row.id==='unarmed')+1,0,grapple);
 }
 const specials=entries.filter(row=>!classIds.has(row)&&row.type!=='Incantesimo'&&
   row.type!=='Attacco'&&
   !['attack','two_weapon','opportunity','spell_cast','cast_spell'].includes(row.id));
 // Typed racial alternatives belong to Actions as well as the source trait.
 // Their use button re-enters the shared ability payment/effect pipeline;
 // Hide also exposes the ordinary Stealth check without inventing a new roll.
 for(const row of classAbilities.filter(row=>row.action_ref||
   String(row.id||'').startsWith('activated:')&&row.time==='reaction')){
   if(specials.some(item=>item.id===row.id))continue;
   specials.push({...row,
     ...(row.action_ref==='hide'?{skill_ids:['stealth']}:{}),
     type:'Capacità'});
 }
 const basicInActions=actionsBase.filter(row=>row.id==='attack'||row.id==='two_weapon'||
  row.id==='opportunity'&&row.available||row.id==='spell_cast'&&row.available||row.monster_action);
 const other=[...basicInActions,...specials,...classAbilities.filter(row=>row.monster_action)];
 const ordering=(a,b,time)=>{
  const order=row=>row.id==='attack'&&time==='action'?-100:
   row.id==='opportunity'&&time==='reaction'?-100:
   row.id==='two_weapon'&&time==='bonus'?-100:
   row.id==='spell_cast'&&time==='action'?-90:0;
  return order(a)-order(b);
 };
 const renderTiming=rows=>BATTLE_TIMINGS.map(([time,label])=>{
  const matching=rows.filter(row=>row.time===time).sort((a,b)=>ordering(a,b,time));
  return matching.length?'<details class="play-battle-action-group" data-action-timing="'+esc(time)+'"'+' open'+'>'+
    '<summary class="play-battle-action-heading">'+actionGlyph(HEADER_GLYPHS[time]||'proficiency')+
    '<span>'+esc(label)+'</span></summary>'+
    '<div class="play-battle-action-rows">'+matching.map(row=>battleAttackRow(row,calculated,attacksById,descriptions,record)).join('')+'</div></details>':'';
 }).join('')||'<p class="play-empty">Nessuna azione disponibile.</p>';
 const timingOverrides=entries.filter(row=>row.action_change_origin&&row.time!==row.original_time);
 const damageOverrides=arr(calculated.action_damage_bonuses).flatMap(grant=>{
  const action=allBase.find(row=>row.id===grant.action_id)||entries.find(row=>row.id===grant.action_id);
  return action?[{...action,action_change_origin:grant.parent_origin||grant.origin_id,
   action_change_feature:grant.origin_name||'',original_time:action.time,
   action_damage:[grant]}]:[];
 });
 return {
  attacks:'<div class="play-battle-action-rows play-battle-attack-flat">'+
   weapon.map(row=>battleAttackRow(row,calculated,attacksById,descriptions,record)).join('')+'</div>',
  others:renderTiming(other),movement:'',
  checks:battleSkillChecksPanel(calculated),
  spells:'',
  abilityEntries:classAbilities,
  basicActions:allBase,
  offhandEligibility,
  overriddenActions:timingOverrides,
  modifiedActions:[...timingOverrides,...damageOverrides]
 };
}


export function monsterActionOptionsMarkup(item={}){
 const monsterOptions=arr(item.options);
 const optionMarkup=monsterOptions.length?
  '<div class="play-battle-monster-options"><span class="play-battle-monster-options-title">Opzioni · scegli una</span>'+
  monsterOptions.map(option=>{
   const facts=[
    option.area_shape?option.area_feet+' ft · '+option.area_shape:'',
    option.save_ability?'TS '+option.save_ability.toUpperCase()+(option.save_dc?' · CD '+option.save_dc:''):'',
    option.damage_formula?'Danni '+option.damage_formula:'',
    ...arr(option.conditions).map(condition=>'Condizione '+condition)
   ].filter(Boolean);
   return '<details class="play-battle-monster-option" name="monster-options-'+esc(item.id)+'" data-monster-option="'+esc(option.id)+'">'+
    '<summary>'+esc(option.name)+'</summary><div class="play-battle-monster-option-body">'+
    (facts.length?'<small>'+facts.map(esc).join(' · ')+'</small>':'')+
    '<p>'+esc(option.description)+'</p></div></details>';
  }).join('')+'</div>':'';
 return optionMarkup;
}
