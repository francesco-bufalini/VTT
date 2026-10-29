// Class/subclass trait powers which use the SAME spell-slot payment as spells.
// The source catalog declares the feature, timing, effect and prerequisites.
import {slotUsePatch} from './native_sheet.js';
import {resolveVariant,variantOwns} from './creature_variants.js';

const rows=v=>Array.isArray(v)?v:[];
const low=v=>String(v??'').trim().toLowerCase();
const same=(a,b)=>low(a)===low(b);
const members=record=>rows(record.classes).length?record.classes:[{name:record.class,source:record.class_source,level:record.level}];
const hasOrigin=(record,feature)=>record.origin_enabled?.[feature.origin_id]!==false&&
  record.origin_enabled?.[feature.origin_key]!==false&&
  !rows(record.proficiency_origins).some(row=>row.disabled&&[feature.origin_id,feature.origin_key].includes(row.id));
export function slotFeaturePowers(record={},calculated={},catalog={}){
 return rows(catalog.powers).flatMap(rule=>{
  const owner=rule.owner||{};
  const member=members(record).find(row=>same(row.name,owner.class_name)&&
    same(row.source||record.class_source||'PHB',owner.class_source)&&
    Number(row.level)>=Number(owner.min_class_level||1));
  if(!member)return [];
  const feature=rows(calculated.features).find(row=>same(row.name,owner.trait)&&
    same(row.requirements?.class_name||row.class_name||String(row.origin_key||'').split('|')[2],owner.class_name)&&
    same(row.requirements?.class_source||row.class_source||String(row.origin_key||'').split('|')[1],owner.class_source)&&
    !row.inactive&&!row.disabled&&hasOrigin(record,row));
  if(!feature)return [];
  return [{...rule,origin_id:feature.origin_id,feature_description:feature.entries||feature.description||'',
    available:!rule.require_active||!!record.active_class_features?.[rule.require_active]}];
 });
}
export function slotFeaturePaymentOptions(power,calculated={}){
 const min=Math.max(1,Number(power?.payment?.minimum_level)||1);
 if(power?.payment?.kind!=='spell_slot')return [];
 const slots=rows(calculated.spell_slots).filter(slot=>Number(slot.level)>=min&&
   Number(slot.total)>Number(slot.spent));
 const result=slots.map(slot=>({id:'slot:'+slot.level,level:Number(slot.level),pact:false,
   label:'Slot '+slot.level+'° · '+(Number(slot.total)-Number(slot.spent))+' disponibili'}));
 const pact=calculated.pact_slots||{};
 if(power.payment.allow_pact!==false&&Number(pact.level)>=min&&Number(pact.total)>Number(pact.spent))
  result.push({id:'pact:'+pact.level,level:Number(pact.level),pact:true,
   label:'Patto · '+pact.level+'° livello'});
 return result;
}
export function slotFeatureUsePatch(record={},calculated={},catalog={},id='',payment='',dice=[]){
 const power=slotFeaturePowers(record,calculated,catalog).find(row=>row.id===id);
 if(!power)throw Error('Privilegio non disponibile.');
 if(!power.available)throw Error('Devi essere in Forma selvatica per usare questo privilegio.');
 const choice=slotFeaturePaymentOptions(power,calculated).find(row=>row.id===payment);
 if(!choice)throw Error('Slot incantesimo non disponibile.');
 // Reuse the same bounded mutation as spellcasting. No custom slot counter.
 const patch=slotUsePatch(record,choice.pact?0:choice.level,1,calculated);
 const effect=power.effect||{};
 if(effect.kind!=='heal')return {patch,power,level:choice.level,healed:0,rolls:[]};
 const count=Math.max(1,Number(effect.dice_per_slot_level)||1)*choice.level;
 const faces=Number(effect.die_faces)||8;
 if(!Number.isInteger(count)||count>90||!Array.isArray(dice)||dice.length!==count||
  dice.some(n=>!Number.isInteger(n)||n<1||n>faces))
  throw Error('Tiro di cura non valido.');
 const current=resolveVariant(record);
 const currentHp=Math.max(0,Number(current.current_hp)||0);
 const maxHp=Math.max(0,Number(current.max_hp??current.max_hp_base)||0);
 const amount=dice.reduce((a,b)=>a+b,0);
 // Some forms only override the miniature, not their HP. In that case
 // display the rolled recovery but do not heal the human base-form HP.
 const tracked=effect.target==='current_form'?variantOwns(record,'hp'):
  true;
 if(tracked)patch.current_hp=Math.min(maxHp,currentHp+amount);
 return {patch,power,level:choice.level,healed:tracked?Math.min(amount,Math.max(0,maxHp-currentHp)):0,
  rolls:dice,manual_healing:!tracked?amount:0};
}
