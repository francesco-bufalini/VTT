// Stable target for any non-d20 roll provided by a feat, species, class or item.
// Extensions and optional dice reference this ID, never the translated label.
import {effectExtensionsFor} from './effect_extensions.js';
import {formulaValue as sheetFormulaValue} from './sheet_rules.js';
const rows=value=>Array.isArray(value)?value:[];
export const featureRollTarget=ability=>!ability?.roll_effect?'':
 String(ability.roll_effect.target||'').startsWith('feature_roll:')?
  String(ability.roll_effect.target):
  String(ability.ability_id||ability.id||'').trim()?
  'feature_roll:'+String(ability.ability_id||ability.id).replace(/^activated:/,''):'';
const resolveFeatureRollFormula=(value,calculated={})=>{
 const expression=String(value??'').trim().replace(/\s+/g,'');
 if(!/^(?:[+-]?\d+|(?:proficiency|attuned_item_count|attuned_items|attunement_used|(?:str|dex|con|int|wis|cha)_mod)(?:[+-]\d+)?)$/.test(expression))return null;
 const values={...calculated.values};
 if(!Number.isFinite(Number(values.proficiency))&&Number.isFinite(Number(calculated.stats?.proficiency)))values.proficiency=Number(calculated.stats.proficiency);
 for(const ability of ['str','dex','con','int','wis','cha']){
  const key='ability_mod:'+ability;
  if(!Number.isFinite(Number(values[key]))&&Number.isFinite(Number(calculated.abilities?.[ability]?.modifier)))values[key]=Number(calculated.abilities[ability].modifier);
 }
 try{return sheetFormulaValue(expression,{...calculated,values});}catch{return null;}
};
// Numeric trait bonuses use formula_bonuses elsewhere in the sheet. Feature
// rolls have no permanent score to mutate, so resolve the same typed source
// only while displaying the matching ability's roll.
export function featureRollFlatBonuses(record={},calculated={},ability={}){
 const target=featureRollTarget(ability);
 if(!target)return [];
 return rows(record.formula_bonuses).filter(row=>row?.target===target&&!row.disabled&&
   record.origin_enabled?.[row.origin_id]!==false&&
   !rows(record.proficiency_origins).some(origin=>origin.id===row.origin_id&&origin.disabled))
  .flatMap(row=>{
   const amount=resolveFeatureRollFormula(row.expression,calculated);
   if(amount===null||!amount)return [];
   return [{id:'feature-formula:'+row.id,origin_id:row.origin_id||'',
    origin_name:row.origin_name||'Bonus al tiro della capacità',target,
    flat_bonus:amount,optional:true,automatic:false}];
  });
}
export function featureRollExtensionBonuses(calculated={},ability={}){
 const target=featureRollTarget(ability);
 if(!target)return [];
 return effectExtensionsFor(calculated.effect_extensions,{kind:'ability',id:ability.ability_id||ability.id,name:ability.name})
  .filter(row=>row.operation==='bonus_roll').flatMap(row=>{
   const raw=String(row.value??'').trim().replace(/\s+/g,'');
   const dice=/^[1-9]\d*d(?:4|6|8|10|12|20|100)(?:[+-]\d+)?$/i.test(raw);
   const flat=dice?null:resolveFeatureRollFormula(raw,calculated);
   if(!dice&&flat===null||!dice&&flat===0)return [];
   return [{id:'extension-roll:'+row.id,origin_id:row.origin_id||'',
    origin_name:row.origin_name||'Estensione · '+(row.target_name||ability.name),
    granting_trait:row.origin_name||'',target,condition_label:row.description||'',
    ...(dice?{dice:raw}:{flat_bonus:flat}),optional:true,automatic:true}];
  });
}
