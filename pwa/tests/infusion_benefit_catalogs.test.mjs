import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {infusionDefinitionsFromOptionLists,infusionItemActionsFromBenefits} from '../infusion_benefit_catalogs.js';
import {projectItemOptionBenefits} from '../power_selection.js';
const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const optionLists=read('../../vtt/enrichment/benefits/option_list.json');
const actions=read('../../vtt/enrichment/benefits/action.json');

test('all sixteen pre-2024 infusion definitions come from option_list',()=>{
 const options=infusionDefinitionsFromOptionLists(optionLists);
 assert.equal(options.length,16);
 assert(options.some(row=>row.id==='infusion|tce|replicate magic item'&&row.replicable_items?.length>40));
 assert(options.some(row=>row.id==='infusion|tce|enhanced weapon'&&row.numeric_item_bonuses?.bonus_weapon===1));
 assert(options.some(row=>row.id==='infusion|tce|resistant armor'&&row.effect_choice?.key==='damage_type'));
});

test('eight item-granted actions are projected only on their own extended object',()=>{
 const options=infusionDefinitionsFromOptionLists(optionLists);
 const itemActions=infusionItemActionsFromBenefits(actions);
 assert.equal(itemActions.length,8);
 const infusion=options.find(row=>row.id==='infusion|tce|radiant weapon');
 const option={id:'optional:tce:radiant-weapon',name:'Radiant Weapon',
  definition:infusion,requires_attunement:true};
 const item={id:'weapon:longsword',instance_id:'sword-1',name:'Longsword',
  type:'M',quantity:1,equipped_slots:['main'],attuned:true,attuned_count:1,
  option_extensions:[option]};
 const catalogs={abilityGrants:{artificer_infusions:options,infusion_item_actions:itemActions}};
 const record={inventory:[item]};
 const rendered=projectItemOptionBenefits(record,catalogs);
 const granted=rendered.action_grants.filter(row=>row.origin_id.startsWith('item-option:'));
 assert.equal(granted.length,2);
 assert.deepEqual(granted.map(row=>row.name),['Accendere o spegnere la luce','Lampo accecante']);
 assert.equal(granted[0].action_type,'bonus');
 assert.equal(granted[0].resource_cost,0);
 assert.equal(granted[1].action_type,'reaction');
 assert.equal(granted[1].tracker_id,'item-option-charges:sword-1:optional:tce:radiant-weapon');
 assert.equal(granted[1].resource_cost,1);
 assert.equal(projectItemOptionBenefits({...record,inventory:[{...item,option_extensions:[]}]},catalogs).action_grants.length,0);
});
