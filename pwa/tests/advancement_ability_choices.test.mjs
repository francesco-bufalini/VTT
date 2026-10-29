import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {pendingCharacterChoices,savePendingChoice,singleNewPendingChoice,choicesForTrait,permanentSubtraitsForTrait} from '../pending_choices.js';
import {collectTraitRows} from '../trait_projection.js';
import {traitBenefitGroups} from '../trait_benefits.js';
const abilities=JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url),'utf8'));
const base=()=>({kind:'character',rules_version:'2014',abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10},inventory:[],feats_catalog:[]});
const catalogs={abilityGrants:abilities,originDetails:{feats:{
 'alert|phb':{entries:['Cannot be surprised']},
 'athlete|xphb':{entries:['Athlete benefits']}
}}};
const calc=(record,index=catalogs)=>calculateSheet(record,index);
const pending=(record,index=catalogs)=>pendingCharacterChoices(record,calc(record,index),index);
const find=(rows,id)=>{const row=rows.find(x=>x.id===id);assert(row,id+' not found');return row;};

test('Aarakocra fixed EEPC and DMG increases appear among available origin choices but never duplicate',()=>{
 for(const [source,dex,wis] of [['EEPC',12,11],['DMG',12,12]]){
  const c={...base(),species:'Aarakocra',species_source:source};
  const p=pending(c),fixed=find(p,'ability-fixed:race|'+source.toLowerCase()+'|aarakocra');
  assert.equal(fixed.remaining,0);assert.equal(fixed.kind,'ability_fixed');
  assert.deepEqual(fixed.amounts,{dex:2,wis:source==='EEPC'?1:2});
  assert.equal(calc(c).abilities.dex.score,dex);
  assert.equal(calc(c).abilities.wis.score,wis);
  assert.throws(()=>savePendingChoice(c,fixed,['dex']),/automatici/);
 }
});
test('MPMM Aarakocra chooses +2/+1 or three +1, with unique abilities and origin-controlled grants',()=>{
 let c={...base(),species:'Aarakocra',species_source:'MPMM'};
 const sid='race|mpmm|aarakocra';
 let p=pending(c);
 const mode=find(p,'ability-mode:'+sid);
 assert.equal(mode.options.length,2);
 assert.equal(calc(c).abilities.dex.score,10);
 c={...c,...savePendingChoice(c,mode,['0'])};
 p=pending(c);
 const first=find(p,'ability:'+sid+':0'),second=find(p,'ability:'+sid+':1');
 assert.equal(first.amount,2);assert.equal(second.amount,1);
 c={...c,...savePendingChoice(c,first,['dex'])};
 assert.throws(()=>savePendingChoice(c,{...second,used_elsewhere:['dex']},['dex']),/differente/);
 c={...c,...savePendingChoice(c,find(pending(c),'ability:'+sid+':1'),['wis'])};
 assert.equal(calc(c).abilities.dex.score,12);
 assert.equal(calc(c).abilities.wis.score,11);
 assert.equal(calc({...c,origin_enabled:{[sid]:false}}).abilities.dex.score,10);
 c={...c,...savePendingChoice(c,find(pending(c),'ability-mode:'+sid),['1'])};
 assert.equal(calc(c).abilities.dex.score,10,'changing variant invalidates earlier allocation');
 let third=find(pending(c),'ability:'+sid+':0');
 assert.equal(third.count,3);
 c={...c,...savePendingChoice(c,third,['str','con','cha'])};
 for(const stat of ['str','con','cha'])assert.equal(calc(c).abilities[stat].score,11);
});
test('each class-level ASI allows score allocation or an owned feat, all linked to the source feature',async()=>{
 const asi={id:'5etools:class_features:phb:ability%20score%20improvement:fighter:4',
 name:'Ability Score Improvement',class_name:'Fighter',class_source:'PHB',source:'PHB',
 level:4,entries:['Increase a score or choose a feat']};
 const index={...catalogs,classFeatures:{class_features:[asi],subclass_features:[]}};
 let c={...base(),class:'Fighter',class_source:'PHB',classes:[{name:'Fighter',source:'PHB',level:4}]};
 let calculated=calc(c,index);
 const feature=calculated.features.find(x=>x.name==='Ability Score Improvement');
 assert(feature);
 const originId=feature.origin_id;
 let mode=find(pending(c,index),'advancement-mode:'+originId);
 assert.deepEqual(mode.options,['ability:0','ability:1','feat']);
 assert.deepEqual(mode.option_labels['ability:1'],'+1 a 2 caratteristiche');
 c={...c,...savePendingChoice(c,mode,['ability:1'])};
 assert(!pending(c,index).some(x=>x.id==='ability-mode:'+originId),
   'the permanent sub-trait contains the chosen allocation mode');
 let picker=find(pending(c,index),'ability:'+originId+':0');
 assert.equal(picker.count,2);
 c={...c,...savePendingChoice(c,picker,['str','con'])};
 calculated=calc(c,index);
 assert.equal(calculated.abilities.str.score,11);
 assert.equal(calculated.abilities.con.score,11);
 const granted=traitBenefitGroups({category:'classi',rank:2,
  origin_key:feature.origin_key,feature_origin:originId},c,calculated);
 assert(granted.some(row=>row.type==='bonus'&&row.items.length>=2));
 const projected=await collectTraitRows(c,calculated,{
  entries:async category=>category==='class_features'?[asi]:[],
  detail:async(_category,row)=>row
 });
 const owningRow=projected.find(row=>row.name==='Ability Score Improvement'&&
  row.feature_origin===originId);
 assert(owningRow,'the real class trait owns its permanent selection');
 assert(permanentSubtraitsForTrait(owningRow,c,pending(c,index))
   .some(row=>row.selection==='+1 a 2 caratteristiche'));
 c={...c,...savePendingChoice(c,find(pending(c,index),'advancement-mode:'+originId),['feat'])};
 assert.equal(calc(c,index).abilities.str.score,10,'switching to a feat revokes ASI');
 const featChoice=find(pending(c,index),'advancement-feat:'+originId);
 assert(featChoice.options.includes('phb|alert'));
 assert(!featChoice.options.includes('xphb|athlete'),
   'A 2014 character must not be offered feats from the 2024 Player Handbook');
 c={...c,...savePendingChoice(c,featChoice,['phb|alert'])};
 assert.equal(c.feats_catalog.length,1);
 assert.equal(c.feats_catalog[0].granted_by,originId);
 const rows=await collectTraitRows(c,calc(c,index),{
  entries:async category=>category==='feats'?[{name:'Alert',source:'PHB',entries:['Initiative']}] : [],
  detail:async(_category,row)=>row
 });
 const featTrait=rows.find(row=>row.category==='talenti'&&row.name.toLowerCase()==='alert');
 assert(featTrait);assert(featTrait.origin.includes('Ability Score Improvement'));
 const asiBenefit=traitBenefitGroups({category:'classi',rank:2,origin_key:feature.origin_key,
  feature_origin:originId},c,calc(c,index));
 assert(asiBenefit.some(group=>group.type==='feats'));
 c={...c,...savePendingChoice(c,find(pending(c,index),'advancement-mode:'+originId),['ability:0'])};
 assert.equal(c.feats_catalog.length,0,'switching away must revoke its owned feat');
 assert.equal(pending(c,index).find(x=>x.id==='advancement-mode:'+originId)?.selected[0],'ability:0');
});
test('XPHB Ability Score Improvement feat itself offers +2 or +1/+1 through its own trait',()=>{
 let c={...base(),rules_version:'2024',feats_catalog:[{name:'Ability Score Improvement',source:'XPHB'}]};
 const id='feat|xphb|ability score improvement';
 c={...c,...savePendingChoice(c,find(pending(c),'ability-mode:'+id),['0'])};
 c={...c,...savePendingChoice(c,find(pending(c),'ability:'+id+':0'),['dex'])};
 assert.equal(calc(c).abilities.dex.score,12);
 const p=pending(c);
 const owner={category:'talenti',rank:0,origin_key:'feat|ability score improvement|xphb'};
 assert(choicesForTrait(owner,c,p).some(row=>row.id==='ability-mode:'+id));
 assert(traitBenefitGroups(owner,c,calc(c)).some(group=>group.type==='bonus'));
});

test('saving ASI choice automatically exposes exactly one dependent modal at each step',()=>{
 const asi={id:'5etools:class_features:phb:ability%20score%20improvement:fighter:4',
  name:'Ability Score Improvement',class_name:'Fighter',class_source:'PHB',
  source:'PHB',level:4};
 const index={...catalogs,classFeatures:{class_features:[asi],subclass_features:[]}};
 let c={...base(),class:'Fighter',class_source:'PHB',
   classes:[{name:'Fighter',source:'PHB',level:4}]};
 const sid=find(pending(c,index),'advancement-mode:'+pending(c,index).find(x=>x.kind==='advancement_mode').origin_id).origin_id;
 const saved=(choice,selection)=>{
  const before=pending(c,index);
  c={...c,...savePendingChoice(c,choice,selection)};
  return singleNewPendingChoice(before,pending(c,index),choice);
 };
 const main=find(pending(c,index),'advancement-mode:'+sid);
 const second=saved(main,['ability:0']);
 assert(second,'the ASI branch directly opens its one-part score picker');
 assert.equal(second.kind,'ability');
 assert.equal(second.origin_id,sid);
 assert.equal(second.count,1);
 assert.equal(second.amount,2);
 assert.equal(saved(second,['str']),null,'a completed choice does not reopen a popup');
 // Switching to feats creates only the selected feat picker.
 c={...c,...savePendingChoice(c,find(pending(c,index),'advancement-mode:'+sid),[])};
 const featMode=find(pending(c,index),'advancement-mode:'+sid);
 const featFollowUp=saved(featMode,['feat']);
 assert(featFollowUp);assert.equal(featFollowUp.kind,'advancement_feat');
 assert.equal(featFollowUp.origin_id,sid);
 assert.equal(saved(featFollowUp,['phb|alert']),null);
});

test('auto-follow-up is suppressed for multiple newly created options, existing choices, or incomplete saves',()=>{
 let c={...base(),species:'Aarakocra',species_source:'MPMM'};
 const first=pending(c),mode=first.find(x=>x.kind==='ability_mode');
 assert(mode);
 c={...c,...savePendingChoice(c,mode,['0'])};
 const next=pending(c);
 assert.equal(next.filter(x=>x.id.startsWith('ability:race|mpmm|aarakocra:')).length,2);
 assert.equal(singleNewPendingChoice(first,next,mode),null,
  'two newly opened ability parts must not select one arbitrarily');
 const previouslyOpen=[{id:'old',remaining:1,origin_id:'other'}];
 const newlyOpen=[...previouslyOpen,{id:'new',kind:'proficiency',remaining:1}];
 assert.equal(singleNewPendingChoice([{id:'main',remaining:1},...previouslyOpen],
   [{id:'main',remaining:0},...newlyOpen],{id:'main'}).id,'new',
 'unrelated older unresolved choices must not suppress a unique NEW dependent choice');
 assert.equal(singleNewPendingChoice([{id:'main',remaining:1}],
   [{id:'main',remaining:1},{id:'new',remaining:1}],{id:'main'}),null,
 'partially completed parent must not open another modal');
 assert.equal(singleNewPendingChoice([{id:'main',remaining:1}],
   [{id:'main',remaining:0},{id:'new1',remaining:1},{id:'new2',remaining:1}],{id:'main'}),null);
 assert.equal(singleNewPendingChoice([{id:'main',remaining:1}],
   [{id:'main',remaining:0},{id:'unchanged',remaining:0}],{id:'main'}),null);
 assert.equal(singleNewPendingChoice([{id:'main',remaining:1}],
   [{id:'main',remaining:0},{id:'new',remaining:1}],{id:'stale'}),null);
});

test('permanent choice branches appear nested only under their owning trait',()=>{
 const sid='race|mpmm|aarakocra';
 let c={...base(),species:'Aarakocra',species_source:'MPMM'};
 const own={category:'razza',rank:0,origin_key:'species|aarakocra|mpmm'};
 const stranger={category:'classi',rank:2,origin_key:'class|phb|ranger',
   feature_origin:'feature:other'};
 let shown=permanentSubtraitsForTrait(own,c,pending(c));
 assert.equal(shown.length,1);
 assert.equal(shown[0].choice_id,'ability-mode:'+sid);
 assert.equal(shown[0].selection,'Da scegliere');
 assert.deepEqual(permanentSubtraitsForTrait(stranger,c,pending(c)),[]);
 c={...c,...savePendingChoice(c,find(pending(c),'ability-mode:'+sid),['0'])};
 shown=permanentSubtraitsForTrait(own,c,pending(c));
 assert.equal(shown.length,3,'the selected distribution exposes its two existing score pickers');
 assert.equal(shown[0].selection,'+2 a 1 caratteristica e +1 a 1 caratteristica');
 assert(shown.slice(1).every(x=>x.depth===1&&x.kind==='pending'));
 const origin='feature:class|phb|ranger|favored-enemy:1';
 const trait={category:'classi',rank:2,origin_key:'class|phb|ranger',feature_origin:origin};
 const power={id:'ranger_favored_enemy_phb',selection_kind:'subtrait',
  origin_id:origin,title:'Nemici prescelti',options:[{id:'humanoids',name:'Umanoidi'}],
  layers:{prepared:{enabled:true,trigger:null,limit:1,
   selected:[{id:'humanoids',subchoices:['Orc','Goblin']}]}}};
 shown=permanentSubtraitsForTrait(trait,c,[],[power]);
 assert.equal(shown.length,1);
 assert.equal(shown[0].selection,'Umanoidi · Orc, Goblin');
 assert.equal(shown[0].model_id,power.id);
 assert.equal(permanentSubtraitsForTrait(stranger,c,[],[power]).length,0);
 assert.equal(permanentSubtraitsForTrait(trait,c,[],[{
   ...power,layers:{prepared:{...power.layers.prepared,trigger:'long_rest'}}
 }]).length,0,'choices that change on a rest are not permanent sub-traits');
});
