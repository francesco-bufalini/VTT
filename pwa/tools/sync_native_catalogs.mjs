// Regenerate the browser's existing catalog URLs from native structured data.
// No native files are changed; no catalog output is edited by hand.
import {readFile,writeFile} from 'node:fs/promises';
const read=async path=>JSON.parse(await readFile(new URL(path,import.meta.url),'utf8'));
const mechanics=await read('../../vtt/data/class_mechanics_5etools.json');
const resources=await read('../../vtt/data/class_resource_overrides.json');
mechanics.resource_overrides=resources.classes;
mechanics.resource_overrides_meta=resources.meta;
const references=await read('../../vtt/data/creature_references_5etools.json');
// These structured race rows are also the native speed source. Keep only
// mechanics/identity here; the existing features URL owns descriptions.
mechanics.races=references.races.map(({id,name,source,speed,size,creatureTypes})=>({id,name,source,speed,size,creatureTypes}));
const proficiencies=await read('../../vtt/data/proficiency_grants_5etools.json');
mechanics.subraces=proficiencies.subrace.map(row=>{
 const full=mechanics.races.find(r=>r.name.toLowerCase()===(row.raceName+' ('+row.name+')').toLowerCase()&&r.source.toLowerCase()===row.source.toLowerCase());
 return {name:row.name,source:row.source,raceName:row.raceName,raceSource:row.raceSource,
  id:full?.id||'subrace:'+row.raceName.toLowerCase()+'|'+row.raceSource.toLowerCase()+'|'+row.name.toLowerCase()+'|'+row.source.toLowerCase()};
});
await writeFile(new URL('../catalog/class_mechanics.json',import.meta.url),JSON.stringify(mechanics,null,2)+'\n');
console.log('PWA: class mechanics, resource supplement and species movement regenerated.');
