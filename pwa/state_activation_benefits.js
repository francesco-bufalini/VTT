// A state activation changes a State but does not own its passive benefits.
const list=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();

export function projectStateActivationBenefits(payload,states=[]){
 if(payload==null)return list(states);
 if(payload.schema_version!==2||payload.scope!=='catalog'||
    payload.benefit_type!=='state_activation'||!Array.isArray(payload.entries))
   throw Error('Catalogo state_activation non valido');
 const rules=list(states).map(state=>({...state}));
 const byId=new Map(rules.map((rule,i)=>[rule.id,i]));
 const used=new Set();
 for(const entry of payload.entries){
  const ref=entry?.granted_by?.ref||{},benefit=entry?.benefit||{};
  const config=benefit.state_activation||{};
  if(!entry?.id||benefit.type!=='state_activation'||!config.state_id||
     !['toggle','activate','deactivate'].includes(config.mode)||
     !['action','bonus','reaction','free','contextual','movement'].includes(config.activation))
    throw Error('Beneficio state_activation non valido: '+String(entry?.id||''));
  // Origins other than class/subclass still need their own state owner adapter;
  // never attach an unrelated trait by matching just its display name.
  if(entry.granted_by?.kind!=='5etools'||
     !['class_feature','subclass_feature'].includes(ref.category))continue;
  if(used.has(config.state_id))throw Error('Stato con attivazioni duplicate: '+config.state_id);
  used.add(config.state_id);
  const index=byId.get(config.state_id);
  if(index===undefined)throw Error('Stato non definito: '+config.state_id);
  const rule=rules[index];
  if(norm(rule.trait)!==norm(ref.name)||norm(rule.class_name)!==norm(ref.class_name)||
     norm(rule.class_source)!==norm(ref.class_source)||
     norm(rule.subclass)!==norm(ref.subclass))
    throw Error('Origine non corrispondente allo stato: '+config.state_id);
  if(config.group&&config.group!==rule.group)
    throw Error('Gruppo esclusivo non corrispondente allo stato: '+config.state_id);
  rules[index]={...rule,activation:config.activation,
    deactivation:config.deactivation||'free',
    activation_mode:config.mode,
    ...(config.trigger?{activation_trigger:config.trigger}:{}),
    ...(config.resource?{activation_resource:{...config.resource}}:{})};
 }
 return rules;
}

export async function loadStateActivationBenefits(fetcher=fetch){
 let response;
 try{response=await fetcher('/benefits/state_activation.json')}catch{return null}
 if(!response?.ok)return null;
 const payload=await response.json();
 if(payload?.schema_version!==2||payload?.benefit_type!=='state_activation'||
    payload?.scope!=='catalog'||!Array.isArray(payload.entries))
   throw Error('Catalogo state_activation non valido');
 return payload;
}
