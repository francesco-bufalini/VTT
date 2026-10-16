// An opt-in sample character for first-time PWA exploration.
// This record is LOCAL ONLY and never sent to the game host.
import { createCreature, openCreatureEditor } from "./creatures.js";

export async function createDemoCreature() {
  const created=await createCreature("character","Eroe di prova");
  const editor=await openCreatureEditor(created.id);
  const record=editor.read();
  await editor.update({
    name:"Eroe di prova",
    player_name:"Dimostrazione",
    class:"Fighter",
    subclass:"Champion",
    level:3,
    species:"Human",
    background:"Soldier",
    rules_version:"2014",
    current_hp:24,
    max_hp_base:28,
    temporary_hp:0,
    armor_class_base:16,
    initiative:2,
    speed_base:30,
    abilities:{str:16,dex:14,con:14,int:10,wis:12,cha:8},
    inventory:[
      {id:"weapon:longsword|phb",name:"Spada lunga",quantity:1,equipped:true},
      {id:"armor:chain mail|phb",name:"Cotta di maglia",quantity:1,equipped:true},
      {id:"item:healing potion|dmg",name:"Pozione di guarigione",quantity:2}
    ],
    resource_trackers:[
      {id:"demo_second_wind",name:"Second Wind",max:1,
        max_formula:"",origin_name:"Fighter",recharge:"short_rest"}
    ],
    resource_tracker_spent:{demo_second_wind:0},
    notes:"Personaggio dimostrativo offline. Puoi modificarlo, esportarlo come JSON VTT oppure eliminarlo.",
    linked_token_sync_id:"",
    linked_token_name:""
  });
  await editor.flush();
  return record.id;
}
