// The same distance labels are used for attack rows, trait details and
// equipped-weapon facts. The rules engine keeps distances in feet.
const positiveFeet=value=>{
 if(value===null||value===undefined||value==='')return null;
 const number=Number(value);
 return Number.isFinite(number)&&number>0?number:null;
};

// Ranged weapon attacks expose both published bands. A ranged spell or
// special attack can have a single maximum without a long-range band.
export function attackRangeLabel(attack={}){
 const short=positiveFeet(attack.range_feet);
 if(short===null)return '';
 if(attack.melee===true)return 'Portata '+short+' ft';
 const long=positiveFeet(attack.long_range_feet);
 return long===null?'Gittata '+short+' ft':
   'Gittata corta '+short+' ft · lunga '+long+' ft';
}

// Inventory items store weapon range as a 5eTools-style "short/long" string.
export function inventoryRangeLabel(value){
 const raw=String(value??'').trim();
 if(!raw)return '';
 const parsed=/^(\d+(?:\.\d+)?)(?:\s*\/\s*(\d+(?:\.\d+)?))?$/.exec(raw);
 if(!parsed)return 'Gittata '+raw+' ft';
 return attackRangeLabel({melee:false,range_feet:Number(parsed[1]),
   long_range_feet:parsed[2]===undefined?0:Number(parsed[2])});
}
