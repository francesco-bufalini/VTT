import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {featureTableSpellGrants,supplementalFeatureSpellGrants,sessionSpellEntries} from '../spell_selection.js';

const artificer=(subclass='Alchemist',level=5)=>({
 kind:'character',class:'Artificer',class_source:'TCE',level,rules_version:'2014',
 classes:[{name:'Artificer',source:'TCE',level,subclass,subclass_source:'TCE'}],
 abilities:{str:10,dex:10,con:10,int:16,wis:10,cha:10}
});
const alchemist={name:'Alchemist Spells',class_name:'Artificer',class_source:'TCE',
 subclass_name:'Alchemist',subclass_source:'TCE',level:3,
 entries:[{type:'table',caption:'Alchemist Spells',colLabels:['Artificer Level','Spell'],
   rows:[['3rd','{@spell healing word}, {@spell ray of sickness}'],
     ['5th','{@spell flaming sphere}, {@spell Melf\'s acid arrow}'],
     ['9th','{@spell gaseous form}, {@spell mass healing word}']]}]};
const spells=[
 {id:'phb2014_healing_word',name:'Healing Word',level:1,source:'PHB'},
 {id:'phb2014_ray_of_sickness',name:'Ray of Sickness',level:1,source:'PHB'},
 {id:'phb2014_flaming_sphere',name:'Flaming Sphere',level:2,source:'PHB'},
 {id:'phb2014_melfs_acid_arrow',name:"Melf's Acid Arrow",level:2,source:'PHB'},
 {id:'phb2014_gaseous_form',name:'Gaseous Form',level:3,source:'PHB'},
 {id:'phb2014_magic_missile',name:'Magic Missile',level:1,source:'PHB'},
 {id:'phb2014_thunderwave',name:'Thunderwave',level:1,source:'PHB'},
 {id:'phb2014_mirror_image',name:'Mirror Image',level:2,source:'PHB'},
 {id:'phb2014_shatter',name:'Shatter',level:2,source:'PHB'}
];
const featureFor=(name,subclass,entries=[])=>({
 origin_id:'feature:class|tce|artificer|subclass|'+subclass.toLowerCase()+'|tce|'+name.toLowerCase(),
 origin_key:'class|tce|artificer|subclass|'+subclass.toLowerCase()+'|tce',
 name,entries,requirements:{class_name:'Artificer',class_source:'TCE'},level:3
});

test('structured subclass table grants exactly the spells unlocked at the class level',()=>{
 const feature=featureFor(alchemist.name,'Alchemist',alchemist.entries);
 const grants=featureTableSpellGrants(artificer(),[feature],spells,[{name:'Artificer',ability:'int'}]);
 assert.deepEqual(grants.map(g=>g.spell_id),[
  'phb2014_healing_word','phb2014_ray_of_sickness',
  'phb2014_flaming_sphere','phb2014_melfs_acid_arrow']);
 assert.ok(grants.every(g=>g.origin_id===feature.origin_id&&g.origin_name===feature.name&&g.mode==='prepared'));
 assert.equal(featureTableSpellGrants(artificer('Alchemist',3),[feature],spells).length,2);
 assert.equal(featureTableSpellGrants(artificer('Alchemist',9),[feature],spells).length,5);
 assert.equal(featureTableSpellGrants(artificer('Alchemist',9),[{...feature,name:'Expanded Spell List'}],spells).length,0);
});

test('always-prepared spells are projected by the sheet, not written into editable class selections',()=>{
 const character=artificer();
 const actual=calculateSheet(character,{classMechanics:{classes:[],additional_spells:[]},
   classFeatures:{class_features:[],subclass_features:[alchemist]},spells});
 const grants=actual.origin_spells.filter(g=>g.mechanic_source==='5etools.feature.spell_table');
 assert.equal(grants.length,4);
 assert.ok(grants.every(g=>g.origin_id.startsWith('feature:class|tce|artificer|subclass|alchemist|')&&g.payment_mode==='slot'));
 assert.equal(character.origin_spell_grants,undefined);
 assert.equal(character.prepared_spells,undefined);
 assert.deepEqual(sessionSpellEntries(character,actual,spells).filter(row=>row.grant_id).map(row=>row.id),
   grants.map(row=>row.spell_id));
 const disabled=calculateSheet({...character,origin_enabled:{
   [grants[0].origin_id]:false
 }},{classMechanics:{classes:[],additional_spells:[]},
   classFeatures:{class_features:[],subclass_features:[alchemist]},spells});
 assert.equal(disabled.origin_spells.length,0);
});

test('typed Armorer data is bound only to the selected subclass trait and its class level',()=>{
 const arcaneArmor=featureFor('Arcane Armor','Armorer');
 const supplement=[{class_name:'Artificer',class_sources:['TCE'],subclass:'Armorer',subclass_sources:['TCE'],
   feature_names:['Armorer Spells','Arcane Armor'],
   levels:[{level:3,spells:['magic missile','thunderwave']},
     {level:5,spells:['mirror image','shatter']}]}];
 const grants=supplementalFeatureSpellGrants(artificer('Armorer',5),[arcaneArmor],spells,
   supplement,[{name:'Artificer',ability:'int'}]);
 assert.equal(grants.length,4);
 assert.ok(grants.every(g=>g.origin_id===arcaneArmor.origin_id&&g.spellcasting_ability==='int'));
 assert.equal(supplementalFeatureSpellGrants(artificer('Armorer',3),[arcaneArmor],spells,supplement).length,2);
 assert.equal(supplementalFeatureSpellGrants(artificer('Alchemist',5),[arcaneArmor],spells,supplement).length,0);
 assert.equal(supplementalFeatureSpellGrants(artificer('Armorer',5),[],spells,supplement).length,0);
});

test('Luckstone grants all ability checks, initiative and saving throws only when attuned',()=>{
 const itemRule={names:['Stone of Good Luck','Stone of Good Luck (Luckstone)'],sources:['DMG'],
   bonuses:{ability_check:1,saving_throw:1}};
 const stone={id:'5etools:magic_item:luckstone',name:'Stone of Good Luck',source:'DMG',
   req_attune:true,attuned:true,quantity:1,type:'W'};
 const character={kind:'character',level:4,abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10},
   inventory:[stone]};
 const without=calculateSheet({...character,inventory:[]},{itemGrants:[itemRule]});
 const active=calculateSheet(character,{itemGrants:[itemRule]});
 assert.equal(active.values['ability_check:dex']-without.values['ability_check:dex'],1);
 assert.equal(active.values['initiative']-without.values['initiative'],1);
 assert.equal(active.values['skill:perception']-without.values['skill:perception'],1);
 assert.equal(active.stats.passive_perception-without.stats.passive_perception,1);
 assert.equal(active.values['save:wis']-without.values['save:wis'],1);
 assert.equal(active.bonuses.filter(b=>b.origin_id==='item:'+stone.id).length,2);
 for(const changed of [{...stone,attuned:false},{...stone,active:false},
   {...stone,name:'Unrelated'}]){
   const result=calculateSheet({...character,inventory:[changed]},{itemGrants:[itemRule]});
   assert.equal(result.values['initiative'],without.values['initiative']);
   assert.equal(result.values['save:wis'],without.values['save:wis']);
 }
 const own=calculateSheet({...character,inventory:[{...stone,bonusAbilityCheck:2}]},
   {itemGrants:[itemRule]});
 assert.equal(own.values.initiative-without.values.initiative,2,
   'specific structured fields override the supplemental fallback');
});

test('actual bundled Alchemist subclass table grants real spells at levels 3 and 5',()=>{
 const index=JSON.parse(readFileSync(new URL('../catalog/classes.json',import.meta.url),'utf8'));
 const mechanics=JSON.parse(readFileSync(new URL('../catalog/class_mechanics.json',import.meta.url),'utf8'));
 const bundled=JSON.parse(readFileSync(new URL('../catalog/spells.json',import.meta.url),'utf8')).spells;
 const record=artificer('Alchemist',5);
 const projected=calculateSheet(record,{classFeatures:index,classMechanics:mechanics,spells:bundled});
 const spells=projected.origin_spells.filter(g=>/alchemist.*spells/i.test(g.origin_name||''));
 assert.equal(spells.length,4,'class-feature catalog should preserve the structured Alchemist Spells table');
 assert.ok(spells.every(g=>g.mode==='prepared'&&g.payment_mode==='slot'));
});
