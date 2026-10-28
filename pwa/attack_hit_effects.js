// Reusable on-hit combat debuffs from structured attack metadata.
// A hit is confirmed by the player; never assume a d20 roll hit a target.
// Debuffs on linked local sheets are scoped to the actual target of a later
// attack. An explicit target is required, because Thunder Gauntlets excludes
// attacks against its original wielder.
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();

export function onHitRollEffects(attack={}){
 return rows(attack.on_hit_effects).filter(row=>
  row?.trigger==='on_hit'&&row.operation==='roll_mode'&&
  ['advantage','disadvantage'].includes(row.mode)&&row.target==='attack_roll'&&
  row.duration==='until_start_of_next_turn');
}
export function hitEffectExpired(effect={},snapshot={}){
 const combat=snapshot?.combat;
 const added=Number(effect.applied_round);
 const now=Number(combat?.round);
 if(!combat?.active||!Number.isFinite(added)||added<1||!Number.isFinite(now))return false;
 if(now>added+1)return true;
 if(now<added+1)return false;
 const entries=rows(combat.entries);
 const sourceIndex=entries.findIndex(entry=>String(entry?.token_id||'')===String(effect.source_token_id||''));
 return sourceIndex>=0&&Number(combat.active_index)>=sourceIndex;
}
export function attackHitEffectPatch(targetRecord={},attack={},effectIndex=0,{
 source_token_id='',target_token_id='',source_name='',source_creature_id='',snapshot={}
}={}){
 const effect=onHitRollEffects(attack)[effectIndex];
 if(!effect)throw Error('Questo attacco non ha un effetto applicabile sul colpo.');
 if(!source_token_id||!target_token_id)throw Error('Seleziona due token collegati alla partita.');
 const identifier='attack-hit:'+source_token_id+':'+String(attack.id||'')+':'+target_token_id+':'+effectIndex;
 const mark={id:identifier,source_token_id,target_token_id,
  source_creature_id,source_name,attack_id:String(attack.id||''),attack_name:String(attack.name||''),
  operation:effect.operation,target:effect.target,mode:effect.mode,
  condition_label:effect.condition_label||'',duration:effect.duration,
  applied_round:snapshot?.combat?.active?Number(snapshot.combat.round)||0:0};
 const active=rows(targetRecord.applied_hit_effects).filter(row=>row.id!==identifier&&!hitEffectExpired(row,snapshot));
 return {applied_hit_effects:[...active,mark]};
}
export function attackHitRollSources(record={},rollTarget='',context='',snapshot={}){
 if(!/^(?:attack_hit:|casting_hit:)/.test(rollTarget))return [];
 const targetTokenId=String(context||'').startsWith('attack_target:')?
  String(context).slice('attack_target:'.length):'';
 if(!targetTokenId)return [];
 return rows(record.applied_hit_effects).filter(effect=>
  effect?.mode==='disadvantage'||effect?.mode==='advantage')
 .filter(effect=>effect.target==='attack_roll'&&effect.target_token_id&&
  targetTokenId!==effect.source_token_id&&!hitEffectExpired(effect,snapshot))
 .map(effect=>({id:effect.id,origin_id:effect.id,origin_name:
   (effect.attack_name||'Attacco')+' · '+(effect.source_name||'Fonte'),
   mode:effect.mode,condition_label:effect.condition_label||'',kind:'effect'}));
}
