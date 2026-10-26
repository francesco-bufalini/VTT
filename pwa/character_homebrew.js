// Reuse locally owned homebrew in every character picker without copying it into
// another character or publishing it to a remote session. The archive remains
// the source of truth; deleting/editing the original is reflected on the next read.
const ITEM_CATEGORIES=new Set(['items','weapons','armor','tools','mundane_items','magic_items']);
const CUSTOM_SOURCES=new Set(['personalizzato','homebrew','custom']);
const array=value=>Array.isArray(value)?value:[];
const normalize=value=>String(value??'').trim().toLocaleLowerCase('it');
const plain=value=>value&&typeof value==='object'&&!Array.isArray(value);
const isHomebrew=row=>Boolean(row?._homebrew)||
  String(row?.id||'').startsWith('homebrew:')||
  CUSTOM_SOURCES.has(normalize(row?.source));
const itemCategory=row=>({
  weapon:'weapons',armor:'armor',tool:'tools',magic:'magic_items'
})[row?.custom_item_type]||'items';
function matchesCategory(requested,actual,row){
  if(requested===actual)return true;
  if(!ITEM_CATEGORIES.has(requested)||!ITEM_CATEGORIES.has(actual))return false;
  if(requested==='items')return true;
  if(actual==='items')return itemCategory(row)===requested;
  return false;
}
function sharedId(kind,row){
  const name=normalize(row.name),source=normalize(row.source);
  // A local-only ID must not masquerade as a portable homebrew definition:
  // portable IDs require an actual saved dependency in the homebrew store.
  let hash=2166136261;
  for(const char of kind+'|'+source+'|'+name){
    hash^=char.codePointAt(0);hash=Math.imul(hash,16777619);
  }
  return 'local_shared_'+kind+'_'+(hash>>>0).toString(36);
}
function sanitized(row,kind){
  const value={...(plain(row.data)?row.data:{}),...row};
  if(!value.name||!isHomebrew(value))return null;
  value.source=String(value.source||'Personalizzato');
  if(!value.id)value.id=sharedId(kind,value);
  // Instance state is not part of an item/spell definition and must never
  // leak from the owner to another character's new copy.
  if(ITEM_CATEGORIES.has(kind)){
    for(const key of ['instance_id','quantity','equipped','equipped_slots','attuned',
      'attuned_count','active','instance_overrides','container_id','infusion',
      'charges_spent','uses_spent'])delete value[key];
  }
  if(kind==='spells'){
    if(!Number.isInteger(Number(value.level))||Number(value.level)<0||Number(value.level)>9)return null;
    for(const key of ['casting_classes','casting_class','grant_id','origin_id',
      'origin_name','caster_ability','casting_label','prepared','known'])delete value[key];
  }
  delete value._description_warning;
  delete value.data;
  value._homebrew=true;
  value._category=kind;
  return value;
}

/** Homebrew definitions embedded in locally stored characters, deduplicated.
 *  Global definitions should take precedence when merging the result.
 */
export function characterHomebrewEntries(category,creatures=[]){
  const results=[],seenIds=new Set(),seenNames=new Set();
  const add=(value,kind)=>{
    if(!plain(value)||!matchesCategory(category,kind,value))return;
    const row=sanitized(value,kind);
    if(!row)return;
    const id=String(row.id||''),nameKey=kind+'|'+normalize(row.source)+'|'+normalize(row.name);
    if(seenIds.has(id)||seenNames.has(nameKey))return;
    seenIds.add(id);seenNames.add(nameKey);results.push(row);
  };
  for(const current of creatures){
    const c=current?.creature||current;
    if(!plain(c))continue;
    for(const definition of array(c.homebrew_content))
      if(plain(definition)&&typeof definition.category==='string')
        add(definition,definition.category);
    for(const row of array(c.inventory))add(row,
      ITEM_CATEGORIES.has(row?.category)?row.category:'items');
    for(const field of ['spells','prepared_spells','spellbook_spells','known_spells'])
      for(const row of array(c[field]))add(row,'spells');
    for(const [field,kind] of [
      ['feats_catalog','feats'],['backgrounds_catalog','backgrounds'],
      ['class_features_catalog','class_features'],
      ['species_traits_catalog','species_traits'],
      ['optional_features_catalog','optional_features'],
      ['weapons_catalog','weapons'],['armor_catalog','armor'],
      ['tools_catalog','tools']])
      for(const row of array(c[field]))add(row,kind);
    for(const row of array(c.classes)){
      add(row,'classes');
      if(row?.subclass)add({id:row.subclass_id,source:row.subclass_source,
        name:row.subclass},'subclasses');
    }
    for(const [kind,name,id,source] of [
      ['backgrounds',c.background,c.background_id,c.background_source],
      ['races',c.species,c.species_id,c.species_source],
      ['races',c.subrace,c.subrace_id,c.subrace_source],
      ['classes',c.class,c.class_id,c.class_source],
      ['subclasses',c.subclass,c.subclass_id,c.subclass_source]])
      if(name)add({name,id,source},kind);
  }
  return results.sort((a,b)=>a.name.localeCompare(b.name,'it'));
}

export function appendSharedHomebrew(rows,shared){
  const combined=[...rows],ids=new Set(),names=new Set();
  const register=row=>{
    if(row?.id)ids.add(String(row.id));
    if(row?._homebrew)names.add(String(row._category||'')+'|'+normalize(row.source)+'|'+normalize(row.name));
  };
  combined.forEach(register);
  for(const row of shared){
    const nameKey=String(row._category||'')+'|'+normalize(row.source)+'|'+normalize(row.name);
    if(ids.has(String(row.id))||names.has(nameKey))continue;
    combined.push(row);register(row);
  }
  return combined;
}
