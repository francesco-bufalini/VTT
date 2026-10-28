// Source-qualified declarative class/subclass defenses (2014).
// No runtime behavior belongs in this catalog: condition evaluation lives in class_defenses.js.
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
