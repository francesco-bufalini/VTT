// Regenerate the browser's existing catalog URLs from native structured data.
// No native files are changed; no catalog output is edited by hand.
import {readFile,writeFile} from 'node:fs/promises';
import {projectSpeciesAttacks} from './species_mechanics.mjs';
const read=async path=>JSON.parse(await readFile(new URL(path,import.meta.url),'utf8'));
// Project typed TCE infusion data to a URL already served by PwaHost.
// Older native snapshots lack selectors: use source-qualified structured
// fallbacks, never English-description parsing in browser runtime.
const infusionSelectors={
  "infusion|tce|arcane propulsion armor": {
    "item_selector": {
      "nonmagical": true,
      "kinds": [
        "armor"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|armor of magical strength": {
    "item_selector": {
      "nonmagical": true,
      "kinds": [
        "armor"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|boots of the winding path": {
    "item_selector": {
      "nonmagical": true,
      "name_contains_any": [
        "boot"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|enhanced arcane focus": {
    "item_selector": {
      "nonmagical": true,
      "name_contains_any": [
        "rod",
        "staff",
        "wand"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|enhanced defense": {
    "item_selector": {
      "nonmagical": true,
      "kinds": [
        "armor",
        "shield"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|enhanced weapon": {
    "item_selector": {
      "nonmagical": true,
      "kinds": [
        "weapon"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|helm of awareness": {
    "item_selector": {
      "nonmagical": true,
      "name_contains_any": [
        "helm"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|homunculus servant": {
    "item_selector": {
      "nonmagical": true,
      "kinds": [
        "other",
        "tool"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|mind sharpener": {
    "item_selector": {
      "nonmagical": true,
      "kinds": [
        "armor"
      ],
      "name_contains_any": [
        "robe"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|radiant weapon": {
    "item_selector": {
      "nonmagical": true,
      "kinds": [
        "weapon"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|repeating shot": {
    "item_selector": {
      "nonmagical": true,
      "kinds": [
        "weapon"
      ],
      "properties_all": [
        "A"
      ]
    },
    "application_kind": "enhancement",
    "numeric_item_selector": {
      "item_types": [
        "R"
      ]
    }
  },
  "infusion|tce|replicate magic item": {
    "item_selector": {
      "id_prefix": "magic_item:"
    },
    "application_kind": "replicate"
  },
  "infusion|tce|repulsion shield": {
    "item_selector": {
      "nonmagical": true,
      "kinds": [
        "shield"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|resistant armor": {
    "item_selector": {
      "nonmagical": true,
      "kinds": [
        "armor"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|returning weapon": {
    "item_selector": {
      "nonmagical": true,
      "kinds": [
        "weapon"
      ],
      "properties_all": [
        "T"
      ]
    },
    "application_kind": "enhancement"
  },
  "infusion|tce|spell-refueling ring": {
    "item_selector": {
      "nonmagical": true,
      "name_contains_any": [
        "ring"
      ]
    },
    "application_kind": "enhancement"
  }
};
const abilityIndex=await read('../../vtt/data/structured_ability_grants_5etools.json');
const choicePolicies=await read('../../vtt/data/ability_choice_policies_5etools.json');
Object.assign(abilityIndex,choicePolicies);
// PHB feat actions, contextual roll modes and resource trackers are maintained
// in native typed data; the browser only projects those declarations.
const featMechanics=await read('../../vtt/data/feat_mechanics_2014.json');
abilityIndex.feat_mechanics=featMechanics.feats;
const baseOverrides=await read('../../vtt/data/base_value_overrides.json');
abilityIndex.base_value_overrides={feats:baseOverrides.feats,features:baseOverrides.features,items:baseOverrides.items,species:baseOverrides.species,optional_features:baseOverrides.optional_features};
const featNumeric=await read('../../vtt/data/feat_numeric_bonuses_2014.json');
abilityIndex.feat_numeric_bonuses=featNumeric.feats;
const infusionNative=await read('../../vtt/data/artificer_infusions_5etools.json');
abilityIndex.artificer_infusions=infusionNative.infusions.map(row=>{
  const typed=infusionSelectors[row.id]||{};
  const fields={...row,item_selector:row.item_selector||typed.item_selector||{},
    application_kind:row.application_kind||typed.application_kind||'enhancement'};
  if(typed.numeric_item_selector&&fields.numeric_item_bonuses&&!fields.numeric_item_bonuses.item_selector)
    fields.numeric_item_bonuses={...fields.numeric_item_bonuses,item_selector:typed.numeric_item_selector};
  return fields;
});
abilityIndex.meta={...abilityIndex.meta,artificer_infusions:'TCE typed infusion mechanics projected from vtt/data/artificer_infusions_5etools.json; selectors follow structured item-enhancement contract',
 feat_numeric_bonuses:'PHB 2014 unconditional numeric feat effects from vtt/data/feat_numeric_bonuses_2014.json'};
await writeFile(new URL('../catalog/ability_grants.json',import.meta.url),JSON.stringify(abilityIndex,null,2)+'\n');
const mechanics=await read('../../vtt/data/class_mechanics_5etools.json');
const resources=await read('../../vtt/data/class_resource_overrides.json');
mechanics.resource_overrides=resources.classes;
mechanics.resource_overrides_meta=resources.meta;
mechanics.monster_resources=[];
for(const part of ['a','b','c','mm']){
 const document=await read('../../vtt/data/fightclub_monster_resources_2014_'+part+'.json');
 for(const row of document.monsters)if(!mechanics.monster_resources.some(r=>r.source.toUpperCase()===row.source.toUpperCase()&&r.name.toLowerCase()===row.name.toLowerCase()))mechanics.monster_resources.push(row);
}
const additional=await read('../../vtt/data/additional_spells_5etools.json');
mechanics.additional_spells=additional.entries;
mechanics.additional_spells_meta=additional.meta;
const legacyText=await readFile(new URL('../../vtt/spells/spell_catalog_phb_2014.gd',import.meta.url),'utf8');
const legacyStart=legacyText.indexOf('{',legacyText.indexOf('const SPELLS:'));
mechanics.legacy_spells=Object.values(JSON.parse(legacyText.slice(legacyStart)));
const references=await read('../../vtt/data/creature_references_5etools.json');
 // Mirror the native CreatureRules.species_creature_type lookup. 5etools puts
 // many non-Humanoid types inside the named "Creature Type" trait, not in
 // creatureTypes. Keep source-qualified entries so 2014/2024 books do not mix.
 const creatureKinds=['aberration','beast','celestial','construct','dragon','elemental',
  'fey','fiend','giant','humanoid','monstrosity','ooze','plant','undead'];
 const speciesTypes=references.races.flatMap(race=>{
  const trait=(race.entries||[]).find(entry=>String(entry?.name||'').trim().toLowerCase()==='creature type');
  if(!trait)return [];
  const text=JSON.stringify(trait.entries||[]).toLowerCase();
  const kind=creatureKinds.find(value=>new RegExp('\\b'+value+'\\b').test(text));
  return kind?[{id:race.id,name:race.name,source:race.source,creatureTypes:[kind]}]:[];
 });
 await writeFile(new URL('../catalog/species_types.json',import.meta.url),
  JSON.stringify({version:1,source:'vtt/data/creature_references_5etools.json',races:speciesTypes},null,2)+'\n');

// These structured race rows are also the native speed source. Keep only
// mechanics/identity here; the existing features URL owns descriptions.
await writeFile(new URL('../catalog/species_attacks.json',import.meta.url),
 JSON.stringify(projectSpeciesAttacks(references.races),null,2)+'\n');
mechanics.races=references.races.map(({id,name,source,speed,size,creatureTypes})=>({id,name,source,speed,size,creatureTypes}));
const proficiencies=await read('../../vtt/data/proficiency_grants_5etools.json');
const browserProficiencies=await read('../catalog/proficiency_grants.json');
browserProficiencies.subrace=proficiencies.subrace;
// Ownership is authored in the native typed index and must survive a PWA sync.
// Supplemental browser-only feat grants remain untouched.
for(const group of ['race','subrace','feat']){
 const current=browserProficiencies[group]||[];
 for(const source of proficiencies[group]||[]){
  const row=current.find(candidate=>candidate.name===source.name&&candidate.source===source.source);
  if(!row)continue;
  for(const field of ['trait_proficiencies','trait_proficiency_choices']){
   if(source[field])row[field]=source[field];
  }
 }
}
// Source-qualified, unconditional feat proficiencies missing from typed 5etools
// fields use the existing proficiency evaluator (no runtime feat exceptions).
const featProficiencies=await read('../../vtt/data/feat_proficiency_bonuses_2014.json');
for(const row of featProficiencies.feats){
 const existing=browserProficiencies.feat.find(feat=>feat.name.toLowerCase()===row.name.toLowerCase()&&feat.source.toLowerCase()===row.source.toLowerCase());
 if(existing){
  for(const [key,items] of Object.entries(row))if(Array.isArray(items))
   existing[key]=[...new Set([...(existing[key]||[]),...items])];
 }else browserProficiencies.feat.push(row);
}
await writeFile(new URL('../catalog/proficiency_grants.json',import.meta.url),JSON.stringify(browserProficiencies)+'\n');
const featureCatalog=await read('../../vtt/data/subclass_features_5etools.json');
mechanics.resource_features=[...references.class_features,...featureCatalog.subclass_features].map(row=>Object.fromEntries(['id','name','class_name','class_source','subclass_name','subclass_short_name','subclass_source','level'].filter(k=>row[k]!==undefined).map(k=>[k,row[k]])));
const previousSubraceIdentities=(await read('../catalog/class_mechanics.json')).subraces||[];
mechanics.subraces=proficiencies.subrace.map(row=>{
 const full=mechanics.races.find(r=>r.name.toLowerCase()===(row.raceName+' ('+row.name+')').toLowerCase()&&r.source.toLowerCase()===row.source.toLowerCase());
 return {name:row.name,source:row.source,raceName:row.raceName,raceSource:row.raceSource,
  id:full?.id||'subrace:'+row.raceName.toLowerCase()+'|'+row.raceSource.toLowerCase()+'|'+row.name.toLowerCase()+'|'+row.source.toLowerCase()};
});
// A selectable subrace can have no unconditional proficiency grant.
for(const row of previousSubraceIdentities)if(!mechanics.subraces.some(s=>s.id===row.id)&&
 mechanics.races.some(r=>r.id===row.id))mechanics.subraces.push(row);
for(const row of additional.entries.filter(row=>row.kind==='race'&&row.blocks?.length>1))for(const block of row.blocks){
 if(!block.name||mechanics.subraces.some(s=>s.raceName===row.name&&s.raceSource===row.source&&s.name===block.name))continue;
 mechanics.subraces.push({name:block.name,source:row.source,raceName:row.name,raceSource:row.source,
  id:'subrace:'+row.name.toLowerCase()+'|'+row.source.toLowerCase()+'|'+block.name.toLowerCase()+'|'+row.source.toLowerCase()});
}
await writeFile(new URL('../catalog/class_mechanics.json',import.meta.url),JSON.stringify(mechanics,null,2)+'\n');
const subclassCatalog=await read('../../vtt/data/subclasses_5etools.json');
const subclassFeatures=await read('../../vtt/data/subclass_features_5etools.json');
const classes={version:1,classes:references.classes.map(({id,name,source})=>({id,name,source})),
 subclasses:subclassCatalog.subclasses,
 class_features:references.class_features,subclass_features:subclassFeatures.subclass_features};
await writeFile(new URL('../catalog/classes.json',import.meta.url),JSON.stringify(classes)+'\n');
console.log('PWA: native class/origin mechanics, species references, and 2014 spell definitions regenerated.');
