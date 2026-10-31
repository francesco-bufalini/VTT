import {minimumXpForLevel} from './character_core.js';

const list=value=>Array.isArray(value)?value:[];
const norm=value=>String(value||'').trim().toLowerCase();

/** Number of additional levels actually afforded by accumulated XP. */
export function availableXpLevels(record={}){
 if(record.kind==='monster'||record.variant_rules_kind==='monster')return 0;
 const owned=list(record.classes).filter(row=>row?.name);
 const current=owned.length?owned.reduce((sum,row)=>sum+Math.max(1,Number(row.level)||1),0):
   record.class?Math.max(1,Number(record.level)||1):0;
 const xp=Number(record.xp);
 if(!current||!Number.isSafeInteger(xp)||xp<0)return 0;
 let count=0;
 // A single level-up operation handles up to 20 levels, not a lifetime maximum.
 while(count<20&&xp>=minimumXpForLevel(current+count+1))count++;
 return count;
}

/**
 * A class advancement can cover a single level or an entire range (e.g.
 * Fighter 2→5). The saved character is already at its final level; this
 * read-only projection associates each gained feature and pending choice with
 * its own class level, without granting HP or repeating a feature.
 */
export function levelUpSteps(calculated={},progress={}){
 const start=Number(progress.fromLevel),end=Number(progress.toLevel);
 if(!Number.isInteger(start)||!Number.isInteger(end)||start<0||end-start>20||end<=start)
   return [];
 const name=norm(progress.className),source=norm(progress.classSource),index=Number(progress.classIndex);
 const relevant=feature=>{
  const parts=String(feature?.origin_key||'').toLowerCase().split('|');
  return parts[0]==='class'&&parts[2]===name&&(!source||parts[1]===source)&&
    !feature.disabled&&!feature.inactive;
 };
 const features=list(calculated.features).filter(relevant);
 const pending=list(calculated.pending_choices).filter(choice=>Number(choice?.remaining)>0);
 const known=new Set();
 return Array.from({length:end-start},(_,i)=>{
  const level=start+i+1;
  const unlocked=features.filter(feature=>Number(feature.level)===level)
    .filter(feature=>{
      const key=feature.origin_id||feature.key||feature.name+'|'+level;
      if(known.has(key))return false;
      known.add(key);return true;
    });
  const choices=pending.filter(choice=>{
    if(choice.kind==='subclass'&&Number(choice.class_index)===index){
      const unlock=Math.max(start+1,Math.min(end,Number(choice.unlock_level)||(start+1)));
      return level===unlock;
    }
    return unlocked.some(feature=>feature.origin_id&&feature.origin_id===choice.origin_id);
  });
  return {level,totalLevel:Number(progress.fromTotal||0)+i+1,features:unlocked,choices};
 });
}

/** Class hit die comes from 5etools class metadata, not a class-name switch. */
export function classHitDieFaces(entry={}){
 const candidates=[entry.hd?.faces,entry.hit_dice?.faces,entry.hitDie?.faces,
   entry.hit_die?.faces,entry.hit_die,entry.hitDice,entry.hit_dice,entry.hd];
 for(const value of candidates){
   const faces=typeof value==='string'?Number(value.match(/d(6|8|10|12)\b/i)?.[1]||value):Number(value);
   if([6,8,10,12].includes(faces))return faces;
 }
 return 0;
}
export function averageHitDie(faces){
 if(![6,8,10,12].includes(Number(faces)))throw Error('Dado vita della classe non disponibile.');
 return Number(faces)/2+1;
}
export function hpGainForLevels(rolls,constitutionModifier){
 const con=Number(constitutionModifier);
 if(!Number.isInteger(con)||con<-30||con>30||!Array.isArray(rolls)||!rolls.length||rolls.length>20)
   throw Error('Avanzamento dei PF non valido.');
 return rolls.reduce((sum,roll)=>{
   if(!Number.isInteger(roll)||roll<1||roll>20)throw Error('PF dal dado non validi.');
   return sum+Math.max(1,roll+con);
 },0);
}
export function levelUpHpPatch(record,rolls,constitutionModifier,{firstCharacterLevel=false}={}){
 const gained=hpGainForLevels(rolls,constitutionModifier);
 const base=Number(record.max_hp_base??record.max_hp??0);
 const current=Number(record.current_hp??0);
 if(!Number.isFinite(base)||base<0||!Number.isFinite(current)||current<0)
   throw Error('PF attuali non validi.');
 // A new character starts with the archive's provisional 1 HP, not an
 // additional class-level HP. Preserve any intentionally customized value.
 const replaceDefault=firstCharacterLevel&&base===1&&current===1;
 return {max_hp_base:base+(replaceDefault?gained-1:gained),
   current_hp:current+(replaceDefault?gained-1:gained)};
}

const number=value=>Number.isFinite(Number(value))?Number(value):0;
const positive=value=>Math.max(0,number(value));
const same=(a,b)=>norm(a)===norm(b);
const named=(label,from,to)=>({label,from,to});
const difference=(label,previous,next)=>number(previous)!==number(next)?
 named(label,number(previous),number(next)):null;

/**
 * Read-only intermediate level for the already selected class. All derived
 * rules are calculated by calculateSheet; this function never writes a sheet.
 */
export function levelUpProjectedRecord(record={},plan={},gained=1){
 const n=Number(gained);
 if(!Number.isInteger(n)||n<1||n>20)throw Error('Livelli di anteprima non validi.');
 const classes=list(record.classes).map(row=>({...row}));
 if(!classes.some(row=>row?.name)&&record.class)classes.splice(0,classes.length,{
   name:record.class,source:record.class_source||'',id:record.class_id||'',
   subclass:record.subclass||'',subclass_source:record.subclass_source||'',level:Number(record.level)||1
 });
 const index=Number(plan.classIndex);
 if(Number.isInteger(index)&&index>=0){
   const row=classes[index];
   if(!row||!same(row.name,plan.className)||
     plan.classSource&&row.source&&!same(row.source,plan.classSource))
     throw Error('Classe non disponibile per il livellaggio.');
   row.level=(Number(row.level)||1)+n;
 }else{
   if(!plan.className||classes.some(row=>same(row.name,plan.className)))
     throw Error('Nuova classe non valida.');
   const index=classes.findIndex(row=>!row?.name);
   const member={name:plan.className,source:plan.classSource||'',id:plan.classId||'',level:n};
   if(index>=0)classes[index]=member;
   else classes.push(member);
 }
 const total=classes.filter(row=>row?.name);
 const level=total.reduce((sum,row)=>sum+Math.max(1,Number(row.level)||1),0);
 if(!Number.isSafeInteger(level))throw Error('Livello totale non valido.');
 const first=total[0]||{};
 return {...record,classes:total,level,
   class:first.name||'',class_source:first.source||'',class_id:first.id||'',
   subclass:first.subclass||'',subclass_source:first.subclass_source||'',
   subclass_id:first.subclass_id||''};
}
function optionLabels(entries){
 return [...new Set(entries.map(entry=>String(entry||'').trim()).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'it'));
}
function uniqueFeatures(from=[],to=[],className='',classSource=''){
 const owned=new Set(list(from).map(f=>String(f.key||f.origin_id||f.name+'|'+f.origin_key)));
 return list(to).filter(f=>{
   const parts=String(f.origin_key||'').split('|');
   const match=parts[0]==='class'&&same(parts[2],className)&&
     (!classSource||same(parts[1],classSource));
   return match&&!f.inactive&&!f.disabled&&
     !owned.has(String(f.key||f.origin_id||f.name+'|'+f.origin_key));
 }).map(f=>({name:f.name,level:f.level,origin_id:f.origin_id}));
}
/**
 * Differences represent newly usable capacities, not spells or infusions
 * already chosen on the character. The calculation snapshots are authoritative.
 */
export function levelUpProjectionChanges(before={},after={},context={}){
 const changes=[];
 const add=value=>{if(value)changes.push(value);};
 add(difference('Bonus competenza',before.stats?.proficiency,after.stats?.proficiency));
 const oldCasting=new Map(list(before.casting_classes).map(row=>[row.id,row]));
 for(const row of list(after.casting_classes)){
   const old=oldCasting.get(row.id)||{};
   const owner=row.name||'Classe';
   if(Number.isInteger(Number(row.limit))&&number(row.limit)>=0&&
      number(row.limit)!==number(old.limit)){
     const mode=row.mode==='Preparati'?'Incantesimi preparabili':'Incantesimi conosciuti';
     add(named(owner+' · '+mode,positive(old.limit),positive(row.limit)));
   }
   add(difference(owner+' · Trucchetti',old.cantrips,row.cantrips));
   add(difference(owner+' · Livello massimo incantesimi',old.max_level,row.max_level));
 }
 const oldSlots=new Map(list(before.spell_slots).map(row=>[Number(row.level),row]));
 for(const row of list(after.spell_slots)){
   const old=oldSlots.get(Number(row.level));
   add(difference('Slot incantesimi · '+row.level+'°',old?.total,row.total));
 }
 add(difference('Slot del Patto',before.pact_slots?.total,after.pact_slots?.total));
 if(number(after.pact_slots?.total)>0||number(before.pact_slots?.total)>0)
   add(difference('Livello degli slot del Patto',before.pact_slots?.level,after.pact_slots?.level));
 const oldSelections=new Map(list(before.selection_models).map(model=>[model.id,model]));
 const stageLabels={learned:'Opzioni imparabili',prepared:'Opzioni preparabili',applied:'Opzioni applicabili'};
 for(const model of list(after.selection_models)){
   if(model.benefit_type==='spell_selection')continue;
   const old=oldSelections.get(model.id);
   for(const [stage,layer] of Object.entries(model.layers||{})){
     if(layer.limit===null||layer.automatic)continue;
     add(difference(model.title+' · '+stageLabels[stage]+' · massimo',old?.layers?.[stage]?.limit,layer.limit));
   }
   const eligible=row=>list(row?.options).filter(option=>number(option.min_level)<=number(row.level));
   const previousIds=new Set(eligible(old).map(option=>option.id));
   const added=eligible(model).filter(option=>!previousIds.has(option.id));
   if(added.length)changes.push({label:model.title+' · Nuove opzioni selezionabili',from:0,to:added.length,options:optionLabels(added.map(option=>option.name))});
 }
 const oldGrants=new Set(list(before.origin_spells).map(row=>String(row.id||row.origin_id+'|'+row.spell_id)));
 const newGrants=list(after.origin_spells).filter(row=>
   !oldGrants.has(String(row.id||row.origin_id+'|'+row.spell_id)));
 if(newGrants.length){
   const names=newGrants.map(row=>{
     const spell=list(context.spells).find(s=>s.id===row.spell_id);
     return spell?.name||row.spell_name||row.name||row.spell_id;
   });
   changes.push({label:'Incantesimi concessi dai privilegi',from:0,to:newGrants.length,
     options:optionLabels(names)});
 }
 const oldChoices=new Map(list(before.origin_choices).map(row=>[row.id,row]));
 for(const row of list(after.origin_choices)){
   const old=oldChoices.get(row.id);
   const previous=positive(old?.count),next=positive(row.count);
   if(next>previous)add(named('Scelte di incantesimi · '+(row.origin_name||row.name||'Privilegio'),previous,next));
 }
 const oldTrackers=new Map(list(before.trackers).map(row=>[row.id,row]));
 for(const row of list(after.trackers)){
   if(row.disabled||row.inactive)continue;
   const old=oldTrackers.get(row.id);
   add(difference('Risorsa · '+(row.name||row.id),old?.max,row.max));
 }
 add(difference('Attacchi per azione',before.attacks_per_action,after.attacks_per_action));
 add(difference('Oggetti in sintonia · massimo',
   before.values?.attunement_max,after.values?.attunement_max));
 const prevProf=new Set(list(before.proficiencies));
 const newProf=list(after.proficiencies).filter(p=>!prevProf.has(p));
 if(newProf.length)changes.push({label:'Nuove competenze',from:0,to:newProf.length,
   options:optionLabels(newProf.map(s=>s.replace(/^expertise:/,'Maestria · ')
     .replace(/^skill:/,'Abilità · ').replace(/^tool:/,'Strumento · ')
     .replace(/^language:/,'Lingua · ').replace(/^armor:/,'Armatura · ')
     .replace(/^weapon:/,'Arma · ').replace(/^save:/,'Tiro salvezza · ')))});
 return changes;
}
/** Compute every gained level from the same structured calculator used by the sheet. */
export function levelUpProgressionImpact(record,plan,catalogs,calculate){
 if(typeof calculate!=='function')throw Error('Calcolo del personaggio non disponibile.');
 const length=Number(plan.toLevel)-Number(plan.fromLevel);
 if(!Number.isInteger(length)||length<1||length>20)return [];
 let previous=calculate(record,catalogs);
 const result=[];
 for(let gained=1;gained<=length;gained++){
   const updatedRecord=levelUpProjectedRecord(record,plan,gained);
   const next=calculate(updatedRecord,catalogs);
   result.push({
     level:Number(plan.fromLevel)+gained,totalLevel:updatedRecord.level,
     features:uniqueFeatures(previous.features,next.features,plan.className,plan.classSource),
     changes:levelUpProjectionChanges(previous,next,{
       spells:catalogs.spells
     })
   });
   previous=next;
 }
 return result;
}
