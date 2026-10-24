// Bundled structured rule supplements: no runtime JSON fetch, no English-text scraping.
// The owners and prerequisites are checked against the creature's actual traits.
export const supplementalClassSpells=[
  {
    "class_name": "Artificer",
    "class_sources": [
      "TCE",
      "EFA"
    ],
    "subclass": "Armorer",
    "subclass_sources": [
      "TCE",
      "EFA"
    ],
    "feature_names": [
      "Armorer Spells",
      "Arcane Armor"
    ],
    "levels": [
      {
        "level": 3,
        "spells": [
          "magic missile",
          "thunderwave"
        ]
      },
      {
        "level": 5,
        "spells": [
          "mirror image",
          "shatter"
        ]
      },
      {
        "level": 9,
        "spells": [
          "hypnotic pattern",
          "lightning bolt"
        ]
      },
      {
        "level": 13,
        "spells": [
          "fire shield",
          "greater invisibility"
        ]
      },
      {
        "level": 17,
        "spells": [
          "passwall",
          "wall of force"
        ]
      }
    ]
  }
];
export const supplementalItemBonuses=[
  {
    "names": [
      "Stone of Good Luck",
      "Stone of Good Luck (Luckstone)",
      "Luckstone"
    ],
    "sources": [
      "DMG",
      "XDMG"
    ],
    "bonuses": {
      "ability_check": 1,
      "saving_throw": 1
    }
  }
];
