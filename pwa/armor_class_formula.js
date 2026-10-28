// Shared armor-class explanation for both the equipment panel and the score popup.
// The numerical result remains owned by sheet_rules.
import {itemKind,resolveOwnedItem,armorDexterityBonus,armorDexterityLimit} from './item_controls.js';

export function armorClassBaseFormula(record={},calculated={}){
 const inventory=Array.isArray(record.inventory)?record.inventory:[];
 const worn=inventory.find(item=>Array.isArray(item?.equipped_slots)&&
   item.equipped_slots.includes('body')&&itemKind(item)==='armor');
 const armor=worn?resolveOwnedItem(worn):null;
 const shields=inventory.filter(item=>Array.isArray(item?.equipped_slots)&&
   item.equipped_slots.some(slot=>slot==='main'||slot==='off')&&itemKind(item)==='shield')
   .map(resolveOwnedItem);
 const shieldBonus=shields.reduce((value,item)=>Math.max(value,Number(item.ac)||0),0);
 const dex=Number(calculated.values?.['ability_mod:dex']??0);
 const dexCap=armor?armorDexterityLimit(armor):null;
 const armorDex=armor?armorDexterityBonus(armor,dex):0;
 const rawMonsterAc=Array.isArray(record.stat_block?.ac)?
   record.stat_block.ac.find(row=>typeof row==='number'||row?.ac!==undefined):record.stat_block?.ac;
 const monsterAc=typeof rawMonsterAc==='object'?rawMonsterAc?.ac:rawMonsterAc;
 const naturalBase=record.kind==='monster'?(monsterAc??10):(record.armor_class_base??10);
 const naturalFormula=String(record.armor_natural_formula||
   ((record.kind==='character'&&Number(naturalBase)===10)?'10 + dex_mod':String(naturalBase)));
 const appliedNatural=calculated.base_override_applied?.ac_unarmored;
 const chosenNatural=appliedNatural?.expression;
 const displayedNatural=chosenNatural?String(chosenNatural):naturalFormula;
 const usedNatural=Boolean(chosenNatural&&(!armor||appliedNatural.allow_armor||appliedNatural.ignore_armor));
 const formula=armor&&!usedNatural?
   String(Number(armor.ac)||10)+
   (dexCap===0?' (senza DES)':' + ('+armorDex+' DES'+
    (dexCap===null?'':', max '+(dexCap>=0?'+':'')+dexCap)+')')+
   (shieldBonus?' + '+shieldBonus+' scudo':''):
   displayedNatural+(shieldBonus?' + '+shieldBonus+' scudo':'');
 return {formula,sourceLabel:armor&&!usedNatural?'Formula armatura indossata':'Formula CA naturale'};
}
