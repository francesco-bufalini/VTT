// Source-qualified class and subclass defenses for the pre-2024 (2014) rules.
// A feature must actually belong to the character. Never infer effects from prose.
// Ranks: 1 resistance, 2 damage immunity, 3 condition immunity, -1 vulnerability.
const rows = value => Array.isArray(value) ? value : [];
const norm = value => String(value ?? '').trim().toLowerCase();
const same = (a,b) => norm(a) === norm(b);
const rule = (owner, feature, entries, options={}) => ({owner, feature, entries, ...options});
const defenses = (rank, ...keys) => keys.map(key => ({rank,key}));

// These unconditional grants are deliberately separate from reactive/temporary
// features (e.g. Dampen Elements, Spell Resistance, Empty Body) and from
// damage-to-other-creatures effects (e.g. Ancestral Protectors).
export const CLASS_DEFENSE_RULES = [
 rule('Artificer','Chemical Mastery',[
  ...defenses(1,'acid','poison'),...defenses(3,'poisoned')
 ],{class_source:'TCE',subclass:'Alchemist',subclass_source:'TCE'}),
 rule('Cleric','Soul of the Forge',defenses(1,'fire'),
  {subclass:'Forge Domain',subclass_source:'XGE',aliases:['Soul of Forge']}),
 rule('Cleric','Saint of Forge and Fire',defenses(2,'fire'),
  {subclass:'Forge Domain',subclass_source:'XGE'}),
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
 // Rage itself already has an independent defensive projection. This
 // immunity is additional and must vanish the moment Rage ends.
 rule('Barbarian','Mindless Rage',defenses(3,'charmed','frightened'),
  {subclass:'Path of the Berserker',subclass_source:'PHB',active:'rage'})
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
  for(const {rank,key} of rule.entries){
   const id='defense:class:'+feature.origin_id+':'+rank+':'+key;
   if(removed.has(id))continue;
   out.push({id:'auto|'+id,benefit_id:id,rank,key,automatic:true,
    disabled:false,origin_id:feature.origin_id,
    origin_name:'Tratto · '+feature.name,origin_parent_id:feature.origin_key,
    origin_parent_name:rule.subclass||rule.owner,granting_trait:feature.name});
  }
 }
 return out;
}
