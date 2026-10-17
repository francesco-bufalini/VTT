#!/usr/bin/env python3
"""Normalize the user-supplied 5etools action cache; no runtime prose inference.

python scripts/generate_combat_actions.py --data-root .5etools-cache
Names/IDs and typed mechanics are curated; displayed rule text comes from source
entries. Variant catalogue contains reference metadata, not copied book chapters.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
NAMES = {
 "Activate an Item": ("activate_item", "Attivare un oggetto magico"),
 "Attack": ("attack", "Attaccare"), "Dash": ("dash", "Scattare"),
 "Disengage": ("disengage", "Disimpegnarsi"), "Dodge": ("dodge", "Schivare"),
 "Help": ("help", "Aiutare"), "Hide": ("hide", "Nascondersi"),
 "Ready": ("ready", "Preparare"), "Search": ("search", "Cercare"),
 "Use an Object": ("use_object", "Usare un oggetto"), "Utilize": ("utilize", "Utilizzare"),
 "Grapple": ("grapple", "Afferrare una creatura"), "Shove": ("shove", "Spingere"),
 "Shove Aside": ("shove_aside", "Spingere lateralmente"), "Disarm": ("disarm", "Disarmare"),
 "Two-Weapon Fighting": ("two_weapon", "Combattere con due armi"),
 "Climb onto a Bigger Creature": ("climb_large", "Arrampicarsi su una creatura più grande"),
 "Overrun": ("overrun", "Travolgere"), "Tumble": ("tumble", "Passare con acrobazia"),
 "Mark": ("mark", "Marcare un avversario"), "Healing Surge": ("healing_surge", "Impulso curativo"),
 "Escape a Grapple": ("escape_grapple", "Sfuggire a una lotta"),
 "Don or Doff a Shield": ("shield", "Indossare o rimuovere uno scudo"),
 "Stabilize a Creature": ("stabilize", "Stabilizzare una creatura"),
 "End Concentration": ("end_concentration", "Interrompere concentrazione"),
 "Opportunity Attack": ("opportunity", "Attacco di opportunità"),
 "Improvising an Action": ("improvise", "Improvvisare un'azione"),
 "Other Activity": ("other_activity", "Interagire e comunicare"),
 "Identify a Spell": ("identify_spell", "Identificare un incantesimo"),
 "Waking Someone": ("wake", "Svegliare qualcuno"),
 "Influence": ("influence", "Influenzare"), "Study": ("study", "Studiare")
}
SKILLS = {"hide": ["stealth"], "search": ["perception", "investigation"],
 "grapple": ["athletics"], "shove": ["athletics"], "prone": ["athletics"],
 "shove_aside": ["athletics"], "escape_grapple": ["athletics", "acrobatics"],
 "climb_large": ["athletics", "acrobatics"], "overrun": ["athletics"],
 "tumble": ["acrobatics"], "stabilize": ["medicine"], "identify_spell": ["arcana"]}
ATTACKS = {"grapple", "shove", "prone", "disarm", "shove_aside"}
ORDER = ["attack", "dash", "disengage", "dodge", "help", "hide", "ready", "search",
 "use_object", "utilize", "improvise"]

def slug(name):
 return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")

def plain(value):
 if isinstance(value, str):
  # Explicit display text in tagged references is field three, otherwise name.
  while "{@" in value:
   new = re.sub(r"\{@[^ {}]+ ([^{}]+)\}", lambda m: m[1].split("|")[0], value)
   if new == value: break
   value = new
  return value
 if isinstance(value, list): return "\n\n".join(filter(None, (plain(v) for v in value)))
 if isinstance(value, dict):
  title = value.get("name", "")
  body = plain(value.get("entries", value.get("entry", value.get("items", ""))))
  return (title + ":\n" if title else "") + body
 return ""

def link(kind, name, source):
 return "https://5e.tools/" + kind + ".html#" + quote(name.lower(), safe="") + "_" + source.lower()

def generate(data_root):
 actions = json.loads((data_root / "actions.json").read_text(encoding="utf-8"))["action"]
 variants = json.loads((data_root / "variantrules.json").read_text(encoding="utf-8"))["variantrule"]
 output = []
 for raw in actions:
  if raw["name"] not in NAMES: continue
  if raw["source"] not in ("PHB", "DMG", "XGE", "XPHB"): continue
  key, title = NAMES[raw["name"]]
  times = [v.get("unit", "action") if isinstance(v, dict) else "free" if v == "Free" else "action" for v in raw.get("time", ["Free"])]
  if key == "other_activity": times = ["free"]
  variant = key if raw.get("fromVariant") and raw["source"] == "DMG" else "spellcasting_xge" if raw.get("fromVariant") and raw["source"] == "XGE" else ""
  if key == "healing_surge": variant = "healing_surges_dmg"
  elif variant: variant = variant + "_dmg" if raw["source"] == "DMG" else variant
  row = dict(id=key, name=title, source_name=raw["name"], source=raw["source"], page=raw.get("page", 0),
   edition="2024" if raw["source"] == "XPHB" else "2014", timings=times,
   description=plain(raw.get("entries", [])), source_url=link("actions", raw["name"], raw["source"]),
   variant_id=variant, skills=SKILLS.get(key, []), parent_action="attack" if key in ATTACKS else "",
   action_id=key if key in ("help", "shove", "grapple") else "")
  # A shove has two outcomes with the same rule text and distinct stable effects.
  output.append(row)
  if key == "shove":
   output.append(dict(row, id="prone", name="Mandare prono", action_id="prone", skills=["athletics"]))
 # Movement is a turn resource, not an extra action. These PHB excerpts are
 # independently verified against the official 2014 Basic Rules, Combat.
 for edition, source in [("2014", "PHB"), ("2024", "XPHB")]:
  if edition == "2014":
   output.append(dict(id="movement", name="Muoversi", source_name="Movement and Position", source=source, page=190, edition=edition, timings=["movement"], description="On your turn, you can move a distance up to your speed.", source_url="https://www.dndbeyond.com/sources/dnd/basic-rules-2014/combat#MovementandPosition", variant_id="", skills=[], parent_action="", action_id=""))
   output.append(dict(id="drop_prone", name="Gettarsi a terra", source_name="Being Prone", source=source, page=190, edition=edition, timings=["free"], description="You can drop prone without using any of your speed.", source_url="https://www.dndbeyond.com/sources/dnd/basic-rules-2014/combat#BeingProne", variant_id="", skills=[], parent_action="", action_id=""))
 speed = next(x for x in variants if x["source"] == "XPHB" and x["name"] == "Speed")
 output.append(dict(id="movement", name="Muoversi", source_name="Speed", source="XPHB", page=speed["page"], edition="2024", timings=["movement"], description=plain(speed["entries"]), source_url=link("variantrules", "Speed", "XPHB"), variant_id="", skills=[], parent_action="", action_id=""))
 strike = next(x for x in variants if x["source"] == "XPHB" and x["name"] == "Unarmed Strike")
 for key, title in [("grapple", "Afferrare una creatura"), ("shove", "Spingere"), ("prone", "Mandare prono")]:
  output.append(dict(id=key, name=title, source_name="Unarmed Strike", source="XPHB", page=strike["page"], edition="2024", timings=["action"], description=plain(strike["entries"]), source_url=link("variantrules", "Unarmed Strike", "XPHB"), variant_id="", skills=[], parent_action="attack", action_id=key))
 variant_rows = []
 for raw in variants:
  if raw["source"] not in ("DMG", "PHB", "XGE") or not raw.get("ruleType"): continue
  # Action Options can explicitly be enabled individually (DMG p. 271).
  if raw["name"] == "Action Options":
   for action in output:
    if action["source"] == "DMG" and action["variant_id"] and action["id"] != "healing_surge":
     variant_rows.append(dict(id=action["variant_id"], name=action["name"], source="DMG", page=action["page"], category="Opzioni di azione", source_url=action["source_url"], affects_actions=True))
   continue
  variant_rows.append(dict(id=slug(raw["name"]) + "_" + raw["source"].lower(), name=raw["name"],
   source=raw["source"], page=raw.get("page", 0), category="Varianti 2014", source_url=link("variantrules", raw["name"], raw["source"]), affects_actions=raw["name"] == "Spellcasting"))
 healing = next(x for x in variants if x["source"] == "DMG" and x["name"] == "Healing")
 for child in healing["entries"]:
  if isinstance(child, dict) and child.get("name"):
   variant_rows.append(dict(id=slug(child["name"]) + "_dmg", name=child["name"], source="DMG", page=266,
    category="Guarigione", source_url=link("variantrules", "Healing", "DMG"), affects_actions=child["name"] == "Healing Surges"))
 variant_rows.append(dict(id="healing_surges_bonus_dmg", name="Healing Surges · azione bonus", source="DMG", page=266,
  category="Guarigione", source_url=link("variantrules", "Healing", "DMG"), affects_actions=True))
 output.sort(key=lambda r: (r["edition"], ORDER.index(r["id"]) if r["id"] in ORDER else 99, r["name"]))
 # Provenance is deterministic: rerunning unchanged inputs yields identical bytes.
 return dict(version=1, upstream="https://5e.tools/data/actions.json", source_sha256={n:hashlib.sha256((data_root / (n+'.json')).read_bytes()).hexdigest() for n in ("actions", "variantrules")},
  description="Generated source-native rule descriptions; translated titles and structured action grouping only. Variants are opt-in. No source text is synthesized at runtime.",
  actions=output, variants=sorted(variant_rows, key=lambda r:(r["category"],r["name"])))

if __name__ == "__main__":
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument("--data-root", type=Path, default=ROOT / ".5etools-cache")
 args=parser.parse_args()
 result=generate(args.data_root)
 path=ROOT / "vtt/data/combat_actions_5etools.json"
 path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
 print(f"Generated {len(result['actions'])} actions and {len(result['variants'])} variant choices")
