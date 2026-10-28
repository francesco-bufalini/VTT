// Source-qualified class and subclass defenses for the pre-2024 (2014) rules.
// A feature must actually belong to the character. Never infer effects from prose.
// Ranks: 1 resistance, 2 damage immunity, 3 condition immunity, -1 vulnerability.
const rows = value => Array.isArray(value) ? value : [];
const norm = value => String(value ?? '').trim().toLowerCase();
const same = (a,b) => norm(a) === norm(b);
const rule = (owner, feature, entries, options={}) => ({owner, feature, entries, ...options});
const defenses = (rank, ...keys) => keys.map(key => ({rank,key}));
const DAMAGE_TYPES=['acid','bludgeoning','cold','fire','force','lightning','necrotic',
 'piercing','poison','psychic','radiant','slashing','thunder'];
const ALL_BUT_PSYCHIC=DAMAGE_TYPES.filter(type=>type!=='psychic');

// These unconditional grants are deliberately separate from reactive/temporary
// features (e.g. Dampen Elements, Spell Resistance, Empty Body) and from
// damage-to-other-creatures effects (e.g. Ancestral Protectors).
export const CLASS_DEFENSE_RULES = [
 rule('Artificer','Chemical Mastery',[
  ...defenses(1,'acid','poison'),...defenses(3,'poisoned')
 ],{class_source:'TCE',subclass:'Alchemist',subclass_source:'TCE'}),
 rule('Cleric','Soul of the Forge',defenses(1,'fire'),
  {subclass:'Forge Domain',subclass_source:'XGE',aliases:['Soul of Forge']}),
 rule('Cleric','Saint of Forge and Fire',[
  ...defenses(2,'fire'),
  ...defenses(1,'bludgeoning','piercing','slashing').map(entry=>({...entry,
   condition_label:'Solo attacchi non magici, mentre indossi armatura pesante',
   requires_heavy_armor:true}))
 ],{subclass:'Forge Domain',subclass_source:'XGE'}),
 rule('Druid',"Nature's Ward",[
  ...defenses(2,'poison'),...defenses(3,'poisoned','disease')
 ],{subclass:'Circle of the Land',subclass_source:'PHB'}),
 rule('Druid','Fungal Body',defenses(3,'blinded','deafened','frightened','poisoned'),
  {subclass:'Circle of Spores',subclass_source:'TCE'}),
 rule('Fighter','Guarded Mind',defenses(1,'psychic'),
  {subclass:'Psi Warrior',subclass_source:'TCE'}),
 rule('Monk','Purity of Body',[
  ...defenses(2,'poison'),...defenses(3,'poisoned','disease')
 ]),
 rule('Paladin','Divine Health',defenses(3,'disease')),
 rule('Paladin','Aura of Courage',defenses(3,'frightened'),{conscious:true}),
 rule('Paladin','Aura of Devotion',defenses(3,'charmed'),
  {subclass:'Oath of Devotion',subclass_source:'PHB',conscious:true}),
 rule('Sorcerer','Heart of the Storm',defenses(1,'lightning','thunder'),
  {subclass:'Storm Sorcery',subclass_source:'XGE',aliases:['Heart of Storm']}),
 rule('Warlock','Radiant Soul',defenses(1,'radiant'),
  {subclass:'The Celestial',subclass_source:'XGE'}),
 rule('Warlock','Oceanic Soul',defenses(1,'cold'),
  {subclass:'The Fathomless',subclass_source:'TCE'}),
 rule('Warlock','Thought Shield',defenses(1,'psychic'),
  {subclass:'The Great Old One',subclass_source:'PHB'}),
 rule('Warlock','Beguiling Defenses',defenses(3,'charmed'),
  {subclass:'The Archfey',subclass_source:'PHB'}),
 rule('Wizard','Inured to Undeath',defenses(1,'necrotic'),
  {subclass:'School of Necromancy',subclass_source:'PHB'}),
 rule('Wizard','Spell Resistance',[
  {rank:1,key:'spell_damage',condition_label:'Solo danni causati da incantesimi'}
 ],{subclass:'School of Abjuration',subclass_source:'PHB'}),
 rule('Paladin','Aura of Warding',[
  {rank:1,key:'spell_damage',condition_label:'Solo danni causati da incantesimi'}
 ],{subclass:'Oath of the Ancients',subclass_source:'PHB',conscious:true}),
 // Rage itself already has an independent defensive projection. This
 // immunity is additional and must vanish the moment Rage ends.
 rule('Barbarian','Mindless Rage',defenses(3,'charmed','frightened'),
  {subclass:'Path of the Berserker',subclass_source:'PHB',active:'rage'}),
 rule('Warlock','Fiendish Resilience',[],{
  subclass:'The Fiend',subclass_source:'PHB',
  choice:{options:DAMAGE_TYPES,rank:1,label:'Resistenza scelta al riposo',
   condition_label:'Non si applica ai danni di armi magiche o argentate'}
 }),
 rule('Warlock','Elemental Gift',[],{
  subclass:'The Genie',subclass_source:'TCE',
  choice:{options:['bludgeoning','thunder','fire','cold'],rank:1,
   label:'Tipo di genio patrono',
   option_labels:{bludgeoning:'Dao · Contundenti',thunder:'Djinni · Tuono',
    fire:'Efreeti · Fuoco',cold:'Marid · Freddo'}}
 }),
 rule('Barbarian','Storm Soul',[],{
  subclass:'Path of the Storm Herald',subclass_source:'XGE',
  choice:{options:['fire','lightning','cold'],rank:1,label:'Ambiente della tempesta',
   option_labels:{fire:'Deserto · Fuoco',lightning:'Mare · Fulmine',cold:'Tundra · Freddo'}}
 }),
 rule('Barbarian','Totem Spirit',defenses(1,...ALL_BUT_PSYCHIC),{
  subclass:'Path of the Totem Warrior',subclass_source:'PHB',active:'rage',
  choice:{options:['bear','eagle','wolf','elk','tiger'],grant_only:'bear',
   label:'Spirito totemico',
   option_labels:{bear:'Orso',eagle:'Aquila',wolf:'Lupo',elk:'Alce',tiger:'Tigre'}}
 })
];

const muted = (record,id) => Boolean(id && (
 record.origin_enabled?.[id]===false ||
 rows(record.proficiency_origins).some(row=>row?.id===id&&row.disabled)
));

function hasCondition(record,name) {
 return rows(record.conditions).some(c=>same(typeof c==='string'?c:c?.id||c?.name,name));
}
function ruleMatchesFeature(rule,feature) {
 const key=norm(feature.origin_key);
 if(!key.startsWith('class|'))return false;
 const parts=key.split('|');
 if(parts[2]!==norm(rule.owner))return false;
 if(rule.class_source && parts[1]!==norm(rule.class_source))return false;
 if(![rule.feature,...rows(rule.aliases)].some(n=>same(feature.name,n)))return false;
 if(rule.subclass) {
  if(parts[3]!=='subclass'||parts[4]!==norm(rule.subclass)||
    rule.subclass_source&&parts[5]!==norm(rule.subclass_source))return false;
 } else if(parts.includes('subclass'))return false;
 return true;
}

// The same class-owned feature ID drives the choice popup and defense rules.
export function classDefenseChoices(record={},features=[]) {
 if(record.rules_version==='2024'||record.kind==='monster')return [];
 const result=[];
 for(const feature of rows(features)){
  const rule=CLASS_DEFENSE_RULES.find(row=>row.choice&&ruleMatchesFeature(row,feature));
  if(!rule||feature.disabled||feature.inactive||muted(record,feature.origin_id)||
     muted(record,feature.origin_key)||
     muted(record,feature.origin_key.split('|').slice(0,3).join('|'))||
     record.trait_enabled?.[feature.key]===false)continue;
  const options=rule.choice.options;
  const chosen=norm(record.origin_defense_choices?.[feature.origin_id]);
  const selected=options.includes(chosen)?[chosen]:[];
  result.push({id:'defense:'+feature.origin_id,
   kind:'defense',origin_id:feature.origin_id,defense_source_id:feature.origin_id,
   name:'Tratto · '+feature.name,label:rule.choice.label,
   count:1,selected,remaining:selected.length?0:1,options,
   option_labels:rule.choice.option_labels||{}});
 }
 return result;
}
export function classDefenseEntries(record={},features=[],removed=new Set()) {
 if(record.rules_version==='2024'||record.kind==='monster')return [];
 const out=[];
 for(const feature of rows(features)) {
  const rule=CLASS_DEFENSE_RULES.find(row=>ruleMatchesFeature(row,feature));
  if(!rule || feature.disabled || feature.inactive ||
     muted(record,feature.origin_id) || muted(record,feature.origin_key) ||
     record.trait_enabled?.[feature.key]===false)continue;
  const classParent=feature.origin_key.split('|').slice(0,3).join('|');
  if(muted(record,classParent))continue;
  if(rule.conscious&&(hasCondition(record,'unconscious')||
    hasCondition(record,'incapacitated')))continue;
  if(rule.active&&!record.active_class_features?.[rule.active])continue;
  const chosen=norm(record.origin_defense_choices?.[feature.origin_id]);
  const chosenValid=rule.choice?.options.includes(chosen);
  const entries=[...rule.entries];
  if(chosenValid && !rule.choice.grant_only)
   entries.push({rank:rule.choice.rank,key:chosen,condition_label:rule.choice.condition_label||''});
  if(rule.choice?.grant_only && chosen!==rule.choice.grant_only)continue;
  if(rule.choice && !chosenValid)continue;
  for(const {rank,key,condition_label,requires_heavy_armor} of entries){
   if(requires_heavy_armor&&!rows(record.inventory).some(item=>{
    const slots=rows(item?.equipped_slots);
    return Number(item?.quantity??1)>0&&slots.includes('body')&&
     String(item?.type||'').split('|')[0].toUpperCase()==='HA';
   }))continue;
   const id='defense:class:'+feature.origin_id+':'+rank+':'+key;
   if(removed.has(id))continue;
   out.push({id:'auto|'+id,benefit_id:id,rank,key,automatic:true,
    disabled:false,origin_id:feature.origin_id,
    origin_name:'Tratto · '+feature.name,origin_parent_id:feature.origin_key,
    origin_parent_name:rule.subclass||rule.owner,granting_trait:feature.name,
    ...(condition_label?{condition_label}:{})});
  }
 }
 return out;
}
