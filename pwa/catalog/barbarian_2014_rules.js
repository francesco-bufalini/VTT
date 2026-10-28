// Source-qualified 2014 Barbarian supplemental benefits.
// Effect kinds are interpreted generically; only data here names D&D features.
export const BARBARIAN_2014_GRANTS = [
 {kind:'numeric',id:'barbarian:2014:fast-movement',feature:'Fast Movement',target:'speed',expression:'10',requires:['no_heavy_armor']},
 {kind:'numeric',id:'barbarian:2014:totem-elk-speed',feature:'Totem Spirit',subclass:'Totem Warrior',defense_choice:'elk',target:'speed',expression:'15',requires:['rage','no_heavy_armor','conscious'],origin_suffix:' (Elk)'},
 {kind:'action',id:'barbarian:2014:totem-eagle-dash',feature:'Totem Spirit',subclass:'Totem Warrior',defense_choice:'eagle',name:'Totem Spirit · Aquila · Scatto',action_type:'bonus',description:'Durante l’Ira puoi effettuare Scatto come azione bonus. Gli attacchi di opportunità contro di te hanno svantaggio; applicalo manualmente.'},
 {kind:'roll_mode',id:'barbarian:2014:danger-sense',feature:'Danger Sense',target:'save:dex',mode:'advantage',condition_label:'Solo contro effetti che puoi vedere; non se sei accecato, assordato o incapacitato.'},
 {kind:'initiative',feature:'Feral Instinct'},
 {kind:'proficiency',feature:'Primal Knowledge',repeat_per_feature:true,min_feature_level:3,source_fallback:'TCE',choose:{from:['animal handling','athletics','intimidation','nature','perception','survival'],count:1}},
 {kind:'proficiency',feature:'Aspect of the Beast',subclass:'Totem Warrior',state_choice:{group:'barbarian_totem_aspect',value:'barbarian_totem_aspect:tiger'},choose:{from:['acrobatics','athletics','stealth','survival'],count:2}},
 {kind:'spell_choice',id:'barbarian:2014:giant-power:cantrip',feature:'Giant Power',subclass:'Giant',spell_options:['phb2014_druidcraft','phb2014_thaumaturgy'],count:1,mode:'known',stage:'3',usage:'at_will',tracker_id:'',spellcasting_ability:'wis',spellcasting_ability_options:[]}
];
