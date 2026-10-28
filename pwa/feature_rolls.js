// Stable target for any non-d20 roll provided by a feat, species, class or item.
// Extensions and optional dice reference this ID, never the translated label.
import {effectExtensionsFor} from './effect_extensions.js';
const rows=value=>Array.isArray(value)?value:[];
export const featureRollTarget=ability=>ability?.roll_effect&&
 String(ability.id||'').trim()?'feature_roll:'+String(ability.id):'';
const formulaValue=(value,calculated={})=>{
 const text=String(value??'').trim().replace(/\s+/g,'');
 if(/^[+-]?\d+$/.test(text))return Number(text);
 const match=/^(proficiency|(?:str|dex|con|int|wis|cha)_mod)([+-]\d+)?$/.exec(text);
 if(!match)return null;
 const base=match[1]==='proficiency'?Number(calculated.values?.proficiency??calculated.stats?.proficiency):
  Number(calculated.abilities?.[match[1].slice(0,3)]?.modifier);
 return Number.isFinite(base)?base+Number(match[2]||0):null;
};
export function featureRollExtensionBonuses(calculated={},ability={}){
 const target=featureRollTarget(ability);
 if(!target)return [];
 return effectExtensionsFor(calculated.effect_extensions,{kind:'ability',id:ability.id,name:ability.name})
  .filter(row=>row.operation==='bonus_roll').flatMap(row=>{
   const raw=String(row.value??'').trim().replace(/\s+/g,'');
   const dice=/^[1-9]\d*d(?:4|6|8|10|12|20|100)(?:[+-]\d+)?$/i.test(raw);
   const flat=dice?null:formulaValue(raw,calculated);
   if(!dice&&flat===null||!dice&&flat===0)return [];
   return [{id:'extension-roll:'+row.id,origin_id:row.origin_id||'',
    origin_name:row.origin_name||'Estensione · '+(row.target_name||ability.name),
    granting_trait:row.origin_name||'',target,condition_label:row.description||'',
    ...(dice?{dice:raw}:{flat_bonus:flat}),optional:true,automatic:true}];
  });
}
