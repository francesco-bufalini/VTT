// Explain a complete d20 roll without re-implementing the character evaluator.
// Every applied formula grant comes from calculateSheet.roll_components; it has
// already passed origin, requirements and circular-dependency checks.
import {SKILLS,validBonusDice} from './sheet_rules.js';
import {armorClassBaseFormula} from './armor_class_formula.js';

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
// Return a concrete granting trait instead of routing proficiency to the retired editor.
export function attackGrantOrigin(calculated,target){
 const id=String(target||'').replace(/^attack_hit:/,'');
 const attack=list(calculated?.attacks).find(row=>row.id===id);
 if(attack?.origin_id)return String(attack.origin_id);
 if(id.startsWith('infusion:'))return id;
 if(id.startsWith('item:')){
  // Offhand and thrown attacks still belong to the same equipped item trait.
  const key=id.replace(/^item:(?:off:|throw:(?:main|off):)?/,'');
  return 'item:'+key;
 }
 if(id.startsWith('shield:improvised:'))return 'item:'+id.split(':').slice(3).join(':');
 if(id.startsWith('monster:'))return 'monster|'+id.split(':')[1];
 if(id.startsWith('class_feature:')){
  const normalized=id.slice('class_feature:'.length).replace(/_/g,' ').toLowerCase();
  return String(list(calculated?.features).find(row=>String(row.name||'').toLowerCase()===normalized)?.origin_id||'');
 }
 return '';
}
function trainingOrigin(record,target,calculated){
 const kind=target.startsWith('skill:')?'skill':target.startsWith('save:')?'save':'';
 const key=target.split(':')[1]||'';
 const sourceItem=attackGrantOrigin(calculated,target);
 const owned=list(record?.inventory).find(row=>'item:'+row.id===sourceItem);
 const weaponKeys=new Set(['weapon:all']);
 if(owned?.name)weaponKeys.add('weapon:'+String(owned.name).toLowerCase());
 if(owned?.weapon_category)weaponKeys.add('weapon:'+String(owned.weapon_category).toLowerCase());
 const candidates=target.startsWith('attack_hit:')?
   Object.entries(calculated?.proficiency_sources||{})
    .filter(([sourceKey])=>weaponKeys.has(sourceKey))
    .flatMap(([,sources])=>list(sources)):
   kind==='skill'&&trainingRank(calculated,target)===2?
     list(calculated?.proficiency_sources?.['expertise:'+key]):
     list(calculated?.proficiency_sources?.[kind+':'+key]);
 const declared=candidates;
 if(declared.length)return {id:declared[0].id,name:declared[0].name};
 const choices=list(record?.proficiency_choices);
 const row=choices.find(c=>!c?.disabled&&(c.kind===kind||
   kind==='skill'&&c.kind==='expertise')&&c.key===key&&c.origin_id);
 if(row)return {id:row.origin_id,name:row.origin_name||list(calculated?.origins).find(o=>o.id===row.origin_id)?.name||'Competenza'};
 // Weapon/spell attack proficiency follows general rules. In multiclass
 // characters, assigning it to a guessed class would fabricate provenance.
 return {id:'proficiency:unattributed',
   name:kind==='skill'&&trainingRank(calculated,target)===2?'Maestria · origine non attribuita':'Competenze · origine non attribuita'};
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
   result.push({kind,formula:bonusText((Number(row.multiplier)||1)*scale===1?row.expression:((Number(row.multiplier)||1)*scale)+' × ('+row.expression+')'),
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
   originName:'Base · regole',originId:target.startsWith('attack_hit:')?attackGrantOrigin(calculated,target):'',key:'base'};
 if(!monsterAttack&&Math.abs(remainder)>0.000001)result.push({
   kind:'rules',formula:(remainder<0?'−':'+')+' Altri modificatori',
   expanded:signed(remainder),value:remainder,originName:'Contributo non attribuito',
   originId:'',section:'formula_bonuses',key:'rules'});
 // Dado bonus selections belong to the same source as flat grants.
 // The result is not thrown during a preview: show the symbolic die on
 // both rows until the user actually rolls it.
 for(const [i,row] of list(diceBonuses).entries()){
  const flat=Number(row?.flat_bonus);
  const hasFlat=Object.hasOwn(row||{},'flat_bonus')&&Number.isSafeInteger(flat);
  const dice=String(row?.dice||'').replace(/\s+/g,'');
  if(!hasFlat&&!validBonusDice(dice))continue;
  const expression=hasFlat?(flat>=0?'+':'')+flat:'+'+dice;
  result.push({kind:hasFlat?'bonus':'dice',formula:expression,expanded:expression,value:0,
   originId:String(row.origin_id||''),originName:row.origin_name||'Bonus',
   section:row.origin_id?'':'formula_bonuses',key:'bonus:'+i});
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
function damageModifierExpression(value,attack,notation,detached=0){
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
 const abilityApplies=attack?.damage_ability_applies??(abilityAmount!==0);
 if(matches&&Object.hasOwn(abilityNames,ability)&&Number.isFinite(abilityAmount)&&
   Number.isFinite(extra)&&staticBase+abilityAmount+extra-detached===value&&abilityApplies){
   const remaining=staticBase+extra-detached;
   return ' + Mod.'+abilityNames[ability]+(remaining?damageSign(remaining):'');
 }
 // A zero-valued ability still contributes symbolically when the underlying
 // attack uses it. Conversely, an offhand style bonus must not fabricate one.
 if(!value)return '';
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
 // The calculated roll already includes unconditional numeric benefits. Use
 // their verified origin breakdown only for presentation: the roll formula and
 // result must remain unchanged. No particular Fighting Style is special here.
 const source=normalizeDamage(attack?.damage_base_formula);
 const attackMod=Number(attack?.damage_ability_modifier)+Number(attack?.damage_extra_modifier);
 const expected=source+(attackMod>0?'+'+attackMod:attackMod<0?String(attackMod):'');
 const verified=source&&Number.isFinite(attackMod)&&
   expected===notation&&normalizeDamage(attack?.damage)===notation;
 const bonusRows=verified?list(attack?.damage_bonus_components)
   .filter(row=>Number.isSafeInteger(Number(row?.value))&&Number(row.value)!==0):[];
 const detached=bonusRows.reduce((total,row)=>total+Number(row.value),0);
 const baseModifier=modifier-detached;
 const segments=groups.map((group,index)=>{
   const base=index===0;
   const formula=group.dice.join(' + ');
   return {key:'damage:'+index,kind:base?'base':'formula',
     formula:(base?'':' + ')+formula+(base?damageModifierExpression(baseModifier,attack,notation,detached):''),
     expanded:'',damageType:group.damageType,originName:base?'Danno base':'Danno aggiuntivo',
     originId:base?String(attack?.origin_id||''):'',value:base?baseModifier:0};
 });
 // Numeric grants inherit the damage type of the weapon's base dice unless
 // their mechanics explicitly model a separately typed damage component.
 for(const [index,row] of bonusRows.entries()){
   const value=Number(row.value);
   segments.push({key:'damage:bonus:'+index,kind:'formula',
     formula:signed(value),expanded:signed(value),value,
     damageType:groups[0]?.damageType||'',originId:String(row.origin_id||''),
     originName:row.origin_name||'Bonus',
     section:row.origin_id?'':'formula_bonuses'});
 }
 return segments;
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
  // Exhausted trackers remain usable by explicit choice; the caller warns before overspending.
  result.push({...row,selectionId:'bonus:'+i,remaining,
    spent:tracker?Number(tracker.spent||0):null,
    tracker_name:tracker?.name||'',tracker_cost:tracker?Math.max(1,Number(row.tracker_cost)||1):0});
 }
 for(const row of kind==='damage'?(calculated?.trait_state_optional_dice||[]):[]){
  if(row.attack_id!==attackId)continue;
  const tracker=trackerFor(row.tracker_id);
  if(!tracker)continue;
  result.push({...row,selectionId:row.id,
    tracker_name:tracker.name,spent:Number(tracker.spent||0),
    remaining:Math.max(0,Number(tracker.max)-Number(tracker.spent||0))});
 }
 return result;
}
// Scores are deterministic values, not rolls: reuse the provenance tiles but
// never introduce a d20, dice result, or a roll action.
export function sheetScoreOriginSegments(record,calculated,target){
 const total=Number(calculated?.values?.[target]);
 if(!Number.isFinite(total))return [];
 const all=calculated?.roll_components||{};
 const linked=calculated?.companion_owner_values;
 let sourceRows=[];
 let base=total;
 let formula='Valore di base';
 let baseName='Regole e dati della creatura';
 if(target==='passive_perception'||target.startsWith('passive_skill:')){
   // Passive skill scores inherit resolved training/bonuses without adding to
   // the active d20 roll; feat-specific passive grants remain separate terms.
   const skill=target==='passive_perception'?'perception':target.slice('passive_skill:'.length);
   const label=SKILLS.find(([id])=>id===skill)?.[1]||skill;
   sourceRows=sheetRollOriginSegments(record,calculated,'skill:'+skill)
     .filter(row=>row.kind!=='mode'&&row.kind!=='dice')
     .map(row=>row.kind==='base'?{
       ...row,formula:row.formula.replace(/^1d20/,'10'),
       expanded:row.expanded.replace(/^1d20/,'10'),
       value:row.value+10,
       originName:label+' passiva · base'}:row);
 }else{
   const baseValues={
     hp:()=>Number(linked?.hp??record?.max_hp_base??record?.max_hp??1),
     second_max:()=>Number(record?.second_form_max_hp??0),
      attunement_max:()=>Math.max(0,Number(record?.attunement_max_base??3)),
     proficiency:()=>Number(linked?.proficiency??(2+Math.floor((Math.max(1,Number(calculated?.stats?.level)||1)-1)/4)))
   };
   if(target.startsWith('ability:')){
     base=Number(record?.abilities?.[target.split(':')[1]]??10);
     formula='Punteggio di base';
     baseName='Caratteristica';
   }else if(target.startsWith('ability_mod:')){
     const ability=target.split(':')[1];
     const effective=Number(calculated?.values?.['ability:'+ability]??record?.abilities?.[ability]??10);
     base=Math.floor((effective-10)/2);
     formula='⌊(Punt.'+(abilityNames[ability]||ability.toUpperCase())+' − 10) / 2⌋';
     baseName='Modificatore della caratteristica';
   }else if(baseValues[target]){
     base=baseValues[target]();
     formula=target==='hp'?'PF di base':target==='proficiency'?'Competenza per livello':
        target==='attunement_max'?'Sintonie di base':'PF seconda forma di base';
     baseName=target==='hp'?'Creatura':target==='proficiency'?'Progressione':target==='attunement_max'?'Sintonia':'Seconda forma';
   }else{
     base=total-list(all[target]).reduce((sum,row)=>sum+num(row.value),0);
     if(target==='ac'){
       const armorFormula=armorClassBaseFormula(record,calculated);
       formula=linked?.explanations?.ac||armorFormula.formula;
       baseName=linked?.explanations?.ac?'Proprietario · '+linked.owner_name:armorFormula.sourceLabel;
      }else formula=target.startsWith('speed')?'Velocità di base':'Valore di base';
   }
   if(linked?.explanations?.[target]){
     formula=linked.explanations[target];baseName='Proprietario · '+linked.owner_name;
   }
   sourceRows=[{kind:'base',formula,expanded:String(base),value:base,
     originId:'',originName:baseName,key:'base'}];
 }
 const applied=new Set();
 for(const row of list(sourceRows)){
   if(row.originId)applied.add(row.originId);
 }
 // Direct grants remain separate and navigable. A derived passive score
 // intentionally includes its skill-derived terms AND direct passive grants.
 for(const row of list(all[target])){
   const value=num(row.value),id=String(row.origin_id||'');
   const formula=bonusText(row.dice_notation||row.expression);
   const existing=id&&sourceRows.find(item=>item.originId===id);
   if(existing){
     existing.formula+=' '+formula;existing.expanded+=' '+signed(value);
     existing.value+=value;
   }else sourceRows.push({kind:'formula',formula,expanded:signed(value),value,
     originId:id,originName:row.origin_name||'Bonus',key:String(row.id||'')});
 }
 const remaining=total-sourceRows.reduce((sum,row)=>sum+num(row.value),0);
 if(Math.abs(remaining)>0.000001){
   const first=sourceRows.find(row=>row.kind==='base');
   if(first){first.value+=remaining;first.expanded=String(first.value);}
   else sourceRows.push({kind:'base',formula:'Altri valori di base',
     expanded:signed(remaining),value:remaining,originId:'',originName:'Regole della creatura'});
 }
 return sourceRows;
}
export function sheetRollOriginHtml(segments,escapeHtml){
 const esc=escapeHtml;
 return '<div class="sheet-roll-origin-terms" role="group" aria-label="Formula del tiro per origine">'+segments.map(row=>{
   const baseEdit=Boolean(row.kind==='base'&&row.editBaseTarget);
   const clickable=baseEdit||Boolean(row.originId||row.section);
   const tag=clickable?'button':'div';
   const action=baseEdit?' type="button" data-act="sheet-score-edit-base" data-score-base-target="'+esc(row.editBaseTarget)+'"':
     clickable?' type="button" data-act="roll-origin-open" data-origin-id="'+esc(row.originId)+'" data-origin-section="'+esc(row.section||'')+'"':'';
   return '<'+tag+action+
     ' class="sheet-roll-origin-term'+(clickable?' is-link':'')+(row.kind==='base'?' is-base':'')+(baseEdit?' is-base-editable':'')+'" title="'+esc(baseEdit?'Modifica '+row.originName:row.originName)+'">'+
     '<span class="sheet-roll-origin-symbol">'+esc(row.formula)+'</span>'+
     (row.expanded?'<span class="sheet-roll-origin-value">'+esc(row.expanded)+'</span>':'')+
     (row.damageType!==undefined?'<span class="sheet-roll-origin-damage-type">'+esc(rollDamageName(row.damageType))+'</span>':'')+
     '<span class="sheet-roll-origin-name">'+esc(sheetRollOriginLabel(row.originName))+'</span></'+tag+'>';
 }).join('')+'</div>';
}
