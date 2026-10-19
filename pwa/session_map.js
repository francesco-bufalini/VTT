// Read-only tactical presentation: initiative order is native, never inferred.
export function tokenGroups(data) {
  const tokens = Array.isArray(data?.tokens) ? data.tokens.filter(t =>
    t && typeof t.id === "string" && t.id && typeof t.name === "string") : [];
  const compare = (a,b) => a.name.localeCompare(b.name,"it",{sensitivity:"base"}) ||
    a.id.localeCompare(b.id);
  const byId=new Map(tokens.map(t=>[t.id,t]));
  const active=Boolean(data?.combat?.active);
  if(!active)return {active:false,round:0,turnId:"",participants:[...tokens].sort(compare),outside:[]};
  const seen=new Set(),participants=[];
  const rows=Array.isArray(data?.combat?.entries)?data.combat.entries:[];
  let turnId="";
  rows.forEach((row,i)=>{
    const id=String(row?.token_id||"");
    if(!byId.has(id)||seen.has(id))return;
    const token=byId.get(id);
    participants.push({...token,initiative:row.initiative});
    seen.add(id);
    if(i===data.combat.active_index)turnId=id;
  });
  return {active:true,round:data.combat.round||1,turnId,participants,
    outside:tokens.filter(t=>!seen.has(t.id)).sort(compare)};
}

// The desktop increments revision on accepted incoming/outgoing automatic
// sync. Token projections are also compared to cover offline/local changes.
export function snapshotRevision(data) {
  if(!data)return "";
  return JSON.stringify([data.revision||0,data.view_revision||0,data.area_revision||0,data.combat||{},
    (data.tokens||[]).map(t=>[t.id,t.name,t.conditions,t.active_spell_ids,
      t.current_miniature_id,t.default_miniature_id,t.position])]);
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
