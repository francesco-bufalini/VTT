import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {customLineageRaceOptions} from '../catalog_data.js';
import {referencePatch,availableReferenceRows} from '../native_sheet.js';
import {selectedSources,fixedProficiencies} from '../structured_effects.js';
import {calculateSenses} from '../sense_rules.js';
import {pendingCharacterChoices,savePendingChoice} from '../pending_choices.js';

const senseCatalog=JSON.parse(readFileSync(new URL('../catalog/sense_grants.json',import.meta.url),'utf8'));
const profCatalog=JSON.parse(readFileSync(new URL('../catalog/proficiency_grants.json',import.meta.url),'utf8'));
const abilityCatalog=JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url),'utf8'));
const baseline={id:'5etools:races:tce:custom%20lineage',name:'Custom Lineage',source:'TCE'};
const base={kind:'character',rules_version:'2014',species:'',species_source:'',
  level:1,inventory:[],feats_catalog:[],proficiency_choices:[]};
const trait={name:'Feat',origin_key:'species|5etools:races:tce:custom%20lineage|tce',
  origin_id:'feature:species|5etools:races:tce:custom%20lineage|tce|1|feat',
  key:'species|5etools:races:tce:custom%20lineage|tce|1|feat'};
const catalogs={proficiencyGrants:profCatalog,abilityGrants:abilityCatalog,
  originDetails:{feats:{'alert|phb':{name:'Alert',source:'PHB'},
    'new feat|xphb':{name:'New Feat',source:'XPHB'}}},
  classMechanics:{additional_spells:[]}};
test('only the two exclusive TCE lineage choices are offered',()=>{
 const result=customLineageRaceOptions([baseline,{name:'Elf',source:'PHB'}]);
 assert.equal(result.length,3);
 assert.deepEqual(result.slice(0,2).map(r=>r.origin_sense_choice),
   ['darkvision','skill']);
 assert(!result.some(r=>r.name==='Custom Lineage'));
 const visible=availableReferenceRows(base,'species','races',{races:result});
 assert.equal(visible.length,3);
 for(const option of result.slice(0,2)){
   const changes=referencePatch(base,'species',option);
   assert.equal(changes.species,'Custom Lineage');
   assert.equal(changes.species_id,baseline.id);
   assert.equal(changes.origin_sense_choices['race|tce|custom lineage'],option.origin_sense_choice);
   const record={...base,...changes};
   const source=selectedSources(record,profCatalog);
   assert.equal(source.length,1);
   assert.deepEqual(source[0].source.languageProficiencies,[{common:true,anyStandard:1}]);
   const actual=calculateSenses(record,[],senseCatalog);
   assert.equal(actual.distances.darkvision,option.origin_sense_choice==='darkvision'?60:undefined);
   const pending=pendingCharacterChoices(record,{features:[trait]},catalogs);
   const skill=pending.filter(row=>row.proficiency_kind==='skill');
   assert.equal(skill.length,option.origin_sense_choice==='skill'?1:0);
   const feat=pending.find(row=>row.kind==='advancement_feat'&&row.origin_id===trait.origin_id);
   assert(feat);
   assert.equal(feat.remaining,1);
   assert(feat.options.includes('phb|alert'));
   assert(!feat.options.includes('xphb|new feat'));
   const chosen=savePendingChoice(record,feat,['phb|alert']);
   assert.equal(chosen.feats_catalog[0].granted_by,trait.origin_id);
   assert.equal(pendingCharacterChoices({...record,...chosen},{features:[trait]},catalogs)
     .find(row=>row.id===feat.id).remaining,0);
 }
});
test('legacy lineage stores and feat entries are preserved through either variant',()=>{
 const saved={...base,species:'Custom Lineage',species_source:'TCE',
  feats_catalog:[{name:'Alert',source:'PHB',granted_by:trait.origin_id}],
  origin_sense_choices:{'race|tce|custom lineage':'skill'}};
 const variants=customLineageRaceOptions([baseline]);
 const row=variants[0];
 const result=referencePatch(saved,'species',row);
 assert.equal(result.feats_catalog,undefined);
 assert.equal(result.origin_sense_choices['race|tce|custom lineage'],'darkvision');
 assert.equal(pendingCharacterChoices({...saved,...result},{features:[trait]},catalogs)
   .find(choice=>choice.origin_id===trait.origin_id).remaining,0);
});
