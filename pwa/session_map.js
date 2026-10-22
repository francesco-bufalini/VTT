// Read-only tactical presentation: initiative order is native, never inferred.
export function casterToken(creature, data, owner) {
  const tokens=Array.isArray(data?.tokens)?data.tokens:[];
  const linked=tokens.find(t=>t.id===creature?.linked_token_sync_id);
  if(linked)return linked;
  const matches=tokens.filter(t=>t.creature_id===creature?.id&&t.owner_id===owner&&owner);
  if(matches.length>1)throw Error("Più token sono associati a questa creatura. Seleziona il collegamento corretto in Partita.");
  return matches[0]||null;
}

export function tokenGroups(data) {
  const tokens = Array.isArray(data?.tokens) ? data.tokens.filter(t =>
    t && typeof t.id === "string" && t.id && typeof t.name === "string") : [];
  const compare = (a,b) => a.name.localeCompare(b.name,"it",{sensitivity:"base"}) ||
    a.id.localeCompare(b.id);
  const byId=new Map(tokens.map(t=>[t.id,t]));
  const active=Boolean(data?.combat?.active);
  if(!active)return {active:false,round:0,turnId:"",activeEnvironment:false,participants:[...tokens].sort(compare),outside:[]};
  const seen=new Set(),participants=[];
  const rows=Array.isArray(data?.combat?.entries)?data.combat.entries:[];
  let turnId="",activeEnvironment=false,seenEnvironment=false;
  rows.forEach((row,i)=>{
    const id=String(row?.token_id||"");
    if(row?.environment===true && !id){
      if(seenEnvironment)return;
      seenEnvironment=true;
      participants.push({id:"",name:String(row.name||"Turno ambientale"),
        initiative:row.initiative,environment:true});
      if(i===data.combat.active_index)activeEnvironment=true;
      return;
    }
    if(!byId.has(id)||seen.has(id))return;
    const token=byId.get(id);
    participants.push({...token,initiative:row.initiative});
    seen.add(id);
    if(i===data.combat.active_index)turnId=id;
  });
  return {active:true,round:data.combat.round||1,turnId,activeEnvironment,participants,
    outside:tokens.filter(t=>!seen.has(t.id)).sort(compare)};
}

// The desktop increments revision on accepted incoming/outgoing automatic
// sync. Token projections are also compared to cover offline/local changes.
export function snapshotRevision(data) {
  if(!data)return "";
  return JSON.stringify([data.revision||0,data.view_revision||0,data.area_revision||0,data.combat||{},
    (data.tokens||[]).map(t=>[t.id,t.name,t.conditions,t.active_spell_ids,
      t.current_miniature_id,t.default_miniature_id,t.party_id,t.size_name,
      t.footprint_cells,t.position])]);
}

// The desktop returns WebP as base64 JSON. Do NOT use a data: URL in an
// <img>: our restrictive desktop CSP intentionally permits only self/Blob.
export function snapshotBlob(snapshot) {
  if(!snapshot||snapshot.ok!==true||snapshot.format!=="webp"||
    typeof snapshot.image!=="string"||!snapshot.image.length||
    snapshot.image.length>1800000||
    !/^[A-Za-z0-9+/]*={0,2}$/.test(snapshot.image))return null;
  try{
    const decoded=atob(snapshot.image);
    const bytes=new Uint8Array(decoded.length);
    for(let i=0;i<decoded.length;i++)bytes[i]=decoded.charCodeAt(i);
    return new Blob([bytes],{type:"image/webp"});
  }catch{
    return null;
  }
}


// The passive Partita map is a dedicated viewport. Pointer gestures are
// consumed by this canvas, not by the page (especially important on iOS).
// Preserve its zoom/pan across the session's frequent polling rerenders.
export class SessionMapViewer {
  constructor(){
    this.canvas=null;this.image=null;this.url="";this.zoom=1;
    this.panX=0;this.panY=0;this.pointers=new Map();this.observer=null;
  }
  reset(){this.zoom=1;this.panX=0;this.panY=0;this.draw();}
  mount(canvas,url){
    if(!canvas)return;
    if(this.canvas!==canvas){
      this.observer?.disconnect();
      this.canvas=canvas;this.pointers.clear();
      canvas.addEventListener("pointerdown",e=>{
        e.preventDefault();
        canvas.setPointerCapture?.(e.pointerId);
        this.pointers.set(e.pointerId,this.point(e));
      });
      canvas.addEventListener("pointermove",e=>{
        if(!this.pointers.has(e.pointerId))return;
        e.preventDefault();
        const next=this.point(e),prev=this.pointers.get(e.pointerId);
        if(this.pointers.size===1){
          this.panX+=next[0]-prev[0];this.panY+=next[1]-prev[1];
        }else if(this.pointers.size===2){
          const other=[...this.pointers].find(([id])=>id!==e.pointerId)?.[1];
          if(other){
            const oldDistance=Math.hypot(prev[0]-other[0],prev[1]-other[1]);
            const newDistance=Math.hypot(next[0]-other[0],next[1]-other[1]);
            const oldMid=[(prev[0]+other[0])/2,(prev[1]+other[1])/2];
            const newMid=[(next[0]+other[0])/2,(next[1]+other[1])/2];
            if(oldDistance>1)this.zoomAt(newDistance/oldDistance,...oldMid);
            this.panX+=newMid[0]-oldMid[0];this.panY+=newMid[1]-oldMid[1];
          }
        }
        this.pointers.set(e.pointerId,next);this.draw();
      });
      const end=e=>{this.pointers.delete(e.pointerId);};
      canvas.addEventListener("pointerup",end);
      canvas.addEventListener("pointercancel",end);
      canvas.addEventListener("lostpointercapture",end);
      canvas.addEventListener("wheel",e=>{
        e.preventDefault();
        this.zoomAt(Math.exp(-e.deltaY*0.001),...this.point(e));
      },{passive:false});
      canvas.addEventListener("dblclick",e=>{
        e.preventDefault();this.zoomAt(1.5,...this.point(e));
      });
      this.observer=typeof ResizeObserver!=="undefined"?
        new ResizeObserver(()=>this.draw()):null;
      this.observer?.observe(canvas);
    }
    this.setImage(url);
    this.draw();
  }
  point(event){
    const rect=this.canvas.getBoundingClientRect();
    return [event.clientX-rect.left,event.clientY-rect.top];
  }
  transform(){
    const w=this.canvas?.clientWidth||300,h=this.canvas?.clientHeight||300;
    const iw=this.image?.naturalWidth||2048,ih=this.image?.naturalHeight||2048;
    const scale=Math.min(w/iw,h/ih)*this.zoom;
    return {w,h,iw,ih,scale,x:(w-iw*scale)/2+this.panX,y:(h-ih*scale)/2+this.panY};
  }
  zoomAt(factor,x,y){
    if(!Number.isFinite(factor)||factor<=0)return;
    const before=this.transform();
    const px=(x-before.x)/before.scale,py=(y-before.y)/before.scale;
    this.zoom=Math.max(1,Math.min(4,this.zoom*factor));
    const after=this.transform();
    this.panX+=x-(after.x+px*after.scale);
    this.panY+=y-(after.y+py*after.scale);
    this.draw();
  }
  setImage(url){
    if(!url||url===this.url)return;
    this.url=url;
    const image=new window.Image();
    image.onload=()=>{if(this.url===url){this.image=image;this.draw();}};
    image.onerror=()=>{if(this.url===url){this.image=null;this.draw();}};
    image.src=url;
  }
  draw(){
    const canvas=this.canvas;
    if(!canvas||!canvas.isConnected)return;
    const t=this.transform(),dpr=Math.min(window.devicePixelRatio||1,3);
    const w=Math.max(1,Math.round(t.w*dpr)),h=Math.max(1,Math.round(t.h*dpr));
    if(canvas.width!==w)canvas.width=w;
    if(canvas.height!==h)canvas.height=h;
    const ctx=canvas.getContext("2d");if(!ctx)return;
    ctx.setTransform(dpr,0,0,dpr,0,0);
    ctx.fillStyle="#101827";ctx.fillRect(0,0,t.w,t.h);
    if(!this.image||!this.image.complete)return;
    ctx.imageSmoothingEnabled=true;
    ctx.imageSmoothingQuality="high";
    ctx.drawImage(this.image,t.x,t.y,t.iw*t.scale,t.ih*t.scale);
  }
}
