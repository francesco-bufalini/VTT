// Read-only, source-bound summaries for the PWA's trait cards.
// Use structured grants only; never extract mechanics from free-form descriptions.
import {contextualFeatureDescriptors,classFeatureDescriptors,classFeatureRollSources} from './feature_mechanics.js';
import {SENSE_NAMES,senseRange} from './sense_rules.js';
import {attackRangeLabel} from './attack_range.js';
import {resolveOwnedItem} from './item_controls.js';
import {attackCountBenefits} from './attack_count_benefits.js';
import {effectExtensionLabel,effectExtensionsFor} from './effect_extensions.js';
import {monsterActions} from './monster_traits.js';
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
const ABILITIES={str:'Forza',dex:'Destrezza',con:'Costituzione',int:'Intelligenza',wis:'Saggezza',cha:'Carisma'};
const SKILLS={
 'acrobatics':'Acrobazia','animal handling':'Addestrare Animali',arcana:'Arcano',
 athletics:'Atletica',deception:'Inganno',history:'Storia',insight:'Intuizione',
 intimidation:'Intimidire',investigation:'Indagare',medicine:'Medicina',
 nature:'Natura',perception:'Percezione',performance:'Intrattenere',
 persuasion:'Persuasione',religion:'Religione','sleight of hand':'Rapidità di Mano',
 stealth:'Furtività',survival:'Sopravvivenza'
};
const DAMAGE={
 acid:'Acido',bludgeoning:'Contundenti',cold:'Freddo',fire:'Fuoco',force:'Forza',
 spell_damage:'Danni da incantesimi',
 lightning:'Fulmine',necrotic:'Necrotici',piercing:'Perforanti',poison:'Veleno',
 psychic:'Psichici',radiant:'Radianti',slashing:'Taglienti',thunder:'Tuono'
};
const DEFENSE_CONDITIONS={blinded:'Accecato',charmed:'Affascinato',deafened:'Assordato',
 disease:'Malattie',frightened:'Spaventato',grappled:'Afferrato',incapacitated:'Incapacitato',
 paralyzed:'Paralizzato',petrified:'Pietrificato',poisoned:'Avvelenato',restrained:'Trattenuto',
 stunned:'Stordito',unconscious:'Privo di sensi',exhaustion:'Indebolimento'};
const ACTION_TIMES={legendary:'Azione leggendaria',lair:'Azione di tana',legendary_resistance:'Resistenza leggendaria',action:'Azione',bonus:'Azione bonus',reaction:'Reazione',free:'Azione gratuita',movement:'Movimento',contextual:'Contestuale'};
const actionTime=value=>ACTION_TIMES[norm(typeof value==='object'?value?.unit||value?.type:value)]||String(value||'Contestuale');
const describe=value=>typeof value==='string'?value:Array.isArray(value)?value.map(describe).filter(Boolean).join(' · '):
 value&&typeof value==='object'?describe(value.entries??value.entry??value.description??value.text??''):'';
const classOf=feature=>norm(feature?.requirements?.class_name||feature?.class_name||String(feature?.origin_key||'').split('|')[2]);
const sourceOf=feature=>norm(feature?.requirements?.class_source||feature?.class_source||String(feature?.origin_key||'').split('|')[1]);
const damageLabel=type=>DAMAGE[norm(type)]||({T:'Tuono',L:'Fulmine'}[type]||String(type||''));
const abilityDetails=rule=>{
 const items=[];
 for(const attack of rows(rule.attacks)){
  const distance=attackRangeLabel(attack);
  items.push('Attacco · '+attack.name+' · '+attack.damage+' '+damageLabel(attack.damage_type)+
   (distance?' · '+distance:''));
  if(attack.bonus_die)items.push('Dado aggiuntivo · '+attack.bonus_die.dice+' '+
   damageLabel(attack.bonus_die.damage_type)+
   (attack.bonus_die.recharge==='turn'?' · Una volta per turno':''));
 }
 for(const grant of rows(rule.numeric_grants))
  items.push('Bonus · '+traitBenefitTargetLabel(grant.target)+' '+signedTraitFormula(grant.amount));
 for(const name of rows(rule.granted_features))items.push('Privilegio disponibile · '+name);
 return items;
};
const RECOVERY={short_rest:'Riposo breve',long_rest:'Riposo lungo',turn:'Inizio turno',d6:'Ricarica d6'};
const TARGETS={ability_check:'Tutte le prove di caratteristica (incl. iniziativa)',
 saving_throw:'Tutti i tiri salvezza',attack_roll:'Tiri per colpire',
 damage_roll:'Tiri di danno',any_d20:'Qualunque d20',ac:'Classe armatura',
 initiative:'Iniziativa',hp:'PF massimi',second_max:'PF seconda forma',
 speed:'Camminata',proficiency:'Competenza',passive_perception:'Percezione passiva',
 pact_slot:'Slot del Patto',spell_dc:'CD incantesimi',spell_attack:'Attacco incantesimi',
 attunement_max:'Sintonie massime'};
export function signedTraitFormula(expression){
 const raw=String(expression??'').trim();
 return raw&&!/^[+\-−]/.test(raw)?'+'+raw:raw;
}
export function traitBenefitSources(trait={},record={}){
 const ids=new Set([trait.feature_origin,trait.proficiency_origin,...rows(trait.extension_origin_ids),
  ...rows(trait.monster_legacy_keys).flatMap(key=>['feature:'+key,'feature:trait:'+key]),
  ...(trait.key?['feature:trait:'+trait.key]:[]),
  ...(trait.rank===0?[trait.origin_key]:[]),
  ...(trait.category==='oggetti'&&trait.rank===0?
    [trait.item_base_origin,trait.infusion_origin_id]:[])].filter(Boolean));
 // Catalog summary cards and rule grants sometimes use different IDs for
 // the same *owned* species or feat. Only the summary card gets these aliases.
 if(trait.rank===0&&trait.category==='razza'){
  // Parent species and subrace are independent sources. Never attribute a
  // subrace grant to the parent species' summary (or vice versa).
  if(String(trait.origin_key||'').startsWith('species|')&&record.species)
   ids.add('race|'+norm(record.species_source)+'|'+norm(record.species));
  if(String(trait.origin_key||'').startsWith('subrace|')&&record.subrace)
   ids.add('subrace|'+norm(record.subrace_source)+'|'+norm(record.subrace));
 }
 if(trait.rank===0&&trait.category==='talenti'){
  for(const feat of rows(record.feats_catalog)){
   if(!feat?.name)continue;
   if('feat|'+(feat.id||norm(feat.name)+'|'+norm(feat.source))===trait.origin_key)
    ids.add('feat|'+norm(feat.source)+'|'+norm(feat.name));
  }
 }
 return ids;
}
// Resolve a clickable roll grant to its exact owning trait. Sources loaded
// from a flattened 5etools subrace can have distinct display/projection IDs;
// a qualified name and origin key recover the same card without routing to
// the parent species or an unrelated same-named trait.
export function rollGrantTraitRow(traits=[],record={},originId='',{traitName='',originKey=''}={}){
 const id=String(originId||''),name=norm(traitName),key=String(originKey||'');
 const scored=rows(traits).map(row=>{
  const direct=id&&row.feature_origin===id;
  const qualified=!!(key&&name&&row.origin_key===key&&norm(row.name)===name);
  const alternate=!!(name&&norm(row.name)===name&&
    (!key||row.origin_key===key));
  const source=id&&traitBenefitSources(row,record).has(id);
  const scope=key&&row.origin_key===key;
  const score=qualified?9:direct&&(!key||scope)?8:
    alternate?7:direct?6:
    source&&(!key||scope)?5:scope&&(!name||norm(row.name)===name)?4:
    source?3:0;
  return {row,score};
 }).filter(item=>item.score>0)
  .sort((a,b)=>b.score-a.score||b.row.rank-a.row.rank);
 return scored[0]?.row||null;
}

export function traitBenefitTargetLabel(value=''){
 const key=String(value);
 if(TARGETS[key])return TARGETS[key];
 const [type,...rest]=key.split(':'),name=rest.join(':');
 if(type==='passive_skill')return (SKILLS[name]||name)+' passiva';
 if(key==='ac_unarmored')return 'CA senza armatura';
 if(type==='attack_damage_base')return 'Danno base · '+(name==='unarmed'?'Colpo senz’armi':name);
 if(type==='skill')return 'Abilità · '+(SKILLS[name]||name);
 if(type==='ability_check')return 'Prova · '+(ABILITIES[name]||name);
 if(type==='casting_hit')return 'Attacco magico · '+(ABILITIES[name]||name);
 if(type==='save')return 'TS · '+(ABILITIES[name]||name);
 if(type==='ability')return 'Punteggio · '+(ABILITIES[name]||name);
 if(type==='ability_mod')return 'Modificatore · '+(ABILITIES[name]||name);
 if(type==='speed')return {climb:'Scalata',swim:'Nuoto',fly:'Volo',burrow:'Scavo'}[name]||key;
 if(type==='slot')return 'Slot livello '+name;
 if(type==='tracker')return 'Tracker · '+name;
 if(type==='attack_hit')return 'Tiro per colpire · '+name;
 if(type==='attack_damage')return 'Danni · '+name;
 if(type==='action_damage')return 'Danni azione · '+({'attack':'Azione di attacco','opportunity':'Attacco di opportunità','two_weapon':'Attacco con arma secondaria','spell_cast':'Lanciare un incantesimo','ability_checks':'Prova abilità'}[name]||name.replaceAll('_',' '));
 if(type==='attack_range')return 'Portata · '+name;
 return key;
}
function proficiencyLabel(key){
 const [kind,...parts]=String(key).split(':'),name=parts.join(':');
 return {skill:SKILLS[name]||name,expertise:SKILLS[name]||name,
  save:ABILITIES[name]||name,weapon:({'firearms':'Armi da fuoco','firearm':'Armi da fuoco'}[norm(name)]||name),armor:name,tool:name,language:name}[kind]||name;
}
const proficiencyKinds={skill:'Abilità',expertise:'Maestria',
 save:'Tiri salvezza',weapon:'Armi',attack:'Attacchi',armor:'Armature',tool:'Strumenti',language:'Lingue'};
const proficiencyOrder=['skill','expertise','save','weapon','attack','armor','tool','language'];
/** Returns ordered groups with {type,title,items:[{label,value}]}.
 * No grouping by guessed trait names: every grant must match an origin ID.
 */
export function traitBenefitGroups(trait={},record={},calculated={}){
 const ids=traitBenefitSources(trait,record),groups=new Map();
 const stateRule=rows(calculated.trait_state_catalog).find(rule=>
  trait.state_id&&rule.id===trait.state_id);
 // Typed owner bindings take precedence over their broad race/feat origin.
 // Never duplicate an explicitly owned resource on the overview card.
 const belongs=row=>{
  if(!row)return false;
  // For physical infusions the source is the specific item instance. Their
  // parent Infuse Item class feature grants the choice, not a second copy of
  // the applied benefits or the effect's description.
  if(row.target_kind==='item'&&String(row.origin_id||'').startsWith('infusion:'))
   return ids.has(row.origin_id);
  if(row.granting_trait){
   // Prefer the actual feature ID to avoid duplicate benefits on repeated
   // same-name traits; never fall back to the broad source when it exists.
   if(String(row.origin_id||'').startsWith('feature:'))
    return ids.has(row.origin_id);
   return norm(trait.name)===norm(row.granting_trait)&&
    (!row.origin_parent_name||
     norm(String(trait.origin||'').split(' · ').pop())===norm(row.origin_parent_name));
  }
  return [row.origin_id,row.parent_origin].some(id=>id&&ids.has(id))||
   Boolean(stateRule&&String(row.id||'').startsWith('trait_state:'+stateRule.id+':'));
 };
 const add=(type,title,label,value='',id='',extra={})=>{
  label=String(label??'').trim();value=String(value??'').trim();
  if(!label)return;
  if(!groups.has(type))groups.set(type,{type,title,items:[],seen:new Set()});
  const group=groups.get(type),key=label+'\u0000'+value;
  if(group.seen.has(key))return;
  group.seen.add(key);group.items.push({label,value,id,...extra});
 };
 // The same learn / prepare / apply model appears as a benefit of its owner.
 // Existing spellcasting detail rows and state capabilities remain unchanged.
 if(trait.rank!==0)for(const model of rows(calculated.power_selections)){
  if(!model.origin_id||!ids.has(model.origin_id))continue;
  for(const [stage,layer] of Object.entries(model.layers||{})){
   const label=({learned:'Imparati',prepared:'Preparati',applied:'Applicati'})[stage]||stage;
   const details=layer.used+(layer.limit!==null?' / '+layer.limit:'')+
    (layer.change_label?' · '+layer.change_label:'');
   add('power_selections','Selezione dei poteri',model.title+' · '+label,details);
  }
 }
 for(const sense of rows(calculated.senses?.grants)){
  if(!belongs(sense))continue;
  add('senses','Sensi',SENSE_NAMES[sense.type]||sense.type,
   senseRange(sense.range_feet),'sense:'+String(sense.id||''));
 }
 for(const waiver of rows(calculated.armor_strength_waivers)){
   if(waiver.scope!=='all'||!belongs(waiver))continue;
   add('effects','Effetti e limitazioni','Armature pesanti',
     'Ignora la penalità di velocità per Forza insufficiente','armor_waiver:'+waiver.id);
 }
 // Spellcasting/Pact Magic already owns class casting in the numeric projection.
 // Display that existing entitlement on its exact trait instead of copying
 // learned/prepared spells into automatic feature grants.
 if(trait.rank!==0)for(const member of rows(calculated.casting_classes)){
  if(!member.granting_trait_id||!ids.has(member.granting_trait_id))continue;
  const count=Number(member.limit);
  add('spellcasting','Lancio di incantesimi','Incantesimi di classe',
   member.mode==='Preparati'?
    'Preparazione'+(count>=0?' · massimo '+count:''):
    'Conosciuti'+(count>=0?' · '+count+' previsti dalla progressione':''));
  add('spellcasting','Lancio di incantesimi','Caratteristica da incantatore',
   ABILITIES[member.ability]||String(member.ability||'').toUpperCase());
  if(Number(member.cantrips)>0)
   add('spellcasting','Lancio di incantesimi','Trucchetti conosciuti',String(member.cantrips));
  if(Number(member.max_level)>0)
   add('spellcasting','Lancio di incantesimi','Livello massimo incantesimi',String(member.max_level));
  const ordinary=rows(calculated.spell_slots).filter(slot=>Number(slot.total)>0)
   .map(slot=>String(slot.level)+'°: '+Math.max(0,Number(slot.total)-Number(slot.spent||0))+'/'+slot.total);
  if(ordinary.length)
   add('spellcasting','Lancio di incantesimi','Slot condivisi',ordinary.join(' · '));
  const pact=calculated.pact_slots;
  if(pact&&Number(pact.total)>0)
   add('spellcasting','Lancio di incantesimi','Slot del Patto',
    Math.max(0,Number(pact.total)-Number(pact.spent||0))+'/'+pact.total+' · livello '+pact.level);
 }
 // An infused item's structured companion grant is displayed on that exact
 // object's benefit card. Mere knowledge of an infusion never grants a pet.
 if(trait.category==='oggetti'&&trait.rank===0){
  for(const index of rows(trait.item_inventory_indices)){
   const infused=rows(record.inventory)[index]?.infusion;
   if(!infused?.id)continue;
   const definition=rows(calculated.infusion_catalog).find(row=>row.id===infused.id);
   if(!definition?.companion?.rule_id)continue;
   add('companions','Sottocreature','Creatura concessa',definition.name,
    'companion:'+String(definition.companion.rule_id));
  }
 }
 for(const grant of rows(calculated.feature_item_grants)){
  if(!ids.has(grant.origin_id))continue;
  if(Number(grant.infusion_capacity_bonus)>0)
   add('effects','Effetti e limitazioni','Oggetti infusi attivi','+'+grant.infusion_capacity_bonus+' (non aumenta le infusioni conosciute)');
  const total=rows(record.inventory).filter(item=>item.feature_item_grant_id===grant.id&&Number(item.quantity??1)>0).length;
  for(const option of rows(grant.items)){
   const capacity=Number(grant.max_owned)||0;
   const canDuplicate=!!grant.allow_duplicate_choices&&capacity>1;
   const available=(!option.owned||canDuplicate&&Number(option.owned)<capacity)&&
    (!capacity||total<capacity||grant.replace_existing&&capacity===1);
   add('items','Oggetti concessi',option.name,
    (option.owned?'Posseduto'+(option.owned>1?' ×'+option.owned:'')+' · ':'')+
    (option.description||'Da aggiungere'),'',{
    grant_id:grant.id,option_id:option.id,owned:!!option.owned,available,
    requires_activation:!!grant.activation_action_id});
  }
 }
 // A chosen feat is an owned trait whose granting class-level ASI remains
 // inspectable as the origin. Do not manufacture a second copy of its bonuses.
 for(const feat of rows(record.feats_catalog)){
  if(!feat?.granted_by||!ids.has(feat.granted_by)||feat.disabled)continue;
  add('feats','Talenti concessi',feat.name,String(feat.source||''),
    'feat:'+String(feat.id||'')); 
 }
 // A replacement or score floor is a non-additive benefit; show the exact
 // source and formula on its owning trait, not as a numeric bonus.
 for(const rule of rows(calculated.base_value_overrides)){
  if(!belongs(rule))continue;
  const operation={replace:'Sostituisce',minimum:'Valore minimo',alternative:'Formula alternativa'}[rule.mode]||rule.mode;
  add('base_overrides','Sostituzioni dei valori base',traitBenefitTargetLabel(rule.target),
   operation+' · '+rule.expression,'base_override:'+String(rule.id||''));
 }
 // Attack-count grants are non-additive benefits owned by individual traits.
 const attackGrants=Array.isArray(calculated.attack_count_benefits)?
   calculated.attack_count_benefits:attackCountBenefits(record,calculated.features);
 for(const grant of attackGrants){
  if(!belongs(grant))continue;
  const routine=trait.category==='mostro'&&trait.monster_role==='multiattack';
  if(!routine)add('attack_count','Attacchi per azione','Attacchi disponibili',
   '×'+grant.attacks_per_action,'attack_count:'+grant.id);
 }
 for(const grant of rows(calculated.attack_actions)){
  if(!belongs(grant))continue;
  const steps=rows(grant.steps).map(step=>Number(step.count||1)+' × '+
   (step.selector?.name||step.selector?.category||'Attacco a scelta')).join(' → ');
  add('attack_actions','Azioni di attacco',grant.name,
   (grant.time||'action')+(grant.cost?' · '+grant.cost+' · '+(grant.tracker||grant.tracker_id):'')+
   ' · '+steps,'attack_action:'+grant.id);
 }
 // Exhaustion has one virtual state trait, backed by structured rules rather
 // than a generated prose-only entry. All cumulative tier effects belong here.
 const exhaustionLevel=Number(String(trait.condition_id||'').match(/^exhaustion:([1-6])$/)?.[1]||0);
 if(exhaustionLevel)for(const rule of rows(calculated.exhaustion_effects)){
  if(Number(rule.level)!==exhaustionLevel)continue;
  const label=rule.label||traitBenefitTargetLabel(rule.target||rule.targets?.[0]||'');
  const source='exhaustion:'+exhaustionLevel+':'+rule.type+':'+rule.min_level+':'+(rule.target||rule.operation||'');
  if(rule.type==='roll_mode')
   add('roll_modes','Vantaggi e svantaggi',label,
    rule.mode==='advantage'?'Vantaggio':'Svantaggio',source);
  else if(rule.type==='roll_modifier'){
   const amount=(Number(rule.per_level)||0)*exhaustionLevel;
   add('bonus','Bonus',label,(amount>=0?'+':'')+amount,source);
  }else if(rule.type==='value'){
   const amount=Number(rule.per_level)*exhaustionLevel;
   const value=rule.operation==='add'&&Number.isFinite(amount)?
     (amount>=0?'+':'')+amount+' ft':String(rule.detail||'Effetto attivo');
   add('effects','Effetti e limitazioni',label,value,source);
  }else if(rule.type==='condition')
   add('effects','Effetti e limitazioni',label,rule.detail||'Condizione attiva',source);
 }
 // Passive species rules belong to their 5etools trait. Show reminders
 // without manufacturing an action or an expendable tracker.
 for(const note of rows(calculated.racial_passive_notes)){
   if(!belongs(note))continue;
   add('effects','Effetti e limitazioni',note.name||note.trait,
     note.description||'',String(note.id||'racial-passive'));
 }
 // Passive, manually selected proficiency multipliers have no always-on
 // numeric grant. Display their condition on the exact granting trait.
 for(const rule of rows(calculated.roll_bonus_rules)){
  if(!rule?.passive||!rule?.bonus)continue;
  const feature=rows(calculated.features).find(row=>!row.disabled&&
   norm(row.name)===norm(rule.feature_name)&&
   classOf(row)===norm(rule.class_name)&&
   (!rule.class_source||sourceOf(row)===norm(rule.class_source))&&
   (!rule.subclass_name||String(row.origin_key||'').includes('|subclass|')));
  if(!feature)continue;
  let owner=feature.origin_id;
  if(rule.required_optional_feature){
   const option=rows(record.optional_features_catalog).find(row=>!row.disabled&&
    norm(row.name)===norm(rule.required_optional_feature)&&
    (!rule.optional_source||norm(row.source)===norm(rule.optional_source)));
   if(!option)continue;
   owner=option.origin_id||'optional|'+norm(option.source)+'|'+norm(option.name);
  }
  if(!ids.has(owner))continue;
  const mode=rule.bonus.proficiency_mode||'';
  const value=mode==='tool_expertise'?'Competenza ×2':
   mode==='favored_terrain_expertise'?'Competenza ×2':
   mode==='untrained_half_physical'?'½ competenza (arrotondata per eccesso)':'½ competenza (arrotondata per difetto)';
  add('bonus','Bonus applicabili al tiro',rule.bonus.name||feature.name,
   value+' · '+String(rule.bonus.condition_label||'Applica quando previsto dal privilegio'),
   'passive_class:'+rule.id);
 }
 // Conditional class roll options use the same generic typed rule as the
 // roll popup. Their condition is a manual choice, never an assumed state.
 for(const rule of rows(calculated.roll_bonus_rules)){
  if(rule.passive||!rule.bonus?.targets?.length)continue;
  const feature=rows(calculated.features).find(row=>norm(row.name)===norm(rule.feature_name)&&
   classOf(row)===norm(rule.class_name)&&
   (!rule.class_source||sourceOf(row)===norm(rule.class_source))&&
   (!rule.subclass_name||String(row.origin_key||'').includes('|subclass|')));
  if(!feature||!ids.has(feature.origin_id))continue;
  const condition=String(rule.bonus.condition_label||'Da verificare');
  const value=rule.bonus.roll_mode?
   (rule.bonus.roll_mode==='advantage'?'Vantaggio':'Svantaggio'):
   rule.bonus.ability_modifier?'Mod. '+(ABILITIES[rule.bonus.ability_modifier]||rule.bonus.ability_modifier):
   Number.isFinite(Number(rule.bonus.flat_bonus))?signedTraitFormula(rule.bonus.flat_bonus):
   String(rule.bonus.dice||'');
  add(rule.bonus.roll_mode?'roll_modes':'bonus',
   rule.bonus.roll_mode?'Vantaggi e svantaggi':'Bonus applicabili al tiro',
   rule.bonus.name||feature.name,value+' · '+condition);
 }
 const bonusSeen=new Set();
 const multipliers=new Map(Object.values(calculated.roll_components||{}).flat().map(row=>[row.id,row.multiplier]));
 for(const row of [...rows(calculated.bonuses),...rows(calculated.automatic_bonuses)]){
  if(!belongs(row))continue;
  const id=String(row.id||'');
  if(id&&bonusSeen.has(id))continue;
  if(id)bonusSeen.add(id);
  add('bonus','Bonus',traitBenefitTargetLabel(row.target),
   signedTraitFormula(row.dice_notation||row.expression)+(row.dice_notation?' → '+signedTraitFormula(row.expression):'')+
   (Number(row.multiplier??multipliers.get(row.id))>1?' ×'+Number(row.multiplier??multipliers.get(row.id)):'')+
   (row.disabled?' · Disattivato':''),'bonus:'+String(row.id||''));
 }
 for(const row of [...rows(record.dice_bonuses),...rows(calculated.racial_roll_bonuses)]){
  if(row.disabled||!belongs(row))continue;
  const copies=trait.category==='oggetti'&&trait.rank===0?trait.item_active_quantity:1;
  add('bonus','Bonus',rows(row.targets).length?rows(row.targets).map(traitBenefitTargetLabel).join(' · '):traitBenefitTargetLabel(row.target),
   (row.proficiency_multiplier?'Competenza ×'+row.proficiency_multiplier+' (contestuale)':
     row.flat_proficiency?'Bonus di competenza'+(row.damage_type?' · '+damageLabel(row.damage_type):''):
     row.weapon_damage_die?'1 dado danno dell’arma':
     Object.hasOwn(row,'flat_bonus')?signedTraitFormula(String(row.flat_bonus)):signedTraitFormula(row.dice))+
   (row.condition_label?' · '+row.condition_label:'')+(copies>1?' ×'+copies:''),
   'dice:'+String(row.id||[row.origin_id,row.target,row.dice].join('|')));
 }
 // An attack is a benefit in its own right; bonuses to an attack are
 // separate numeric benefits and must not be confused with the granted attack.
 const stateAttackIds=new Set(rows(stateRule?.attacks).map(attack=>String(attack.id)));
 for(const attack of rows(calculated.attacks)){
  const itemId=String(trait.item_id||trait.origin_key||'').replace(/^item:/,'');
  const fromItem=trait.category==='oggetti'&&trait.rank===0&&
   String(trait.origin_key||'').startsWith('item:')&&
   (String(attack.id||'').startsWith('item:'+itemId)||
    String(attack.id||'').includes(':'+itemId));
  if(!belongs(attack)&&!stateAttackIds.has(String(attack.id))&&!fromItem&&!rows(trait.monster_attack_ids).includes(attack.id))continue;
  const details=[attack.damage&&String(attack.damage)+' '+String(attack.damage_type||''),
   attackRangeLabel(attack)].filter(Boolean).join(' · ');
  add('attacks','Attacchi concessi',attack.name,details,'attack:'+String(attack.id||''));
 }
 // Equipping armor or a shield supplies AC even when no numeric bonus row
 // exists: their base/bonus is stored on the owned item, not on a trait formula.
 if(trait.category==='oggetti'&&trait.rank===0){
  for(const saved of rows(record.inventory)){
   const item=resolveOwnedItem(saved);
   if(trait.item_id?trait.item_id!==String(item.id||saved.id||'')||
      rows(trait.item_inventory_indices).length&&
      !rows(trait.item_inventory_indices).includes(rows(record.inventory).indexOf(saved)):
      trait.origin_key!=='item:'+String(item.id||saved.id||''))continue;
   const slots=rows(item.equipped_slots);
   const kind=String(item.type||'').split('|')[0].toUpperCase();
   const amount=Number(item.ac);
   if(!Number.isFinite(amount)||!amount)continue;
   if(kind==='S'&&(slots.includes('off')||slots.includes('main')))
    add('armor_class','Classe armatura','Scudo','+'+amount+' CA','armor:'+String(item.id||''));
   else if(['LA','MA','HA'].includes(kind)&&slots.includes('body'))
    add('armor_class','Classe armatura','Armatura','CA base '+amount,'armor:'+String(item.id||''));
  }
 }
 // Reuse the very sources used to resolve actual rolls, so active class
 // privileges and data-defined roll modes share the same provenance.
 const rollTargets=['ability_check:str','save:str','save:dex','initiative',
  ...rows(calculated.attacks).map(attack=>'attack_hit:'+attack.id),
  ...rows(calculated.casting_classes).map(c=>'casting_hit:'+c.ability)];
 for(const target of [...new Set(rollTargets)]){
  for(const source of classFeatureRollSources(record,calculated,target)){
   if(String(source.origin_id||'').startsWith('feature:trait:'))continue;
   if(exhaustionLevel&&source.condition_id===trait.condition_id)continue; // One rule row per scope
   if(!(source.origin_id&&ids.has(source.origin_id))&&
    !(source.kind==='condition'&&trait.condition_id===source.condition_id))continue;
   // A structured roll-mode benefit already describes this scope once.
   // Avoid repeating it for every attack using the same mode.
   const explicit=rows(calculated.features).find(feature=>feature.origin_id===source.origin_id);
   if(rows(explicit?.roll_modes).some(rule=>rule.mode===source.mode&&
     (rows(rule.targets).length?rule.targets:[rule.target]).some(scope=>
      scope===target||
      scope==='attack_roll'&&target.startsWith('attack_hit:')||
      scope==='saving_throw'&&target.startsWith('save:')||
      scope==='ability_check'&&(target.startsWith('ability_check:')||target==='initiative')||
      scope==='spell_attack'&&target.startsWith('casting_hit:'))))continue;
   add('roll_modes','Vantaggi e svantaggi',traitBenefitTargetLabel(target),
    source.mode==='advantage'?'Vantaggio':'Svantaggio','roll_mode:'+source.origin_id+':'+source.mode+':'+target);
  }
 }
 for(const rule of rows(calculated.trait_state_roll_modes)){
  if(!belongs(rule))continue;
  add('roll_modes','Vantaggi e svantaggi',traitBenefitTargetLabel(rule.target),
   rule.mode==='advantage'?'Vantaggio':'Svantaggio','roll_mode:'+rule.origin_id+':'+rule.mode+':'+rule.target);
 }
 for(const feature of rows(calculated.features)){
  if(feature.disabled||!ids.has(feature.origin_id))continue;
  for(const rule of rows(feature.roll_modes)){
   if(!['advantage','disadvantage'].includes(rule?.mode))continue;
   for(const target of (rows(rule.targets).length?rule.targets:[rule.target])){
    if(!target)continue;
    add('roll_modes','Vantaggi e svantaggi',traitBenefitTargetLabel(target),
     rule.mode==='advantage'?'Vantaggio':'Svantaggio',
     'roll_mode:'+feature.origin_id+':'+rule.mode+':'+target);
   }
  }
 }

 // Source-qualified racial advantages and disadvantages retain their
 // precise condition_label on the owning trait, including suppressed
 // sunlight sensitivity and conditional charm/fright saves.
 for(const rule of rows(calculated.racial_roll_modes)){
  if(!belongs(rule)||!['advantage','disadvantage'].includes(rule.mode))continue;
  const label=traitBenefitTargetLabel(rule.target);
  const condition=rule.condition_label?' · '+rule.condition_label:' · Sempre';
  add('roll_modes','Vantaggi e svantaggi',label,
   (rule.mode==='advantage'?'Vantaggio':'Svantaggio')+condition,
   rule.benefit_id||rule.id);
 }
 // Contextual, source-qualified feat advantages are separate from ordinary
 // Constitution saving throws and stay visible on the granting feat card.
 for(const rule of rows(calculated.feat_roll_modes)){
  if(!belongs(rule)||!['advantage','disadvantage'].includes(rule.mode))continue;
  const context=rule.context==='concentration_damage'?' · concentrazione':'';
  add('roll_modes','Vantaggi e svantaggi',traitBenefitTargetLabel(rule.target)+context,
   (rule.mode==='advantage'?'Vantaggio':'Svantaggio')+
     (rule.condition_label?' · '+rule.condition_label:''),
   'roll_mode:'+rule.origin_id+':'+rule.mode+':'+rule.target+':'+
     (rule.context||'')+':'+(rule.condition_label||''));
 }
 for(const rule of rows(calculated.feat_roll_bonuses)){
  if(!belongs(rule)||rule.flat_bonus!=='equipped_shield_ac'&&
    !Number.isFinite(Number(rule.flat_bonus)))continue;
  const amount=rule.flat_bonus==='equipped_shield_ac'?'Bonus CA dello scudo':
    signedTraitFormula(rule.flat_bonus);
  add('bonus','Bonus applicabili al tiro',traitBenefitTargetLabel(rule.target),
   amount+(rule.condition_label?' · '+rule.condition_label:''),
   'feat_bonus:'+rule.origin_id+':'+rule.target+':'+(rule.condition_label||''));
 }
 // Typed movement costs remain attributable to the exact feat, not to
 // every species or character that happens to have the resulting speed.
 for(const rule of rows(calculated.feat_movement_rules)){
  if(!belongs(rule))continue;
  if(rule.mode==='climb_at_walking_cost')
    add('bonus','Movimento','Scalata','Nessun costo aggiuntivo: puoi usare la velocità di camminata.',
      'feat_movement:'+rule.origin_id+':'+rule.mode);
 }
 // Reusable d20 rerolls remain visible on the trait that owns them.
 for(const rule of rows(calculated.feat_d20_rerolls)){
  if(!belongs(rule))continue;
  const targets=rows(rule.targets).map(traitBenefitTargetLabel).join(' · ')||'Qualunque d20';
  add('d20_rerolls','Ritiri del d20',targets,
   (rule.trigger==='on_one'?'Quando esce 1':'Dopo il tiro')+
    (rule.tracker_id?' · '+(rows(calculated.trackers).find(t=>t.id===rule.tracker_id)?.name||'Risorsa'): ' · gratuito'),
   'd20_reroll:'+String(rule.id||''));
 }
 // User-authored mode grants carry the same stable source as other trait bonuses.
 for(const row of rows(record.roll_mode_grants)){
  if(row.disabled||!belongs(row)||!['advantage','disadvantage'].includes(row.mode))continue;
  add('roll_modes','Vantaggi e svantaggi',traitBenefitTargetLabel(row.target),
   row.mode==='advantage'?'Vantaggio':'Svantaggio','roll_mode:'+String(row.id||''));
 }
 for(const featureName of rows(stateRule?.granted_features)){
  add('granted_features','Privilegi concessi',featureName,
   'Disponibile durante questo stato');
 }
 // One Competenze section: each filled row has the proficiency *type* at
 // left (where a numeric bonus has its target) and its value on the right.
 // Stable kind/name sorting keeps expertise and language rows easy to scan.
 const proficiencies=Object.entries(calculated.proficiency_sources||{})
  .filter(([,sources])=>rows(sources).some(source=>source?.id&&ids.has(source.id)))
  .flatMap(([key,sources])=>rows(sources).filter(source=>source?.id&&ids.has(source.id)).map(source=>({
   kind:key.split(':')[0],name:proficiencyLabel(key),
   originId:source.origin_parent_id||source.id,key
  })))
  .sort((a,b)=>{
   const ai=proficiencyOrder.indexOf(a.kind),bi=proficiencyOrder.indexOf(b.kind);
   return (ai<0?100:ai)-(bi<0?100:bi)||
    a.name.localeCompare(b.name,'it',{sensitivity:'base',numeric:true});
  });
 for(const item of proficiencies)
  add('proficiency','Competenze',proficiencyKinds[item.kind]||'Altre competenze',item.name,'proficiency:'+item.originId+':'+item.kind+':'+norm(item.key.split(':').slice(1).join(':')));
 // One section for all defenses and vulnerabilities, with the kind in the
 // left-hand column and the protected/affected damage or condition on the right.
 const defenseKinds={
  1:['Resistenza',0],2:['Immunità ai danni',1],
  3:['Immunità alle condizioni',2],[-1]:['Vulnerabilità',3]
 };
 const defenses=rows(calculated.damage_defense_entries??record.damage_defense_entries)
  .filter(row=>!row.disabled&&belongs(row)&&defenseKinds[Number(row.rank)])
  .map(row=>({
   label:defenseKinds[Number(row.rank)][0],
   order:defenseKinds[Number(row.rank)][1],
   value:((Number(row.rank)===3?DEFENSE_CONDITIONS:DAMAGE)[norm(row.key)]||String(row.key||''))+
    (row.condition_label?' · '+row.condition_label:''),id:row.benefit_id||'defense:'+String(row.origin_id||'')+':'+row.rank+':'+norm(row.key)
  }))
  .sort((a,b)=>a.order-b.order||a.value.localeCompare(b.value,'it',{sensitivity:'base'}));
 for(const row of defenses)
  add('defenses','Resistenze, immunità e vulnerabilità',row.label,row.value,row.id);
 for(const modifier of rows(calculated.incoming_damage_modifiers)){
  if(!belongs(modifier))continue;
  const type=modifier.damage_type?' · '+(DAMAGE[norm(modifier.damage_type)]||modifier.damage_type):' · Tutti i danni';
  const mode=modifier.optional?'Utilizzabile':'Permanente';
  const cost=modifier.tracker_id?' · Tracker '+modifier.tracker_id+' (−'+(modifier.tracker_cost||1)+')':'';
  add('incoming_damage','Modificatori ai danni subiti',
   'Danni subiti',modifier.expression+type+' · '+mode+cost,
   'incoming_damage:'+modifier.id);
 }

 for(const row of rows(calculated.trackers)){
  if(!belongs(row)&&!rows(trait.monster_tracker_ids).includes(row.id)){
   // Unattributed automatic class pools are shown only in the class overview,
   // never against an unrelated individual class feature.
   if(!(trait.rank===0&&trait.category==='classi'&&
     !row.origin_id?.startsWith('feature:')&&row.origin_class&&
     ids.has('class|'+norm(row.origin_class_source)+'|'+norm(row.origin_class))))continue;
  }
  const maximum=Number(row.max);
  const suffix=Number.isFinite(maximum)?String(maximum):'';
  const reset=RECOVERY[row.recharge]||'';
  add('resources','Risorse e tracker',row.name,(suffix?('Max '+suffix):'')+(reset?((suffix?' · ':'')+reset):''),'tracker:'+String(row.id||''));
 }
 for(const spell of rows(trait.granted_spells))
  add('spells','Incantesimi concessi',spell.name,spell.level===0?'Trucchetto':
    Number.isInteger(spell.level)?'Livello '+spell.level:'','spell:'+String(spell.origin_id||'')+':'+String(spell.id||''));
 for(const extension of rows(calculated.effect_extensions)){
  // Item-targeted effects belong only to the physical copy represented by
  // this card. A separate Rod with the same catalog ID cannot inherit them.
  const indices=rows(trait.item_inventory_indices).length?
    trait.item_inventory_indices:rows(record.inventory).map((_,index)=>index);
  const onItem=trait.category==='oggetti'&&trait.rank===0&&
   extension.target_kind==='item'&&indices.some(index=>{
    const item=rows(record.inventory)[index];
    return item&&String(trait.item_id||String(trait.origin_key||'').replace(/^item:/,''))===String(item.id||'')&&
     effectExtensionsFor([extension],{kind:'item',id:item.id,name:item.name,
      instance_id:item.instance_id,inventory_index:index}).length>0;
   });
  if(!belongs(extension)&&!onItem)continue;
  const target=(extension.target_kind==='spell'?'Incantesimo':
   extension.target_kind==='item'?'Oggetto':'Capacità')+' · '+(extension.target_name||extension.target_id);
  add('effect_extensions','Estensioni degli effetti',target,
   effectExtensionLabel(extension,{cha_mod:calculated.abilities?.cha?.modifier}),
   belongs(extension)?'effect_extension:'+String(extension.id||''):'');
 }
 for(const action of rows(record.action_grants)){
  if(action.disabled||!belongs(action))continue;
  add('actions','Azioni concesse',action.name||action.label||action.id,
   String(action.action_type||action.time||''),'action:'+String(action.id||[action.origin_id,action.name].join('|')));
 }
 // Always display declared activations on the granting trait, not only
 // those currently projected as usable battle actions. Passive source traits
 // remain separate and class-overview cards cannot claim child privileges.
 // Class/species overview cards must not claim their child features.
 // A concrete trait can be rank zero (e.g. a feat or item), though.
 const ownFeatureIds=new Set([trait.feature_origin,'feature:trait:'+String(trait.key||'')].filter(Boolean));
 const ownerFeatures=rows(calculated.features).filter(feature=>
  feature?.origin_id&&ownFeatureIds.has(feature.origin_id));
 const previewOwned=trait.rank!==0||!['classi','razza','background'].includes(trait.category);
 const noLongerAvailable=id=>id&&(record.origin_enabled?.[id]===false||
   rows(record.proficiency_origins).some(row=>row.id===id&&row.disabled));
 const inactiveSource=feature=>trait.inactive||feature?.inactive||feature?.disabled||
   noLongerAvailable(feature?.origin_id)||noLongerAvailable(feature?.origin_key);
 const abilitySourceIds=new Set();
 const actionResource=name=>rows(calculated.trackers).find(t=>norm(t.name)===norm(name));
 const resourceCost=(name,count=1)=>{
  if(!name||!Number(count))return 'Nessun costo';
  return Number(count)+' '+(Number(count)===1?'utilizzo':'utilizzi')+' · '+name;
 };
 const statusFor=(feature,resourceName='',active=false)=>{
  if(inactiveSource(feature))return 'Tratto disattivato';
  if(active)return 'Attiva';
  const tracker=actionResource(resourceName);
  if(tracker&&Number(tracker.max)-Number(tracker.spent||0)<=0)return 'Risorsa esaurita';
  return 'Attivabile';
 };
 const abilityNames=new Set();
 const addAbility=(label,details)=>{
  const key=norm(label);
  if(abilityNames.has(key))return;
  abilityNames.add(key);
  add('abilities','Capacità attivabili',label,'','',{
   status:details.status,timing:details.timing,cost:details.cost,
   description:details.description,requirements:details.requirements||'',
   options:details.options||[],
   effects:details.effects||[]
  });
  if(details.origin_id)abilitySourceIds.add(String(details.origin_id));
 };
 const declaredMonsterActions=new Set(rows(trait.monster_actions).map(row=>row.id));
 for(const action of monsterActions(record,calculated.trackers).filter(row=>declaredMonsterActions.has(row.parent_action_id||row.id))){
  const tracker=rows(calculated.trackers).find(t=>t.id===action.tracker_id);
  addAbility(action.name,{origin_id:action.origin_id,status:trait.inactive?'Tratto disattivato':tracker&&Number(tracker.max)-Number(tracker.spent||0)<action.cost?'Risorsa esaurita':'Promemoria',
   timing:actionTime(action.time),cost:resourceCost(tracker?.name||action.tracker_id,action.cost),description:action.description,options:action.options,effects:[]});
 }
 // Non-class feats can declare actions via the same typed benefits schema.
 for(const action of rows(calculated.feat_actions)){
  if(!belongs(action))continue;
  addAbility(action.name,{
   origin_id:action.origin_id,status:trait.inactive?'Tratto disattivato':
     action.descriptive_only?'Promemoria':'Attivabile',
   timing:actionTime(action.action_type||action.time),
   cost:action.descriptive_only?'Nessun utilizzo in app':
     Number(action.resource_cost)>0?String(action.resource_cost)+' utilizzi':'Nessun costo',
   description:describe(action.description),effects:[]
  });
 }
 for(const rule of rows(calculated.trait_state_catalog)){
  const owner=ownerFeatures.find(feature=>norm(feature.name)===norm(rule.trait)&&
   classOf(feature)===norm(rule.class_name)&&
   (!rule.class_source||sourceOf(feature)===norm(rule.class_source)));
  if(!owner)continue;
  const action=rows(calculated.state_actions).find(row=>row.state_id===rule.id);
  const blocked=trait.inactive||owner.disabled||owner.inactive;
  const kinds=rows(rule.require_equipped?.kinds).map(kind=>({armor:'armatura',shield:'scudo'}[kind]||kind));
  const condition=rule.require_equipped?
   (kinds.join(' / ')||'Equipaggiamento')+' equipaggiata'+
     (rule.require_equipped.slot==='body'?' sul corpo':' nello slot '+rule.require_equipped.slot):'';
  const exclusive=rule.group?'Un solo modello attivo per gruppo':'';
  addAbility(rule.name,{
   status:action?.active?'Attiva':blocked?'Tratto disattivato':action?'Attivabile':'Requisiti mancanti',
   timing:actionTime(action?.time||rule.time||'free'),cost:'Nessun costo',
   description:rule.summary||'',
   requirements:[condition,exclusive].filter(Boolean).join(' · '),
   effects:abilityDetails(rule)
  });
 }
 for(const ability of contextualFeatureDescriptors(record,calculated.features,
   calculated.feature_rules,calculated.values?.proficiency)){
  if(!ownFeatureIds.has(ability.origin_id))continue;
  const resource=ability.resource_tracker?.name||'';
  addAbility(ability.name,{
   origin_id:ability.origin_id,
   status:trait.inactive||!ability.available?'Tratto disattivato':statusFor(null,resource),
   timing:actionTime(ability.action_type),cost:resourceCost(resource,ability.tracker_cost),
   description:describe(ability.description),effects:[]
  });
 }
 // Data-driven feature actions, including unavailable choices. Read from the
 // same structured timing catalog as the native action economy; these entries
 // remain tied to an exact class feature rather than the whole class.
 for(const rule of rows(calculated.feature_rules?.actions)){
  if(!rule.feature||!rule.name)continue;
  const memberKey='class|'+norm(rule.class_source)+'|'+norm(rule.class_name);
  const feature=ownerFeatures.find(f=>norm(f.name)===norm(rule.feature)&&
   (norm(f.origin_key)===memberKey||norm(f.origin_key).startsWith(memberKey+'|'))&&
   (!rule.subclass||norm(f.origin_key).includes('|subclass|')&&
    norm(f.origin_key).split('|').slice(4,5).some(sub=>
      norm(sub).replace(/^(circle of |the )/,'')===norm(rule.subclass).replace(/^(circle of |the )/,''))));
  if(!feature)continue;
  const tracker=actionResource(rule.tracker_name);
  const resource=tracker?.name||rule.tracker_name||'';
  addAbility(rule.name,{
   origin_id:feature.origin_id,status:statusFor(feature,resource),
   timing:actionTime(rule.activation),cost:resourceCost(resource,resource?1:0),
   description:describe(rule.detail||feature.entries||feature.description),
   requirements:rule.subclass?'Sottoclasse · '+rule.subclass:'',
   effects:[]
  });
 }
 for(const ability of classFeatureDescriptors(record,calculated)){
  if(!ownFeatureIds.has(ability.origin_id))continue;
  addAbility(ability.name,{
   origin_id:ability.origin_id,status:trait.inactive||ability.unavailable_reason==='disabled'?'Tratto disattivato':
    ability.unavailable_reason==='state'?'Modello richiesto':ability.active?'Attiva':'Attivabile',
   timing:actionTime(ability.time),cost:resourceCost(ability.resource_name,ability.cost),
   description:describe(ability.description),
   requirements:ability.required_states.length?'Richiede '+ability.required_states.map(rule=>rule.name).join(' / '):'',
   effects:[]
  });
 }
 // Features with explicit activation metadata work across classes, feats,
 // species, backgrounds, monster traits and other structured origins. Only
 // actual activation fields qualify: a descriptive/passive trait is not a power.
 if(previewOwned)for(const source of ownerFeatures){
  const activation=source.action_type||source.activation_type||source.activation||source.time;
  const kind=String(source.action_kind||'').toLowerCase();
  if(!activation||['passive','permanent','none'].includes(norm(activation))||
    kind==='passive')continue;
  if(abilitySourceIds.has(String(source.origin_id)))continue;
  const tracker=rows(calculated.trackers).find(row=>
   row.origin_id===source.origin_id||norm(row.name)===norm(source.resource_name||source.tracker_name));
  const resource=tracker?.name||source.resource_name||source.tracker_name||'';
  addAbility(source.name,{
   origin_id:source.origin_id,status:statusFor(source,resource,
    !!record.active_class_features?.[source.id||source.key]),
   timing:actionTime(activation),cost:resourceCost(resource,resource?1:0),
   description:describe(source.entries||source.description),
   requirements:describe(source.activation_requirements||source.prerequisite||''),
   effects:[]
  });
 }
 // A trait may have a catalog activation but no structured effect record
 // (e.g. an item or the top-level feat itself). Preserve its own action data.
 if(previewOwned&&!ownerFeatures.length){
  const activation=trait.action_type||trait.activation_type||trait.activation;
  if(activation&&!['passive','permanent','none'].includes(norm(activation))){
   addAbility(trait.name,{status:trait.inactive?'Tratto disattivato':'Attivabile',
    timing:actionTime(activation),cost:resourceCost(trait.resource_name,trait.resource_name?1:0),
    description:describe(trait.entries),effects:[]});
  }
 }
 // Manually granted actions remain readable even when explicitly disabled.
 // They retain their separate editable "Azioni concesse" list above.
 for(const action of rows(record.action_grants)){
  if(!previewOwned||!belongs(action))continue;
  const resource=action.resource_name||action.tracker_name||
   rows(calculated.trackers).find(t=>t.id===action.tracker_id)?.name||'';
  addAbility(action.name||action.label||action.id,{
   status:trait.inactive||action.disabled?'Tratto disattivato':statusFor(null,resource),
   timing:actionTime(action.action_type||action.time),
   cost:resourceCost(resource,action.tracker_cost??(resource?1:0)),
   description:describe(action.description||action.detail),
   requirements:describe(action.requirements),
   effects:[]
  });
 }
 for(const effect of rows(calculated.activatable_abilities)){
  if(!effect?.name||!previewOwned||!ids.has(effect.origin_id))continue;
  const source=ownerFeatures.find(f=>f.origin_id===effect.origin_id);
  // The manifest can represent the same activation as a native rule under
  // another label (e.g. Rage / Ira). Keep the richer native row only.
  if(abilitySourceIds.has(String(effect.origin_id))&&source)continue;
  addAbility(effect.name,{
   status:effect.unavailable||inactiveSource(source)?'Tratto disattivato':
    statusFor(source,effect.resource_name||effect.tracker_name,
      !!record.active_class_features?.[effect.id]),
   timing:actionTime(effect.action_type||effect.activation_mode),
   cost:resourceCost(effect.resource_name||effect.tracker_name||'',effect.resource_cost??0),
   description:describe(effect.description),requirements:describe(effect.requirements?.note||effect.requirements?.description||''),
   effects:[]
  });
 }
 for(const effect of rows(calculated.active_feature_effects)){
  if(!effect.effective||!belongs(effect))continue;
  add('effects','Effetti attivi',effect.name||'Capacità',effect.summary||'Attivo','effect:'+String(effect.id||[effect.origin_id,effect.name].join('|')));
 }
 const removed=new Set(rows(record.trait_benefit_removed?.[trait.key]));
 return [...groups.values()].map(({type,title,items})=>({type,title,items:items.filter(item=>!removed.has(item.id))})).filter(group=>group.items.length);
}
