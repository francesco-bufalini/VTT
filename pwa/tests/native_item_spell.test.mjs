import {test} from "node:test";
import assert from "node:assert/strict";
import {itemKind,requiresAttunement,isCatalogItem,createOwnedItem,changeOwnedItem}
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
  const old={spells:[a],prepared_spells:[a],spellbook_spells:[b]};
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
  assert.deepEqual(addSelectedSpell(old,a,"spellbook_spells").spellbook_spells,[b,a]);
  assert.deepEqual(removeSelectedSpell(old,"spellbook_spells",0).spellbook_spells,[]);
  assert.throws(()=>removeSelectedSpell(old,"spells",0),/non valido/);
});
test("spell catalog rejects missing IDs or unsupported levels",()=>{
  assert.throws(()=>addSelectedSpell({},"A"),/non valido/);
  assert.throws(()=>addSelectedSpell({},{id:"spell:z",name:"Z",level:10}),/non valido/);
});
