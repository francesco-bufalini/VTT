// Build-time, source-qualified damage defenses from 5etools' typed race fields.
// No natural-language parsing in the browser and no invented damage selection.
const types = {resist:1, immune:2, conditionImmune:3, vulnerable:-1};
const labels = {
 'aasimar':'Celestial Resistance','aetherborn':'Born of Aether',
 'autognome':'Mechanical Nature','dhampir':'Trace of Undeath',
 'dragonborn':'Damage Resistance','dragonborn (chromatic)':'Draconic Resistance',
 'dragonborn (gem)':'Draconic Resistance','dragonborn (metallic)':'Draconic Resistance',
 'duergar':'Dwarven Resilience','dwarf':'Dwarven Resilience',
 'githyanki':'Psychic Resilience','githzerai':'Psychic Resilience',
 'goblin':'Grit','goliath':'Mountain Born','grung':'Poison Immunity',
 'kalashtar':'Mental Discipline','naga':'Poison Immunity',
 'plasmoid':'Natural Resilience','reborn':'Deathless Nature',
 'rimekin':'Cold Resistance','sea elf':'Child of the Sea',
 'shadar-kai':'Necrotic Resistance','skeleton':'Undead Nature',
 'tiefling':'Hellish Resistance','triton':'Guardian of the Depths',
 'vampire':'Vampiric Resistance','warforged':'Constructed Resilience',
 'yuan-ti':'Poison Resilience','yuan-ti pureblood':'Poison Immunity',
 'zombie':'Undead Nature','elf (shadar-kai)':'Necrotic Resistance',
 'genasi (air)':'Lightning Resistance','genasi (fire)':'Fire Resistance',
 'genasi (water)':'Acid Resistance','half-elf (variant; mark of storm)':"Storm's Boon",
 'halfling (stout)':'Stout Resilience'
};
const norm = value => String(value || '').trim().toLowerCase();
const available = race => (race.entries || []).filter(t => t && typeof t === 'object' && t.name)
 .map(t => String(t.name));
const aliases = {
 'guardian of the depths':['Guardians of the Depths'],
 'constructed resilience':['Construct Resilience']
};
function owner(race, rank, key) {
 const name=norm(race.name);
 const desired=name==='skeleton'&&rank===-1?'Brittle Bones':
  name==='reborn'&&norm(race.source)==='rhw'?'Strange Endurance':
  labels[name]||labels[name.replace(/ \(.+\)$/,'')]||'';
 const options=[desired,...(aliases[norm(desired)]||[])].filter(Boolean);
 return available(race).find(n=>options.some(x=>norm(x)===norm(n)))||'';
}
export function projectSpeciesDefenses(races=[]) {
 const valid=new Map();
 const output=[];
 // First index verified native typed fields, never guess from prose.
 for(const race of races) {
  if(norm(race.source)==='xphb'||!race.id||!race.name||!race.source)continue;
  const entries=[],choices=[];
  for(const [field,rank] of Object.entries(types)){
   for(const value of Array.isArray(race[field])?race[field]:[]){
    if(typeof value==='string' && /^[a-z][a-z-]*$/i.test(value)){
     const trait=owner(race,rank,value);
     if(trait)entries.push({rank,key:norm(value),trait});
    }else if(value?.choose?.from?.length){
     const trait=owner(race,rank,'');
     if(trait)choices.push({rank,trait,from:value.choose.from.filter(x=>typeof x==='string').map(norm)});
    }
   }
  }
  if(entries.length||choices.length){
   const data={id:race.id,name:race.name,source:race.source,entries,choices};
   valid.set(norm(race.name)+'|'+norm(race.source),data);
   output.push(data);
  }
 }
 // 5etools' flattened subraces repeat a verified parent's exact named trait
 // but often omit the parent's top-level typed resist/immune fields.
 for(const race of races){
  if(norm(race.source)==='xphb'||output.some(r=>r.id===race.id))continue;
  const parentName=String(race.name||'').replace(/ \(.+\)$/,'');
  if(parentName===race.name)continue;
  const owned=new Set(available(race).map(norm));
  const parents=output.filter(r=>norm(r.name)===norm(parentName));
  const sameSource=parents.filter(r=>norm(r.source)===norm(race.source));
  const best=sameSource.length?sameSource:parents;
  const inherited=[...new Map(best.flatMap(p=>p.entries).filter(e=>owned.has(norm(e.trait))).map(e=>[e.rank+'|'+e.key,e])).values()];
  const inheritedChoices=[...new Map(best.flatMap(p=>p.choices).filter(e=>owned.has(norm(e.trait))).map(e=>[e.rank+'|'+e.trait,e])).values()];
  if(inherited.length||inheritedChoices.length)output.push({id:race.id,name:race.name,source:race.source,entries:inherited,choices:inheritedChoices});
 }
 return {version:1,source:'vtt/data/creature_references_5etools.json',races:output};
}
