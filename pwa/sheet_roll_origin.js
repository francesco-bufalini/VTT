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
 const abilityBase=ability?Math.floor((score-10)/2):0;
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
   let running=score;
   for(const row of list(all['ability:'+ability])){
     const next=running+num(row.value);
     const difference=Math.floor((next-10)/2)-Math.floor((running-10)/2);
     running=next;
     if(difference)add({...row,value:difference,expression:'Mod.'+abilityNames[ability]+' ('+row.expression+')'},1,'score');
   }
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
export function sheetRollOriginHtml(segments,escapeHtml){
 const esc=escapeHtml;
 return '<div class="sheet-roll-origin-terms" role="group" aria-label="Formula del tiro per origine">'+segments.map(row=>{
   const clickable=row.kind!=='base'&&(row.originId||row.section);
   const tag=clickable?'button':'div';
   return '<'+tag+(clickable?' type="button" data-act="roll-origin-open" data-origin-id="'+esc(row.originId)+'" data-origin-section="'+esc(row.section||'')+'"':'')+
     ' class="sheet-roll-origin-term'+(clickable?' is-link':'')+(row.kind==='base'?' is-base':'')+'" title="'+esc(row.originName)+'">'+
     '<span class="sheet-roll-origin-symbol">'+esc(row.formula)+'</span>'+
     (row.expanded?'<span class="sheet-roll-origin-value">'+esc(row.expanded)+'</span>':'')+
     '<span class="sheet-roll-origin-name">'+esc(sheetRollOriginLabel(row.originName))+'</span></'+tag+'>';
 }).join('')+'</div>';
}
