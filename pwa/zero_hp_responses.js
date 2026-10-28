// Optional, source-qualified responses to an incoming hit that would drop a
// creature to 0 HP. Prevention is applied before subtracting HP; it is not healing.
import {hitPointPatch} from './native_sheet.js';
const rows=value=>Array.isArray(value)?value:[];
const nonnegative=value=>Math.max(0,Math.trunc(Number(value)||0));
export function availableZeroHpResponses(record={},calculated={},damage=0){
 const incoming=nonnegative(damage),hp=nonnegative(record.current_hp),temp=nonnegative(record.temporary_hp);
 // A transformed character uses a separate HP/overflow ledger. Do not consume
 // a base-race ability against variant HP until that transition is supported.
 if(record.current_form_id||hp===0||incoming<hp+temp)return [];
 const maximum=nonnegative(calculated.stats?.max_hp);
 return rows(calculated.damage_responses).filter(ability=>{
  const rule=ability?.damage_response;
  if(!rule||rule.trigger!=='would_reach_zero'||!['reduce_damage','retain_one_hp'].includes(rule.effect))return false;
  if(rule.require_not_instant_death&&incoming-temp-hp>=maximum)return false;
  const tracker=rows(calculated.trackers).find(t=>t.id===ability.tracker_id&&!t.disabled);
  if(!tracker||nonnegative(tracker.max)===0||!ability.tracker_id)return false;
  return Math.max(nonnegative(record.resource_tracker_spent?.[tracker.id]),
    nonnegative(tracker.spent))<nonnegative(tracker.max);
 });
}
export function resolveZeroHpDamage(record={},calculated={},incomingDamage=0,responseId='',rollTotal=null){
 const incoming=nonnegative(incomingDamage);
 const response=availableZeroHpResponses(record,calculated,incoming)
  .find(ability=>ability.id===responseId);
 if(!response)throw Error('Risposta ai danni non disponibile o utilizzi esauriti.');
 const effect=response.damage_response.effect;
 let prevented=0,damage=incoming;
 if(effect==='reduce_damage'){
  if(!response.roll_effect||!Number.isSafeInteger(rollTotal))
   throw Error('Inserisci il risultato intero del tiro di riduzione.');
  prevented=Math.min(incoming,nonnegative(rollTotal));
  damage=incoming-prevented;
 }
 const hp=hitPointPatch(record,-damage,calculated);
 if(effect==='retain_one_hp')hp.current_hp=1;
 const tracker=rows(calculated.trackers).find(t=>t.id===response.tracker_id);
 const spent=Math.max(nonnegative(record.resource_tracker_spent?.[response.tracker_id]),
   nonnegative(tracker?.spent));
 return {damage,prevented,response,patch:{...hp,
  resource_tracker_spent:{...(record.resource_tracker_spent||{}),[response.tracker_id]:spent+1}}};
}
