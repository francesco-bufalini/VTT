// The six mutually exclusive condition tiers own the effect data. Each tier
// includes its cumulative 2014 rules; no effect comes from trait_states.json.
import {exhaustionLevel} from './condition_catalog.js';
const list=value=>Array.isArray(value)?value:[];
const SPEED_TARGETS=new Set(['speed','speed:climb','speed:swim','speed:fly','speed:burrow']);
const LABELS={
 ability_check:'Prove di caratteristica',attack_roll:'Tiri per colpire',
 saving_throw:'Tiri salvezza',any_d20:'Prove d20',speed:'Velocità',
 hp:'PF massimi',dead:'Stato'
};
function conditionBenefitEntries(catalog,type,edition,level){
 return list(catalog?.[type]?.entries).filter(entry=>{
  const ref=entry?.granted_by?.ref||{},benefit=entry?.benefit||{};
  return entry.granted_by?.kind==='5etools'&&ref.category==='condition'&&
   ref.name==='Exhaustion'&&ref.source===(edition==='2014'?'PHB':'XPHB')&&
   ref.edition===edition&&ref.level===level&&
   benefit.type===type&&benefit.parameters?.exhaustion_tier===true&&
   benefit.rules_version===edition;
 }).map(entry=>entry.benefit);
}
export function activeExhaustionEffects(record={},catalog={}){
 const edition=record.rules_version==='2024'?'2024':'2014';
 const level=exhaustionLevel(record);
 if(!level)return [];
 const origin_id='state|condition:exhaustion:'+level;
 const rules=[];
 for(const benefit of conditionBenefitEntries(catalog,'roll_mode',edition,level))
  for(const mode of list(benefit.roll_modes)){
   if(!mode.target||!['advantage','disadvantage'].includes(mode.mode))continue;
   rules.push({type:'roll_mode',min_level:level,level,
    target:mode.target,mode:mode.mode,label:LABELS[mode.target]||mode.target,
    detail:mode.mode==='disadvantage'?'Svantaggio':'Vantaggio',origin_id});
  }
 for(const benefit of conditionBenefitEntries(catalog,'roll_bonus',edition,level)){
  const rule=benefit.bonus||{},amount=Number(rule.flat_bonus);
  if(!rule.target||!Number.isFinite(amount))continue;
  rules.push({type:'roll_modifier',min_level:level,level,target:rule.target,
   per_level:amount/level,label:LABELS[rule.target]||rule.target,origin_id});
 }
 for(const benefit of conditionBenefitEntries(catalog,'base_override',edition,level)){
  const base=benefit.base_override||{},params=benefit.parameters||{},
    factor=Number(base.expression),targets=list(params.targets);
  if(!base.target||!['multiply','set','add'].includes(base.operation)||
   !Number.isFinite(factor)||!targets.length||!targets.includes(base.target))continue;
  const detail=base.operation==='multiply'?(factor===.5?(base.target==='hp'?'Dimezzati':'Dimezzata'):'Moltiplicati') :
   base.operation==='set'?(factor===0?'Ridotta a 0':'Valore imposto') :
   'Riduzione della velocità';
  rules.push({type:'value',min_level:Number(params.stage)||level,level,
   operation:base.operation,targets,origin_id,
   ...(base.operation==='multiply'?{factor}:{}),
   ...(base.operation==='set'?{value:factor}:{}),
   ...(base.operation==='add'?{per_level:factor/level}:{}),
   ...(Number.isFinite(Number(params.minimum))?{minimum:Number(params.minimum)}:{}),
   label:LABELS[base.target]||base.target,detail});
 }
 for(const benefit of conditionBenefitEntries(catalog,'condition',edition,level)){
  const condition=benefit.parameters?.result_condition;
  if(condition)rules.push({type:'condition',min_level:level,level,
    condition,label:LABELS[condition]||condition,detail:condition==='dead'?'Morte':condition,origin_id});
 }
 return rules.sort((a,b)=>(a.min_level||0)-(b.min_level||0));
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
