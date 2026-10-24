import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pendingCharacterChoices,savePendingChoice,choicesForTrait,knownProficiencyOptions,removeOwnedFeatPatch} from '../pending_choices.js';
import {nativeSection} from '../native_sheet.js';
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

test('single-choice options retain the radio styling and checkbox deselection',()=>{
 const ui=readFileSync(new URL('../ui.js',import.meta.url),'utf8');
 const css=readFileSync(new URL('../mobile_metal_theme.css',import.meta.url),'utf8');
 assert.match(ui,/const inputType='checkbox'/,
   'single choice must remain a togglable checkbox rather than a radio input');
 assert.match(ui,/choice\.count===1\?' pending-choice-option--single'/,
   'only one-option selectors should receive the former radio appearance');
 assert.match(css,/\.pending-choice-option--single input\[type="checkbox"\]:checked/,
   'the selected state should use the circular radio indicator');
 assert.match(css,/\.pending-choice-option--single input\[type="checkbox"\]\{[\s\S]*?border-radius:50%/,
   'the single-choice control must look circular');
});

test('already owned proficiencies are flagged for skills, expertise, tools, and languages',()=>{
 const c=artificer();
 const skill=choices(c).find(x=>x.label==='Abilità');
 const known=knownProficiencyOptions(c,{
  proficiencies:['skill:history','expertise:arcana','tool:smith\'s tools','language:elvish']},skill);
 assert(known.has('history'),'already trained skill');
 assert(known.has('arcana'),'existing expertise implies skill proficiency');
 assert(!known.has('nature'),'untrained skill must not be flagged');
 const indexWithChoice={...index,background:[...index.background,
  {name:'Local Tester',source:'TST',
   toolProficiencies:[{any:1}],languageProficiencies:[{any:1}]}]};
 const rec={...c,background:'Local Tester',background_source:'TST'};
 const all=pendingCharacterChoices(rec,{}, {proficiencyGrants:indexWithChoice});
 for(const [kind,key] of [['tool','smith\'s tools'],['language','elvish']]){
  const choice=all.find(row=>row.proficiency_kind===kind);
  assert(choice);
  assert(knownProficiencyOptions(rec,{proficiencies:[kind+':'+key]},choice).has(key));
 }
});

test('custom language and tool choices persist as structured grants, can be edited and removed',()=>{
 const c={...artificer(),background:'Local Tester',background_source:'TST'};
 const customCatalogs={proficiencyGrants:{...index,background:[...index.background,
  {name:'Local Tester',source:'TST',toolProficiencies:[{any:2}],
   languageProficiencies:[{any:2}]}]}};
 const find=(record,kind)=>pendingCharacterChoices(record,{},customCatalogs)
   .find(row=>row.proficiency_kind===kind&&row.name==='Local Tester');
 const language=find(c,'language'),tool=find(c,'tool');
 assert(language.custom_allowed&&tool.custom_allowed);
 assert(!find(c,'skill')?.custom_allowed);
 const first=savePendingChoice(c,language,['elvish','__custom__:Lingua del Crepuscolo']);
 const updated={...c,...first};
 assert(first.proficiency_choices.some(row=>row.custom&&row.key==='lingua del crepuscolo'));
 const resumed=find(updated,'language');
 assert(resumed.selected.includes('lingua del crepuscolo'));
 assert.deepEqual(resumed.custom_values,['lingua del crepuscolo']);
 assert(!resumed.options.includes('lingua del crepuscolo'),'manual values are edited separately');
 assert.equal(resumed.remaining,0);
 const second=savePendingChoice(updated,tool,['__custom__:Strumenti dell\'alchimista celeste']);
 const withTools={...updated,...second};
 assert(find(withTools,'tool').selected.includes('strumenti dell\'alchimista celeste'));
 assert.equal(find(withTools,'language').remaining,0);
 const cleared=savePendingChoice(withTools,find(withTools,'language'),[]);
 const withoutLanguage={...withTools,...cleared};
 assert.equal(find(withoutLanguage,'language').remaining,2);
 assert(find(withoutLanguage,'tool').selected.includes('strumenti dell\'alchimista celeste'));
 assert.throws(()=>savePendingChoice(c,language,['__custom__:']),/Selezione/);
 assert.throws(()=>savePendingChoice(c,language,['__custom__:'+('a'.repeat(81))]),/Selezione/);
 assert.throws(()=>savePendingChoice(c,language,['elvish','__custom__:dragonborn','__custom__:drow']),/Selezione/);
 assert.throws(()=>savePendingChoice(c,language,['__custom__:elvish']),/Selezione/);
 const skill=find(c,'skill')||choices(c).find(row=>row.label==='Abilità');
 assert.throws(()=>savePendingChoice(c,skill,['__custom__:my skill']),/Selezione/);
});

test('Other Proficiencies summarizes trained skills and expertise as well as tools and languages',()=>{
 const html=nativeSection({...artificer(),name:'Tester'},'info',{
  field:()=>'',area:()=>'',panel:(title,body)=>'<section data-summary="'+title+'">'+body+'</section>',
  calculated:{proficiencies:['skill:history','expertise:arcana',
    'tool:smith\'s tools','language:elvish'],values:{}}
 });
 const panel=html.match(/<section data-summary="Altre competenze">([\s\S]*?)<\/section>/)?.[1];
 assert(panel,'the Other Proficiencies panel must be present');
 assert.match(panel,/<dt>Abilità<\/dt><dd>Arcano, Storia<\/dd>/);
 assert.match(panel,/<dt>Maestrie<\/dt><dd>Arcano<\/dd>/);
 assert.match(panel,/<dt>Strumenti<\/dt><dd>smith&#39;s tools<\/dd>/);
 assert.match(panel,/<dt>Linguaggi<\/dt><dd>elvish<\/dd>/);
});

test('Skilled 2014 and 2024 share one three-choice skill/tool budget',()=>{
 for(const source of ['PHB','XPHB']){
  const feat=index.feat.find(row=>row.name==='Skilled'&&row.source===source);
  assert.deepEqual(feat?.proficiencyChoices?.[0]?.choose?.fromKinds,['skill','tool']);
  const c={...artificer(),feats_catalog:[{name:'Skilled',source}]};
  const picks=choices(c).filter(row=>row.origin_id==='feat|'+source.toLowerCase()+'|skilled');
  assert.equal(picks.length,1);
  const choice=picks[0];
  assert.equal(choice.proficiency_kind,'mixed');
  assert.equal(choice.count,3);
  assert(choice.options.includes('skill:arcana'));
  assert(choice.options.includes("tool:smith's tools"));
  assert.throws(()=>savePendingChoice(c,choice,[
   'skill:arcana','skill:history','tool:smith\'s tools','tool:thieves\' tools']),/Selezione/);
  const patch=savePendingChoice(c,choice,['skill:arcana','tool:smith\'s tools','tool:thieves\' tools']);
  assert.deepEqual(patch.proficiency_choices.map(row=>row.kind),['skill','tool','tool']);
  assert.equal(choices({...c,...patch}).find(row=>row.id===choice.id).remaining,0);
  const changed=savePendingChoice({...c,...patch},choice,['skill:perception','skill:history']);
  assert.deepEqual(changed.proficiency_choices.map(row=>row.kind),['skill','skill']);
  assert(!changed.proficiency_choices.some(row=>row.key==="smith's tools"));
  assert.equal(choices({...c,...changed}).find(row=>row.id===choice.id).remaining,1);
 }
});

test('Skilled mixed picker supports custom tools, known badges and origin-safe removal',()=>{
 const c={...artificer(),feats_catalog:[{name:'Skilled',source:'XPHB'},{name:'Skill Expert',source:'TCE'}],
  proficiency_choices:[{kind:'skill',key:'arcana',origin_id:'manual',origin_name:'Classe'}],
  origin_enabled:{'feat|xphb|skilled':true,manual:true}};
 const choice=choices(c).find(row=>row.proficiency_kind==='mixed');
 assert(choice.custom_allowed);
 const known=knownProficiencyOptions(c,{proficiencies:['skill:arcana',"tool:smith's tools"]},choice);
 assert(known.has('skill:arcana')&&known.has("tool:smith's tools"));
 const patch=savePendingChoice(c,choice,['skill:history','__custom__:Strumenti arcani']);
 const owned={...c,...patch};
 assert(patch.proficiency_choices.some(row=>row.kind==='tool'&&row.custom&&row.key==='strumenti arcani'));
 assert(choices(owned).find(row=>row.id===choice.id).selected.includes('tool:strumenti arcani'));
 assert.throws(()=>savePendingChoice(c,choice,['__custom__:arcana<unsafe>']),/Selezione/);
 const removed=removeOwnedFeatPatch(owned,'feat|skilled|xphb');
 assert.deepEqual(removed.feats_catalog.map(row=>row.name),['Skill Expert']);
 assert.deepEqual(removed.proficiency_choices,[{kind:'skill',key:'arcana',origin_id:'manual',origin_name:'Classe'}]);
 assert(!Object.hasOwn(removed.origin_enabled,'feat|xphb|skilled'));
 assert(!choices({...owned,...removed}).some(row=>row.origin_id==='feat|xphb|skilled'));
 assert.throws(()=>removeOwnedFeatPatch(owned,'feat|missing|xphb'),/Talento/);
});

test('Crafter and Musician 2024 use structured restricted tool selections',()=>{
 for(const [name,options] of [['Crafter',["smith's tools","carpenter's tools"]],
   ['Musician',['lute','flute']]]){
  const c={...artificer(),feats_catalog:[{name,source:'XPHB'}]};
  const featChoice=choices(c).find(row=>row.origin_id==='feat|xphb|'+name.toLowerCase());
  assert(featChoice,name+' must offer proficiency choices');
  assert.equal(featChoice.proficiency_kind,'tool');
  assert.equal(featChoice.count,3);
  assert(options.every(key=>featChoice.options.includes(key)));
  assert(!featChoice.options.includes(name==='Crafter'?'lute':"smith's tools"));
  assert.throws(()=>savePendingChoice(c,featChoice,['wrong category']),/Selezione/);
 }
});

test('owned feat cards expose an independent remove button and confirmed modal',()=>{
 const ui=readFileSync(new URL('../ui.js',import.meta.url),'utf8');
 const css=readFileSync(new URL('../mobile_metal_theme.css',import.meta.url),'utf8');
 assert.match(ui,/trait\.category==='talenti'&&trait\.rank===0/);
 assert.match(ui,/data-act="feat-remove"/);
 assert.match(ui,/data-act="feat-remove-confirm"/);
 assert.match(ui,/removeOwnedFeatPatch\(state\.editor\.read\(\),key\)/);
 assert.match(css,/\.trait-feat-remove/);
});
