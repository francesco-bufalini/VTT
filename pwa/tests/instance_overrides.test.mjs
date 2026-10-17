import {test} from "node:test";
import assert from "node:assert/strict";
import {resolveOwnedItem,changeItemOverride,WEAPON_SIZES} from "../item_controls.js";
import {calculateSheet} from "../sheet_rules.js";

const abilities={str:12,dex:18,con:10,int:10,wis:10,cha:10};
const character=inventory=>({kind:"character",name:"Prova",level:4,abilities,
  inventory,formula_bonuses:[],resource_trackers:[],
  proficiency_choices:[{kind:"weapon",key:"longsword"}]});

test("item overrides resolve only for owned copy, never mutate catalog snapshot",()=>{
 const source={id:"weapon:test",name:"Longsword",type:"M",damage:"1d8",range:"20/60",properties:["V"],
   bonus_weapon:1,quantity:1,equipped_slots:["main"],instance_overrides:{damage:"1d10",weapon_size:"Large",bonus_weapon:2}};
 const resolved=resolveOwnedItem(source);
 assert.equal(resolved.damage,"1d10");
 assert.equal(resolved.weapon_size,"Large");
 assert.equal(resolved.bonus_weapon,2);
 assert.equal(source.damage,"1d8");
 assert.equal(source.bonus_weapon,1);
 const result=calculateSheet(character([source]));
 assert.equal(result.attacks[0].damage,"2d10 + 1 + 2");
 assert.equal(result.attacks[0].hit,1+2+2);
});

test("armor AC and numeric item bonuses are based on resolved overrides",()=>{
 const armor={id:"armor:hide",name:"Hide",type:"MA",ac:12,quantity:1,active:true,
   bonus_ac:1,equipped_slots:["body"],instance_overrides:{ac:15,bonus_ac:2}};
 const result=calculateSheet(character([armor]));
 assert.equal(result.stats.armor_class,19);
 assert.equal(result.automatic_bonuses.some(r=>r.origin_id==="item:armor:hide"),true);
 const unchanged=calculateSheet(character([{...armor,instance_overrides:{}}]));
 assert.equal(unchanged.stats.armor_class,15);
});

test("editing one weapon splits stack without losing the untouched copies",()=>{
 const stack={id:"weapon:blade",name:"Blade",type:"M",damage:"1d8",quantity:3,
   equipped_slots:["main"],instance_overrides:{}};
 const changed=changeItemOverride([stack],0,"weapon_size","Large");
 assert.equal(changed.length,2);
 assert.equal(changed[0].quantity,2);
 assert.deepEqual(changed[0].equipped_slots,["main"]);
 assert.equal(changed[1].quantity,1);
 assert.deepEqual(changed[1].equipped_slots,[]);
 assert.equal(changed[1].instance_overrides.weapon_size,"Large");
 assert.equal(stack.quantity,3);
 assert.equal(WEAPON_SIZES.includes("Large"),true);
 assert.equal(changeItemOverride(changed,1,"weapon_size","")[1].instance_overrides.weapon_size,undefined);
 assert.throws(()=>changeItemOverride([stack],0,"weapon_size","Colossal"),/Valore/);
 assert.throws(()=>changeItemOverride([stack],0,"damage","1d999"),/Valore/);
 assert.throws(()=>changeItemOverride([stack],0,"range","90/30"),/Valore/);
 assert.throws(()=>changeItemOverride([stack],0,"ac",50),/incompatibile/);
});

test("infusion attunement requirement is respected even without catalog",()=>{
 const obj={name:"Rod",id:"local_rod",custom_item_type:"other",equipped:true,attuned:false,
   infusion:{id:"infusion|tce|enhanced arcane focus",requires_attunement:true}};
 const calc=calculateSheet(character([{...obj,bonus_spell_attack:2}]));
 assert.equal(calc.bonuses.filter(r=>r.origin_id==="item:local_rod").length,0);
 const calc2=calculateSheet(character([{...obj,attuned:true,bonus_spell_attack:2}]));
 assert.ok(calc2.bonuses.some(r=>r.origin_id==="item:local_rod"));
});
