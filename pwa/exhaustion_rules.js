// Effects originate solely from catalog/trait_states.json. The existing
// numeric creature.exhaustion remains the source of truth for rests and saves.
import {exhaustionLevel} from './condition_catalog.js';
const list=value=>Array.isArray(value)?value:[];
const SPEED_TARGETS=new Set(['speed','speed:climb','speed:swim','speed:fly','speed:burrow']);
export function activeExhaustionEffects(record={},catalog={}){
 const rules=catalog?.[record.rules_version==='2024'?'2024':'2014'];
 const level=exhaustionLevel(record);
 return level?list(rules).filter(effect=>effect&&
   Number.isInteger(effect.min_level)&&effect.min_level>=1&&level>=effect.min_level)
   .map(effect=>({...effect,level,
    origin_id:'state|condition:exhaustion:'+level})): [ ];
}
export function exhaustionEffectApplies(effect,target){
 const keys=list(effect.targets).length?effect.targets:[effect.target];
 return keys.some(key=>key===target||
  key==='ability_check'&&(target==='initiative'||/^(?:ability_check:|ability_mod:|skill:)/.test(target))||
  key==='saving_throw'&&target.startsWith('save:')||
  key==='attack_roll'&&/^(?:attack_hit:|casting_hit:)/.test(target)||
  key==='any_d20'&&(target==='initiative'||/^(?:ability_check:|ability_mod:|skill:|save:|attack_hit:|casting_hit:)/.test(target)));
}
export function exhaustionAdjustedValue(value,target,effects=[]){
 if(!Number.isFinite(value))return value;
 return list(effects).filter(rule=>rule.type==='value'&&
   list(rule.targets).includes(target)).reduce((total,rule)=>{
    let next=total;
    if(rule.operation==='multiply'&&Number.isFinite(rule.factor))next=Math.floor(next*rule.factor);
    else if(rule.operation==='set'&&Number.isFinite(rule.value))next=rule.value;
    else if(rule.operation==='add'){
      const amount=Number.isFinite(rule.per_level)?rule.per_level*rule.level:rule.amount;
      if(Number.isFinite(amount))next+=amount;
    }
    if(Number.isFinite(rule.minimum))next=Math.max(rule.minimum,next);
    return next;
   },value);
}
export function exhaustionRollModifier(effects=[],target=''){
 return list(effects).filter(rule=>rule.type==='roll_modifier'&&
   exhaustionEffectApplies(rule,target)).reduce((total,rule)=>
    total+(Number(rule.per_level)||0)*(Number(rule.level)||0),0);
}
export function exhaustionRollModes(effects=[],target=''){
 return list(effects).filter(rule=>rule.type==='roll_mode'&&
   ['advantage','disadvantage'].includes(rule.mode)&&
   exhaustionEffectApplies(rule,target))
   .map(rule=>({mode:rule.mode,kind:'condition',
    condition_id:'exhaustion:'+rule.level,
    origin_id:rule.origin_id,
    origin_name:'Indebolimento · Livello '+rule.level}));
}
export function exhaustionIsDead(effects=[]){
 return list(effects).some(rule=>rule.type==='condition'&&rule.condition==='dead');
}
export function exhaustionRemovablePatch(record={},id=''){
 if(!id)return null;
 const level=exhaustionLevel(record);
 if(id==='exhaustion:'+level&&level>0)
  return {exhaustion:0,conditions:list(record.conditions).filter(code=>
    code!=='exhaustion'&&!/^exhaustion:[1-6]$/.test(code))};
 if(!list(record.conditions).includes(id))return null;
 const patch={conditions:record.conditions.filter(code=>code!==id)};
 if(id==='concentrating')patch.concentrating_spell_id='';
 return patch;
}
