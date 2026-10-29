// Typed d20 rerolls. Sources come from feat/trait grants or the ordinary
// inspiration state, never from feature-name checks or prose matching.
const entries=value=>Array.isArray(value)?value:[];
export function rerollTargetMatches(target,key){
 const roll=String(key||'');
 if(target==='any_d20')return /^(?:save:|skill:|ability_check:|attack_hit:|casting_hit:)/.test(roll)||roll==='initiative';
 if(target==='saving_throw')return roll.startsWith('save:');
 if(target==='attack_roll')return roll.startsWith('attack_hit:')||roll.startsWith('casting_hit:');
 if(target==='ability_check')return roll.startsWith('ability_check:')||roll.startsWith('skill:')||roll==='initiative';
 if(target==='spell_attack')return roll.startsWith('casting_hit:');
 if(target==='initiative')return roll==='initiative';
 return target===roll;
}
export function availableD20Rerolls(record={},calculated={},target='',outcome=null){
 const sources=[...entries(calculated.feat_d20_rerolls)];
 if(record.inspiration)sources.push({id:'inspiration',name:'Ispirazione',origin_name:'Ispirazione',
  targets:['any_d20'],payment_mode:'inspiration',tracker_cost:1});
 return sources.filter(row=>{
  if(!row||row.disabled||!entries(row.targets).some(t=>rerollTargetMatches(t,target)))return false;
  if(row.trigger==='on_one'&&(!outcome||!entries(outcome.parts?.[0]?.rolls).includes(1)))return false;
  if(row.payment_mode==='inspiration')return Boolean(record.inspiration);
  if(!row.tracker_id)return true;
  const tracker=entries(calculated.trackers).find(t=>t.id===row.tracker_id&&!t.disabled);
  const cost=Math.max(1,Number(row.tracker_cost)||1);
  return !!tracker&&(Number(tracker.max)-Number(tracker.spent||0))>=cost;
 });
}
export function offerD20Reroll(outcome={},die,source={}){
 if(!Array.isArray(outcome.parts)||outcome.parts[0]?.kind==='flat'||
    !Array.isArray(outcome.parts[0]?.rolls)||!outcome.parts[0].rolls.length||
    !Number.isSafeInteger(outcome.total)||typeof die!=='function')
  throw Error('Tiro d20 originale non disponibile.');
 const result=die(20);
 if(!Number.isInteger(result)||result<1||result>20)throw Error('Nuovo d20 non valido.');
 const previous=Number(outcome.parts[0].subtotal);
 const parts=[{...outcome.parts[0],rolls:[...outcome.parts[0].rolls,result],
  notation:(outcome.parts[0].rolls.length+1)+'d20 · ritiro'},...outcome.parts.slice(1)];
 return {...outcome,count:parts[0].rolls.length,rolls:[...parts[0].rolls],
  parts,notation:String(outcome.notation||'')+' · +1d20',
  d20_reroll:{source_id:String(source.id||''),source_name:String(source.origin_name||source.name||'Ritiro'),
    previous,new_roll:result,selected:'previous',before_total:outcome.total}};
}
export function chooseD20Reroll(outcome={},choice='previous'){
 const data=outcome.d20_reroll;
 if(!data||!['previous','new'].includes(choice))throw Error('Scelta del ritiro non valida.');
 const kept=choice==='new'?data.new_roll:data.previous;
 const parts=[{...outcome.parts[0],subtotal:kept},...outcome.parts.slice(1)];
 const total=data.before_total-data.previous+kept;
 return {...outcome,parts,total,d20_reroll:{...data,selected:choice},
  detail:String(outcome.detail||'').replace(/ · ritiro d20 \[[^\]]*\]$/,'').replace(/ · totale -?\d+(?: · .*?)?$/,'')+
   ' · totale '+total+' · ritiro d20 ['+data.previous+' → '+data.new_roll+': '+kept+']'};
}
