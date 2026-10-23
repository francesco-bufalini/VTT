// Explain a complete d20 roll without re-implementing the character evaluator.
// Every applied formula grant comes from calculateSheet.roll_components; it has
// already passed origin, requirements and circular-dependency checks.
import {SKILLS,validBonusDice} from './sheet_rules.js';

const list = value => Array.isArray(value) ? value : [];
const num = value => Number.isFinite(Number(value)) ? Number(value) : 0;
const abilityNames = {str:'FOR',dex:'DES',con:'COS',int:'INT',wis:'SAG',cha:'CAR'};
const signed = value => (value < 0 ? '−' : '+') + Math.abs(value);
export const sheetRollSymbol = value => String(value ?? '').replace(/\b(str|dex|con|int|wis|cha)_mod\b/gi,(_,a)=>'Mod.'+abilityNames[a.toLowerCase()])
 .replace(/\b(str|dex|con|int|wis|cha)_score\b/gi,(_,a)=>'Punt.'+abilityNames[a.toLowerCase()])
 .replace(/\b(proficiency|prof)\b/gi,'Mod.Competenza')
 .replace(/\*/g,' × ');
function bonusText(expression) {
 const raw=sheetRollSymbol(expression).trim();
 return /^[+-]/.test(raw)?raw.startsWith('-')?'−'+raw.slice(1).trim():'+'+raw.slice(1).trim():'+'+raw;
}
function abilityFor(target,calculated){
 if(target.startsWith('skill:'))return SKILLS.find(([key])=>key===target.slice(6))?.[2]||'';
 if(target.startsWith('save:'))return target.slice(5);
 if(target.startsWith('ability_check:')||target.startsWith('ability_mod:'))return target.split(':')[1]||'';
 if(target==='initiative')return 'dex';
 if(target.startsWith('casting_hit:'))return target.slice('casting_hit:'.length);
 if(target.startsWith('attack_hit:'))return list(calculated?.attacks).find(a=>'attack_hit:'+a.id===target)?.ability||'';
 return '';
}
function trainingRank(calculated,target){
 const skills=list(calculated?.proficiencies);
 if(target.startsWith('skill:')){
   const name=target.slice(6);
   return skills.includes('expertise:'+name)?2:skills.includes('skill:'+name)?1:0;
 }
 if(target.startsWith('save:'))return skills.includes('save:'+target.slice(5))?1:0;
 if(target.startsWith('casting_hit:'))return 1;
 if(target.startsWith('attack_hit:')&&!target.startsWith('attack_hit:monster:'))
   return list(calculated?.attacks).find(a=>'attack_hit:'+a.id===target)?.proficient?1:0;
 return 0;
}
function trainingOrigin(record,target,calculated){
 const kind=target.startsWith('skill:')?'skill':target.startsWith('save:')?'save':'';
 const key=target.split(':')[1]||'';
 const declared=kind==='skill'&&trainingRank(calculated,target)===2?
   list(calculated?.proficiency_sources?.['expertise:'+key]):
   list(calculated?.proficiency_sources?.[kind+':'+key]);
 if(declared.length)return {id:declared[0].id,name:declared[0].name};
 const choices=list(record?.proficiency_choices);
 const row=choices.find(c=>!c?.disabled&&(c.kind===kind||
   kind==='skill'&&c.kind==='expertise')&&c.key===key&&c.origin_id);
 if(row)return {id:row.origin_id,name:row.origin_name||list(calculated?.origins).find(o=>o.id===row.origin_id)?.name||'Competenza'};
 // Weapon/spell attack proficiency follows general rules. In multiclass
 // characters, assigning it to a guessed class would fabricate provenance.
 return {id:'',name:kind==='skill'&&trainingRank(calculated,target)===2?'Maestria':'Competenza',
   section:'proficiency_choices'};
}
// Returns symbolic and expanded numeric forms for each source. No random dice
// are evaluated merely by opening the popup.
export function sheetRollOriginSegments(record,calculated,target,{mode='normal',diceBonuses=[],modeSources=[],cancelled=false}={}){
 const total=Number(calculated?.values?.[target]);
 if(!Number.isFinite(total))return [];
 const all=calculated?.roll_components||{};
 const result=[];
 const monsterAttack=target.startsWith('attack_hit:')&&
   String(list(calculated?.attacks).find(a=>'attack_hit:'+a.id===target)?.explanation||'').startsWith('Bestiario ');
 const ability=monsterAttack?'':abilityFor(target,calculated);
 const rank=monsterAttack?0:trainingRank(calculated,target);
 const score=num(record?.abilities?.[ability]??10);
 // Score grants change Mod.FOR / Mod.DES itself; they aren't additional
 // bonuses to an attack formula. Display the effective modifier in Base.
 const adjustedScore=score+list(all['ability:'+ability]).reduce((sum,row)=>sum+num(row.value),0);
 const abilityBase=ability?Math.floor((adjustedScore-10)/2):0;
 const profTotal=num(calculated?.values?.proficiency);
 const proficiencyExtras=list(all.proficiency).reduce((sum,row)=>sum+num(row.value),0);
 const proficiencyBase=profTotal-proficiencyExtras;
 let core=ability?abilityBase:0;
 let consumed=0;
 const appended=new Set();
 const add=(row,scale=1,kind='formula')=>{
   if(!row||!Number.isFinite(Number(row.value)))return;
   const value=num(row.value)*scale, id=String(row.id||row.origin_id||'')+'|'+kind+'|'+scale;
   if(appended.has(id))return;
   appended.add(id);consumed+=value;
   result.push({kind,formula:bonusText(scale===1?row.expression:scale+' × ('+row.expression+')'),
     expanded:signed(value),value,originId:String(row.origin_id||''),
     originName:row.origin_name||'Bonus',
     section:row.origin_id?'':'formula_bonuses',key:id});
 };
 if(ability){
   // Only bonuses applied directly to the modifier deserve separate terms.
   for(const row of list(all['ability_mod:'+ability]))add(row);
 }
 if(rank){
   // This is a standard rules contribution but the source of proficiency is
   // still a navigable trait, unlike the base d20 + ability modifier.
   const source=trainingOrigin(record,target,calculated);
   const amount=rank*proficiencyBase;
   consumed+=amount;
   result.push({kind:'training',formula:'+'+(rank===2?'2 × ':'')+'Mod.Competenza',
     expanded:signed(amount),value:amount,originId:source.id,
     originName:source.name,section:source.section||'',key:'training'});
   for(const row of list(all.proficiency))add(row,rank);
 }
 const targetKeys=[];
 if(target==='initiative'||target.startsWith('skill:')||target.startsWith('ability_check:'))targetKeys.push('ability_check');
 if(target.startsWith('save:'))targetKeys.push('saving_throw');
 if(target.startsWith('casting_hit:'))targetKeys.push('spell_attack');
 targetKeys.push(target);
 for(const key of targetKeys)for(const row of list(all[key]))add(row);
 // Some legacy monsters and attack rules have additional built-in terms not
 // represented by a grant. Keep their value in Base instead of inventing an
 // origin or silently dropping it.
 const remainder=total-core-consumed;
 const base={kind:'base',formula:'1d20'+(ability?' + Mod.'+abilityNames[ability]:
   monsterAttack?' + Attacco del bestiario':' + Base'),
   expanded:'1d20 '+signed(monsterAttack?total-consumed:core),value:monsterAttack?total-consumed:core,
   originName:'Base · regole',originId:'',key:'base'};
 if(!monsterAttack&&Math.abs(remainder)>0.000001)result.push({
   kind:'rules',formula:(remainder<0?'−':'+')+' Altri modificatori',
   expanded:signed(remainder),value:remainder,originName:'Contributo non attribuito',
   originId:'',section:'formula_bonuses',key:'rules'});
 // Dado bonus selections belong to the same source as flat grants.
 // The result is not thrown during a preview: show the symbolic die on
 // both rows until the user actually rolls it.
 for(const [i,row] of list(diceBonuses).entries()){
   const dice=String(row?.dice||'').replace(/\s+/g,'');
   if(!validBonusDice(dice))continue;
   result.push({kind:'dice',formula:'+'+dice,expanded:'+'+dice,value:0,
     originId:String(row.origin_id||''),originName:row.origin_name||'Dado bonus',
     section:row.origin_id?'':'formula_bonuses',key:'dice:'+i});
 }
 // One source gets one segment even if it grants training and multiple
 // flat/dice bonuses. Keep separate terms within that origin's two rows.
 const grouped=[],byOrigin=new Map();
 for(const row of result){
   const id=row.originId;
   if(!id||!byOrigin.has(id)){
     grouped.push({...row});
     if(id)byOrigin.set(id,grouped[grouped.length-1]);
     continue;
   }
   const previous=byOrigin.get(id);
   previous.formula+=' '+row.formula;
   previous.expanded+=' '+row.expanded;
   previous.value+=row.value;
 }
 const ordered=[];
 const activeModes=list(modeSources).filter(row=>['advantage','disadvantage'].includes(row.mode));
 if(activeModes.length){
   const seen=new Set();
   for(const row of activeModes){
     const key=row.mode+'|'+String(row.origin_id||'')+'|'+String(row.origin_name||'');
     if(seen.has(key))continue;
     seen.add(key);
     ordered.push({kind:'mode',formula:row.mode==='advantage'?'ADV':'DIS',
       expanded:cancelled?'Annullato':'',value:0,
       originId:row.origin_id||'',originName:row.origin_name||'Origine',
       section:row.kind==='condition'?'conditions':'',key});
   }
 }else if(mode==='advantage'||mode==='disadvantage'){
   ordered.push({kind:'mode',formula:mode==='advantage'?'ADV':'DIS',
     expanded:'',value:0,originId:'',originName:'Modalità scelta',key:'mode'});
 }
 ordered.push(base,...grouped);
 return ordered;
}
// UI-only abbreviation: keep the original provenance ID and full name
// unchanged for navigation/tooltips while skipping generic prefixes.
export function sheetRollOriginLabel(name){
 const full=String(name||'').trim();
 const short=full.replace(/^(?:(?:oggetto|tratto|privilegio|item)\s*[-–—:·]\s*)+/gi,'').trim();
 return short||full;
}
// The damage formula and the damage types are independent data: one type
// covers every die group, or an ordered list maps to the respective groups.
// Never invent a type when an ambiguous list does not match the die groups.
const damageSign=value=>Number(value)<0?' − '+Math.abs(Number(value)):' + '+Number(value);
const normalizeDamage=value=>String(value||'').replace(/\s+/g,'').replace(/−/g,'-');
const damageDie=term=>/^\+?[1-9]\d*d(?:2|3|4|6|8|10|12|20|100)$/i.test(term);
const damageInteger=term=>/^[+-]?\d+$/.test(term);
function damageModifierExpression(value,attack,notation){
 if(!value)return '';
 const ability=String(attack?.ability||'').toLowerCase();
 const source=normalizeDamage(attack?.damage_base_formula);
 const rawModifier=Number(attack?.damage_ability_modifier)+Number(attack?.damage_extra_modifier);
 const expected=source+(rawModifier>0?'+'+rawModifier:rawModifier<0?String(rawModifier):'');
 const matches=source&&normalizeDamage(attack?.damage)===normalizeDamage(notation)&&
   expected===normalizeDamage(notation);
 const sourceTerms=source.match(/[+-]?[^+-]+/g)||[];
 const staticBase=sourceTerms.filter(damageInteger).reduce((sum,term)=>sum+Number(term),0);
 const abilityAmount=Number(attack?.damage_ability_modifier);
 const extra=Number(attack?.damage_extra_modifier);
 if(matches&&Object.hasOwn(abilityNames,ability)&&Number.isFinite(abilityAmount)&&
   Number.isFinite(extra)&&staticBase+abilityAmount+extra===value&&abilityAmount!==0){
   const remaining=staticBase+extra;
   return ' + Mod.'+abilityNames[ability]+(remaining?damageSign(remaining):'');
 }
 // An unknown source must not be falsely identified as a Strength modifier.
 return ' + Modificatore';
}
// One section for base damage dice and their modifier. Different damage
// types get separate sections. Keep the numeric roll untouched.
export function damageRollSegments(roll,type='',attack=null){
 const notation=normalizeDamage(roll?.notation);
 const terms=notation.match(/[+-]?[^+-]+/g)||[];
 const dice=terms.filter(damageDie);
 const labels=(Array.isArray(type)?type.map(String):String(type||'').split(/[,;]/))
   .map(value=>value.trim()).filter(Boolean);
 const typed=labels.length===1||labels.length===dice.length;
 const groups=[];
 for(let i=0;i<dice.length;i++){
   const kind=typed?(labels.length===1?labels[0]:labels[i]):'';
   const term=dice[i].replace(/^\+/,'');
   const previous=groups.at(-1);
   if(previous&&previous.damageType===kind)previous.dice.push(term);
   else groups.push({damageType:kind,dice:[term]});
 }
 const modifier=Number(roll?.modifier)||0;
 return groups.map((group,index)=>{
   const base=index===0;
   const formula=group.dice.join(' + ');
   return {key:'damage:'+index,kind:base?'base':'formula',
     formula:(base?'':' + ')+formula+(base?damageModifierExpression(modifier,attack,notation):''),
     expanded:'',damageType:group.damageType,originName:base?'Danno base':'Danno aggiuntivo',
     originId:'',value:base?modifier:0};
 });
}
export const rollDamageName=type=>{
 const labels={L:'Fulmine',T:'Tuono',A:'Acido',C:'Freddo',F:'Fuoco',
  N:'Necrotico',P:'Veleno',R:'Radioso',Y:'Psichico',B:'Contundente',
  S:'Tagliente',I:'Perforante',lightning:'Fulmine',thunder:'Tuono',
  bludgeoning:'Contundente',piercing:'Perforante',slashing:'Tagliente',
  acid:'Acido',cold:'Freddo',fire:'Fuoco',force:'Forza',
  necrotic:'Necrotico',poison:'Veleno',psychic:'Psichico',radiant:'Radiante'};
 const raw=String(type||'').trim();
 return labels[raw]||labels[raw.toLowerCase()]||raw||'Non specificato';
};
// These optional sources are never added automatically. They remain a
// selection belonging to the roll dialog and are validated before rolling.
export function rollOptionalDice(record,calculated,bonuses=[],{kind='d20',attackId=''}={}){
 const result=[];
 const trackerFor=id=>(calculated?.trackers||[]).find(t=>t.id===id&&!t.disabled);
 for(const [i,row] of (Array.isArray(bonuses)?bonuses:[]).entries()){
  const tracker=row.tracker_id?trackerFor(row.tracker_id):null;
  if(row.tracker_id&&!tracker)continue;
  const remaining=tracker?Math.max(0,Number(tracker.max||0)-Number(tracker.spent||0)):null;
  if(remaining!==null&&remaining<Math.max(1,Number(row.tracker_cost)||1))continue;
  result.push({...row,selectionId:'bonus:'+i,remaining,
    spent:tracker?Number(tracker.spent||0):null,
    tracker_name:tracker?.name||'',tracker_cost:tracker?Math.max(1,Number(row.tracker_cost)||1):0});
 }
 if(kind==='damage'&&attackId==='class_feature:lightning_launcher'){
  const tracker=trackerFor('feature:lightning_launcher:extra_damage');
  const remaining=tracker?Math.max(0,Number(tracker.max)-Number(tracker.spent||0)):0;
  if(remaining>0)result.push({id:'lightning-launcher:extra',selectionId:'lightning-launcher:extra',
   dice:'1d6',damage_type:'lightning',origin_name:'Lightning Launcher',
   origin_id:tracker.origin_id,tracker_id:tracker.id,tracker_cost:1,
   tracker_name:tracker.name,spent:Number(tracker.spent||0),remaining});
 }
 return result;
}
export function sheetRollOriginHtml(segments,escapeHtml){
 const esc=escapeHtml;
 return '<div class="sheet-roll-origin-terms" role="group" aria-label="Formula del tiro per origine">'+segments.map(row=>{
   const clickable=row.kind!=='base'&&(row.originId||row.section);
   const tag=clickable?'button':'div';
   return '<'+tag+(clickable?' type="button" data-act="roll-origin-open" data-origin-id="'+esc(row.originId)+'" data-origin-section="'+esc(row.section||'')+'"':'')+
     ' class="sheet-roll-origin-term'+(clickable?' is-link':'')+(row.kind==='base'?' is-base':'')+'" title="'+esc(row.originName)+'">'+
     '<span class="sheet-roll-origin-symbol">'+esc(row.formula)+'</span>'+
     (row.expanded?'<span class="sheet-roll-origin-value">'+esc(row.expanded)+'</span>':'')+
     (row.damageType!==undefined?'<span class="sheet-roll-origin-damage-type">'+esc(rollDamageName(row.damageType))+'</span>':'')+
     '<span class="sheet-roll-origin-name">'+esc(sheetRollOriginLabel(row.originName))+'</span></'+tag+'>';
 }).join('')+'</div>';
}
