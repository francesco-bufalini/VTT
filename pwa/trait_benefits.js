// Read-only, source-bound summaries for the PWA's trait cards.
// Use structured grants only; never extract mechanics from free-form descriptions.
import {CLASS_FEATURE_RULES,classFeatureRollSources} from './feature_mechanics.js';
import {resolveOwnedItem} from './item_controls.js';
import {attackCountBenefits} from './attack_count_benefits.js';
import {effectExtensionLabel,effectExtensionsFor} from './effect_extensions.js';
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
 lightning:'Fulmine',necrotic:'Necrotici',piercing:'Perforanti',poison:'Veleno',
 psychic:'Psichici',radiant:'Radianti',slashing:'Taglienti',thunder:'Tuono'
};
const ACTION_TIMES={action:'Azione',bonus:'Azione bonus',reaction:'Reazione',free:'Azione gratuita',movement:'Movimento',contextual:'Contestuale'};
const actionTime=value=>ACTION_TIMES[norm(typeof value==='object'?value?.unit||value?.type:value)]||String(value||'Contestuale');
const describe=value=>typeof value==='string'?value:Array.isArray(value)?value.map(describe).filter(Boolean).join(' · '):
 value&&typeof value==='object'?describe(value.entries??value.entry??value.description??value.text??''):'';
const classOf=feature=>norm(feature?.requirements?.class_name||feature?.class_name||String(feature?.origin_key||'').split('|')[2]);
const sourceOf=feature=>norm(feature?.requirements?.class_source||feature?.class_source||String(feature?.origin_key||'').split('|')[1]);
const damageLabel=type=>DAMAGE[norm(type)]||({T:'Tuono',L:'Fulmine'}[type]||String(type||''));
const abilityDetails=rule=>{
 const items=[];
 for(const attack of rows(rule.attacks)){
  const reach=attack.melee?'Portata ':'Gittata ';
  items.push('Attacco · '+attack.name+' · '+attack.damage+' '+damageLabel(attack.damage_type)+
   ' · '+reach+attack.range_feet+(attack.long_range_feet?'/'+attack.long_range_feet:'')+' ft');
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
 const ids=new Set([trait.feature_origin,trait.proficiency_origin,
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
 if(type==='attack_range')return 'Portata · '+name;
 return key;
}
function proficiencyLabel(key){
 const [kind,...parts]=String(key).split(':'),name=parts.join(':');
 return {skill:SKILLS[name]||name,expertise:SKILLS[name]||name,
  save:ABILITIES[name]||name,weapon:({'firearms':'Armi da fuoco','firearm':'Armi da fuoco'}[norm(name)]||name),armor:name,tool:name,language:name}[kind]||name;
}
const proficiencyKinds={skill:'Abilità',expertise:'Maestria',
 save:'Tiri salvezza',weapon:'Armi',armor:'Armature',tool:'Strumenti',language:'Lingue'};
const proficiencyOrder=['skill','expertise','save','weapon','armor','tool','language'];
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
  add('attack_count','Attacchi per azione','Attacchi disponibili',
   '×'+grant.attacks_per_action,'attack_count:'+grant.id);
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
 for(const row of rows(record.dice_bonuses)){
  if(row.disabled||!belongs(row))continue;
  const copies=trait.category==='oggetti'&&trait.rank===0?trait.item_active_quantity:1;
  add('bonus','Bonus',traitBenefitTargetLabel(row.target),signedTraitFormula(row.dice)+(copies>1?' ×'+copies:''),'dice:'+String(row.id||[row.origin_id,row.target,row.dice].join('|')));
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
  if(!belongs(attack)&&!stateAttackIds.has(String(attack.id))&&!fromItem)continue;
  const reach=attack.melee?'Portata ':'Gittata ';
  const range=Number(attack.range_feet);
  const details=[attack.damage&&String(attack.damage)+' '+String(attack.damage_type||''),
   Number.isFinite(range)&&range>0?reach+range+' ft':'',
   Number(attack.long_range_feet)>0?'Lunga '+attack.long_range_feet+' ft':''].filter(Boolean).join(' · ');
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

 // Contextual, source-qualified feat advantages are separate from ordinary
 // Constitution saving throws and stay visible on the granting feat card.
 for(const rule of rows(calculated.feat_roll_modes)){
  if(!belongs(rule)||!['advantage','disadvantage'].includes(rule.mode))continue;
  const context=rule.context==='concentration_damage'?' · concentrazione':'';
  add('roll_modes','Vantaggi e svantaggi',traitBenefitTargetLabel(rule.target)+context,
   rule.mode==='advantage'?'Vantaggio':'Svantaggio',
   'roll_mode:'+rule.origin_id+':'+rule.mode+':'+rule.target+':'+(rule.context||''));
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
 const defenses=rows(record.damage_defense_entries)
  .filter(row=>!row.disabled&&belongs(row)&&defenseKinds[Number(row.rank)])
  .map(row=>({
   label:defenseKinds[Number(row.rank)][0],
   order:defenseKinds[Number(row.rank)][1],
   value:DAMAGE[norm(row.key)]||String(row.key||''),id:'defense:'+String(row.origin_id||'')+':'+row.rank+':'+norm(row.key)
  }))
  .sort((a,b)=>a.order-b.order||a.value.localeCompare(b.value,'it',{sensitivity:'base'}));
 for(const row of defenses)
  add('defenses','Resistenze, immunità e vulnerabilità',row.label,row.value,row.id);
 for(const row of rows(calculated.trackers)){
  if(!belongs(row)){
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
    return item&&String(trait.item_id||'')===String(item.id||'')&&
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
   effects:details.effects||[]
  });
  if(details.origin_id)abilitySourceIds.add(String(details.origin_id));
 };
 // Non-class feats can declare actions via the same typed benefits schema.
 for(const action of rows(calculated.feat_actions)){
  if(!belongs(action))continue;
  addAbility(action.name,{
   origin_id:action.origin_id,status:trait.inactive?'Tratto disattivato':'Attivabile',
   timing:actionTime(action.action_type||action.time),
   cost:Number(action.resource_cost)>0?String(action.resource_cost)+' utilizzi':'Nessun costo',
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
 for(const [key,owner,featureName,label,resource,time,mode] of CLASS_FEATURE_RULES){
  const source=ownerFeatures.find(feature=>norm(feature.name)===norm(featureName)&&
    classOf(feature)===norm(owner)&&
    (norm(owner)!=='artificer'||sourceOf(feature)==='tce'));
  if(!source)continue;
  const requirement=rows(calculated.trait_state_catalog).find(rule=>
   rows(rule.granted_features).some(name=>norm(name)===norm(source.name))&&
   norm(rule.class_name)===norm(owner));
  const gated=!!requirement&&!rows(calculated.active_trait_state_ids).includes(requirement.id);
  const active=mode==='toggle'&&!!record.active_class_features?.[key]&&!trait.inactive&&!source.disabled&&!gated;
  addAbility(label,{
   origin_id:source.origin_id,status:active?'Attiva':trait.inactive||source.disabled?'Tratto disattivato':
    gated?'Modello richiesto':'Attivabile',
   timing:actionTime(time),cost:resource?'1 utilizzo · '+resource:'Nessun costo',
   description:describe(source.entries??source.description),
   requirements:requirement?'Richiede '+requirement.name:'',
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
