import {classFeatureRollSources} from './feature_mechanics.js';
import {resolveOwnedItem} from './item_controls.js';
// Read-only, source-bound summaries for the PWA's trait cards.
// Use structured grants only; never extract mechanics from free-form descriptions.
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
const RECOVERY={short_rest:'Riposo breve',long_rest:'Riposo lungo',turn:'Inizio turno',d6:'Ricarica d6'};
const TARGETS={ability_check:'Tutte le prove di caratteristica (incl. iniziativa)',
 saving_throw:'Tutti i tiri salvezza',attack_roll:'Tiri per colpire',
 damage_roll:'Tiri di danno',any_d20:'Qualunque d20',ac:'Classe armatura',
 initiative:'Iniziativa',hp:'PF massimi',second_max:'PF seconda forma',
 speed:'Camminata',proficiency:'Competenza',passive_perception:'Percezione passiva',
 pact_slot:'Slot del Patto',spell_dc:'CD incantesimi',spell_attack:'Attacco incantesimi',
 attunement_max:'Oggetti in sintonia'};
export function signedTraitFormula(expression){
 const raw=String(expression??'').trim();
 return raw&&!/^[+\-−]/.test(raw)?'+'+raw:raw;
}
export function traitBenefitSources(trait={},record={}){
 const ids=new Set([trait.feature_origin,trait.proficiency_origin,
  ...(trait.key?['feature:trait:'+trait.key]:[]),
  ...(trait.rank===0?[trait.origin_key]:[])].filter(Boolean));
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
 const belongs=row=>row&&([row.origin_id,row.parent_origin].some(id=>id&&ids.has(id))||
  stateRule&&String(row.id||'').startsWith('trait_state:'+stateRule.id+':'));
 const add=(type,title,label,value='',id='')=>{
  label=String(label??'').trim();value=String(value??'').trim();
  if(!label)return;
  if(!groups.has(type))groups.set(type,{type,title,items:[],seen:new Set()});
  const group=groups.get(type),key=label+'\u0000'+value;
  if(group.seen.has(key))return;
  group.seen.add(key);group.items.push({label,value,id});
 };
 const bonusSeen=new Set();
 for(const row of [...rows(calculated.bonuses),...rows(calculated.automatic_bonuses)]){
  if(!belongs(row))continue;
  const id=String(row.id||'');
  if(id&&bonusSeen.has(id))continue;
  if(id)bonusSeen.add(id);
  add('bonus','Bonus alle formule',traitBenefitTargetLabel(row.target),
   signedTraitFormula(row.expression)+(row.disabled?' · Disattivato':''),'bonus:'+String(row.id||''));
 }
 for(const row of rows(record.dice_bonuses)){
  if(row.disabled||!belongs(row))continue;
  add('dice','Dadi bonus',traitBenefitTargetLabel(row.target),signedTraitFormula(row.dice),'dice:'+String(row.id||[row.origin_id,row.target,row.dice].join('|')));
 }
 // An attack is a benefit in its own right; bonuses to an attack are
 // separate numeric benefits and must not be confused with the granted attack.
 const stateAttackIds=new Set(rows(stateRule?.attacks).map(attack=>String(attack.id)));
 for(const attack of rows(calculated.attacks)){
  const itemId=String(trait.origin_key||'').replace(/^item:/,'');
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
   if(trait.origin_key!=='item:'+String(item.id||saved.id||''))continue;
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
   if(!(source.origin_id&&ids.has(source.origin_id))&&
    !(source.kind==='condition'&&trait.condition_id===source.condition_id))continue;
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
 // One Competenze section: each filled row has the proficiency *type* at
 // left (where a numeric bonus has its target) and its value on the right.
 // Stable kind/name sorting keeps expertise and language rows easy to scan.
 const proficiencies=Object.entries(calculated.proficiency_sources||{})
  .filter(([,sources])=>rows(sources).some(source=>source?.id&&ids.has(source.id)))
  .flatMap(([key,sources])=>rows(sources).filter(source=>source?.id&&ids.has(source.id)).map(source=>({
   kind:key.split(':')[0],name:proficiencyLabel(key),originId:source.id,key
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
 for(const action of rows(record.action_grants)){
  if(action.disabled||!belongs(action))continue;
  add('actions','Azioni concesse',action.name||action.label||action.id,
   String(action.action_type||action.time||''),'action:'+String(action.id||[action.origin_id,action.name].join('|')));
 }
 for(const effect of rows(calculated.active_feature_effects)){
  if(!effect.effective||!belongs(effect))continue;
  add('effects','Effetti attivi',effect.name||'Capacità',effect.summary||'Attivo','effect:'+String(effect.id||[effect.origin_id,effect.name].join('|')));
 }
 const removed=new Set(rows(record.trait_benefit_removed?.[trait.key]));
 return [...groups.values()].map(({type,title,items})=>({type,title,items:items.filter(item=>!removed.has(item.id))})).filter(group=>group.items.length);
}
