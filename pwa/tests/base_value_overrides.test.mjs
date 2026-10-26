import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {addBenefitPatch,removeBenefitPatch,restoreBenefitPatch} from '../trait_benefit_editor.js';
import {traitBenefitGroups} from '../trait_benefits.js';

const native=JSON.parse(readFileSync(new URL('../../vtt/data/base_value_overrides.json',import.meta.url)));
const packaged=JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url)));
const catalogs={abilityGrants:packaged,classMechanics:{},proficiencyGrants:{},originDetails:{races:{},feats:{},backgrounds:{}}};
const base=(patch={})=>({kind:'character',rules_version:'2014',level:3,abilities:{str:12,dex:14,con:12,int:10,wis:10,cha:10},
 armor_class_base:10,max_hp_base:20,inventory:[],...patch});
const sheet=c=>calculateSheet(c,catalogs);
const gauntlets={id:'gauntlet-1',name:'Gauntlets of Ogre Power',source:'DMG',type:'W',quantity:1,
 reqAttune:true,attuned_count:1,active:true,equipped_slots:[]};

test('native base-value supplement stays exactly synced with packaged PWA rules',()=>{
 assert.deepEqual(packaged.base_value_overrides,
  {feats:native.feats,features:native.features,items:native.items});
});

test('Tavern Brawler PHB replaces unarmed damage die, not the Strength modifier or all attacks',()=>{
 const c=base({feats_catalog:[{name:'Tavern Brawler',source:'PHB'}]});
 const attacker=sheet(c);
 const main=attacker.attacks.find(row=>row.id==='unarmed');
 const off=attacker.attacks.find(row=>row.id==='unarmed:off');
 assert.equal(main.damage_base_formula,'1d4');
 assert.equal(main.damage,'1d4 + 1');
 assert.equal(off.damage,'1d4 + 1');
 assert.equal(sheet(base()).attacks.find(row=>row.id==='unarmed').damage,'2');
 assert.equal(sheet({...c,feats_catalog:[{name:'Tavern Brawler',source:'XPHB'}]}).attacks.find(row=>row.id==='unarmed').damage_base_formula,'1');
 assert.equal(sheet({...c,origin_enabled:{'feat|phb|tavern brawler':false}}).attacks.find(row=>row.id==='unarmed').damage,'2');
 const source=main.damage_base_formula;
 assert.equal(source,'1d4');
 const override=attacker.base_value_overrides.find(row=>row.target==='attack_damage_base:unarmed');
 assert(override?.id.startsWith('auto|feat|phb|tavern brawler|'));
 const suppressed={...c,trait_benefit_removed:{x:['base_override:'+override.id]}};
 assert.equal(sheet(suppressed).attacks.find(row=>row.id==='unarmed').damage,'2');
 const trait={category:'talenti',rank:0,key:'feat|tavern brawler|phb',origin_key:'feat|tavern brawler|phb'};
 assert(traitBenefitGroups(trait,c,attacker).some(group=>group.type==='base_overrides'));
});

test('attuned magic items provide a minimum ability score, respect higher scores and relinquish effect',()=>{
 const initial=sheet(base({inventory:[gauntlets]}));
 assert.equal(initial.abilities.str.score,19);
 assert.equal(initial.abilities.str.modifier,4);
 assert.equal(initial.saves.str,4);
 assert.equal(initial.attacks.find(a=>a.id==='unarmed').damage,'5');
 assert.equal(sheet(base({inventory:[{...gauntlets,attuned_count:0}]})).abilities.str.score,12);
 assert.equal(sheet(base({inventory:[{...gauntlets,active:false}]})).abilities.str.score,12);
 assert.equal(sheet(base({inventory:[gauntlets],origin_enabled:{'item:gauntlet-1':false}})).abilities.str.score,12);
 assert.equal(sheet(base({inventory:[gauntlets],abilities:{str:22,dex:14,con:12,int:10,wis:10,cha:10}})).abilities.str.score,22);
 assert.equal(sheet(base({inventory:[{...gauntlets,source:'XDMG'}]})).abilities.str.score,12);
 const belt={...gauntlets,id:'belt-1',name:'Belt of Hill Giant Strength'};
 assert.equal(sheet(base({inventory:[gauntlets,belt]})).abilities.str.score,21);
 assert.equal(sheet(base({inventory:[{...gauntlets,id:'head',name:'Headband of Intellect'}]})).abilities.int.score,19);
 const row=initial.base_value_overrides.find(x=>x.target==='ability:str');
 assert(row?.origin_id==='item:gauntlet-1');
 assert(traitBenefitGroups({category:'oggetti',rank:0,origin_key:'item:gauntlet-1',key:'item:gauntlet-1'},
   base({inventory:[gauntlets]}),initial).some(g=>g.type==='base_overrides'));
});

test('alternate natural armor competes only without armor and preserves shield bonus',()=>{
 const draconic={id:'5etools:class_features:phb:draconic-resilience:sorcerer:1',name:'Draconic Resilience',
   class_name:'Sorcerer',class_source:'PHB',level:1};
 const types={...catalogs,classFeatures:{class_features:[draconic],subclass_features:[]}};
 const c=base({class:'Sorcerer',class_source:'PHB',classes:[{name:'Sorcerer',source:'PHB',level:3}]});
 const calc=x=>calculateSheet(x,types);
 assert.equal(sheet(c).stats.armor_class,12);
 assert.equal(calc({...c,origin_enabled:{'class|phb|sorcerer':false}}).stats.armor_class,12);
 assert.equal(calc({...c,features:[draconic]}).stats.armor_class,15);
 const derived=calc({...c,classes:[{name:'Sorcerer',source:'PHB',level:3}]});
 // A direct subclass trait is not inferred from class alone. When the native
 // catalog lists it, its alternate armor formula is evaluated dynamically.
 assert.equal(derived.stats.armor_class,15);
 const shield={id:'s',name:'Shield',source:'PHB',type:'S',ac:2,quantity:1,equipped_slots:['off']};
 assert.equal(calc({...c,inventory:[shield]}).stats.armor_class,17);
 const armor={id:'leather',name:'Leather Armor',source:'PHB',type:'LA',ac:11,quantity:1,equipped_slots:['body']};
 assert.equal(calc({...c,inventory:[armor]}).stats.armor_class,13);
});

test('manual replacement can be added, inspected, disabled, removed and restored by trait',()=>{
 const trait={key:'trait:custom-base',origin:'Test trait',name:'Test'};
 const c=base({origin_enabled:{'feature:trait:trait:custom-base':true}});
 const patch=addBenefitPatch(c,trait,'base_override',
  {target:'ability:str',mode:'minimum',expression:'20'},'trait:custombase');
 const granted={...c,...patch};
 assert.equal(sheet(granted).abilities.str.score,20);
 assert.equal(sheet({...granted,origin_enabled:{'feature:trait:trait:custom-base':false}}).abilities.str.score,12);
 const benefit={type:'base_overrides',id:'base_override:trait:custombase'};
 assert.equal(removeBenefitPatch(granted,trait,benefit).base_value_overrides.length,0);
 assert.throws(()=>addBenefitPatch(c,trait,'base_override',
  {target:'attack_damage_base:unarmed',mode:'minimum',expression:'1d4'},'trait:validkey'),/Modalità/);
 assert.throws(()=>addBenefitPatch(c,trait,'base_override',
  {target:'ability:str',mode:'replace',expression:'1d4'},'trait:validkey'),/numerica/);
});
