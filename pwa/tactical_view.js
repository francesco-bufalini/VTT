// The browser viewer consumes exactly the same public mobile snapshot projection
// as Android's map_snapshot_view.gd; gameplay/LOS/range remain native Godot.
const AIM_PHASES = new Set(["point", "direction_point", "multi_target_points",
  "wall_start", "wall_segment", "wall_center", "wall_radius", "wall_arc_start",
  "wall_arc_end", "summon_point", "teleport_destination"]);

export function validateSnapshot(data) {
  if (!data || data.ok !== true || data.format !== "webp" ||
      !Number.isInteger(data.width) || !Number.isInteger(data.height) ||
      data.width < 1 || data.height < 1 || data.width > 2048 || data.height > 2048 ||
      typeof data.image !== "string" || data.image.length > 1800000 ||
      !/^[A-Za-z0-9+/]*={0,2}$/.test(data.image) ||
      !Array.isArray(data.markers) || data.markers.length > 512 ||
      !Array.isArray(data.contours) || data.contours.length > 32 ||
      typeof data.snapshot_id !== "string") {
    throw new Error("Snapshot del desktop non valido.");
  }
  for (const marker of data.markers) {
    if (!marker || !Number.isFinite(marker.x) || !Number.isFinite(marker.y) ||
        typeof marker.id !== "string" || !Number.isFinite(marker.radius)) {
      throw new Error("Coordinate dei token non valide.");
    }
  }
  return data;
}
export function imageCoordinates(localX, localY, transform) {
  const {originX,originY,scale,width,height}=transform;
  if (!(scale>0)) return null;
  const x=(localX-originX)/scale, y=(localY-originY)/scale;
  return x>=0 && y>=0 && x<=width && y<=height ? [x,y] : null;
}
export function hitMarker(pixel, markers) {
  if (!pixel) return null;
  let closest=null, best=Infinity;
  for (const marker of markers || []) {
    const d=Math.hypot(pixel[0]-marker.x,pixel[1]-marker.y);
    const threshold=Math.max(14,marker.radius+10);
    if(d<=threshold && d<best){best=d;closest=marker;}
  }
  return closest;
}
export function isAimStatus(status) {
  return !!status?.active && AIM_PHASES.has(status.phase);
}
const clean = value=>String(value??"").replace(/[&<>"']/g,ch=>({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
})[ch]);

export class TacticalViewer {
  constructor({ send, ownerId, notify, onCastAccepted = async()=>{} }) {
    this.send=send;this.ownerId=ownerId;this.notify=notify;this.onCastAccepted=onCastAccepted;
    this.tokenId="";this.attack={};this.image=null;this.snapshot=null;
    this.targeting={};this.preview=null;this.aimPixel=null;this.selectedId="";
    this.zoom=1;this.panX=0;this.panY=0;this.pointers=new Map();
    this.touchMoved=false;this.busy=false;this.root=null;this.onResize=()=>this.draw();
    this.imgUrl="";
  }
  async open(tokenId, attack={}) {
    if(!tokenId)throw new Error("Scegli prima un token.");
    this.close();
    this.tokenId=tokenId;this.attack=structuredClone(attack);
    this.root=document.createElement("div");
    this.root.className="tactical-overlay";
    this.root.innerHTML='<section class="tactical-dialog" role="dialog" aria-modal="true" aria-label="Snapshot della mappa">'+
      '<div class="row between tactical-header"><strong>Vista tattica 2D</strong>'+
      '<button class="btn small" type="button" data-tactical="close" aria-label="Chiudi vista mappa">✕ Chiudi</button></div>'+
      '<div class="row tactical-toolbar">'+
      '<button class="btn small" type="button" data-tactical="refresh">↻ Aggiorna</button>'+
      '<button class="btn small" type="button" data-tactical="zoom-in">＋</button>'+
      '<button class="btn small" type="button" data-tactical="zoom-out">−</button>'+
      '<span class="hint" data-tactical-caption>Caricamento…</span></div>'+
      '<div class="tactical-stage"><canvas class="tactical-canvas" aria-label="Mappa con token e gittate"></canvas></div>'+
      '<div class="tactical-status" role="status" aria-live="polite">Un dito seleziona; trascina per spostarti. Due dita per ingrandire.</div>'+
      '<div class="row tactical-controls"><button class="btn small" type="button" data-tactical="cancel">Annulla incantesimo</button>'+
      '<button class="btn small primary" type="button" data-tactical="finish">Conferma bersagli</button>'+
      '<button class="btn small primary" type="button" data-tactical="confirm-point">Conferma punto</button></div></section>';
    document.body.append(this.root);
    document.body.classList.add("tactical-open");
    this.canvas=this.root.querySelector("canvas");
    this.caption=this.root.querySelector("[data-tactical-caption]");
    this.status=this.root.querySelector(".tactical-status");
    this.root.addEventListener("click",event=>{
      const control=event.target.closest("[data-tactical]");
      if(!control)return;
      this.control(control.dataset.tactical).catch(e=>this.setStatus(e.message,true));
    });
    this.canvas.addEventListener("pointerdown",e=>this.pointerDown(e));
    this.canvas.addEventListener("pointermove",e=>this.pointerMove(e));
    this.canvas.addEventListener("pointerup",e=>this.pointerUp(e));
    this.canvas.addEventListener("pointercancel",e=>this.pointerCancel(e));
    this.canvas.addEventListener("wheel",e=>{
      e.preventDefault();this.zoomAt(Math.exp(-e.deltaY*0.001),e.offsetX,e.offsetY);
    },{passive:false});
    this.onKey=e=>{if(e.key==="Escape")this.close();};
    window.addEventListener("keydown",this.onKey);
    window.addEventListener("resize",this.onResize);
    this.resizeObserver = typeof ResizeObserver !== "undefined" ?
      new ResizeObserver(this.onResize) : null;
    this.resizeObserver?.observe(this.canvas);
    this.updateButtons();
    await this.refresh();
  }
  close() {
    this.resizeObserver?.disconnect();this.resizeObserver=null;
    if(this.onKey)window.removeEventListener("keydown",this.onKey);
    window.removeEventListener("resize",this.onResize);
    this.root?.remove();this.root=null;this.image=null;this.snapshot=null;
    if(this.imgUrl){URL.revokeObjectURL(this.imgUrl);this.imgUrl="";}
    document.body.classList.remove("tactical-open");
    this.pointers.clear();
  }
  setStatus(message, error=false) {
    if(this.status){this.status.textContent=message;this.status.classList.toggle("error",error);}
    if(error)this.notify(message,true);
  }
  updateButtons() {
    if(!this.root)return;
    const active=!!this.targeting?.active;
    const aim=isAimStatus(this.targeting);
    for(const key of ["cancel","finish","confirm-point"]){
      const b=this.root.querySelector('[data-tactical="'+key+'"]');
      if(b){b.hidden=!active || (key==="confirm-point"?!aim:key==="finish"?aim:false);
        b.disabled=this.busy || (key==="confirm-point"&&!this.aimPixel);}
    }
    for(const b of this.root.querySelectorAll("[data-tactical]")){
      if(["cancel","finish","confirm-point"].includes(b.dataset.tactical))continue;
      b.disabled=this.busy;
    }
  }
  async runAction(name,payload) {
    if(this.busy)throw new Error("Attendi la risposta dal desktop.");
    this.busy=true;this.updateButtons();
    try {
      const result=await this.send(name,payload);
      if(!result?.ok)throw new Error(result?.error||"Il desktop ha rifiutato il comando.");
      if(result.targeting)this.targeting=result.targeting;
      this.updateButtons();
      return result;
    }finally{this.busy=false;this.updateButtons();}
  }
  async refresh() {
    if(!this.root)return;
    this.setStatus("Acquisizione dello snapshot dal desktop…");
    const data=validateSnapshot(await this.runAction("snapshot",{
      token_id:this.tokenId,owner_id:await this.ownerId(),field_feet:120,attack:this.attack
    }));
    const raw=atob(data.image), bytes=new Uint8Array(raw.length);
    for(let i=0;i<raw.length;i++)bytes[i]=raw.charCodeAt(i);
    const url=URL.createObjectURL(new Blob([bytes],{type:"image/webp"}));
    let image;
    try {
      image=await new Promise((resolve,reject)=>{
        const el=new Image();
        el.onload=()=>resolve(el);
        el.onerror=()=>reject(new Error("Impossibile decodificare lo snapshot WebP."));
        el.src=url;
      });
    }finally{URL.revokeObjectURL(url);}
    if(!this.root)return;
    const same=this.snapshot?.token_id===data.token_id &&
      this.snapshot?.field_feet===data.field_feet;
    this.snapshot=data;this.image=image;this.targeting=data.targeting||{};
    this.preview=null;this.aimPixel=null;
    if(!same){this.zoom=1;this.panX=0;this.panY=0;}
    this.caption.textContent=String(data.title||"Mappa")+" · "+Math.round(data.field_feet||60)+" ft";
    this.setStatus(this.targeting.active ?
      (this.targeting.instruction||"Scegli un bersaglio sulla mappa.") :
      this.attack?.range_feet?"Tocca un bersaglio per verificarne gittata e distanza." :
      "Tocca un token per selezionarlo. Trascina per spostarti, pizzica per ingrandire.");
    this.updateButtons();this.draw();
  }
  transform() {
    const rect=this.canvas.getBoundingClientRect();
    const width=rect.width||this.canvas.clientWidth||300;
    const height=rect.height||this.canvas.clientHeight||300;
    const imgW=this.snapshot?.width||1536,imgH=this.snapshot?.height||1536;
    const scale=Math.min(width/imgW,height/imgH)*this.zoom;
    return {width:imgW,height:imgH,scale,originX:(width-imgW*scale)/2+this.panX,
      originY:(height-imgH*scale)/2+this.panY,viewW:width,viewH:height};
  }
  draw() {
    if(!this.canvas||!this.canvas.isConnected)return;
    const t=this.transform(),dpr=Math.min(window.devicePixelRatio||1,2);
    const w=Math.max(1,Math.round(t.viewW*dpr)),h=Math.max(1,Math.round(t.viewH*dpr));
    if(this.canvas.width!==w)this.canvas.width=w;
    if(this.canvas.height!==h)this.canvas.height=h;
    const ctx=this.canvas.getContext("2d");
    if(!ctx)return;
    ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,t.viewW,t.viewH);
    ctx.fillStyle="#101827";ctx.fillRect(0,0,t.viewW,t.viewH);
    if(!this.image)return;
    ctx.save();
    ctx.translate(t.originX,t.originY);ctx.scale(t.scale,t.scale);
    ctx.drawImage(this.image,0,0,t.width,t.height);
    for(const contour of this.snapshot?.contours||[]) {
      const pts=contour.points||[];
      if(pts.length<2)continue;
      ctx.beginPath();
      pts.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));
      ctx.closePath();ctx.lineWidth=3/t.scale;
      ctx.strokeStyle=contour.long?"#ffb75e":"#8bd8b5";ctx.stroke();
    }
    const preview=this.preview?.points||[];
    if(preview.length>=3){
      ctx.beginPath();preview.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));
      ctx.closePath();ctx.fillStyle="#86c9eb55";ctx.fill();
      ctx.strokeStyle=this.preview.valid?"#8ddcff":"#ff9a9a";
      ctx.lineWidth=3/t.scale;ctx.stroke();
    }
    for(const marker of this.snapshot?.markers||[]){
      const radius=Math.max(9/t.scale,marker.radius);
      const selected=marker.id===this.selectedId ||
        (this.targeting.selected_ids||[]).includes(marker.id) ||
        (this.preview?.affected_ids||[]).includes(marker.id);
      ctx.beginPath();ctx.arc(marker.x,marker.y,radius,0,Math.PI*2);
      ctx.lineWidth=(selected?5:2)/t.scale;
      ctx.strokeStyle=selected?"#e7bd77":marker.selected?"#8bd8b5":"#e3f0ff";
      ctx.stroke();
      if(selected){ctx.fillStyle="#e7bd7733";ctx.fill();}
      ctx.font=(13/t.scale)+"px system-ui,sans-serif";
      ctx.textAlign="center";ctx.textBaseline="bottom";ctx.fillStyle="#fff";
      ctx.shadowColor="#101827";ctx.shadowBlur=8/t.scale;
      ctx.fillText(String(marker.name||"" ).slice(0,38),marker.x,marker.y-radius-4/t.scale);
      ctx.shadowBlur=0;
    }
    if(this.aimPixel){
      const [x,y]=this.aimPixel;
      ctx.strokeStyle="#e7bd77";ctx.lineWidth=2/t.scale;
      ctx.beginPath();ctx.moveTo(x-15/t.scale,y);ctx.lineTo(x+15/t.scale,y);
      ctx.moveTo(x,y-15/t.scale);ctx.lineTo(x,y+15/t.scale);ctx.stroke();
    }
    ctx.restore();
  }
  zoomAt(factor,x,y) {
    const before=this.transform(),point=imageCoordinates(x,y,before);
    this.zoom=Math.max(1,Math.min(8,this.zoom*factor));
    const after=this.transform();
    if(point){
      this.panX+=x-(after.originX+point[0]*after.scale);
      this.panY+=y-(after.originY+point[1]*after.scale);
    }
    this.draw();
  }
  pointerDown(e) {
    this.canvas.setPointerCapture?.(e.pointerId);
    this.pointers.set(e.pointerId,[e.offsetX,e.offsetY]);
    this.touchMoved=this.pointers.size>1;
  }
  pointerMove(e) {
    if(!this.pointers.has(e.pointerId))return;
    const old=this.pointers.get(e.pointerId),point=[e.offsetX,e.offsetY];
    if(this.pointers.size===1) {
      const dx=point[0]-old[0],dy=point[1]-old[1];
      if(Math.abs(dx)+Math.abs(dy)>2)this.touchMoved=true;
      this.panX+=dx;this.panY+=dy;
    }else if(this.pointers.size===2){
      const other=[...this.pointers].find(([id])=>id!==e.pointerId)?.[1];
      if(other){
        const from=Math.hypot(old[0]-other[0],old[1]-other[1]);
        const to=Math.hypot(point[0]-other[0],point[1]-other[1]);
        if(from>1 && to>1)this.zoomAt(to/from,(point[0]+other[0])/2,(point[1]+other[1])/2);
      }
    }
    this.pointers.set(e.pointerId,point);this.draw();
  }
  pointerCancel(e){this.pointers.delete(e.pointerId);this.touchMoved=true;}
  pointerUp(e) {
    const tap=this.pointers.size===1&&!this.touchMoved;
    this.pointers.delete(e.pointerId);
    if(!this.pointers.size)this.touchMoved=false;
    if(!tap||this.busy)return;
    const coord=imageCoordinates(e.offsetX,e.offsetY,this.transform());
    if(!coord)return;
    this.tap(coord).catch(error=>this.setStatus(error.message,true));
  }
  async tap(pixel) {
    if(!this.snapshot)return;
    const marker=hitMarker(pixel,this.snapshot.markers);
    this.selectedId=marker?.id||"";
    const payload={token_id:this.tokenId,owner_id:await this.ownerId(),
      target_id:marker?.id||"",snapshot_id:this.snapshot.snapshot_id,pixel};
    if(isAimStatus(this.targeting) && !marker){
      this.aimPixel=pixel;this.preview=null;this.updateButtons();this.draw();
      try {
        const result=await this.runAction("preview_spell",payload);
        this.preview=result.preview||null;
        this.setStatus(this.preview?.valid?"Anteprima pronta · conferma il punto.":"Punto fuori gittata o non valido.");
      }catch(error){this.setStatus(error.message,true);}
    }else if(this.targeting.active){
      await this.runAction("target_spell",payload);
      await this.refresh();
    }else if(marker && Object.keys(this.attack).length){
      const result=await this.runAction("target_attack",{
        token_id:this.tokenId,target_id:marker.id,attack:this.attack
      });
      this.setStatus("Bersaglio: "+marker.name+" · distanza "+
        Math.ceil(result.distance_feet||0)+" ft"+
        (result.long_range?" · gittata lunga (svantaggio)":""));
    }else{
      this.setStatus(marker ? "Token: "+marker.name+
        (marker.status_text?" · "+marker.status_text:""):"Seleziona un token sulla mappa.");
    }
    this.draw();
  }
  async beginSpell({spell, slotLevel=0, context={}}) {
    if(!this.root)throw new Error("Apri prima lo snapshot della mappa.");
    if(!spell?.id)throw new Error("Seleziona un incantesimo valido.");
    const payload={token_id:this.tokenId,owner_id:await this.ownerId(),
      spell_id:String(spell.id),name:String(spell.name||spell.id),
      source:String(spell.source||""),slot_level:slotLevel,context};
    const result=await this.runAction("begin_spell",payload);
    this.targeting=result.targeting||{};
    // Mirror Android: consume the slot after Godot accepted the cast.
    await this.onCastAccepted(slotLevel,spell);
    await this.refresh();
    return result;
  }
  async control(name) {
    if(name==="close"){this.close();return;}
    if(name==="zoom-in"){this.zoomAt(1.25,this.transform().viewW/2,this.transform().viewH/2);return;}
    if(name==="zoom-out"){this.zoomAt(0.8,this.transform().viewW/2,this.transform().viewH/2);return;}
    if(name==="refresh"){await this.refresh();return;}
    if(!this.targeting.active)throw new Error("Nessun incantesimo in selezione.");
    const payload={token_id:this.tokenId,owner_id:await this.ownerId()};
    if(name==="cancel"||name==="finish"){
      await this.runAction(name==="cancel"?"cancel_spell":"finish_spell",payload);
    }else if(name==="confirm-point"){
      if(!this.aimPixel)throw new Error("Scegli prima un punto sulla mappa.");
      await this.runAction("target_spell",{...payload,target_id:"",
        snapshot_id:this.snapshot.snapshot_id,pixel:this.aimPixel});
    }
    await this.refresh();
  }
}
