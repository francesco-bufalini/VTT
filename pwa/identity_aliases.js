// Additional display identities without changing creature IDs or the historical
// name/party_id fields used by existing tokens, saves and network messages.
const fields={
 names:{array:'identity_names',primary:'name'},
 factions:{array:'identity_factions',primary:'party_id'}
};
export function identityEntries(creature={},kind='names'){
 const config=fields[kind];
 if(!config)throw Error('Tipo di identità non valido');
 const primary=String(creature[config.primary]||'').trim();
 const stored=Array.isArray(creature[config.array])?creature[config.array]:[];
 const entries=stored.map(row=>({
  value:String(typeof row==='string'?row:row?.value||'').trim(),
  active:typeof row==='string'?false:Boolean(row?.active)
 })).filter(row=>row.value);
 if(primary&&!entries.some(row=>row.value===primary))
  entries.unshift({value:primary,active:true});
 if(kind==='names'){
  if(!entries.length)entries.push({value:primary||'Senza nome',active:true});
  const selected=entries.findIndex(row=>row.value===primary);
  const activeIndex=selected>=0?selected:Math.max(0,entries.findIndex(row=>row.active));
  entries.forEach((row,index)=>{row.active=index===activeIndex;});
 }else if(primary){
  const selected=entries.find(row=>row.value===primary);
  if(selected)selected.active=true;
 }
 return entries;
}
export function identityEntriesPatch(creature={},kind,rows=[]){
 const config=fields[kind];
 if(!config)throw Error('Tipo di identità non valido');
 const entries=rows.map(row=>({value:String(row?.value||'').trim(),active:Boolean(row?.active)}))
  .filter(row=>row.value);
 if(kind==='names'){
  if(!entries.length)throw Error('È necessario almeno un nome.');
  const selected=entries.findIndex(row=>row.active);
  const activeIndex=selected>=0?selected:0;
  entries.forEach((row,index)=>{row.active=index===activeIndex;});
  return {[config.array]:entries,name:entries[activeIndex].value};
 }
 return {[config.array]:entries,party_id:entries.find(row=>row.active)?.value||''};
}
