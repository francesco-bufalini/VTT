// Display-only D&D 5e distance units. Internal rules and saved data stay in feet.
export const DISTANCE_UNIT_SETTING='distance_unit';
export const FEET_TO_METRES=1.5/5;
let unit='feet';
export function getDistanceUnit(){return unit;}
export function setDistanceUnit(value){
 if(!['feet','meters'].includes(value))throw Error('Unità di distanza non valida');
 unit=value;return unit;
}
export function distanceUnitLabel(){return unit==='meters'?'m':'ft';}
export function distanceInputValue(feet){
 const n=Number(feet);
 return Number.isFinite(n)?Math.round(n*(unit==='meters'?FEET_TO_METRES:1)*100)/100:0;
}
export function distanceInputFeet(value){
 const n=Number(value);
 if(!Number.isFinite(n))throw Error('Distanza non valida');
 return Math.round((unit==='meters'?n/FEET_TO_METRES:n)*100)/100;
}
const num=n=>Number(n).toLocaleString('it-IT',{maximumFractionDigits:2});
export function formatDistance(feet){
 const n=Number(feet);
 if(!Number.isFinite(n))return '—';
 return num(n*(unit==='meters'?FEET_TO_METRES:1))+' '+distanceUnitLabel();
}
// Convert numeric, application-owned GUI labels only. Never rewrite descriptions or rule fields.
export function formatGuiDistanceText(value){
 const input=String(value??'');
 if(unit!=='meters')return input;
 const duo=/(^|[^\w])(\d+(?:\.\d+)?)\s*×\s*(\d+(?:\.\d+)?)\s*(?:ft|feet)\b/gi;
 const paired=/(^|[^\w])(\d+(?:\.\d+)?)\s*[/–]\s*(\d+(?:\.\d+)?)\s*(?:ft|feet)\b/gi;
 const single=/(^|[^\w])(\d+(?:\.\d+)?)\s*(?:ft|feet)\b/gi;
 let text=input.replace(duo,(_,pre,a,b)=>pre+formatDistance(a)+' × '+formatDistance(b));
 text=text.replace(paired,(_,pre,a,b)=>pre+formatDistance(a)+' / '+formatDistance(b));
 return text.replace(single,(_,pre,a)=>pre+formatDistance(a));
}
export function applyDistanceUnits(root){
 if(unit!=='meters'||!root)return;
 const doc=root.ownerDocument||(root.nodeType===9?root:null);
 if(!doc?.createTreeWalker)return;
 const skip='input,textarea,option,script,style,pre,code,[contenteditable],[class*="description"],[class*="descrizione"],[data-trait-description]';
 const walker=doc.createTreeWalker(root,4),nodes=[];
 while(walker.nextNode())nodes.push(walker.currentNode);
 for(const node of nodes){
  if(!node.parentElement||node.parentElement.closest(skip))continue;
  const updated=formatGuiDistanceText(node.nodeValue);
  if(updated!==node.nodeValue)node.nodeValue=updated;
 }
 for(const el of root.querySelectorAll?.('[title],[aria-label]')||[]){
  if(el.closest(skip))continue;
  for(const key of ['title','aria-label']){
   if(!el.hasAttribute(key))continue;
   const original=el.getAttribute(key),updated=formatGuiDistanceText(original);
   if(updated!==original)el.setAttribute(key,updated);
  }
 }
}
