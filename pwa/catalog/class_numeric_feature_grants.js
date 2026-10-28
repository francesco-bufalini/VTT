// Trait-owned numeric grants, configured independently of the feature projection engine.
// The attuned_item_count formula is evaluated against actual equipped/attuned item copies.
export const CLASS_NUMERIC_FEATURE_GRANTS = [
 {class_name:'Artificer',class_source:'TCE',feature:'Magic Item Adept',max_class_level:13,group:'attunement',targets:['attunement_max'],value:1},
 {class_name:'Artificer',class_source:'TCE',feature:'Magic Item Savant',max_class_level:17,group:'attunement',targets:['attunement_max'],value:2},
 {class_name:'Artificer',class_source:'TCE',feature:'Magic Item Master',group:'attunement',targets:['attunement_max'],value:3},
 {class_name:'Artificer',class_source:'TCE',feature:'Soul of Artifice',group:'soul',targets:['save:str','save:dex','save:con','save:int','save:wis','save:cha'],formula:'attuned_item_count'}
];
