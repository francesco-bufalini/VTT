import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pendingCharacterChoices,savePendingChoice,choicesForTrait} from '../pending_choices.js';
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
test('a selected feat ability can be cleared, leaving a new pending warning',()=>{
  const feat=abilities.feat.find(x=>x.name==='Telepathic'&&x.ability_choices?.length===1);
  const character={...artificer(),feats_catalog:[{name:feat.name,source:feat.source}]};
  const choice=choices(character).find(x=>x.kind==='ability');
  const set=savePendingChoice(character,choice,[choice.options[0]]);
  const saved={...character,...set};
  const clearing=savePendingChoice(saved,choices(saved).find(x=>x.id===choice.id),[]);
  assert.equal(clearing.feats_catalog[0].ability_choice,'');
  const pending=choices({...saved,...clearing}).find(x=>x.id===choice.id);
  assert.equal(pending.selected.length,0);
  assert.equal(pending.remaining,1);
});
test('deselecting all proficiency options preserves other trait choices',()=>{
  const c=artificer(),skillChoice=choices(c).find(x=>x.label==='Abilità');
  const initial=savePendingChoice(c,skillChoice,['arcana','history']);
  const current={...c,...initial,proficiency_choices:[...initial.proficiency_choices,
    {kind:'skill',key:'perception',origin_id:'other',origin_name:'Other'}]};
  const updated=savePendingChoice(current,choices(current).find(x=>x.id===skillChoice.id),[]);
  assert.equal(updated.proficiency_choices.length,1);
  assert.equal(updated.proficiency_choices[0].origin_id,'other');
  assert.equal(choices({...current,...updated}).find(x=>x.id===skillChoice.id).remaining,2);
});
test('trait benefit choices belong only to their structured grant origins',()=>{
  const c=artificer(),skillChoice=choices(c).find(x=>x.label==='Abilità');
  const feat=abilities.feat.find(x=>x.name==='Telepathic'&&x.ability_choices?.length===1);
  c.feats_catalog=[{name:feat.name,source:feat.source}];
  const all=choices(c);
  const classSummary={category:'classi',rank:0,origin_key:skillChoice.origin_id,
    key:skillChoice.origin_id+'|1|description'};
  const classChoices=choicesForTrait(classSummary,c,all);
  assert(classChoices.some(x=>x.id===skillChoice.id));
  assert(!classChoices.some(x=>x.kind==='ability'));
  const featSummary={category:'talenti',rank:0,
    origin_key:'feat|'+feat.name.toLowerCase()+'|'+feat.source.toLowerCase(),key:'feat-summary'};
  const traitChoices=choicesForTrait(featSummary,c,all);
  assert.equal(traitChoices.length,1);
  assert.equal(traitChoices[0].kind,'ability');
  assert.equal(choicesForTrait({category:'classi',rank:2,origin_key:'other',
    feature_origin:'feature:other',key:'unrelated'},c,all).length,0);
});
