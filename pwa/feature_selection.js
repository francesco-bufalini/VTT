// Generic two-stage choice lifecycle for features with learned and prepared banks.
// Existing lists without a prepared bank are treated as already prepared (migration).
const rows=value=>Array.isArray(value)?value:[];
export const choiceIdentity=row=>String(row?.id||'')+'|'+String(row?.plan_item_id||'');
export const sameChoice=(a,b)=>choiceIdentity(a)===choiceIdentity(b);
export function choiceBanks(record,knownField,preparedField,accept=()=>true){
 const known=rows(record[knownField]).filter(accept);
 const prepared=Object.hasOwn(record,preparedField)
  ?rows(record[preparedField])
  :known.map(row=>({id:row.id,plan_item_id:row.plan_item_id||''}));
 return {known,prepared:known.filter(row=>prepared.some(p=>sameChoice(row,p)))};
}
export function learnChoice(record,knownField,preparedField,choice,accept=()=>true){
 const {known,prepared}=choiceBanks(record,knownField,preparedField,accept);
 if(known.some(row=>sameChoice(row,choice)))throw Error('Scelta già conosciuta.');
 return {[knownField]:[...rows(record[knownField]),choice],
  [preparedField]:prepared.map(row=>({id:row.id,plan_item_id:row.plan_item_id||''}))};
}
export function prepareChoice(record,knownField,preparedField,choice,enabled,accept=()=>true){
 const {known,prepared}=choiceBanks(record,knownField,preparedField,accept);
 if(!known.some(row=>sameChoice(row,choice)))throw Error('Scelta non conosciuta.');
 const ready=prepared.filter(row=>!sameChoice(row,choice)).map(row=>({id:row.id,plan_item_id:row.plan_item_id||''}));
 if(enabled)ready.push({id:choice.id,plan_item_id:choice.plan_item_id||''});
 return {[preparedField]:ready};
}
export function forgetChoice(record,knownField,preparedField,choice,accept=()=>true){
 const {known,prepared}=choiceBanks(record,knownField,preparedField,accept);
 if(!known.some(row=>sameChoice(row,choice)))throw Error('Scelta non trovata.');
 return {[knownField]:rows(record[knownField]).filter(row=>!accept(row)||!sameChoice(row,choice)),
  [preparedField]:prepared.filter(row=>!sameChoice(row,choice))
   .map(row=>({id:row.id,plan_item_id:row.plan_item_id||''}))};
}
