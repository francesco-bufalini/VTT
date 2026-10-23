import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pendingCharacterChoices,savePendingChoice} from '../pending_choices.js';
const index=JSON.parse(readFileSync(new URL('../catalog/proficiency_grants.json',import.meta.url),'utf8'));
const abilities=JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url),'utf8'));
const catalogs={proficiencyGrants:index,abilityGrants:abilities};
const artificer=()=>({kind:'character',class:'Artificer',class_source:'TCE',
 classes:[{name:'Artificer',source:'TCE',level:10}],rules_version:'2014',
 feats_catalog:[],proficiency_choices:[],origin_spell_grants:[]});
const choices=(c,calculated={})=>pendingCharacterChoices(c,calculated,catalogs);

test('Artificer class skill pool uses its original limited options',()=>{
 const c=artificer(),pool=choices(c).find(x=>x.kind==='proficiency'&&x.label==='Abilità');
 assert(pool,'the Artificer must have a choice-based skill grant');
 assert.equal(pool.count,2);
 assert.equal(pool.remaining,2);
 assert(pool.options.includes('arcana'));
 assert(pool.options.includes('sleight of hand'));
 assert(!pool.options.includes('acrobatics'));
 const patch=savePendingChoice(c,pool,['arcana','history']);
 assert.deepEqual(patch.proficiency_choices.map(x=>x.origin_id),[pool.origin_id,pool.origin_id]);
 const resumed=choices({...c,...patch}).find(x=>x.id===pool.id);
 assert.equal(resumed.remaining,0);
 assert.deepEqual(resumed.selected,['arcana','history']);
 assert.throws(()=>savePendingChoice(c,pool,['arcana','history','nature']),/Selezione/);
 assert.throws(()=>savePendingChoice(c,pool,['acrobatics']),/Selezione/);
});
test('existing decisions can be changed without mutating unrelated origins',()=>{
 const c=artificer(),choice=choices(c).find(x=>x.label==='Abilità');
 const initial=savePendingChoice(c,choice,['history','arcana']);
 const withOther={...c,...initial,proficiency_choices:[...initial.proficiency_choices,
  {kind:'skill',key:'perception',origin_id:'custom',origin_name:'Altro'}]};
 const changed=savePendingChoice(withOther,choice,['investigation','nature']);
 assert.equal(changed.proficiency_choices.filter(x=>x.origin_id===choice.origin_id).length,2);
 assert(changed.proficiency_choices.some(x=>x.origin_id==='custom'&&x.key==='perception'));
 assert(!changed.proficiency_choices.some(x=>x.origin_id===choice.origin_id&&x.key==='history'));
});
test('disabled origins do not produce false missing-choice warnings',()=>{
 const c=artificer(),pool=choices(c).find(x=>x.label==='Abilità');
 assert(!choices({...c,origin_enabled:{[pool.origin_id]:false}}).some(x=>x.id===pool.id));
});
test('one-score feat choices deduplicate by native feat origin and persist as feat ability_choice',()=>{
 const feat=abilities.feat.find(x=>x.name==='Telepathic'&&x.ability_choices?.length===1);
 assert(feat,'expected a structured feat catalog example');
 const c={...artificer(),feats_catalog:[{name:feat.name,source:feat.source},
   {name:feat.name,source:feat.source,origin_id:'custom'}]};
 const matches=choices(c).filter(x=>x.kind==='ability');
 assert.equal(matches.length,1);
 assert.equal(matches[0].remaining,1);
 const pick=matches[0].options[0],patch=savePendingChoice(c,matches[0],[pick]);
 assert.equal(patch.feats_catalog[0].ability_choice,pick);
 assert.equal(patch.feats_catalog[1].ability_choice,pick);
 assert.equal(choices({...c,...patch}).find(x=>x.kind==='ability').remaining,0);
});
test('native origin spell choices share one unresolved-state list with other abilities',()=>{
 const c=artificer(),choice={id:'origin-1|choose',origin_id:'feature:test',
  origin_name:'Privilegio magico',count:2,remaining:1,selected:[{spell_id:'magic-missile'}]};
 const found=choices(c,{origin_choices:[choice]}).find(x=>x.kind==='spell');
 assert(found);
 assert.equal(found.remaining,1);
 assert.equal(found.count,2);
 assert.deepEqual(found.selected,['magic-missile']);
 assert(!choices({...c,origin_enabled:{'feature:test':false}},{origin_choices:[choice]}).some(x=>x.id===found.id));
});