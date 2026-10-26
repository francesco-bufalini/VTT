import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {featureCompanionRule,eligibleCompanionFeatureRules,matchesCompanionFeature,
 spellCompanionRule,companionTemplateStat,companionSources} from '../companion_rules.js';

const rules=JSON.parse(readFileSync(new URL('../catalog/companion_spells.json',import.meta.url),'utf8'));
const owner=(className,subclass,level)=>({
 kind:'character',rules_version:'2014',
 class:className,subclass,level,classes:[{name:className,level,subclass}],
 abilities:{str:10,dex:10,con:12,int:18,wis:16,cha:18},proficiency_bonus:3
});
const features=(className,name,id='1')=>({features:[{
 origin_id:id,name,origin_key:'class|phb|'+className.toLowerCase()+'|subclass|'+name.toLowerCase().replaceAll(' ','_')
}]});
test('Animating Performance is only eligible for a College of Creation bard at level six',()=>{
 const rule=rules.features.find(row=>row.id==='animating_performance_2014');
 const bard=owner('Bard','College of Creation',6),calculated=features('Bard','Animating Performance','feature:creation');
 assert.equal(featureCompanionRule(bard,calculated,rules,'feature:creation')?.id,rule.id);
 assert(!featureCompanionRule({...bard,subclass:'College of Lore',classes:[{name:'Bard',level:6,subclass:'College of Lore'}]},calculated,rules,'feature:creation'));
 assert(!featureCompanionRule(owner('Bard','College of Creation',5),calculated,rules,'feature:creation'));
 assert(!featureCompanionRule({...bard,rules_version:'2024'},calculated,rules,'feature:creation'));
 assert(!featureCompanionRule({...bard,origin_enabled:{'feature:creation':false}},calculated,rules,'feature:creation'));
 assert.equal(rule.alternative_slot_min,3);
});
test('Dancing Item, steel defender and wildfire spirit are derived from their actual owner',()=>{
 const item=companionTemplateStat(rules.templates.dancing_item,owner('Bard','College of Creation',9),{name:'Tappeto volante',size:'Small'});
 assert.equal(item.name,'Tappeto volante');
 assert.equal(item.size,'S');
 assert.equal(item.hp.average,55);
 assert.equal(item.ac[0],16);
 assert.equal(item.str,18);
 const steel=companionTemplateStat(rules.templates.steel_defender,owner('Artificer','Battle Smith',5));
 assert.equal(steel.hp.average,31);
 assert.equal(steel.speed.walk,40);
 const wildfire=companionTemplateStat(rules.templates.wildfire_spirit,owner('Druid','Circle of Wildfire',7));
 assert.equal(wildfire.hp.average,40);
 const drake=companionTemplateStat(rules.templates.drake_companion,owner('Ranger','Drakewarden',7));
 assert.equal(drake.ac[0],17);
 const servant=companionTemplateStat(rules.templates.homunculus_servant,owner('Artificer','Alchemist',8));
 assert.equal(servant.hp.average,13);
});
test('trait choices must match the source and allowed beast CR/size',async()=>{
 const ranger=owner('Ranger','Beast Master',5);
 const rule=rules.features.find(x=>x.id==='rangers_companion_2014');
 const list=[{key:'a',name:'Wolf',source:'MM',type:'beast',cr:'1/4',size:['M'],load:async()=>({name:'Wolf'})},
   {key:'b',name:'Brown Bear',source:'MM',type:'beast',cr:'1',size:['L'],load:async()=>({name:'Brown Bear'})},
   {key:'c',name:'Rat',source:'MM',type:'beast',cr:'0',size:['T'],load:async()=>({name:'Rat'})}];
 const choices=companionSources(rule,rules,list,ranger);
 assert.deepEqual(choices.map(x=>x.name),['Wolf','Rat']);
 const regular=rules.features.find(x=>x.id==='steel_defender_2014');
 const d=companionSources(regular,rules,[],owner('Artificer','Battle Smith',3));
 assert.equal(d.length,1);
 assert.equal((await d[0].load()).hp.average,21);
});
test('Animate Dead can add multiple creatures; the legacy familiars retain one exclusive sheet',()=>{
 const wizard=owner('Wizard','Evocation',7);
 assert.equal(spellCompanionRule(rules,{name:'Animate Dead'},wizard).limit_per_owner_spell,0);
 assert.equal(spellCompanionRule(rules,{name:'Find Familiar'},wizard).limit_per_owner_spell,1);
 assert.equal(spellCompanionRule(rules,{name:'Animate Dead'},{...wizard,rules_version:'2024'}),null);
});
test('unrelated passive traits do not produce free summons',()=>{
 const bard=owner('Bard','College of Creation',6);
 const p=features('Bard','Performance of Creation','different');
 assert.deepEqual(eligibleCompanionFeatureRules(bard,p,rules),[]);
 assert.equal(featureCompanionRule(bard,p,rules,'different'),null);
});
