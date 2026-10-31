// Present applied item options and source-owned effects as one list.
// The persistence layer still distinguishes editable variants from granted effects.
const rows=value=>Array.isArray(value)?value:[];
const str=value=>String(value??'').trim();
export function itemAppliedOptions(item={},extensions=[],{optionDescription=()=>'',originDescription=()=>''}={}){
 const applied=rows(item.option_extensions);
 const instance=String(item.instance_id||item.id||'');
 const options=applied.map(option=>({
  name:str(option.name)||str(option.id)||'Opzione',
  description:str(optionDescription(option)),
  removable:option.generic_variant===true,
  variant_id:option.generic_variant===true?str(option.id):'',
  effects:[]
 }));
 const seen=new Map();
 for(const extension of rows(extensions)){
  const origin=str(extension.origin_id),parent=str(extension.parent_origin);
  const owned=applied.some(option=>
   origin==='item-option:'+instance+':'+str(option.id)||
   parent&&parent===str(option.origin_id)&&
     (str(extension.origin_name).endsWith(str(option.name))||str(extension.origin_name)===''));
  if(owned)continue;
  const key=origin||parent||'effect:'+str(extension.id);
  if(seen.has(key)){seen.get(key).effects.push(extension);continue;}
  const row={name:str(extension.origin_name)||'Beneficio applicato',
   description:str(originDescription(extension)),removable:false,variant_id:'',
   effects:[extension]};
  seen.set(key,row);
  options.push(row);
 }
 return options;
}
