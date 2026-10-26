// Typed 5etools score allocations. Source policies describe book-wide grants;
// individual origin rows always take precedence. No choices are inferred from prose.
export const STATS=['str','dex','con','int','wis','cha'];
const arr=v=>Array.isArray(v)?v:[];
const norm=v=>String(v||'').toLowerCase();
export function allocationVariants(definitions=[]){
 return arr(definitions).flatMap(raw=>{
  if(!raw||typeof raw!=='object')return [];
  const fields=arr(raw.parts).length?raw.parts:[raw];
  const parts=fields.map(field=>{
   const choose=field.choose;
   if(!choose||!Array.isArray(choose.from))return null;
   const options=[...new Set(choose.from.map(norm).filter(s=>STATS.includes(s)))];
   const count=Number(choose.count??1),amount=Number(choose.amount??1);
   return options.length&&Number.isInteger(count)&&count>0&&count<=6&&
      Number.isInteger(amount)&&amount>0&&amount<=20&&count<=options.length?
      {options,count,amount}:null;
  });
  return parts.every(Boolean)?[{parts,distinct:raw.distinct!==false}]:[];
 });
}
export function originVariants(catalog,group,row,source){
 const explicit=allocationVariants(row?.ability_choices);
 return explicit.length?explicit:
   group==='race'?allocationVariants(catalog?.source_ability_choices?.[String(source||'').toUpperCase()]):[];
}
export function savedAllocation(record,originId,variants,legacy=''){
 const stored=arr(record?.origin_ability_choices).find(r=>r?.origin_id===originId);
 const variant=Number.isInteger(stored?.variant)&&stored.variant>=0&&stored.variant<variants.length?
   stored.variant:variants.length===1?0:-1;
 const allocations=arr(stored?.allocations).filter(x=>STATS.includes(norm(x.ability))&&Number.isInteger(x.part));
 if(!allocations.length&&variants.length===1&&variants[0].parts.length===1){
  const ability=norm(stored?.ability||legacy);
  if(STATS.includes(ability))allocations.push({part:0,ability});
 }
 return {variant,allocations};
}
export function allocationComplete(state,variant){
 if(!variant)return false;
 return variant.parts.every((part,i)=>{
  const chosen=state.allocations.filter(x=>x.part===i).map(x=>x.ability);
  return chosen.length===part.count&&new Set(chosen).size===chosen.length&&chosen.every(x=>part.options.includes(x));
 })&&(!variant.distinct||new Set(state.allocations.map(x=>x.ability)).size===state.allocations.length);
}
export function effectiveAllocations(record,originId,variants,legacy=''){
 const state=savedAllocation(record,originId,variants,legacy),rule=variants[state.variant];
 if(!allocationComplete(state,rule))return [];
 return state.allocations.map(x=>({ability:x.ability,amount:rule.parts[x.part].amount}));
}
export function allocationChoiceRows(record,originId,name,variants,legacy=''){
 if(!variants.length)return [];
 const state=savedAllocation(record,originId,variants,legacy),rows=[];
 // Preserve the original single-stat chooser and persisted ability_choice field.
 // A migration would otherwise silently invalidate old selected feats.
 if(variants.length===1&&variants[0].parts.length===1&&variants[0].parts[0].count===1){
  const part=variants[0].parts[0],selected=state.allocations.map(x=>x.ability).filter(x=>part.options.includes(x));
  return [{id:'ability:'+originId,kind:'ability',origin_id:originId,name,
   label:'Caratteristica (+'+part.amount+')',amount:part.amount,
   count:1,options:part.options,selected,remaining:selected.length?0:1}];
 }
 if(variants.length>1)rows.push({
  id:'ability-mode:'+originId,kind:'ability_mode',origin_id:originId,name,
  label:'Distribuzione degli incrementi',count:1,
  selected:state.variant<0?[]:[String(state.variant)],
  options:variants.map((_,i)=>String(i)),
  option_labels:Object.fromEntries(variants.map((variant,i)=>[String(i),
   variant.parts.map(part=>'+'+part.amount+' a '+part.count+(part.count===1?' caratteristica':' caratteristiche')).join(' e ')])),
  remaining:state.variant<0?1:0
 });
 const rule=variants[state.variant];
 if(!rule)return rows;
 for(const [part,partRule] of rule.parts.entries()){
  const selected=state.allocations.filter(x=>x.part===part).map(x=>x.ability).filter(x=>partRule.options.includes(x));
  rows.push({id:'ability:'+originId+':'+part,kind:'ability',origin_id:originId,name,
   label:'Incremento +'+partRule.amount,amount:partRule.amount,part,variant:state.variant,
   count:partRule.count,options:partRule.options,
   selected,remaining:Math.max(0,partRule.count-selected.length),
   exclusive:rule.distinct,used_elsewhere:state.allocations.filter(x=>x.part!==part).map(x=>x.ability)});
 }
 return rows;
}
export function saveAllocationChoice(record,choice,selected=[]){
 const all=arr(record.origin_ability_choices),original=all.find(x=>x.origin_id===choice.origin_id);
 const rows=all.filter(x=>x.origin_id!==choice.origin_id);
 if(choice.kind==='ability_mode'){
  const variant=selected.length?Number(selected[0]):-1;
  if(variant>=0)rows.push({origin_id:choice.origin_id,variant,allocations:[]});
 }else{
  const variant=Number(choice.variant),part=Number(choice.part);
  const other=arr(original?.allocations).filter(x=>x.part!==part);
  const allocations=[...other,...selected.map(ability=>({part,ability}))];
  if(choice.exclusive&&new Set(allocations.map(x=>x.ability)).size!==allocations.length)
   throw Error('Scegli caratteristiche differenti per gli incrementi.');
  rows.push({origin_id:choice.origin_id,variant,allocations});
 }
 return {origin_ability_choices:rows};
}
