import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resourceTrackers} from '../sheet_rules.js';
import {changeTrackerUses} from '../character_core.js';
import {recoveryPatch} from '../native_sheet.js';
const catalog=JSON.parse(readFileSync(fileURLToPath(new URL('../catalog/class_mechanics.json',import.meta.url)),'utf8'));

// Test the same tracker engine used by calculateSheet, not its retired parallel adapter.
test('class counters use source-qualified native resource rules',()=>{
 const fighter={kind:'character',rules_version:'2024',level:2,classes:[{name:'Fighter',source:'XPHB',level:2}]};
 const feature={class_name:'Fighter',class_source:'XPHB',level:2,name:'Action Surge'};
 const rules={...catalog,resource_features:[feature]};
 const trackers=resourceTrackers(fighter,rules);
 const surge=trackers.find(t=>t.name==='Action Surge');
 assert.ok(surge,'Action Surge should be projected by the active sheet engine');
 assert.equal(surge.id,'class:fighter:xphb:action_surge');
 assert.equal(surge.max,1);
 assert.equal(surge.recharge,'short_rest');
 assert.equal(surge.automatic,true);
 const legacy=resourceTrackers({...fighter,classes:[{name:'Fighter',source:'PHB',level:2}]},rules);
 assert(!legacy.some(t=>t.id==='class:fighter:xphb:action_surge'));
});

test('manual counters use the same spending and rest pipeline',()=>{
 const record={kind:'character',resource_trackers:[{id:'custom',name:'Extra',max:4,recharge:'short_rest'},{id:'manual',name:'Permanent',max:5,recharge:'manual'}],resource_tracker_spent:{custom:1,manual:2}};
 const trackers=resourceTrackers(record,catalog);
 assert.equal(trackers.find(t=>t.id==='custom')?.max,4);
 const paid={...record,...changeTrackerUses(record,'custom',1,trackers)};
 assert.equal(paid.resource_tracker_spent.custom,2);
 const recovered=recoveryPatch(paid,'short_rest',trackers);
 assert.equal(recovered.resource_tracker_spent.custom,undefined);
 assert.equal(recovered.resource_tracker_spent.manual,2);
});
