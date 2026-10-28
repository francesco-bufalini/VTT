import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {passiveClassRollBonuses,classFeatureRollBonuses,classFeatureEntries} from '../feature_mechanics.js';
import {calculateSheet} from '../sheet_rules.js';

const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const rules=read('roll_bonus_rules').features;
const feature=(name,owner,source='PHB',subclass='')=>({
 name,class_name:owner,class_source:source,origin_id:'feature:'+owner+':'+name,
 origin_key:'class|'+source.toLowerCase()+'|'+owner.toLowerCase()+
  (subclass?'|subclass|'+subclass.toLowerCase()+'|'+(subclass==='Champion'?'phb':'tce'):'')
});
const record=(name,source='PHB',subclass='')=>({
 kind:'character',rules_version:'2014',class:name,class_source:source,level:8,
 classes:[{name,source,level:8,subclass,subclass_source:subclass==='Champion'?'PHB':'TCE'}],
 inventory:[],abilities:{str:12,dex:14,con:14,int:16,wis:14,cha:14}
});
const calc=(features,proficiencies=[],value=3)=>({
 features,proficiencies,values:{proficiency:value},roll_bonus_rules:rules,trackers:[]
});
const get=(r,c,target)=>passiveClassRollBonuses(r,c,target);

test('Artificer Tool Expertise is a manual, source-bound bonus on proficient tool checks',()=>{
 const r=record('Artificer','TCE'),f=feature('Tool Expertise','Artificer','TCE');
 const c=calc([f],["tool:tinker's tools"]);
 assert.equal(get(r,c,'ability_check:int')[0]?.flat_bonus,6,'ability check has no tool proficiency baked into it');
 assert.equal(get(r,c,'skill:arcana')[0]?.flat_bonus,6);
 assert.equal(get(r,{...c,proficiencies:[...c.proficiencies,'skill:arcana']},'skill:arcana')[0]?.flat_bonus,3,
  'a skilled check already includes one proficiency bonus');
 assert.equal(get(r,{...c,proficiencies:[...c.proficiencies,'expertise:arcana']},'skill:arcana').length,0,
  'expertise already included cannot be doubled again');
 assert.equal(get(r,c,'initiative').length,0);
 assert.equal(get(r,{...c,proficiencies:[]},'ability_check:int').length,0);
 assert.equal(get({...r,origin_enabled:{[f.origin_id]:false}},c,'ability_check:int').length,0);
 assert.equal(get({...r,rules_version:'2024'},c,'ability_check:int').length,0);
 assert.equal(classFeatureEntries(r,c).length,0,'passive expertise must not appear as an active Battle action');
 assert.deepEqual(classFeatureRollBonuses(r,c,'ability_check:int'),get(r,c,'ability_check:int'));
 assert.equal(get(r,c,'ability_check:int')[0].origin_id,f.origin_id);
 assert.match(get(r,c,'ability_check:int')[0].condition_label,/strumento/);
});

test('Jack of All Trades and Remarkable Athlete apply half proficiency only to untrained checks and do not stack',()=>{
 const bard=feature('Jack of All Trades','Bard');
 const champ=feature('Remarkable Athlete','Fighter','PHB','Champion');
 const b=record('Bard'),f=record('Fighter','PHB','Champion');
 assert.equal(get(b,calc([bard],[],5),'initiative')[0]?.flat_bonus,2);
 assert.equal(get(b,calc([bard],['skill:arcana'],5),'skill:arcana').length,0);
 assert.equal(get(f,calc([champ],[],5),'ability_check:str')[0]?.flat_bonus,2);
 assert.equal(get(f,calc([champ],[],5),'skill:acrobatics')[0]?.flat_bonus,2);
 assert.equal(get(f,calc([champ],[],5),'skill:arcana').length,0);
 assert.equal(get(f,calc([champ],['skill:athletics'],5),'skill:athletics').length,0);
 const mixed={...b,classes:[...b.classes,...f.classes]};
 const applicable=get(mixed,calc([bard,champ],[],5),'skill:athletics');
 assert.equal(applicable.length,1,'half proficiency is not cumulative');
});

test('Natural Explorer doubles trained INT/WIS skill proficiency only in its manual favored-terrain context',()=>{
 const r=record('Ranger'),f=feature('Natural Explorer','Ranger');
 const c=calc([f],['skill:nature','skill:survival']);
 assert.equal(get(r,c,'skill:nature')[0]?.flat_bonus,3);
 assert.equal(get(r,c,'skill:survival')[0]?.flat_bonus,3);
 assert.equal(get(r,c,'skill:history').length,0);
 assert.equal(get(r,{...c,proficiencies:[...c.proficiencies,'expertise:nature']},'skill:nature').length,0);
 assert.equal(get(r,c,'ability_check:int').length,0,'skill qualification is not implied for a raw ability check');
});

test('Rune Knight Fire Rune requires an owned option and tool proficiency and does not stack with Tool Expertise',()=>{
 const art=feature('Tool Expertise','Artificer','TCE');
 const knight=feature('Rune Carver','Fighter','PHB','Rune Knight');
 const fighter=record('Fighter','PHB','Rune Knight'),c=calc([knight],["tool:smith's tools"]);
 assert.equal(get(fighter,c,'ability_check:int').length,0);
 const rune={...fighter,optional_features_catalog:[{name:'Fire Rune',source:'TCE'}]};
 assert.equal(get(rune,c,'ability_check:int')[0]?.flat_bonus,6);
 assert.equal(get(rune,c,'ability_check:int')[0]?.origin_id,'optional|tce|fire rune');
 const mixed={...rune,classes:[...rune.classes,record('Artificer','TCE').classes[0]]};
 assert.equal(get(mixed,calc([knight,art],["tool:smith's tools"]),'ability_check:int').length,1);
});

test('2014 class catalogs expose Tool Expertise at level 6 and do not project it before level 6',()=>{
 const catalogs={classMechanics:read('class_mechanics'),classFeatures:read('classes'),
  proficiencyGrants:read('proficiency_grants'),rollBonusRules:rules};
 const r=record('Artificer','TCE');
 const low={...r,level:5,classes:[{...r.classes[0],level:5}]};
 assert(!calculateSheet(low,catalogs).features.some(f=>f.name==='Tool Expertise'));
 const high={...r,level:6,classes:[{...r.classes[0],level:6}]};
 const output=calculateSheet(high,catalogs);
 assert(output.features.some(f=>f.name==='Tool Expertise'));
 assert(get(high,output,'ability_check:int').some(row=>row.name==='Tool Expertise'));
});
