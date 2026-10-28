// Reusable client-side tactical preview of self-origin cone and line areas.
// Preview never applies conditions/damage or impersonates Godot's spell targeting.
const finite=v=>Number.isFinite(Number(v))?Number(v):0;
export function abilityAreaPolygon(source,aim,area={},pixelsPerFoot=1){
 const [x,y]=source||[],[tx,ty]=aim||[];
 if(![x,y,tx,ty,pixelsPerFoot].every(Number.isFinite)||pixelsPerFoot<=0)return [];
 const d=Math.hypot(tx-x,ty-y);
 if(area.shape==='circle'){
  const radius=finite(area.radius_feet)*pixelsPerFoot;
  if(radius<=0)return [];
  return Array.from({length:48},(_,i)=>{
   const angle=2*Math.PI*i/48;
   return [x+Math.cos(angle)*radius,y+Math.sin(angle)*radius];
  });
 }
 if(d<1e-6||!['line','cone'].includes(area.shape))return [];
 const ux=(tx-x)/d,uy=(ty-y)/d,px=-uy,py=ux;
 const length=finite(area.length_feet||area.radius_feet)*pixelsPerFoot;
 const half=(area.shape==='cone'?length:finite(area.width_feet)*pixelsPerFoot)/2;
 if(!(length>0&&half>0))return [];
 if(area.shape==='line')return [
  [x+px*half,y+py*half],[x+ux*length+px*half,y+uy*length+py*half],
  [x+ux*length-px*half,y+uy*length-py*half],[x-px*half,y-py*half]];
 return [[x,y],[x+ux*length+px*half,y+uy*length+py*half],
   [x+ux*length-px*half,y+uy*length-py*half]];
}
export function pointInAbilityArea(point,polygon,radius=0){
 if(!point||polygon.length<3)return false;
 const [x,y]=point;let inside=false;
 for(let j=polygon.length-1,i=0;i<polygon.length;j=i++){
  const a=polygon[i],b=polygon[j];
  if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])inside=!inside;
  if(radius>0){
   const dx=b[0]-a[0],dy=b[1]-a[1],m=dx*dx+dy*dy;
   const t=m?Math.max(0,Math.min(1,((x-a[0])*dx+(y-a[1])*dy)/m)):0;
   if(Math.hypot(x-a[0]-t*dx,y-a[1]-t*dy)<=radius)return true;
  }
 }
 return inside;
}
export function abilityAreaPreview(snapshot={},casterId='',aim=[],area={}){
 const markers=Array.isArray(snapshot.markers)?snapshot.markers:[];
 const caster=markers.find(x=>x.id===casterId);
 // Match Godot map_snapshot_view.gd's field-feet to image-height scale.
 const scale=Number(snapshot.height||snapshot.width||0)/Number(snapshot.field_feet||0);
 if(!caster||!Number.isFinite(scale)||scale<=0)return null;
 const points=abilityAreaPolygon([caster.x,caster.y],aim,area,scale);
 if(!points.length)return null;
 return {points,valid:true,affected_ids:markers.filter(row=>
  row.id!==casterId&&pointInAbilityArea([row.x,row.y],points,Math.max(0,Number(row.radius)||0)))
  .map(row=>row.id)};
}
