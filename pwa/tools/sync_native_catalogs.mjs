// Regenerate the browser's existing catalog URLs from native structured data.
// No native files are changed; no catalog output is edited by hand.
import {readFile,writeFile} from 'node:fs/promises';
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
const infusionNative=await read('../../vtt/data/artificer_infusions_5etools.json');
abilityIndex.artificer_infusions=infusionNative.infusions.map(row=>{
  const typed=infusionSelectors[row.id]||{};
  const fields={...row,item_selector:row.item_selector||typed.item_selector||{},
    application_kind:row.application_kind||typed.application_kind||'enhancement'};
  if(typed.numeric_item_selector&&fields.numeric_item_bonuses&&!fields.numeric_item_bonuses.item_selector)
    fields.numeric_item_bonuses={...fields.numeric_item_bonuses,item_selector:typed.numeric_item_selector};
  return fields;
});
abilityIndex.meta={...abilityIndex.meta,artificer_infusions:'TCE typed infusion mechanics projected from vtt/data/artificer_infusions_5etools.json; selectors follow structured item-enhancement contract'};
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
// These structured race rows are also the native speed source. Keep only
// mechanics/identity here; the existing features URL owns descriptions.
mechanics.races=references.races.map(({id,name,source,speed,size,creatureTypes})=>({id,name,source,speed,size,creatureTypes}));
const proficiencies=await read('../../vtt/data/proficiency_grants_5etools.json');
const featureCatalog=await read('../../vtt/data/subclass_features_5etools.json');
mechanics.resource_features=[...references.class_features,...featureCatalog.subclass_features].map(row=>Object.fromEntries(['id','name','class_name','class_source','subclass_name','subclass_short_name','subclass_source','level'].filter(k=>row[k]!==undefined).map(k=>[k,row[k]])));
mechanics.subraces=proficiencies.subrace.map(row=>{
 const full=mechanics.races.find(r=>r.name.toLowerCase()===(row.raceName+' ('+row.name+')').toLowerCase()&&r.source.toLowerCase()===row.source.toLowerCase());
 return {name:row.name,source:row.source,raceName:row.raceName,raceSource:row.raceSource,
  id:full?.id||'subrace:'+row.raceName.toLowerCase()+'|'+row.raceSource.toLowerCase()+'|'+row.name.toLowerCase()+'|'+row.source.toLowerCase()};
});
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
