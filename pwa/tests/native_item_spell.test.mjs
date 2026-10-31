import {test} from "node:test";
import assert from "node:assert/strict";
import {itemKind,requiresAttunement,isCatalogItem,createOwnedItem,changeOwnedItem,consolidateOwnedItems,validSlot,equipSlot}
  from "../item_controls.js";
import {spellId,availableSpells,addSelectedSpell,removeSelectedSpell}
  from "../spell_selection.js";

test("catalog items retain immutable metadata and use native mutable instance controls",()=>{
  const weapon={id:"weapon:longsword|phb",name:"Spada lunga",type:"M",damage:"1d8",source:"PHB"};
  const instance=createOwnedItem(weapon,"pwa_test");
  assert.deepEqual(instance.equipped_slots,[]);
  assert.equal(instance.active,true);
  assert.equal(instance.attuned,false);
  assert.equal(itemKind(instance),"weapon");
  assert.equal(isCatalogItem(instance),true);
  assert.throws(()=>changeOwnedItem([instance],0,"name","Another"),/non modificabile/);
  assert.throws(()=>changeOwnedItem([instance],0,"equipped",true),/Battaglia/);
  assert.throws(()=>changeOwnedItem([instance],0,"attuned",true),/sintonia/);
  assert.deepEqual(changeOwnedItem([instance],0,"quantity",4)[0].quantity,4);
  assert.throws(()=>changeOwnedItem([instance],0,"quantity",0),/Quantità/);
  assert.equal(instance.quantity,1,"updating a copy must never mutate original data");
});
test("native attunement can be conditional text, but ordinary objects cannot attune",()=>{
  const magic={id:"magic_item:test",name:"Ring",reqAttune:"by a spellcaster",equipped:true};
  assert.equal(requiresAttunement(magic),true);
  assert.equal(changeOwnedItem([magic],0,"attuned",true)[0].attuned,true);
  const generic={id:"local_test",name:"Badge",custom_item_type:"other",quantity:1};
  const changed=changeOwnedItem([generic],0,"equipped",true);
  assert.equal(changed[0].equipped,true);
  assert.equal(changeOwnedItem(changed,0,"active",false)[0].active,false);
  assert.equal(changeOwnedItem([generic],0,"name","Etichetta")[0].name,"Etichetta");
  assert.throws(()=>changeOwnedItem([generic],0,"quantity",100000),/Quantità/);
});
test("class available spells merge legacy duplicates and stay mirrored on add/remove",()=>{
  const a={id:"spell:a",name:"A",source:"PHB",level:1};
  const b={id:"spell:b",name:"B",source:"XPHB",level:2};
  // Mixed-edition regression fixture explicitly uses 2024 rules. Unspecified
  // sheets default to 2014 and must not offer the newer XPHB entry.
  const old={rules_version:'2024',spells:[a],prepared_spells:[a],spellbook_spells:[b]};
  assert.deepEqual(availableSpells(old),[a]);
  const add=addSelectedSpell(old,b);
  assert.deepEqual(add.prepared_spells,[a,b]);
  assert.deepEqual(add.spells,[a,b]);
  assert.deepEqual(old.prepared_spells,[a]);
  assert.throws(()=>addSelectedSpell(old,a),/già presente/);
  const rm=removeSelectedSpell({...old,...add},"prepared_spells",0);
  assert.deepEqual(rm.prepared_spells,[b]);
  assert.deepEqual(rm.spells,[b]);
  assert.equal(spellId("spell:a"),"spell:a");
  assert.throws(()=>addSelectedSpell(old,a,"spellbook_spells"),/Elenco non valido/);
  assert.throws(()=>removeSelectedSpell(old,"spellbook_spells",0),/Elenco non valido/);
  assert.throws(()=>removeSelectedSpell(old,"spells",0),/non valido/);
});
test("spell catalog rejects missing IDs or unsupported levels",()=>{
  assert.throws(()=>addSelectedSpell({},"A"),/non valido/);
  assert.throws(()=>addSelectedSpell({},{id:"spell:z",name:"Z",level:10}),/non valido/);
});

test("equipping weapons, shields and armor uses native slots and two-hand conflicts",()=>{
  const longsword={id:"w1",name:"Sword",type:"M",damage:"1d8",quantity:1,equipped_slots:[]};
  const greatsword={id:"w2",name:"Greatsword",type:"M",damage:"2d6",properties:["2H"],quantity:1,equipped_slots:[]};
  const shield={id:"s1",name:"Shield",type:"S",quantity:1,equipped_slots:[]};
  const armor={id:"a1",name:"Chain",type:"HA",quantity:1,equipped_slots:[]};
  const initial=[longsword,greatsword,shield,armor];
  assert.equal(validSlot(greatsword,"off"),false);
  assert.equal(validSlot(shield,"off"),true);
  assert.equal(validSlot(armor,"main"),false);
  let rows=equipSlot(initial,"main",0);
  rows=equipSlot(rows,"off",2);
  assert.deepEqual(rows[0].equipped_slots,["main"]);
  assert.deepEqual(rows[2].equipped_slots,["off"]);
  rows=equipSlot(rows,"main",1);
  assert.deepEqual(rows[0].equipped_slots,[]);
  assert.deepEqual(rows[1].equipped_slots,["main"]);
  assert.deepEqual(rows[2].equipped_slots,[],"two-handed main weapon clears offhand");
  rows=equipSlot(rows,"body",3);
  assert.deepEqual(rows[3].equipped_slots,["body"]);
  rows=equipSlot(rows,"main",-1);
  assert.deepEqual(rows[1].equipped_slots,[]);
  assert.deepEqual(rows[3].equipped_slots,["body"]);
  assert.deepEqual(initial[0].equipped_slots,[],"input never mutated");
  assert.throws(()=>equipSlot(initial,"off",1),/incompatibile/);
  assert.throws(()=>equipSlot(initial,"head",1),/Slot/);
});

test("offhand override preserves a two-handed main weapon but never puts 2H weapons offhand",()=>{
  const greatsword={name:"Spadone",type:"M",properties:["2H"],quantity:1,equipped_slots:[]};
  const dagger={name:"Pugnale",type:"M",properties:["L"],quantity:1,equipped_slots:[]};
  const shield={name:"Scudo",type:"S",quantity:1,equipped_slots:[]};
  const initial=[greatsword,dagger,shield];
  const main=equipSlot(initial,"main",0);
  assert.throws(()=>equipSlot(main,"off",1),/secondaria occupata/);
  const unlocked=equipSlot(main,"off",1,{allowOffhandWithTwoHanded:true});
  assert.deepEqual(unlocked[0].equipped_slots,["main"]);
  assert.deepEqual(unlocked[1].equipped_slots,["off"]);
  assert.deepEqual(initial[0].equipped_slots,[]);
  assert.throws(()=>equipSlot(main,"off",0,{allowOffhandWithTwoHanded:true}),/incompatibile/);
  const switched=equipSlot(unlocked,"off",2,{allowOffhandWithTwoHanded:true});
  assert.deepEqual(switched[0].equipped_slots,["main"]);
  assert.deepEqual(switched[2].equipped_slots,["off"]);
  const normal=equipSlot(switched,"main",0);
  assert.deepEqual(normal[2].equipped_slots,[]);
});

test("clearing an equipment slot does not re-equip or remove unrelated equipment",()=>{
  const sword={name:"Spada",type:"M",properties:["L"],equipped_slots:[],quantity:1};
  const shield={name:"Scudo",type:"S",equipped_slots:[],quantity:1};
  const armor={name:"Corazza",type:"HA",equipped_slots:[],quantity:1};
  const main=equipSlot([sword,shield,armor],"main",0);
  const armored=equipSlot(main,"body",2);
  const both=equipSlot(armored,"off",1);
  const withoutShield=equipSlot(both,"off",-1);
  assert.deepEqual(withoutShield.map(item=>item.equipped_slots),[["main"],[],["body"]]);
  const withoutSword=equipSlot(withoutShield,"main",-1);
  assert.deepEqual(withoutSword.map(item=>item.equipped_slots),[[],[],["body"]]);
  const withoutArmor=equipSlot(withoutSword,"body",-1);
  assert.deepEqual(withoutArmor.map(item=>item.equipped_slots),[[],[],[]]);
  const doubleHand=equipSlot([{name:"Spadone",type:"M",properties:["2H"],equipped_slots:[]}],"main",0);
  assert.deepEqual(equipSlot(doubleHand,"main",-1)[0].equipped_slots,[]);
});

test("identical shields collapse into one quantity stack without losing occupied hands",()=>{
  const template={id:"shield:phb",name:"Shield",type:"S",ac:2,source:"PHB"};
  const main={...createOwnedItem(template,"shield_1"),equipped_slots:["main"]};
  const off={...createOwnedItem(template,"shield_2"),equipped_slots:["off"]};
  const before=structuredClone([main,off]);
  const result=consolidateOwnedItems([main,off]);
  assert.equal(result.length,1);
  assert.equal(result[0].quantity,2);
  assert.deepEqual(result[0].equipped_slots,["main","off"]);
  assert.equal(result[0].instance_id,"shield_1");
  assert.deepEqual([main,off],before,"the source archive remains untouched");
  assert.deepEqual(consolidateOwnedItems(result),result,"normalization is idempotent");
  const unequipped={...createOwnedItem(template,"shield_3")};
  const consolidated=consolidateOwnedItems([...result,unequipped]);
  assert.equal(consolidated.length,1);
  assert.equal(consolidated[0].quantity,3);
  assert.deepEqual(consolidated[0].equipped_slots,["main","off"]);
});

test("stacks never discard per-copy overrides, infusion, attunement or conflicting slots",()=>{
  const base={id:"shield:phb",name:"Shield",type:"S",ac:2,quantity:1,equipped_slots:[]};
  const modified={...base,instance_overrides:{bonus_ac:1}};
  assert.equal(consolidateOwnedItems([base,modified]).length,2);
  assert.equal(consolidateOwnedItems([base,{...base,infusion:{id:"infused"}}]).length,2);
  assert.equal(consolidateOwnedItems([base,{...base,attuned:true}]).length,2);
  assert.equal(consolidateOwnedItems([{...base,equipped_slots:["off"]},{...base,equipped_slots:["off"]}]).length,2);
  assert.equal(consolidateOwnedItems([{...base,id:"shield:other"} ,base]).length,2);
  const doc={...base,category:"documents"};
  assert.equal(consolidateOwnedItems([doc,{...doc,instance_id:"doc_2"}]).length,2);
  const nearlyFull={...base,quantity:99999};
  assert.equal(consolidateOwnedItems([nearlyFull,base]).length,2);
});
