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
  if(record.species)ids.add('race|'+norm(record.species_source)+'|'+norm(record.species));
  if(record.subrace)ids.add('subrace|'+norm(record.subrace_source)+'|'+norm(record.subrace));
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
const proficiencyKinds={skill:'Competenze nelle abilità',expertise:'Maestrie',
 save:'Competenze nei tiri salvezza',weapon:'Competenze nelle armi',
 armor:'Competenze nelle armature',tool:'Competenze negli strumenti',language:'Lingue'};
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
 for(const [key,sources] of Object.entries(calculated.proficiency_sources||{})){
  if(!rows(sources).some(source=>source?.id&&ids.has(source.id)))continue;
  const kind=key.split(':')[0];
  add('proficiency:'+kind,proficiencyKinds[kind]||'Competenze',proficiencyLabel(key));
 }
 for(const row of rows(record.damage_defense_entries)){
  if(row.disabled||!belongs(row))continue;
  const rank=Number(row.rank);
  const group={[-1]:['vulnerability','Vulnerabilità'],1:['resistance','Resistenze'],
   2:['damage_immunity','Immunità ai danni'],3:['condition_immunity','Immunità alle condizioni']}[rank];
  if(group)add(group[0],group[1],DAMAGE[norm(row.key)]||String(row.key||''));
 }
 for(const row of rows(calculated.trackers)){
  if(!belongs(row))continue; // Privileges/resources belong to their granting trait only.
  const maximum=Number(row.max);
  const suffix=Number.isFinite(maximum)?String(maximum):'';
  const reset=RECOVERY[row.recharge]||'';
  add('resources','Risorse e tracker',row.name,(suffix?('Max '+suffix):'')+(reset?((suffix?' · ':'')+reset):''));
 }
 // Learned optional capabilities are benefits of their actual granting trait.
 // Never infer ownership merely from membership in the Artificer class.
 if(norm(trait.name)==='infuse item'&&trait.feature_origin){
   const prepared=Object.hasOwn(record,'prepared_optional_features')
     ?rows(record.prepared_optional_features)
     :rows(record.optional_features_catalog).filter(r=>String(r?.id||'').startsWith('infusion|tce|'));
   for(const infusion of rows(record.optional_features_catalog)){
     if(!String(infusion?.id||'').startsWith('infusion|tce|'))continue;
     if(infusion.source_trait_id&&infusion.source_trait_id!==trait.feature_origin)continue;
     const ready=prepared.some(row=>row.id===infusion.id&&
       String(row.plan_item_id||'')===String(infusion.plan_item_id||''));
     add('features','Infusioni concesse',infusion.name+
       (infusion.plan_item_name?' · '+infusion.plan_item_name:''),ready?'Preparata':'Conosciuta');
   }
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
