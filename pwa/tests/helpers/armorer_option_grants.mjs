import {readFileSync} from 'node:fs';
import {calculateSheet} from '../../sheet_rules.js';
import {powerApplicationPatch,powerSelectionModels} from '../../power_selection.js';
const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const grants=read('../../../vtt/enrichment/benefits/option_grant.json');
const lists=read('../../../vtt/enrichment/benefits/option_list.json');
export const armorerSelectionCatalog={optionGrants:grants,optionLists:lists,powerSelections:{selections:[],templates:[]}};
export const withArmorerGrants=catalog=>({...catalog,...armorerSelectionCatalog});
export function applyArmorerModel(record,catalogs,option='armor_model:infiltrator',itemIndex=0){
 const featureContext={features:calculateSheet(record,catalogs).features};
 const root=powerSelectionModels(record,featureContext,armorerSelectionCatalog)
  .find(model=>model.id==='arcane_armor');
 if(!root)throw Error('Arcane Armor not available to this character');
 const initial=powerApplicationPatch(record,featureContext,armorerSelectionCatalog,
  root.id,'arcane_armor',true,{itemIndex});
 const applied={...record,...initial};
 const calculated=calculateSheet(applied,catalogs),ctx={features:calculated.features};
 const targetId=applied.inventory[itemIndex]?.instance_id||applied.inventory[itemIndex]?.id;
 const child=powerSelectionModels(applied,ctx,armorerSelectionCatalog)
  .find(model=>model.id==='armor_model:from:item-instance:'+targetId);
 if(!child)throw Error('Applied Arcane Armor did not grant Armor Model for '+targetId);
 return {...applied,...powerApplicationPatch(applied,ctx,armorerSelectionCatalog,
  child.id,option,true)};
}
