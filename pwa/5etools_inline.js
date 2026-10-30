// Safe, offline-friendly presentation of inline 5etools tags.
// 5etools' full Renderer is not bundled with the PWA; don't load its web runtime.
const escapeHtml=value=>String(value??'').replace(/[&<>"']/g,char=>({
 '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
}[char]));
const references=new Set(['action','condition','spell','item','creature','skill','sense',
 'class','subclass','feat','race','background','optfeature','filter','book','adventure',
 'status','hazard','language','quickref','variantrule']);
export function render5etoolsInline(value){
 const source=String(value??'');
 const parse=text=>{
  let out='';
  for(let i=0;i<text.length;){
   if(text.slice(i,i+2)!=='{@'){out+=escapeHtml(text[i++]);continue;}
   const start=i,head=text.slice(i+2).match(/^([a-z][a-z0-9]*)\s+/i);
   if(!head){out+=escapeHtml(text[i++]);continue;}
   let depth=1,j=i+2+head[0].length;
   for(;j<text.length&&depth;j++){
    if(text.slice(j,j+2)==='{@'){depth++;j++;continue;}
    if(text[j]==='}')depth--;
   }
   if(depth){out+=escapeHtml(text[i++]);continue;}
   const name=head[1].toLowerCase(),inner=text.slice(i+2+head[0].length,j-1);
   const first=inner.split('|')[0],display=inner.split('|').at(-1);
   const label=references.has(name)?(inner.split('|').length>=3?display:first):first;
   if(name==='i')out+='<em>'+parse(inner)+'</em>';
   else if(name==='b')out+='<strong>'+parse(inner)+'</strong>';
   else if(name==='u')out+='<u>'+parse(inner)+'</u>';
   else if(name==='s')out+='<s>'+parse(inner)+'</s>';
   else if(name==='recharge')out+='(Ricarica '+escapeHtml(inner||'6')+')';
   else if(name==='hit')out+=escapeHtml((Number(inner)>=0?'+':'')+inner);
   else if(['damage','dice','scaledice','dc','chance'].includes(name))out+=parse(first);
   else if(name==='atk')out+=escapeHtml(({mw:'Attacco con arma da mischia',rw:'Attacco con arma a distanza',ms:'Attacco con incantesimo in mischia',rs:'Attacco con incantesimo a distanza'}[first]||first));
   else out+=parse(label);
   i=j;
  }
  return out;
 };
 return parse(source);
}
