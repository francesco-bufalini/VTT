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
 const ids=new Set([trait.feature_origin,...(trait.rank===0?[trait.origin_key]:[])].filter(Boolean));
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
  save:ABILITIES[name]||name,weapon:name,armor:name,tool:name,language:name}[kind]||name;
}
const proficiencyKinds={skill:'Abilità',expertise:'Maestria',
 save:'Tiri salvezza',weapon:'Armi',armor:'Armature',tool:'Strumenti',language:'Lingue'};
const proficiencyOrder=['skill','expertise','save','weapon','armor','tool','language'];
/** Returns ordered groups with {type,title,items:[{label,value}]}.
 * No grouping by guessed trait names: every grant must match an origin ID.
 */
export function traitBenefitGroups(trait={},record={},calculated={}){
 const ids=traitBenefitSources(trait,record),groups=new Map();
 const belongs=row=>row&&[row.origin_id,row.parent_origin].some(id=>id&&ids.has(id));
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
   signedTraitFormula(row.expression)+(row.disabled?' · Disattivato':''),row.id||'');
 }
 for(const row of rows(record.dice_bonuses)){
  if(row.disabled||!belongs(row))continue;
  add('dice','Dadi bonus',traitBenefitTargetLabel(row.target),signedTraitFormula(row.dice));
 }
 // One Competenze section: each filled row has the proficiency *type* at
 // left (where a numeric bonus has its target) and its value on the right.
 // Stable kind/name sorting keeps expertise and language rows easy to scan.
 const proficiencies=Object.entries(calculated.proficiency_sources||{})
  .filter(([,sources])=>rows(sources).some(source=>source?.id&&ids.has(source.id)))
  .map(([key])=>({kind:key.split(':')[0],name:proficiencyLabel(key)}))
  .sort((a,b)=>{
   const ai=proficiencyOrder.indexOf(a.kind),bi=proficiencyOrder.indexOf(b.kind);
   return (ai<0?100:ai)-(bi<0?100:bi)||
    a.name.localeCompare(b.name,'it',{sensitivity:'base',numeric:true});
  });
 for(const item of proficiencies)
  add('proficiency','Competenze',proficiencyKinds[item.kind]||'Altre competenze',item.name);
 for(const row of rows(record.damage_defense_entries)){
  if(row.disabled||!belongs(row))continue;
  const rank=Number(row.rank);
  const group={[-1]:['vulnerability','Vulnerabilità'],1:['resistance','Resistenze'],
   2:['damage_immunity','Immunità ai danni'],3:['condition_immunity','Immunità alle condizioni']}[rank];
  if(group)add(group[0],group[1],DAMAGE[norm(row.key)]||String(row.key||''));
 }
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
  add('resources','Risorse e tracker',row.name,(suffix?('Max '+suffix):'')+(reset?((suffix?' · ':'')+reset):''));
 }
 for(const spell of rows(trait.granted_spells))
  add('spells','Incantesimi concessi',spell.name,spell.level===0?'Trucchetto':
    Number.isInteger(spell.level)?'Livello '+spell.level:'');
 for(const action of rows(record.action_grants)){
  if(action.disabled||!belongs(action))continue;
  add('actions','Azioni concesse',action.name||action.label||action.id,
   String(action.action_type||action.time||''));
 }
 for(const effect of rows(calculated.active_feature_effects)){
  if(!effect.effective||!belongs(effect))continue;
  add('effects','Effetti attivi',effect.name||'Capacità',effect.summary||'Attivo');
 }
 return [...groups.values()].map(({type,title,items})=>({type,title,items}));
}
