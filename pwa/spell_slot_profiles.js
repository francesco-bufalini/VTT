// The grant names a standard profile. The engine owns multiclass resolution.
export const SLOT_PROFILES=Object.freeze({
 full_caster:{pool:'shared',divisor:1,single_round:'floor',multiclass_round:'floor'},
 half_caster_down:{pool:'shared',divisor:2,single_round:'ceil',multiclass_round:'floor'},
 half_caster_up:{pool:'shared',divisor:2,single_round:'ceil',multiclass_round:'ceil'},
 third_caster:{pool:'shared',divisor:3,single_round:'ceil',multiclass_round:'floor'},
 third_caster_up:{pool:'shared',divisor:3,single_round:'ceil',multiclass_round:'ceil'},
 pact_magic:{pool:'pact',slot_count:{by_class_level:[[1,1],[2,2],[11,3],[17,4]]},
  slot_level:{by_class_level:[[1,1],[3,2],[5,3],[7,4],[9,5]]}}
});
export function resolveSpellSlotProfile(spec={}){
 if(!spec?.profile)return spec||{};
 const profile=SLOT_PROFILES[spec.profile];
 if(!profile)throw Error('Profilo slot sconosciuto: '+spec.profile);
 return {...profile,...spec,pool:profile.pool};
}
