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
 if(!current||current>=20||!Number.isSafeInteger(xp)||xp<0)return 0;
 let count=0;
 for(let next=current+1;next<=20&&xp>=minimumXpForLevel(next);next++)count++;
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
 if(!Number.isInteger(start)||!Number.isInteger(end)||start<0||end>20||end<=start)
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
