// Explain a complete d20 roll without re-implementing the character evaluator.
// Every applied formula grant comes from calculateSheet.roll_components; it has
// already passed origin, requirements and circular-dependency checks.
import {SKILLS,validBonusDice} from './sheet_rules.js';

const list = value => Array.isArray(value) ? value : [];
const num = value => Number.isFinite(Number(value)) ? Number(value) : 0;
const abilityNames = {str:'FOR',dex:'DES',con:'COS',int:'INT',wis:'SAG',cha:'CAR'};
const signed = value => (value < 0 ? '−' : '+') + Math.abs(value);
const symbol = value => String(value ?? '').replace(/\b(str|dex|con|int|wis|cha)_mod\b/gi,(_,a)=>'Mod.'+abilityNames[a.toLowerCase()])
 .replace(/\b(str|dex|con|int|wis|cha)_score\b/gi,(_,a)=>'Punt.'+abilityNames[a.toLowerCase()])
 .replace(/\b(proficiency|prof)\b/gi,'Mod.Competenza')
 .replace(/\*/g,' × ');
function bonusText(expression) {
 const raw=symbol(expression).trim();
 return /^[+-]/.test(raw)?raw.startsWith('-')?'−'+raw.slice(1).trim():'+'+raw.slice(1).trim():'+'+raw;
}
function abilityFor(target){
 if(target.startsWith('skill:'))return SKILLS.find(([key])=>key===target.slice(6))?.[2]||'';
 if(target.startsWith('save:'))return target.slice(5);
 if(target.startsWith('ability_check:')||target.startsWith('ability_mod:'))return target.split(':')[1]||'';
 if(target==='initiative')return 'dex';
 return '';
}
function trainingRank(calculated,target){
 const skills=list(calculated?.proficiencies);
 if(target.startsWith('skill:')){
   const name=target.slice(6);
   return skills.includes('expertise:'+name)?2:skills.includes('skill:'+name)?1:0;
 }
 if(target.startsWith('save:'))return skills.includes('save:'+target.slice(5))?1:0;
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
 return {id:'',name:kind==='skill'&&trainingRank(calculated,target)===2?'Maestria':'Competenza',section:'proficiency_choices'};
}
function featureForAutoAdvantage(record,calculated,target){
 const names=target==='save:dex'&&record?.active_class_features?.patient_defense?['Patient Defense']:
   target.startsWith('attack_hit:')?['Reckless Attack']:
   target.startsWith('casting_hit:')?['Innate Sorcery']:
   ['Rage'];
 const matching=list(calculated?.features).find(f=>names.some(n=>String(f.name||'').toLowerCase()===n.toLowerCase())&&!f.disabled);
 const name=matching?.name||names[0];
 const classNames={'Rage':'Barbarian','Reckless Attack':'Barbarian',
   'Patient Defense':'Monk','Innate Sorcery':'Sorcerer'};
 const className=classNames[names[0]];
 const member=list(record?.classes).find(row=>String(row.name||'').toLowerCase()===String(className||'').toLowerCase())||
   (String(record?.class||'').toLowerCase()===String(className||'').toLowerCase()?
     {name:record.class,source:record.class_source||''}:null);
 const classOrigin=member?'class|'+String(member.source||'').toLowerCase()+'|'+String(member.name).toLowerCase():'';
 return {id:matching?.origin_id||matching?.origin_key||classOrigin,name};
}
// Returns symbolic and expanded numeric forms for each source. No random dice
// are evaluated merely by opening the popup.
export function sheetRollOriginSegments(record,calculated,target,{mode='normal',diceBonuses=[],autoAdvantage=false}={}){
 const total=Number(calculated?.values?.[target]);
 if(!Number.isFinite(total))return [];
 const all=calculated?.roll_components||{};
 const result=[];
 const ability=abilityFor(target),rank=trainingRank(calculated,target);
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
 core+=total-core-consumed;
 const base={kind:'base',formula:'1d20'+(ability?' + Mod.'+abilityNames[ability]:' + Base'),
   expanded:'1d20 '+signed(core),value:core,originName:'Base · regole',originId:'',key:'base'};
 const ordered=[];
 if(mode==='advantage'||mode==='disadvantage'){
   const source=autoAdvantage&&mode==='advantage'?featureForAutoAdvantage(record,calculated,target):
     {id:'',name:'Modalità scelta'};
   ordered.push({kind:'mode',formula:mode==='advantage'?'ADV':'DIS',
     expanded:mode==='advantage'?'2d20kh1':'2d20kl1',value:0,
     originId:source.id,originName:source.name,key:'mode'});
 }
 ordered.push(base,...result);
 for(const [i,row] of list(diceBonuses).entries()){
   const dice=String(row?.dice||'').replace(/\s+/g,'');
   if(!validBonusDice(dice))continue;
   ordered.push({kind:'dice',formula:'+'+dice,expanded:'+'+dice,originId:String(row.origin_id||''),
     originName:row.origin_name||'Dado bonus',
     section:row.origin_id?'':'formula_bonuses',key:'dice:'+i});
 }
 return ordered;
}
export function sheetRollOriginHtml(segments,escapeHtml){
 const esc=escapeHtml;
 return '<div class="sheet-roll-origin-terms" role="group" aria-label="Formula del tiro per origine">'+segments.map(row=>{
   const clickable=row.kind!=='base'&&(row.originId||row.section);
   const tag=clickable?'button':'div';
   return '<'+tag+(clickable?' type="button" data-act="roll-origin-open" data-origin-id="'+esc(row.originId)+'" data-origin-section="'+esc(row.section||'')+'"':'')+
     ' class="sheet-roll-origin-term'+(clickable?' is-link':'')+(row.kind==='base'?' is-base':'')+'" title="'+esc(row.originName)+'">'+
     '<span class="sheet-roll-origin-symbol">'+esc(row.formula)+'</span>'+
     '<span class="sheet-roll-origin-value">'+esc(row.expanded)+'</span>'+
     '<span class="sheet-roll-origin-name">'+esc(row.originName)+'</span></'+tag+'>';
 }).join('')+'</div>';
}
