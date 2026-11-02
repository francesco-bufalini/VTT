import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {projectStateActivationBenefits,loadStateActivationBenefits} from '../state_activation_benefits.js';
import {traitStateActions,traitStateActivationPatch,activeTraitStates} from '../trait_state_rules.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const catalog=read('../../vtt/enrichment/benefits/state_activation.json');
const source=read('../catalog/trait_states.json').states;
const legacy=source.filter(rule=>rule.group==='barbarian_beast_form');
const baseRule=legacy.find(rule=>rule.id==='barbarian_beast_form:bite');
const grant={id:'test:beast:bite:state-activation',
 granted_by:{kind:'5etools',ref:{category:'subclass_feature',name:'Form of the Beast',
  source:'TCE',class_name:'Barbarian',class_source:'PHB',subclass:'Beast',subclass_source:'TCE'}},
 benefit:{type:'state_activation',state_activation:{state_id:baseRule.id,mode:'toggle',
  activation:'bonus',deactivation:'free',trigger:'on_rage',
  resource:{id:'rage_resource',name:'Rage',cost:1}}}
};
const typed={schema_version:2,scope:'catalog',benefit_type:'state_activation',entries:[grant]};
const record={classes:[{name:'Barbarian',source:'PHB',subclass:'Beast',level:3}],
 resource_tracker_spent:{}};
const features=[{name:'Form of the Beast',class_name:'Barbarian',class_source:'PHB',
 origin_id:'feature:form-of-the-beast',origin_key:'class|phb|barbarian'}];

test('catalog is typed and empty until verified state activations migrate',()=>{
 assert.equal(catalog.benefit_type,'state_activation');
 assert.deepEqual(catalog.entries,[]);
 assert.deepEqual(projectStateActivationBenefits(null,legacy),legacy);
});
test('activation has its own action time and charges an existing tracker',()=>{
 const rules=projectStateActivationBenefits(typed,legacy);
 assert.deepEqual(rules.find(row=>row.id===baseRule.id).attacks,baseRule.attacks);
 const action=traitStateActions(record,features,rules).find(row=>row.state_id===baseRule.id);
 assert.equal(action.time,'bonus');
 assert.equal(action.tracker_id,'rage_resource');
 assert.equal(action.cost,1);
 const patch=traitStateActivationPatch(record,features,rules,baseRule.id,[{id:'rage_resource',max:2}]);
 assert.equal(patch.trait_state_selection.barbarian_beast_form,baseRule.id);
 assert.equal(patch.resource_tracker_spent.rage_resource,1);
 assert.equal(activeTraitStates({...record,...patch},features,rules).length,1);
 const deactivation=traitStateActions({...record,...patch},features,rules).find(row=>row.state_id===baseRule.id);
 assert.equal(deactivation.time,'free');
 assert.equal(deactivation.cost,0);
 const off=traitStateActivationPatch({...record,...patch},features,rules,baseRule.id,[{id:'rage_resource',max:2}]);
 assert.equal(off.trait_state_selection.barbarian_beast_form,'');
 assert.equal(off.resource_tracker_spent,undefined);
});
test('typed resource payments cannot be waived or leave half-activated states',()=>{
 const rules=projectStateActivationBenefits(typed,legacy);
 assert.throws(()=>traitStateActivationPatch(record,features,rules,baseRule.id,[]),
  /Tracker della capacità non disponibile/);
 assert.throws(()=>traitStateActivationPatch(record,features,rules,baseRule.id,
  [{id:'rage_resource',max:0}]),/Utilizzi insufficienti/);
 assert.throws(()=>traitStateActivationPatch(record,features,rules,baseRule.id,
  [{id:'rage_resource',max:2}],{tracker_id:''}),/Tracker richiesto/);
 assert.deepEqual(record.resource_tracker_spent,{});
});
test('activation replaces another member of the exclusive group',()=>{
 const rules=projectStateActivationBenefits(typed,legacy);
 const old={...record,trait_state_selection:{barbarian_beast_form:'barbarian_beast_form:claws'},
  active_class_features:{'trait_state:barbarian_beast_form:claws':{name:'Claws'}}};
 const patch=traitStateActivationPatch(old,features,rules,baseRule.id,[{id:'rage_resource',max:2}]);
 assert.equal(patch.active_class_features['trait_state:barbarian_beast_form:claws'],undefined);
 assert.ok(patch.active_class_features['trait_state:'+baseRule.id]);
});
test('activate-only entries do not deactivate an already active State',()=>{
 const one={...typed,entries:[{...grant,benefit:{...grant.benefit,
   state_activation:{...grant.benefit.state_activation,mode:'activate'}}}]};
 const rules=projectStateActivationBenefits(one,legacy);
 const active={...record,trait_state_selection:{barbarian_beast_form:baseRule.id}};
 assert.equal(traitStateActions(active,features,rules).some(row=>row.state_id===baseRule.id),false);
 assert.deepEqual(traitStateActivationPatch(active,features,rules,baseRule.id,[]),{});
});
test('canonical owner identity and target State are checked',()=>{
 const wrong={...typed,entries:[{...grant,granted_by:{...grant.granted_by,
   ref:{...grant.granted_by.ref,class_name:'Fighter'}}}]};
 assert.throws(()=>projectStateActivationBenefits(wrong,legacy),/Origine/);
 const missing={...typed,entries:[{...grant,benefit:{...grant.benefit,
   state_activation:{...grant.benefit.state_activation,state_id:'missing:state'}}}]};
 assert.throws(()=>projectStateActivationBenefits(missing,legacy),/Stato non definito/);
});
test('older hosts fall back; malformed typed catalogs are rejected',async()=>{
 assert.equal(await loadStateActivationBenefits(async()=>({ok:false})),null);
 assert.deepEqual(await loadStateActivationBenefits(async()=>({ok:true,json:async()=>catalog})),catalog);
 await assert.rejects(()=>loadStateActivationBenefits(async()=>({ok:true,json:async()=>({entries:[]})})),
  /Catalogo state_activation non valido/);
});
