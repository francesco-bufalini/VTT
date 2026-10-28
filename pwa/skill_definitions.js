// Canonical D&D skill names and governing abilities, shared by sheets and traits.
export const SKILLS=[
 ["acrobatics","Acrobazia","dex"],["animal handling","Addestrare Animali","wis"],
 ["arcana","Arcano","int"],["athletics","Atletica","str"],
 ["deception","Inganno","cha"],["history","Storia","int"],
 ["insight","Intuizione","wis"],["intimidation","Intimidire","cha"],
 ["investigation","Indagare","int"],["medicine","Medicina","wis"],
 ["nature","Natura","int"],["perception","Percezione","wis"],
 ["performance","Intrattenere","cha"],["persuasion","Persuasione","cha"],
 ["religion","Religione","int"],["sleight of hand","Rapidità di Mano","dex"],
 ["stealth","Furtività","dex"],["survival","Sopravvivenza","wis"]
];
// Reuse the same key-to-ability mapping for all skill-related mechanics.
export const SKILL_ABILITY=Object.fromEntries(SKILLS.map(([key,,ability])=>[key,ability]));
