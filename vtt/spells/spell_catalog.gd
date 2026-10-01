extends RefCounted

const GeneratedCatalog = preload(
	"res://vtt/spells/spell_catalog_5etools.gd"
)
const SpellAreaCatalog = preload(
	"res://vtt/spells/spell_area_catalog.gd"
)

const CLASS_DISPLAY_NAMES: Dictionary = {
	"Artificer": "Artefice",
	"Bard": "Bardo",
	"Cleric": "Chierico",
	"Druid": "Druido",
	"Monk": "Monaco",
	"Paladin": "Paladino",
	"Ranger": "Ranger",
	"Sorcerer": "Stregone",
	"Warlock": "Warlock",
	"Wizard": "Mago"
}

const CLASS_CANONICAL_NAMES: Dictionary = {
	"Artefice": "Artificer",
	"Bardo": "Bard",
	"Chierico": "Cleric",
	"Druido": "Druid",
	"Monaco": "Monk",
	"Paladino": "Paladin",
	"Ranger": "Ranger",
	"Stregone": "Sorcerer",
	"Warlock": "Warlock",
	"Mago": "Wizard"
}

const LEVEL_NAMES: Array[String] = [
	"Trucchetti", "1° livello", "2° livello", "3° livello", "4° livello",
	"5° livello", "6° livello", "7° livello", "8° livello", "9° livello"
]

# Runtime-only mechanics layered on top of the generated 5eTools catalog.
# Keeping these here avoids modifying the generated file by hand.
const RUNTIME_OVERRIDES: Dictionary = {
	"cloudkill": {
		"movable_aoe_feet": 10.0,
		"movable_aoe_mode": "away_from_caster"
	},
	"doomtide": {
		"movable_aoe_feet": 10.0,
		"movable_aoe_mode": "away_from_caster"
	},
	"incendiary_cloud": {
		"movable_aoe_feet": 10.0,
		"movable_aoe_mode": "free_exact"
	},
	"whirlwind": {
		"movable_aoe_feet": 30.0,
		"movable_aoe_mode": "free"
	},
	"conjure_celestial": {
		"movable_aoe_feet": 30.0,
		"movable_aoe_mode": "free"
	},
	"meteor_swarm": {
		"target_mode": "token_then_multi_point",
		"range_feet": 5280.0,
		"base_target_clicks": 4,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 40.0,
		"visual_style": "fire",
		"projectile_style": "fire",
		"projectile_travel_seconds": 0.8,
		"meteor_drop_height_feet": 60.0,
		"requires_ground": true,
		"transient_seconds": 5.0
	},
	"thunderwave": {
		"forced_movement_feet": 15.0,
		"forced_movement_mode": "away_from_caster",
		"forced_movement_on_failed_save": true
	}
}

# Runtime fields used by the VTT:
# target_mode:
# - self_token: pick caster, then cast a directional self AoE.
# - self_emanation: pick caster, then cast an AoE centered on it.
# - token_then_point: pick caster, then a point in range.
# - token_then_token: pick caster, then one target token.
# - token_then_multi_token: pick caster, then N target clicks.
# - token_then_direction: pick caster, then a point/token which defines direction.
#
# All cantrips imported here are interpreted as cast by a level-17 character.
const SPELLS: Dictionary = {
	"acid_splash": {
		"id": "acid_splash",
		"name": "Acid Splash",
		"source": "XPHB",
		"level": 0,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "60 feet",
		"target": "A point within range",
		"area": "5-foot-radius sphere",
		"components": "V, S",
		"duration": "Instantaneous",
		"classes": ["Stregone", "Mago"],
		"description": "An acidic bubble bursts at a chosen point, affecting creatures in a small sphere.",
		"higher_levels": "Cantrip scaling: at character level 17 the damage is 4d6 Acid.",
		"target_mode": "token_then_point",
		"range_feet": 60,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 5,
		"visual_style": "acid_splash",
		"transient_seconds": 5.0,
		"level17_damage": "4d6 Acid"
	},
	"thunderclap": {
		"id": "thunderclap",
		"name": "Thunderclap",
		"source": "XPHB",
		"level": 0,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "Self (5-foot emanation)",
		"target": "Creatures around the caster",
		"area": "5-foot emanation",
		"components": "S",
		"duration": "Instantaneous",
		"classes": ["Bardo", "Druido", "Stregone", "Warlock", "Mago"],
		"description": "A burst of thunder erupts around the caster.",
		"higher_levels": "Cantrip scaling: at character level 17 the damage is 4d6 Thunder.",
		"target_mode": "self_emanation",
		"aoe_shape": "sphere",
		"aoe_radius_feet": 5,
		"visual_style": "thunderclap",
		"transient_seconds": 5.0,
		"level17_damage": "4d6 Thunder"
	},

	"burning_hands": {
		"id": "burning_hands",
		"name": "Burning Hands",
		"source": "XPHB",
		"level": 1,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "Self",
		"target": "Self",
		"area": "15-foot cone",
		"components": "V, S",
		"duration": "Instantaneous",
		"classes": ["Stregone", "Mago"],
		"description": "A sheet of flame erupts in a 15-foot cone from the caster.",
		"higher_levels": "Damage increases by 1d6 for each slot level above 1.",
		"target_mode": "self_token",
		"aoe_shape": "cone",
		"aoe_length_cells": 3,
		"allow_pitch": true,
		"visual_style": "burning_hands",
		"transient_seconds": 5.0
	},
	"color_spray": {
		"id": "color_spray",
		"name": "Color Spray",
		"source": "XPHB",
		"level": 1,
		"school": "Illusion",
		"casting_time": "1 action",
		"range": "Self",
		"target": "Creatures in the cone",
		"area": "15-foot cone",
		"components": "V, S, M (a pinch of colorful sand)",
		"duration": "Instantaneous",
		"classes": ["Bardo", "Stregone", "Mago"],
		"description": "A fan of dazzling colors bursts from the caster and can briefly blind creatures in the cone.",
		"higher_levels": "No slot scaling.",
		"target_mode": "self_token",
		"aoe_shape": "cone",
		"aoe_length_cells": 3,
		"allow_pitch": true,
		"visual_style": "color_spray",
		"transient_seconds": 5.0
	},
	"fog_cloud": {
		"id": "fog_cloud",
		"name": "Fog Cloud",
		"source": "XPHB",
		"level": 1,
		"school": "Conjuration",
		"casting_time": "1 action",
		"range": "120 feet",
		"target": "A point within range",
		"area": "20-foot-radius sphere",
		"components": "V, S",
		"duration": "Concentration, up to 1 hour",
		"classes": ["Druido", "Ranger", "Stregone", "Mago"],
		"description": "A dense sphere of fog heavily obscures its area.",
		"higher_levels": "The radius increases by 20 feet for each slot level above 1.",
		"target_mode": "token_then_point",
		"range_feet": 120,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 20,
		"radius_per_slot_above_base": 20,
		"persistent": true,
		"visual_style": "fog_cloud"
	},
	"grease": {
		"id": "grease",
		"name": "Grease",
		"source": "XPHB",
		"level": 1,
		"school": "Conjuration",
		"casting_time": "1 action",
		"range": "60 feet",
		"target": "A point on the ground",
		"area": "10-foot square",
		"components": "V, S, M (a bit of pork rind or butter)",
		"duration": "1 minute",
		"classes": ["Stregone", "Mago"],
		"description": "A slick 10-foot square appears on the ground and becomes difficult terrain.",
		"higher_levels": "No slot scaling.",
		"target_mode": "token_then_point",
		"range_feet": 60,
		"requires_ground": true,
		"aoe_shape": "flat_square",
		"aoe_side_feet": 10,
		"persistent": true,
		"visual_style": "grease"
	},
	"ice_knife": {
		"id": "ice_knife",
		"name": "Ice Knife",
		"source": "XPHB",
		"level": 1,
		"school": "Conjuration",
		"casting_time": "1 action",
		"range": "60 feet",
		"target": "One creature",
		"area": "5-foot-radius burst at the target",
		"components": "S, M (a drop of water or a piece of ice)",
		"duration": "Instantaneous",
		"classes": ["Druido", "Stregone", "Mago"],
		"description": "An ice shard is thrown at one creature and then bursts around the target whether the attack hits or misses.",
		"higher_levels": "The burst's Cold damage increases by 1d6 for each slot level above 1.",
		"target_mode": "token_then_token",
		"range_feet": 60,
		"projectile_style": "ice_knife",
		"impact_aoe_shape": "sphere",
		"impact_aoe_radius_feet": 5,
		"impact_style": "ice_knife_burst",
		"transient_seconds": 5.0
	},
	"sleep": {
		"id": "sleep",
		"name": "Sleep",
		"source": "XPHB",
		"level": 1,
		"school": "Enchantment",
		"casting_time": "1 action",
		"range": "60 feet",
		"target": "Creatures in a chosen area",
		"area": "5-foot-radius sphere",
		"components": "V, S, M (a pinch of sand or rose petals)",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Bardo", "Stregone", "Mago"],
		"description": "Creatures chosen in a small sphere can become incapacitated and then unconscious.",
		"higher_levels": "No slot scaling.",
		"target_mode": "token_then_point",
		"range_feet": 60,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 5,
		"visual_style": "sleep",
		"transient_seconds": 5.0
	},
	"thunderwave": {
		"id": "thunderwave",
		"name": "Thunderwave",
		"source": "XPHB",
		"level": 1,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "Self",
		"target": "Creatures in the cube",
		"area": "15-foot cube originating from the caster",
		"components": "V, S",
		"duration": "Instantaneous",
		"classes": ["Bardo", "Druido", "Stregone", "Mago"],
		"description": "A cube of thunderous force erupts from the caster and pushes creatures and unsecured objects away.",
		"higher_levels": "Damage increases by 1d8 for each slot level above 1.",
		"target_mode": "token_then_direction",
		"direction_limit_feet": 15,
		"show_range_preview": false,
		"aoe_shape": "cube",
		"aoe_side_feet": 15,
		"directional_cube": true,
		"visual_style": "thunderwave",
		"transient_seconds": 5.0
	},
	"witch_bolt": {
		"id": "witch_bolt",
		"name": "Witch Bolt",
		"source": "XPHB",
		"level": 1,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "60 feet",
		"target": "One creature",
		"area": "Single sustained link",
		"components": "V, S, M (a twig struck by lightning)",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Stregone", "Warlock", "Mago"],
		"description": "A crackling arc links the caster to one creature for the spell's duration.",
		"higher_levels": "Only the initial damage increases by 1d12 for each slot level above 1.",
		"target_mode": "token_then_token",
		"range_feet": 60,
		"persistent_link": true,
		"projectile_style": "witch_bolt",
		"visual_style": "witch_bolt"
	},

	"cloud_of_daggers": {
		"id": "cloud_of_daggers",
		"name": "Cloud of Daggers",
		"source": "XPHB",
		"level": 2,
		"school": "Conjuration",
		"casting_time": "1 action",
		"range": "60 feet",
		"target": "A point within range",
		"area": "5-foot cube",
		"components": "V, S, M (a sliver of glass)",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Bardo", "Stregone", "Warlock", "Mago"],
		"description": "Spinning magical daggers fill a small cube and damage creatures occupying it.",
		"higher_levels": "Damage increases by 2d4 for each slot level above 2.",
		"target_mode": "token_then_point",
		"range_feet": 60,
		"aoe_shape": "cube",
		"aoe_side_feet": 5,
		"persistent": true,
		"movable_aoe_feet": 30.0,
		"movable_aoe_mode": "free",
		"visual_style": "cloud_of_daggers"
	},
	"shatter": {
		"id": "shatter",
		"name": "Shatter",
		"source": "XPHB",
		"level": 2,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "60 feet",
		"target": "A point within range",
		"area": "10-foot-radius sphere",
		"components": "V, S, M (a chip of mica)",
		"duration": "Instantaneous",
		"classes": ["Bardo", "Stregone", "Mago"],
		"description": "A concussive burst of sound erupts from a chosen point.",
		"higher_levels": "Damage increases by 1d8 for each slot level above 2.",
		"target_mode": "token_then_point",
		"range_feet": 60,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 10,
		"visual_style": "shatter",
		"transient_seconds": 5.0
	},
	"web": {
		"id": "web",
		"name": "Web",
		"source": "XPHB",
		"level": 2,
		"school": "Conjuration",
		"casting_time": "1 action",
		"range": "60 feet",
		"target": "A point within range",
		"area": "20-foot cube",
		"components": "V, S, M (a bit of spiderweb)",
		"duration": "Concentration, up to 1 hour",
		"classes": ["Stregone", "Mago"],
		"description": "Sticky webbing fills a cube, creating difficult and lightly obscured terrain that can restrain creatures.",
		"higher_levels": "No slot scaling.",
		"target_mode": "token_then_point",
		"range_feet": 60,
		"aoe_shape": "cube",
		"aoe_side_feet": 20,
		"persistent": true,
		"visual_style": "web"
	},

	"fear": {
		"id": "fear",
		"name": "Fear",
		"source": "XPHB",
		"level": 3,
		"school": "Illusion",
		"casting_time": "1 action",
		"range": "Self",
		"target": "Creatures in the cone",
		"area": "30-foot cone",
		"components": "V, S, M (a white feather)",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Bardo", "Stregone", "Warlock", "Mago"],
		"description": "A wave of supernatural terror projects outward in a cone.",
		"higher_levels": "No slot scaling.",
		"target_mode": "self_token",
		"aoe_shape": "cone",
		"aoe_length_cells": 6,
		"allow_pitch": true,
		"visual_style": "fear",
		"transient_seconds": 5.0
	},
	"hypnotic_pattern": {
		"id": "hypnotic_pattern",
		"name": "Hypnotic Pattern",
		"source": "XPHB",
		"level": 3,
		"school": "Illusion",
		"casting_time": "1 action",
		"range": "120 feet",
		"target": "Creatures in the area",
		"area": "30-foot cube",
		"components": "S, M (a pinch of confetti)",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Bardo", "Stregone", "Warlock", "Mago"],
		"description": "A twisting pattern of colors flashes momentarily inside a large cube and can incapacitate creatures that see it.",
		"higher_levels": "No slot scaling.",
		"target_mode": "token_then_point",
		"range_feet": 120,
		"aoe_shape": "cube",
		"aoe_side_feet": 30,
		"visual_style": "hypnotic_pattern",
		"transient_seconds": 5.0
	},
	"sleet_storm": {
		"id": "sleet_storm",
		"name": "Sleet Storm",
		"source": "XPHB",
		"level": 3,
		"school": "Conjuration",
		"casting_time": "1 action",
		"range": "150 feet",
		"target": "A point within range",
		"area": "20-foot-radius, 40-foot-high cylinder",
		"components": "V, S, M (a miniature umbrella)",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Druido", "Stregone", "Mago"],
		"description": "Sleet fills a tall cylinder, heavily obscuring it and making its ground difficult terrain.",
		"higher_levels": "No slot scaling.",
		"target_mode": "token_then_point",
		"range_feet": 150,
		"aoe_shape": "cylinder",
		"aoe_radius_feet": 20,
		"aoe_height_feet": 40,
		"persistent": true,
		"visual_style": "sleet_storm"
	},
	"slow": {
		"id": "slow",
		"name": "Slow",
		"source": "XPHB",
		"level": 3,
		"school": "Transmutation",
		"casting_time": "1 action",
		"range": "120 feet",
		"target": "Up to six creatures in the area",
		"area": "40-foot cube",
		"components": "V, S, M (a drop of molasses)",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Bardo", "Stregone", "Mago"],
		"description": "Time is distorted around up to six chosen creatures inside a large cube.",
		"higher_levels": "No slot scaling.",
		"target_mode": "token_then_point",
		"range_feet": 120,
		"aoe_shape": "cube",
		"aoe_side_feet": 40,
		"visual_style": "slow",
		"transient_seconds": 5.0
	},
	"stinking_cloud": {
		"id": "stinking_cloud",
		"name": "Stinking Cloud",
		"source": "XPHB",
		"level": 3,
		"school": "Conjuration",
		"casting_time": "1 action",
		"range": "90 feet",
		"target": "A point within range",
		"area": "20-foot-radius sphere",
		"components": "V, S, M (a rotten egg)",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Bardo", "Stregone", "Mago"],
		"description": "A dense nauseating cloud heavily obscures a sphere and can poison creatures inside it.",
		"higher_levels": "No slot scaling.",
		"target_mode": "token_then_point",
		"range_feet": 90,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 20,
		"persistent": true,
		"visual_style": "stinking_cloud"
	},

	"confusion": {
		"id": "confusion",
		"name": "Confusion",
		"source": "XPHB",
		"level": 4,
		"school": "Enchantment",
		"casting_time": "1 action",
		"range": "90 feet",
		"target": "Creatures in the sphere",
		"area": "10-foot-radius sphere",
		"components": "V, S, M (three nut shells)",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Bardo", "Druido", "Stregone", "Mago"],
		"description": "Chaotic magic affects creatures inside a sphere, disrupting their actions and movement.",
		"higher_levels": "The sphere radius increases by 5 feet for each slot level above 4.",
		"target_mode": "token_then_point",
		"range_feet": 90,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 10,
		"radius_per_slot_above_base": 5,
		"visual_style": "confusion",
		"transient_seconds": 5.0
	},
	"ice_storm": {
		"id": "ice_storm",
		"name": "Ice Storm",
		"source": "XPHB",
		"level": 4,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "300 feet",
		"target": "A point within range",
		"area": "20-foot-radius, 40-foot-high cylinder",
		"components": "V, S, M (a mitten)",
		"duration": "Instantaneous",
		"classes": ["Druido", "Stregone", "Mago"],
		"description": "Hail crashes through a tall cylinder, dealing bludgeoning and cold damage and briefly leaving difficult terrain.",
		"higher_levels": "Bludgeoning damage increases by 1d10 for each slot level above 4.",
		"target_mode": "token_then_point",
		"range_feet": 300,
		"aoe_shape": "cylinder",
		"aoe_radius_feet": 20,
		"aoe_height_feet": 40,
		"visual_style": "ice_storm",
		"transient_seconds": 5.0
	},
	"vitriolic_sphere": {
		"id": "vitriolic_sphere",
		"name": "Vitriolic Sphere",
		"source": "XPHB",
		"level": 4,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "150 feet",
		"target": "A point within range",
		"area": "20-foot-radius sphere",
		"components": "V, S, M (a drop of bile)",
		"duration": "Instantaneous",
		"classes": ["Stregone", "Mago"],
		"description": "A globe of acid streaks to a point and explodes in a large sphere.",
		"higher_levels": "Initial damage increases by 2d4 for each slot level above 4.",
		"target_mode": "token_then_point",
		"range_feet": 150,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 20,
		"visual_style": "vitriolic_sphere",
		"transient_seconds": 5.0
	},

	"cone_of_cold": {
		"id": "cone_of_cold",
		"name": "Cone of Cold",
		"source": "XPHB",
		"level": 5,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "Self",
		"target": "Creatures in the cone",
		"area": "60-foot cone",
		"components": "V, S, M (a small crystal or glass cone)",
		"duration": "Instantaneous",
		"classes": ["Druido", "Stregone", "Mago"],
		"description": "A blast of freezing air surges from the caster through a very large cone.",
		"higher_levels": "Damage increases by 1d8 for each slot level above 5.",
		"target_mode": "self_token",
		"aoe_shape": "cone",
		"aoe_length_cells": 12,
		"allow_pitch": true,
		"visual_style": "cone_of_cold",
		"transient_seconds": 5.0
	},
	"insect_plague": {
		"id": "insect_plague",
		"name": "Insect Plague",
		"source": "XPHB",
		"level": 5,
		"school": "Conjuration",
		"casting_time": "1 action",
		"range": "300 feet",
		"target": "A point within range",
		"area": "20-foot-radius sphere",
		"components": "V, S, M (a locust)",
		"duration": "Concentration, up to 10 minutes",
		"classes": ["Chierico", "Druido", "Stregone"],
		"description": "A dense swarm of locusts fills a sphere, obscuring the area and damaging creatures that enter or remain inside.",
		"higher_levels": "Damage increases by 1d10 for each slot level above 5.",
		"target_mode": "token_then_point",
		"range_feet": 300,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 20,
		"persistent": true,
		"visual_style": "insect_plague"
	},
	"synaptic_static": {
		"id": "synaptic_static",
		"name": "Synaptic Static",
		"source": "XPHB",
		"level": 5,
		"school": "Enchantment",
		"casting_time": "1 action",
		"range": "120 feet",
		"target": "A point within range",
		"area": "20-foot-radius sphere",
		"components": "V, S",
		"duration": "Instantaneous",
		"classes": ["Bardo", "Stregone", "Warlock", "Mago"],
		"description": "Psychic energy erupts in a sphere and can leave affected creatures mentally disrupted.",
		"higher_levels": "No slot scaling.",
		"target_mode": "token_then_point",
		"range_feet": 120,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 20,
		"visual_style": "synaptic_static",
		"transient_seconds": 5.0
	},

	"circle_of_death": {
		"id": "circle_of_death",
		"name": "Circle of Death",
		"source": "XPHB",
		"level": 6,
		"school": "Necromancy",
		"casting_time": "1 action",
		"range": "150 feet",
		"target": "A point within range",
		"area": "60-foot-radius sphere",
		"components": "V, S, M (crushed black pearl powder worth 500+ GP)",
		"duration": "Instantaneous",
		"classes": ["Stregone", "Warlock", "Mago"],
		"description": "A massive wave of necrotic energy expands from a chosen point.",
		"higher_levels": "Damage increases by 2d8 for each slot level above 6.",
		"target_mode": "token_then_point",
		"range_feet": 150,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 60,
		"visual_style": "circle_of_death",
		"transient_seconds": 5.0
	},
	"globe_of_invulnerability": {
		"id": "globe_of_invulnerability",
		"name": "Globe of Invulnerability",
		"source": "XPHB",
		"level": 6,
		"school": "Abjuration",
		"casting_time": "1 action",
		"range": "Self (10-foot emanation)",
		"target": "Area around the caster",
		"area": "10-foot emanation",
		"components": "V, S, M (a glass bead)",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Stregone", "Mago"],
		"description": "An immobile shimmering barrier appears around the caster and blocks lower-level spells from outside.",
		"higher_levels": "The maximum blocked spell level rises by one for each slot level above 6.",
		"target_mode": "self_emanation",
		"aoe_shape": "sphere",
		"aoe_radius_feet": 10,
		"persistent": true,
		"visual_style": "globe_of_invulnerability"
	},
	"otilukes_freezing_sphere": {
		"id": "otilukes_freezing_sphere",
		"name": "Otiluke's Freezing Sphere",
		"source": "XPHB",
		"level": 6,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "300 feet",
		"target": "A point within range",
		"area": "60-foot-radius sphere",
		"components": "V, S, M (a miniature crystal sphere)",
		"duration": "Instantaneous",
		"classes": ["Stregone", "Mago"],
		"description": "A frigid globe streaks to a chosen point and explodes in an enormous sphere of cold.",
		"higher_levels": "Damage increases by 1d6 for each slot level above 6.",
		"target_mode": "token_then_point",
		"range_feet": 300,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 60,
		"visual_style": "otilukes_freezing_sphere",
		"transient_seconds": 5.0
	},
	"sunbeam": {
		"id": "sunbeam",
		"name": "Sunbeam",
		"source": "XPHB",
		"level": 6,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "Self (60-foot line)",
		"target": "A direction from the caster",
		"area": "60-foot-long, 5-foot-wide line",
		"components": "V, S, M (a magnifying glass)",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Chierico", "Druido", "Stregone", "Mago"],
		"description": "A brilliant beam of sunlight projects from the caster along a 60-foot line.",
		"higher_levels": "No slot scaling.",
		"target_mode": "token_then_direction",
		"range_feet": 60,
		"aoe_shape": "line",
		"aoe_length_cells": 12,
		"visual_style": "sunbeam",
		"transient_seconds": 5.0
	},

	"gust_of_wind": {
		"id": "gust_of_wind", "name": "Gust of Wind", "source": "XPHB",
		"level": 2, "school": "Evocation", "casting_time": "1 action",
		"range": "Self", "target": "Self, then choose a direction", "area": "60-foot-long, 10-foot-wide line",
		"components": "V, S, M", "duration": "Concentration, up to 1 minute",
		"classes": ["Druido", "Stregone", "Mago"],
		"description": "A sustained line of strong wind blasts away from the caster and can push creatures.",
		"higher_levels": "No slot scaling.",
		"target_mode": "token_then_direction", "direction_limit_feet": 60,
		"aoe_shape": "line", "aoe_length_cells": 12, "line_width_feet": 10,
		"persistent": true, "visual_style": "gust_of_wind", "show_range_preview": false
	},
	"cloudkill": {
		"id": "cloudkill", "name": "Cloudkill", "source": "XPHB",
		"level": 5, "school": "Conjuration", "casting_time": "1 action",
		"range": "120 feet", "target": "A point within range", "area": "20-foot-radius sphere",
		"components": "V, S", "duration": "Concentration, up to 10 minutes",
		"classes": ["Stregone", "Mago"],
		"description": "A poisonous, heavily obscuring sphere of fog forms at the chosen point. Rules text also moves it 10 feet away from the caster each turn.",
		"higher_levels": "Damage increases by 1d8 for each slot level above 5.",
		"target_mode": "token_then_point", "range_feet": 120,
		"aoe_shape": "sphere", "aoe_radius_feet": 20, "persistent": true,
		"visual_style": "cloudkill"
	},
	"wind_wall": {
		"id": "wind_wall",
		"name": "Wind Wall",
		"source": "XPHB",
		"level": 3,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "120 feet",
		"target": "A point on the ground within range",
		"area": "Up to 50-foot-long, 15-foot-high wall",
		"components": "V, S, M",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Druido", "Ranger"],
		"description": "A continuous wall of strong wind rises from the ground and can follow a shaped path.",
		"higher_levels": "No slot scaling.",
		"target_mode": "wall_design",
		"range_feet": 120,
		"wall_modes": ["polyline"],
		"wall_max_length_feet": 50,
		"wall_height_feet": 15,
		"wall_thickness_feet": 1,
		"wall_requires_ground": true,
		"persistent": true,
		"visual_style": "wind_wall"
	},
	"wall_of_fire": {
		"id": "wall_of_fire",
		"name": "Wall of Fire",
		"source": "XPHB",
		"level": 4,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "120 feet",
		"target": "A solid surface within range",
		"area": "Up to 60-foot wall or 20-foot-diameter ring",
		"components": "V, S, M (a piece of charcoal)",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Druido", "Stregone", "Mago"],
		"description": "A persistent opaque wall of fire. It can be drawn as a segmented wall or as an arc/ring on a solid surface. One side radiates damaging heat out to 10 feet.",
		"higher_levels": "Damage increases by 1d8 for each slot level above 4.",
		"target_mode": "wall_design",
		"range_feet": 120,
		"wall_modes": ["polyline", "circle"],
		"wall_max_length_feet": 60,
		"wall_circle_max_radius_feet": 10,
		"wall_height_feet": 20,
		"wall_thickness_feet": 1,
		"wall_requires_ground": true,
		"wall_choose_damage_side": true,
		"persistent": true,
		"visual_style": "wall_of_fire"
	},
	"wall_of_force": {
		"id": "wall_of_force",
		"name": "Wall of Force",
		"source": "XPHB",
		"level": 5,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "120 feet",
		"target": "A point within range",
		"area": "Ten contiguous 10-foot panels, globe, or hemispherical dome",
		"components": "V, S, M",
		"duration": "Concentration, up to 10 minutes",
		"classes": ["Mago"],
		"description": "An almost invisible barrier of force forms as contiguous panels, a globe, or a hemispherical dome.",
		"higher_levels": "No slot scaling.",
		"target_mode": "wall_design",
		"range_feet": 120,
		"wall_modes": ["polyline", "globe", "dome"],
		"wall_max_length_feet": 100,
		"wall_height_feet": 10,
		"wall_thickness_feet": 0.1,
		"wall_globe_max_radius_feet": 10,
		"persistent": true,
		"visual_style": "wall_of_force"
	},
	"wall_of_stone": {
		"id": "wall_of_stone",
		"name": "Wall of Stone",
		"source": "XPHB",
		"level": 5,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "120 feet",
		"target": "A point within range",
		"area": "Ten contiguous 10-foot-by-10-foot panels",
		"components": "V, S, M",
		"duration": "Concentration, up to 10 minutes",
		"classes": ["Druido", "Stregone", "Mago"],
		"description": "A solid wall of stone is assembled from contiguous panels. The VTT represents the standard ten 10-foot panels as a path with a 100-foot total budget.",
		"higher_levels": "No slot scaling.",
		"target_mode": "wall_design",
		"range_feet": 120,
		"wall_modes": ["polyline"],
		"wall_max_length_feet": 100,
		"wall_height_feet": 10,
		"wall_thickness_feet": 0.5,
		"persistent": true,
		"visual_style": "wall_of_stone"
	},
	"blade_barrier": {
		"id": "blade_barrier",
		"name": "Blade Barrier",
		"source": "XPHB",
		"level": 6,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "90 feet",
		"target": "A point within range",
		"area": "Up to 100-foot wall or 60-foot-diameter ring",
		"components": "V, S",
		"duration": "Concentration, up to 10 minutes",
		"classes": ["Chierico"],
		"description": "A wall of whirling magical blades can be straight or ring-shaped.",
		"higher_levels": "No slot scaling.",
		"target_mode": "wall_design",
		"range_feet": 90,
		"wall_modes": ["polyline", "circle"],
		"wall_max_length_feet": 100,
		"wall_circle_max_radius_feet": 30,
		"wall_height_feet": 20,
		"wall_thickness_feet": 5,
		"persistent": true,
		"visual_style": "blade_barrier"
	},
	"wall_of_ice": {
		"id": "wall_of_ice",
		"name": "Wall of Ice",
		"source": "XPHB",
		"level": 6,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "120 feet",
		"target": "A solid surface within range",
		"area": "Ten contiguous 10-foot panels, globe, or hemispherical dome",
		"components": "V, S, M",
		"duration": "Concentration, up to 10 minutes",
		"classes": ["Mago"],
		"description": "A wall of ice forms as contiguous panels, a globe, or a hemispherical dome.",
		"higher_levels": "Initial damage increases by 2d6 and frigid-air damage by 1d6 for each slot level above 6.",
		"target_mode": "wall_design",
		"range_feet": 120,
		"wall_modes": ["polyline", "globe", "dome"],
		"wall_max_length_feet": 100,
		"wall_height_feet": 10,
		"wall_thickness_feet": 1,
		"wall_globe_max_radius_feet": 10,
		"wall_requires_ground": true,
		"persistent": true,
		"visual_style": "wall_of_ice"
	},
	"wall_of_thorns": {
		"id": "wall_of_thorns",
		"name": "Wall of Thorns",
		"source": "XPHB",
		"level": 6,
		"school": "Conjuration",
		"casting_time": "1 action",
		"range": "120 feet",
		"target": "A solid surface within range",
		"area": "Up to 60-foot wall or 20-foot-diameter circle",
		"components": "V, S, M",
		"duration": "Concentration, up to 10 minutes",
		"classes": ["Druido"],
		"description": "A dense wall of thorny brush can be drawn as a wall or a circle.",
		"higher_levels": "Both damage types increase by 1d8 for each slot level above 6.",
		"target_mode": "wall_design",
		"range_feet": 120,
		"wall_modes": ["polyline", "circle"],
		"wall_max_length_feet": 60,
		"wall_circle_max_radius_feet": 10,
		"wall_height_feet": 10,
		"wall_circle_height_feet": 20,
		"wall_thickness_feet": 5,
		"wall_requires_ground": true,
		"persistent": true,
		"visual_style": "wall_of_thorns"
	},
	"prismatic_wall": {
		"id": "prismatic_wall",
		"name": "Prismatic Wall",
		"source": "XPHB",
		"level": 9,
		"school": "Abjuration",
		"casting_time": "1 action",
		"range": "60 feet",
		"target": "A point within range",
		"area": "Up to 90-foot wall or 30-foot-diameter globe",
		"components": "V, S",
		"duration": "10 minutes",
		"classes": ["Bardo", "Mago"],
		"description": "A seven-layered opaque wall of colored light can be created as a vertical wall or as a globe.",
		"higher_levels": "No slot scaling.",
		"target_mode": "wall_design",
		"range_feet": 60,
		"wall_modes": ["polyline", "globe"],
		"wall_max_length_feet": 90,
		"wall_height_feet": 30,
		"wall_thickness_feet": 0.1,
		"wall_globe_max_radius_feet": 15,
		"persistent": true,
		"visual_style": "prismatic_wall"
	},
	"darkness": {
		"id": "darkness",
		"name": "Darkness",
		"level": 2,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "60 feet",
		"target": "A point within range",
		"area": "15-foot-radius sphere",
		"components": "V, M (bat fur and a piece of coal)",
		"duration": "Concentration, up to 10 minutes",
		"classes": ["Stregone", "Warlock", "Mago"],
		"description": "Magical darkness fills a 15-foot-radius sphere.",
		"higher_levels": "",
		"target_mode": "token_then_point",
		"range_feet": 60,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 15,
		"persistent": true,
		"visual_style": "darkness"
	},
	"lightning_bolt": {
		"id": "lightning_bolt",
		"name": "Lightning Bolt",
		"level": 3,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "Self",
		"target": "Self, then choose a direction",
		"area": "100-foot-long, 5-foot-wide line",
		"components": "V, S, M (a bit of fur and a crystal rod)",
		"duration": "Instantaneous",
		"classes": ["Stregone", "Mago"],
		"description": "A 100-foot line of lightning blasts from the caster in a chosen direction.",
		"higher_levels": "Damage increases by 1d6 for each slot level above 3.",
		"target_mode": "token_then_direction",
		"range_feet": 100,
		"aoe_shape": "line",
		"aoe_length_cells": 20,
		"visual_style": "lightning_bolt",
		"transient_seconds": 5.0
	},

	"misty_step": {
		"id": "misty_step",
		"name": "Misty Step",
		"source": "XPHB",
		"level": 2,
		"school": "Conjuration",
		"casting_time": "Bonus Action",
		"range": "Self",
		"target": "Self",
		"area": "Teleport",
		"components": "V",
		"duration": "Instantaneous",
		"classes": ["Stregone", "Warlock", "Mago"],
		"description": "The caster teleports to an unoccupied space they can see within 30 feet.",
		"higher_levels": "No slot scaling.",
		"target_mode": "teleport_self",
		"teleport_distance_feet": 30,
		"teleport_max_passengers": 0,
		"visual_style": "silver_mist"
	},
	"dimension_door": {
		"id": "dimension_door",
		"name": "Dimension Door",
		"source": "XPHB",
		"level": 4,
		"school": "Conjuration",
		"casting_time": "Action",
		"range": "500 feet",
		"target": "Self; optionally one nearby willing creature",
		"area": "Teleport",
		"components": "V",
		"duration": "Instantaneous",
		"classes": ["Bardo", "Stregone", "Warlock", "Mago"],
		"description": "The caster teleports to a destination within 500 feet and can bring one nearby willing creature.",
		"higher_levels": "No slot scaling.",
		"target_mode": "teleport_self",
		"teleport_distance_feet": 500,
		"teleport_max_passengers": 1,
		"teleport_passenger_range_feet": 5,
		"visual_style": "force"
	},
	"thunder_step": {
		"id": "thunder_step",
		"name": "Thunder Step",
		"source": "XGE",
		"level": 3,
		"school": "Conjuration",
		"casting_time": "Action",
		"range": "90 feet",
		"target": "Self; optionally one nearby willing creature",
		"area": "Teleport; 10-foot-radius thunder burst at departure",
		"components": "V",
		"duration": "Instantaneous",
		"classes": ["Stregone", "Warlock", "Mago"],
		"description": "The caster teleports to an unoccupied space within 90 feet and can bring one nearby willing creature. A thunderous burst remains at the point of departure.",
		"higher_levels": "The thunder damage increases with higher-level slots.",
		"target_mode": "teleport_self",
		"teleport_distance_feet": 90,
		"teleport_max_passengers": 1,
		"teleport_passenger_range_feet": 5,
		"visual_style": "thunder",
		"teleport_departure_aoe_radius_feet": 10,
		"teleport_departure_style": "thunder_step"
	},
	"flaming_sphere": {
		"id": "flaming_sphere",
		"name": "Flaming Sphere",
		"source": "XPHB",
		"level": 2,
		"school": "Conjuration",
		"casting_time": "Action",
		"range": "60 feet",
		"target": "A point within range",
		"area": "5-foot-diameter sphere",
		"components": "V, S, M",
		"duration": "Concentration, up to 1 minute",
		"classes": ["Druido", "Mago"],
		"description": "A persistent fiery sphere appears within range and can be moved up to 30 feet when directed.",
		"higher_levels": "Damage increases with higher-level slots.",
		"target_mode": "token_then_point",
		"range_feet": 60,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 2.5,
		"persistent": true,
		"movable_aoe_feet": 30.0,
		"movable_aoe_mode": "free",
		"visual_style": "fire"
	},
	"fireball": {
		"id": "fireball",
		"name": "Fireball",
		"level": 3,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "150 feet",
		"target": "A point within range",
		"area": "20-foot-radius sphere",
		"components": "V, S, M (a tiny ball of bat guano and sulfur)",
		"duration": "Instantaneous",
		"classes": ["Stregone", "Mago", "Spellblade"],
		"description": "A streak of fire detonates at a chosen point in a 20-foot-radius sphere.",
		"higher_levels": "Damage increases by 1d6 for each slot level above 3.",
		"target_mode": "token_then_point",
		"range_feet": 150,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 20,
		"visual_style": "fireball",
		"transient_seconds": 5.0
	}
}


static func _apply_runtime_overrides(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	var spell_id: String = String(result.get("id", ""))
	var override_value: Variant = RUNTIME_OVERRIDES.get(spell_id, {})
	if override_value is Dictionary:
		for key: Variant in (override_value as Dictionary).keys():
			result[key] = (override_value as Dictionary).get(key)

	# Geometry, range, targeting and generic VFX come from the generated
	# runtime map catalogue. Hand-authored entries still carry descriptive
	# metadata and special mechanics, but no longer need to be the authority
	# for ordinary AoE dimensions.
	result = SpellAreaCatalog.apply_to_spell(result)

	# Condition-only spells such as Hold Person have no map geometry, so the
	# area catalogue has nothing from which to infer targeting. The runtime
	# condition flow still needs a token target.
	if String(result.get("target_mode", "")).is_empty():
		var conditions_value: Variant = result.get("condition_inflict", [])
		if conditions_value is Array and not (conditions_value as Array).is_empty():
			result["target_mode"] = "token_then_token"

	if String(result.get("target_mode", "")).is_empty():
		var misc_value: Variant = result.get("misc_tags", [])
		if misc_value is Array and "SMN" in (misc_value as Array):
			result["target_mode"] = "summon"

	return result


static func _is_runtime_usable(spell_data: Dictionary) -> bool:
	if spell_data.is_empty():
		return false

	var target_mode: String = String(
		spell_data.get("target_mode", "")
	)
	if target_mode in [
		"teleport_self",
		"summon",
		"transform_self",
		"token_then_transform",
		"token_then_multi_transform",
		"resize_token"
	]:
		return true
	if target_mode == "wall_design":
		var modes_value: Variant = spell_data.get("wall_modes", [])
		return modes_value is Array and not (modes_value as Array).is_empty()

	var shape: String = String(spell_data.get("aoe_shape", ""))
	if (
		not shape.is_empty()
		and target_mode in [
			"self_token",
			"self_emanation",
			"token_then_point",
			"token_then_direction",
			"token_then_multi_point"
		]
	):
		return true

	if target_mode == "token_then_token":
		var condition_value: Variant = spell_data.get(
			"condition_inflict",
			[]
		)
		if condition_value is Array and not (condition_value as Array).is_empty():
			return true
		if bool(spell_data.get("forced_movement_on_failed_save", false)):
			return true
		if (
			bool(spell_data.get("persistent_link", false))
			or float(spell_data.get("impact_aoe_radius_feet", 0.0)) > 0.0
			or not String(spell_data.get("projectile_style", "")).is_empty()
		):
			return true

		var spec_value: Variant = spell_data.get("map_effect_spec", {})
		if spec_value is Dictionary:
			var spec: Dictionary = spec_value as Dictionary
			var targeting_value: Variant = spec.get("targeting", {})
			var effect_value: Variant = spec.get("effect", {})
			if (
				targeting_value is Dictionary
				and String(
					(targeting_value as Dictionary).get("type", "")
				) == "token"
				and effect_value is Dictionary
			):
				var effect: Dictionary = effect_value as Dictionary
				if effect.get("geometry", {}) is Dictionary:
					return true

	if target_mode == "token_then_multi_token":
		var multi_condition_value: Variant = spell_data.get(
			"condition_inflict",
			[]
		)
		if (
			multi_condition_value is Array
			and not (multi_condition_value as Array).is_empty()
		):
			return true
		if bool(spell_data.get("forced_movement_on_failed_save", false)):
			return true
		if not String(spell_data.get("projectile_style", "")).is_empty():
			return true

		var multi_spec_value: Variant = spell_data.get("map_effect_spec", {})
		if multi_spec_value is Dictionary:
			var multi_effect_value: Variant = (
				multi_spec_value as Dictionary
			).get("effect", {})
			if multi_effect_value is Dictionary:
				var multi_geometry_value: Variant = (
					multi_effect_value as Dictionary
				).get("geometry", {})
				if (
					multi_geometry_value is Dictionary
					and not (multi_geometry_value as Dictionary).is_empty()
				):
					return true

	return false


static func is_runtime_usable(spell_data: Dictionary) -> bool:
	return _is_runtime_usable(spell_data)


static func catalog_spell(spell_id: String) -> Dictionary:
	var value: Variant = SPELLS.get(spell_id, {})
	if value is Dictionary:
		var manual_result: Dictionary = (value as Dictionary).duplicate(true)
		var generated_value: Variant = GeneratedCatalog.SPELLS.get(
			spell_id,
			{}
		)
		if generated_value is Dictionary:
			var generated_classes: Variant = (
				generated_value as Dictionary
			).get("classes", [])
			if generated_classes is Array:
				manual_result["classes"] = (
					generated_classes as Array
				).duplicate(true)
			for metadata_field: String in [
				"condition_inflict",
				"saving_throw",
				"misc_tags"
			]:
				var generated_metadata: Variant = (
					generated_value as Dictionary
				).get(metadata_field, [])
				if generated_metadata is Array:
					manual_result[metadata_field] = (
						generated_metadata as Array
					).duplicate(true)
		return _apply_runtime_overrides(manual_result)

	value = GeneratedCatalog.SPELLS.get(spell_id, {})
	if value is Dictionary:
		return _apply_runtime_overrides(value as Dictionary)
	return {}


static func spell(spell_id: String) -> Dictionary:
	var result: Dictionary = catalog_spell(spell_id)
	return result if _is_runtime_usable(result) else {}


static func all_spells() -> Array[Dictionary]:
	var merged: Dictionary = {}

	for spell_id: Variant in GeneratedCatalog.SPELLS.keys():
		var generated_value: Variant = GeneratedCatalog.SPELLS.get(
			spell_id,
			{}
		)
		if generated_value is Dictionary:
			merged[String(spell_id)] = (
				generated_value as Dictionary
			).duplicate(true)

	# Hand-authored spell definitions always win.
	for spell_id: Variant in SPELLS.keys():
		var value: Variant = SPELLS.get(spell_id, {})
		if value is Dictionary:
			var manual_copy: Dictionary = (
				value as Dictionary
			).duplicate(true)
			var generated_value: Variant = GeneratedCatalog.SPELLS.get(
				spell_id,
				{}
			)
			if generated_value is Dictionary:
				var generated_classes: Variant = (
					generated_value as Dictionary
				).get("classes", [])
				if generated_classes is Array:
					manual_copy["classes"] = (
						generated_classes as Array
					).duplicate(true)
			merged[String(spell_id)] = manual_copy

	var result: Array[Dictionary] = []
	for value: Variant in merged.values():
		if value is Dictionary:
			result.append(
				_apply_runtime_overrides(value as Dictionary)
			)

	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("name", "")).naturalnocasecmp_to(
				String(b.get("name", ""))
			) < 0
	)
	return result


static func canonical_class_name(class_label: String) -> String:
	return String(CLASS_CANONICAL_NAMES.get(class_label, class_label))


static func class_display_name(class_label: String) -> String:
	var canonical: String = canonical_class_name(class_label)
	return String(CLASS_DISPLAY_NAMES.get(canonical, canonical))


static func class_names() -> Array[String]:
	var found: Dictionary = {}
	for value: Variant in GeneratedCatalog.SPELLS.values():
		if not value is Dictionary:
			continue
		var entry: Dictionary = value as Dictionary
		var classes_value: Variant = entry.get("classes", [])
		if not classes_value is Array:
			continue
		for class_value: Variant in (classes_value as Array):
			var class_label: String = canonical_class_name(
				String(class_value).strip_edges()
			)
			if not class_label.is_empty():
				found[class_label] = true

	var result: Array[String] = []
	for class_value: Variant in found.keys():
		result.append(String(class_value))
	result.sort_custom(
		func(a: String, b: String) -> bool:
			return class_display_name(a).naturalnocasecmp_to(
				class_display_name(b)
			) < 0
	)
	return result


static func spells_for_class_and_level(
	class_label: String,
	level: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in all_spells():
		var classes_value: Variant = entry.get("classes", [])
		if not classes_value is Array:
			continue
		var matches_class: bool = false
		for class_value: Variant in (classes_value as Array):
			if canonical_class_name(String(class_value)) == class_label:
				matches_class = true
				break
		if matches_class and int(entry.get("level", -1)) == level:
			result.append(entry)
	return result
