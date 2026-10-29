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
      const unlock=Math.max(start+1,Math.min(end,Number(choice.unlock_level)||level));
      return level===unlock;
    }
    return unlocked.some(feature=>feature.origin_id&&feature.origin_id===choice.origin_id);
  });
  return {level,totalLevel:Number(progress.fromTotal||0)+i+1,features:unlocked,choices};
 });
}
