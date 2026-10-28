// Shared home for the two distinct projections of two-weapon eligibility.
// Keep the existing 2014/2024 predicates: attack generation and the UI action
// historically have different requirements, which this refactor must preserve.
import {resolveOwnedItem,hasProperty,itemKind} from './item_controls.js';
const arr=value=>Array.isArray(value)?value:[];
const same=(a,b)=>String(a??'').trim().toLowerCase()===String(b??'').trim().toLowerCase();
export function offhandAttackAllowed(record={},main=null,off=null){
 const dual=arr(record.feats_catalog).some(f=>!f?.disabled&&same(f.name,'Dual Wielder'));
 const offAllowed=main&&off&&itemKind(main)==='weapon'&&itemKind(off)==='weapon'&&
   (String(record.rules_version)==='2024'?hasProperty(main,'L')&&(hasProperty(off,'L')||dual&&String(off.type).split('|')[0]!=='R'):
    String(main.type).split('|')[0]!=='R'&&String(off.type).split('|')[0]!=='R'&&(hasProperty(main,'L')&&hasProperty(off,'L')||dual));
 return offAllowed;
}
export function offhandActionEligibility(record={},calculated={}){
 const attacks=arr(calculated.attacks);
 const main=attacks.find(a=>a.slot==='main'&&String(a.id||'').startsWith('item:'));
 const off=attacks.find(a=>a.slot==='off'&&String(a.id||'').startsWith('item:off:'));
 const shield=attacks.find(a=>a.slot==='shield'&&a.hand==='off');
 const equipped=arr(record.inventory).map(resolveOwnedItem);
 const mainItem=equipped.find(item=>arr(item.equipped_slots).includes('main')&&itemKind(item)==='weapon');
 const offItem=equipped.find(item=>arr(item.equipped_slots).includes('off')&&
  ['weapon','shield'].includes(itemKind(item)));
 const edition=String(record.rules_version||'2014');
 const feat=arr(record.feats_catalog).find(row=>!row?.disabled&&
  /^(dual wielder|combattente con due armi)$/i.test(String(row?.name||row?.id||'')));
 const hasBoth=Boolean(main&&(off||shield));
 const light=Boolean(hasBoth&&mainItem&&offItem&&itemKind(offItem)==='weapon'&&
   hasProperty(mainItem,'L')&&hasProperty(offItem,'L'));
 const oneHanded=item=>item&&!hasProperty(item,'2H')&&
  String(item.type||'').split('|')[0].toUpperCase()!=='R';
 const featAvailable=Boolean(edition==='2014'&&feat&&hasBoth&&
  oneHanded(mainItem)&&offItem&&
  (itemKind(offItem)==='shield'||itemKind(offItem)==='weapon'&&oneHanded(offItem)));
 const baseReason=!main?'Equipaggia un’arma nella mano principale.':
  !off&&!shield?'Equipaggia un’arma nella mano secondaria.':
  !mainItem||!offItem?'Equipaggia due armi, una per mano.':
  itemKind(offItem)==='shield'?'Uno scudo non è un’arma Leggera per le regole base.':
  'Per le regole base servono due armi Leggere.';
 return {available:light||featAvailable,base_available:light,feat_available:featAvailable,
  reason:light||featAvailable?'':baseReason,base_reason:light?'':baseReason,
  feat_reason:featAvailable?'':'Per il talento servono due armi a una mano, anche non Leggere, oppure uno scudo utilizzato come arma improvvisata.',
  feat:feat||null};
}
