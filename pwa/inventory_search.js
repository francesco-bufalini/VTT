// One identity per catalog item or group of owned copies, independent of
// their inventory section. This module has no UI or network dependencies.
const text=value=>String(value??'').normalize('NFKD')
  .replace(/[\u0300-\u036f]/g,'').trim().toLocaleLowerCase('it')
  .replace(/\s+/g,' ');
const identity=row=>text(row?.name)+'|'+text(row?.source);
const catalogId=row=>String(row?.id||'').trim().toLocaleLowerCase('it');

export function inventorySearchResults(inventory=[],catalog=[],query='',limit=60){
 const term=text(query);
 if(!term)return [];
 const groups=new Map(),byId=new Map();
 for(const [index,row] of (Array.isArray(inventory)?inventory:[]).entries()){
  if(!row||row.category==='documents')continue;
  const key=identity(row),id=catalogId(row);
  const existing=groups.get(key)||(id?byId.get(id):null);
  const group=existing||{kind:'owned',name:String(row.name||'Oggetto'),
   source:String(row.source||''),quantity:0,indices:[]};
  if(!existing)groups.set(key,group);
  if(id)byId.set(id,group);
  group.indices.push(index);
  group.quantity+=Math.max(1,Math.floor(Number(row.quantity)||1));
 }
 const matches=row=>text(row.name+' '+(row.source||'')).includes(term);
 const owned=[...new Set(groups.values())].filter(matches).map(row=>({...row}));
 const available=[];
 for(const [catalogIndex,row] of (Array.isArray(catalog)?catalog:[]).entries()){
  if(!row?.name||!matches(row))continue;
  const own=groups.get(identity(row))||byId.get(catalogId(row));
  if(own)continue;
  available.push({kind:'catalog',name:String(row.name),source:String(row.source||''),
   quantity:0,indices:[],catalogIndex});
 }
 const order=(a,b)=>text(a.name).startsWith(term)===text(b.name).startsWith(term)?
  a.name.localeCompare(b.name,'it'):text(a.name).startsWith(term)?-1:1;
 return [...owned.sort(order),...available.sort(order)].slice(0,Math.max(1,limit));
}
