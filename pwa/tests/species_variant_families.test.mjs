import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {expandSpeciesVariantFamilies,selectableVariantSubraces,
 variantFamilyAbilityGrants} from '../species_variant_families.js';
import {canonicalSpeciesReferences} from '../catalog_data.js';
import {availableReferenceRows,referencePatch} from '../native_sheet.js';
import {selectedSources} from '../structured_effects.js';
import {dragonbornFtdProfile,dragonbornFtdChoice} from '../dragonborn_ftd.js';

const powers=JSON.parse(readFileSync(new URL('../catalog/species_powers.json',import.meta.url),'utf8'));
const grants=JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url),'utf8'));
const names=['Chromatic','Gem','Metallic'];
const raceCatalog=[{name:'Dragonborn',source:'PHB',id:'phb-parent'},
 ...names.map(name=>({id:'ftd-'+name.toLowerCase(),name:'Dragonborn ('+name+')',
  source:'FTD',entries:[{name:'Breath Weapon',entries:['Breath Weapon']},
   {name:'Draconic Resistance',entries:['Draconic Resistance']}]}))];
const older=names.map(name=>({name,raceName:'Dragonborn',raceSource:'PHB',source:'FTD'}));

test('variant families create three full dragonborn species with color subraces and no PHB inheritance',()=>{
 const family=expandSpeciesVariantFamilies(raceCatalog,selectableVariantSubraces(older),powers);
 const options=canonicalSpeciesReferences(family.races,family.subraces);
 assert.equal(family.derived.length,15);
 for(const name of names){
  const species='Dragonborn ('+name+')';
  const parent=options.find(row=>row.name===species&&!row.raceName);
  assert.equal(parent.source,'FTD');
  assert(parent.entries.some(row=>row.name==='Breath Weapon'));
  const subraces=availableReferenceRows({species, species_source:'FTD',rules_version:'2014',level:5},
    'subrace','races',{races:options});
  assert.equal(subraces.length,5);
  assert(subraces.every(row=>row.raceName===species&&row.raceSource==='FTD'));
  assert(subraces.every(row=>row.entries[0].name==='Draconic Ancestry'));
 }
 assert.equal(options.filter(row=>row.raceName==='Dragonborn'&&row.source==='FTD').length,0);
});

test('choosing a color is an ordinary subrace patch and resolves ancestry with no duplicate choice',()=>{
 const references=expandSpeciesVariantFamilies(raceCatalog,[],powers);
 const parent=references.races.find(row=>row.name==='Dragonborn (Chromatic)');
 const red=references.subraces.find(row=>row.raceName===parent.name&&row.name==='Red');
 const base={kind:'character',rules_version:'2014',species:'',species_source:'',level:5};
 const picked={...base,...referencePatch(base,'species',parent)};
 const record={...picked,...referencePatch(picked,'subrace',red)};
 assert.equal(record.species,parent.name);
 assert.equal(record.subrace,'Red');
 assert.equal(dragonbornFtdProfile(record,powers)?.ancestry?.damage_type,'fire');
 assert.equal(dragonbornFtdChoice(record,powers),null);
});

test('type-level ASI comes from the FTD structured ancestor, not duplicated by each color',()=>{
 const expanded=variantFamilyAbilityGrants(grants);
 for(const name of names){
  const race='Dragonborn ('+name+')';
  const rows=selectedSources({species:race,species_source:'FTD',subrace:'Red',subrace_source:'FTD'},
    expanded);
  assert.equal(rows.filter(row=>row.group==='race').length,1);
  assert.equal(rows.filter(row=>row.group==='subrace').length,0);
  assert(rows[0].source.ability_choices.length>0);
 }
});
