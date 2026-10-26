// Local, portable character-sheet portrait. No server or remote image URL is needed.
// A bounded data URL is part of the creature record and survives offline backup/export.
export const PORTRAIT_MAX_INPUT_BYTES=12*1024*1024;
export const PORTRAIT_MAX_DATA_LENGTH=2*1024*1024;
export const PORTRAIT_MAX_SIDE=1200;
const SUPPORTED_TYPES=new Set(['image/jpeg','image/png','image/webp','image/heic','image/heif']);

export function isPortraitDataUrl(value){
 if(typeof value!=='string'||value.length>PORTRAIT_MAX_DATA_LENGTH)return false;
 const match=/^data:image\/(?:jpeg|png|webp);base64,([a-z0-9+/]+={0,2})$/i.exec(value);
 return !!match&&match[1].length>0;
}

export async function preparePortraitImage(file){
 if(!file||typeof file.size!=='number'||file.size<1||file.size>PORTRAIT_MAX_INPUT_BYTES)
  throw Error('Seleziona un’immagine di massimo 12 MB.');
 const type=String(file.type||'').toLowerCase();
 if(!SUPPORTED_TYPES.has(type))
  throw Error('Formato non supportato. Scegli un’immagine JPG, PNG, WebP o HEIC.');
 const objectUrl=URL.createObjectURL(file);
 const source=new Image();
 try{
  source.decoding='async';
  await new Promise((resolve,reject)=>{
   source.onload=resolve;
   source.onerror=()=>reject(Error('Il dispositivo non riesce ad aprire questa foto. Prova in JPG o PNG.'));
   source.src=objectUrl;
  });
  const width=source.naturalWidth,height=source.naturalHeight;
  if(!width||!height||width>20000||height>20000)
   throw Error('Dimensioni della foto non supportate.');
  const scale=Math.min(1,PORTRAIT_MAX_SIDE/Math.max(width,height));
  const canvas=document.createElement('canvas');
  canvas.width=Math.max(1,Math.round(width*scale));
  canvas.height=Math.max(1,Math.round(height*scale));
  const ctx=canvas.getContext('2d');
  if(!ctx)throw Error('Il dispositivo non supporta l’elaborazione della foto.');
  // Transparent artwork gets a neutral backdrop instead of becoming black.
  ctx.fillStyle='#241c1a';
  ctx.fillRect(0,0,canvas.width,canvas.height);
  ctx.drawImage(source,0,0,canvas.width,canvas.height);
  const portrait=canvas.toDataURL('image/jpeg',0.82);
  canvas.width=canvas.height=0;
  if(!isPortraitDataUrl(portrait))
   throw Error('La foto elaborata supera il limite consentito.');
  return portrait;
 }finally{
  source.onload=source.onerror=null;
  URL.revokeObjectURL(objectUrl);
 }
}
