import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {barbarian2014Supplements,barbarian2014ProficiencyCatalog} from '../barbarian_2014.js';
import {contextualFeatureGrants} from '../feature_mechanics.js';
const featureRules=JSON.parse(readFileSync(new URL('../../vtt/data/feature_timing_recovery_rules.json',import.meta.url),'utf8'));

const feature=(name,sub='',level=3)=>({
 id:'5etools:'+name+':'+sub+':'+level,
 name,source:sub?'TCE':name==='Primal Knowledge'?'TCE':'PHB',
 origin_key:'class|phb|barbarian'+(sub?'|subclass|'+sub.toLowerCase()+'|tce':''),
 origin_id:'feature:barbarian:'+name+':'+sub+':'+level,
 key:'class|phb|barbarian|'+name+':'+sub+':'+level,level
});
const barbarian=(sub='',inventory=[])=>({
 kind:'character',class:'Barbarian',class_source:'PHB',level:14,rules_version:'2014',
 classes:[{name:'Barbarian',source:'PHB',level:14,subclass:sub,subclass_source:'TCE'}],
 inventory,abilities:{str:18,dex:14,con:16,int:10,wis:12,cha:10}
});

test('Fast Movement is numeric, source-gated and stops under heavy armor',()=>{
 const f=feature('Fast Movement','',5),base=barbarian();
 const active=barbarian2014Supplements(base,[f],5);
 assert.deepEqual(active.numeric_grants.map(row=>[row.target,row.expression]),[['speed','10']]);
 const armored=barbarian2014Supplements(barbarian('',[{id:'armor',type:'HA',equipped_slots:['body'],quantity:1}]),[f],5);
 assert.equal(armored.numeric_grants.length,0);
 const disabled=barbarian2014Supplements({...base,origin_enabled:{[f.origin_id]:false}},[f],5);
 assert.equal(disabled.numeric_grants.length,0);
});

test('Feral Instinct is an automatic initiative mode; Danger Sense stays conditional',()=>{
 const instinct=feature('Feral Instinct','',7),danger=feature('Danger Sense','',2);
 const result=barbarian2014Supplements(barbarian(),[instinct,danger]);
 assert.equal(result.initiative_origin,instinct.origin_id);
 assert.deepEqual(result.conditional_modes.map(row=>row.target),['save:dex']);
 assert.match(result.conditional_modes[0].condition_label,/vedere/i);
 assert.equal(barbarian2014Supplements(barbarian(),[danger]).initiative_origin,'');
});

test('Primal Knowledge yields separate source-bound choices at levels 3 and 10',()=>{
 const f3=feature('Primal Knowledge','',3),f10=feature('Primal Knowledge','',10);
 const result=barbarian2014Supplements(barbarian(),[f3,f10]);
 assert.equal(result.proficiency_rows.length,2);
 assert.deepEqual(result.proficiency_rows.map(row=>row.id),[f3.id,f10.id]);
 assert(result.proficiency_rows.every(row=>row.skillProficiencies[0].choose.count===1));
 const index=barbarian2014ProficiencyCatalog({classFeature:[]},result);
 assert.equal(index.classFeature.length,2);
 assert.equal(barbarian2014ProficiencyCatalog(index,result).classFeature.length,2);
});

test('Giant Power cantrip selection has two options and Wisdom spellcasting',()=>{
 const giant=feature('Giant Power','Giant');
 const r=barbarian2014Supplements(barbarian('Path of the Giant'),[giant]);
 assert.equal(r.spell_choices.length,1);
 assert.deepEqual(r.spell_choices[0].spell_options,
  ['phb2014_druidcraft','phb2014_thaumaturgy']);
 assert.equal(r.spell_choices[0].spellcasting_ability,'wis');
 assert.equal(r.spell_choices[0].origin_id,giant.origin_id);
});

test('Subclass trackers attach to the owning feature and use the existing recharge modes',()=>{
 const awareness=feature('Magic Awareness','Wild Magic');
 const bolstering=feature('Bolstering Magic','Wild Magic',6);
 const r=contextualFeatureGrants(barbarian('Wild Magic'),[awareness,bolstering],featureRules,5);
 assert.equal(r.trackers.length,2);
 assert(r.trackers.every(row=>row.max===5&&row.recharge==='long_rest'));
 assert(r.actions.every(row=>r.trackers.some(t=>t.id===row.tracker_id)));
 const other=contextualFeatureGrants(barbarian('Zealot'),[awareness,bolstering],featureRules,5);
 assert.equal(other.trackers.length,0,'do not grant powers of an unowned subclass');
});

test('Elk bonus only applies during Rage, Eagle grants bonus Dash only when selected',()=>{
 const totem=feature('Totem Spirit','Totem Warrior',3);
 const self=barbarian('Path of the Totem Warrior');
 const elk=barbarian2014Supplements({...self,origin_defense_choices:{[totem.origin_id]:'elk'},
  active_class_features:{rage:{}}},[totem],4);
 assert(elk.numeric_grants.some(row=>row.target==='speed'&&row.expression==='15'));
 const idle=barbarian2014Supplements({...self,origin_defense_choices:{[totem.origin_id]:'elk'}},[totem],4);
 assert.equal(idle.numeric_grants.length,0);
 const eagle=barbarian2014Supplements({...self,origin_defense_choices:{[totem.origin_id]:'eagle'}},[totem],4);
 assert(eagle.actions.some(row=>row.name.includes('Aquila')&&row.action_type==='bonus'));
});

test('Tiger Aspect at level 6 requires its independent animal choice',()=>{
 const f=feature('Aspect of the Beast','Totem Warrior',6);
 const self=barbarian('Totem Warrior');
 const absent=barbarian2014Supplements(self,[f],4);
 assert.equal(absent.proficiency_rows.length,0);
 const chosen=barbarian2014Supplements({...self,
  trait_state_selection:{barbarian_totem_aspect:'barbarian_totem_aspect:tiger'}},[f],4);
 assert.equal(chosen.proficiency_rows.length,1);
 assert.equal(chosen.proficiency_rows[0].skillProficiencies[0].choose.count,2);
 const index=barbarian2014ProficiencyCatalog({classFeature:[],subclassFeature:[]},chosen);
 assert.equal(index.classFeature.length,0);
 assert.equal(index.subclassFeature.length,1);
});

test('2014 supplements never leak into 2024 rules',()=>{
 const record={...barbarian(),rules_version:'2024'};
 const r=barbarian2014Supplements(record,[feature('Fast Movement','',5),feature('Danger Sense','',2)]);
 assert.equal(r.numeric_grants.length,0);
 assert.equal(r.conditional_modes.length,0);
 assert.equal(r.actions.length,0);
});

test('Beast forms are three mutually exclusive typed natural attacks',()=>{
 const json=JSON.parse(readFileSync(new URL('../catalog/trait_states.json',import.meta.url),'utf8'));
 const forms=json.states.filter(s=>s.group==='barbarian_beast_form');
 assert.equal(forms.length,3);
 assert.equal(new Set(forms.map(s=>s.id)).size,3);
 assert(forms.every(s=>s.trait==='Form of the Beast'&&s.attacks.length===1));
 assert.equal(forms.find(s=>s.id.endsWith(':tail'))?.attacks[0].range_feet,10);
});

test('new JavaScript module is included in the atomic offline app-shell cache',()=>{
 const sw=readFileSync(new URL('../sw.js',import.meta.url),'utf8');
 assert(sw.includes('"/barbarian_2014.js"'));
});
