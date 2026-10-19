// Pure presentation of native and optional homebrew spell fields.
const str=value=>typeof value==='string'?value.trim():value==null?'':String(value).trim();
const readableTime=value=>{
 if(typeof value==='string')return value.trim();
 if(Array.isArray(value))return value.map(part=>{
   if(typeof part==='string')return part;
   if(!part||typeof part!=='object')return '';
   return [part.number,part.unit,part.condition].filter(v=>v!=null&&v!=='').join(' ');
 }).filter(Boolean).join(' / ');
 return '';
};
const readableComponents=value=>{
 if(typeof value==='string')return value.trim();
 if(Array.isArray(value))return value.map(str).filter(Boolean).join(', ');
 if(!value||typeof value!=='object')return '';
 const parts=[];
 if(value.v)parts.push('V');
 if(value.s)parts.push('S');
 if(value.m){
   const material=typeof value.m==='string'?value.m:value.m?.text||'';
   parts.push('M'+(material?' ('+material+')':''));
 }
 return parts.join(', ');
};
const readableDuration=value=>{
 if(typeof value==='string')return value.trim();
 if(Array.isArray(value))return value.map(readableDuration).filter(Boolean).join(' / ');
 if(!value||typeof value!=='object')return '';
 const d=value.duration||value;
 const unit=str(d.type||d.unit);
 const number=d.amount??d.number;
 return (value.concentration?'Concentrazione, fino a ':'')+
   (value.type==='instant'?'Istantanea':value.type==='permanent'?'Permanente':
     [number,unit].filter(v=>v!=null&&v!=='').join(' '));
};
export function spellFacts(spell={}){
 const rows=[];
 const add=(label,value)=>{if(value!=null&&String(value).trim())rows.push({label,value:String(value).trim()});};
 add('Tempo di lancio',readableTime(spell.casting_time||spell.time));
 add('Gittata',str(spell.range));
 add('Componenti',readableComponents(spell.components));
 add('Durata',readableDuration(spell.duration));
 if((spell.requires_concentration===true||spell.concentration===true)&&
    !rows.some(row=>row.label==='Durata'&&/concentrat/i.test(row.value)))
   add('Concentrazione','Sì');
 if(spell.ritual===true||spell.meta?.ritual===true)add('Rituale','Sì');
 add('Bersaglio',str(spell.target));
 return rows;
}
