#!/usr/bin/env python3
"""Export Ore from a Fight Club backup as a portable VTT creature.
Reads only the named character; never modifies the backup or live archives.
Unknown/custom equipment keeps its original description and numeric fields.
"""
import argparse
import copy
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ABILITIES = ["str", "dex", "con", "int", "wis", "cha"]
SKILLS = ["acrobatics", "animal handling", "arcana", "athletics", "deception", "history", "insight", "intimidation", "investigation", "medicine", "nature", "perception", "performance", "persuasion", "religion", "sleight of hand", "stealth", "survival"]

def integer(node, path, default=0):
    return int(float(node.findtext(path, str(default))))

def paragraphs(nodes):
    return "\n\n".join(n.findtext("name", "") + "\n" + n.findtext("text", "") for n in nodes)

def build(backup):
    root = ET.parse(backup).getroot()
    matches = [c for c in root.findall("character") if c.findtext("name", "").strip().lower().startswith("ore ")]
    if len(matches) != 1:
        raise ValueError("Expected exactly one Ore character")
    c = matches[0]
    if c.findtext("race/name") != "Dwarf, Mountain" or c.findtext("class/name") != "Artificer":
        raise ValueError("This reviewed mapping is specific to Ore's Mountain Dwarf Artificer")
    catalog = json.loads((ROOT / "vtt/data/player_5etools_catalog.json").read_text(encoding="utf-8"))
    infusions = json.loads((ROOT / "vtt/data/artificer_infusions_5etools.json").read_text(encoding="utf-8"))["infusions"]
    spell_text = (ROOT / "vtt/spells/spell_catalog_5etools.gd").read_text(encoding="utf-8")
    spells = json.JSONDecoder().raw_decode(spell_text[spell_text.index("{", spell_text.index("const SPELLS")):])[0]
    legacy_text = (ROOT / "vtt/spells/spell_catalog_phb_2014.gd").read_text(encoding="utf-8")
    spells.update(json.JSONDecoder().raw_decode(legacy_text[legacy_text.index("{", legacy_text.index("const SPELLS")):])[0])
    spell_by_name = {}
    for s in spells.values():
        if s.get("source") != "XPHB":
            spell_by_name.setdefault(s["name"].casefold(), s)
    level = integer(c, "class/level", 1)
    record = dict(id="fightclub:character:" + c.findtext("uid"), kind="character", name=c.findtext("name").strip(),
        rules_version="2014", level=level, xp=integer(c,"xp"), **{"class":"Artificer"}, class_source="TCE", subclass="Armorer", subclass_source="TCE",
        classes=[dict(name="Artificer",source="TCE",level=level,subclass="Armorer",subclass_source="TCE")],
        species="Dwarf", species_source="PHB", subrace="Mountain", subrace_source="PHB", background="Clan Crafter", background_source="SCAG",
        size_name="Medium", footprint=1.0, max_hp_base=integer(c,"hpMax"), current_hp=integer(c,"hpCurrent"),
        inspiration=bool(integer(c,"inspiration")), abilities=dict(zip(ABILITIES,[int(v) for v in c.findtext("abilities").strip(",").split(",")])),
        speed_base=25, speed=25, armor_class_base=10, armor_natural_formula="10 + dex_mod", darkvision=60,
        spellcasting_class="Artificer",spellcasting_ability="int",spell_slots_automatic=True,
        attack_ability="int",artificer_armor_model="infiltrator", feats_catalog=[],optional_features_catalog=[],inventory=[],
        resource_tracker_spent={},resource_trackers=[],spellbook_spells=[],prepared_spells=[],spells=[],
        skill_proficiencies=[],skill_expertise=[],saving_throw_proficiencies=["con","int"],
        languages="Common, Dwarvish, Undercommon", tool_proficiencies="Tattooist; Mason; Thieves; Tinker; Alchemist; Smith",
        class_features=paragraphs(c.findall("class/feat")),racial_background_traits=paragraphs(c.findall("race/feat")+c.findall("background/feat")),
        additional_traits=paragraphs(c.findall("note")), equipment=paragraphs(c.findall(".//item")),attacks=paragraphs(c.findall("attack")))
    # Raw Fight Club scores exclude its mod nodes. Apply ASIs here, while
    # species and the selected Skill Expert ability stay live VTT grants.
    for m in c.findall("class/mod"):
        if integer(m,"category")==1:
            record["abilities"][ABILITIES[integer(m,"type")]] += integer(m,"value")
    for f in c.findall("feat"):
        if f.findtext("name", "").startswith("Skill Expert"):
            feat = copy.deepcopy(next(f for f in catalog["feats"] if f["name"]=="Skill Expert" and f["source"]=="TCE"))
            feat["ability_choice"]="int"; record["feats_catalog"].append(feat)
            for m in f.findall("mod"):
                if integer(m,"category")==4 and integer(m,"type") in range(18):
                    record["skill_expertise"].append(SKILLS[integer(m,"type")])
    for node in [c.find("class"),c.find("background"),*c.findall("feat")]:
        for prof in node.findall("proficiency"):
            code=int(prof.text)
            if 100<=code<118 and SKILLS[code-100] not in record["skill_proficiencies"]:
                record["skill_proficiencies"].append(SKILLS[code-100])
    for field in ["age","height","weight","eyes","skin","hair"]:
        record[field]=c.findtext("race/"+field,"")
    for field, target in [("personality","personality_traits"),("ideals","ideals"),("bonds","bonds"),("flaws","flaws"),("align","alignment")]:
        record[target]=c.findtext("background/"+field,"")
    unresolved=[]
    for xml_spell in c.findall("class/spell"):
        name=xml_spell.findtext("name","").strip().rstrip("*")
        spell=spell_by_name.get(name.casefold())
        if not spell:
            unresolved.append(name);continue
        sid=spell["id"];record["spellbook_spells"].append(sid)
        if integer(xml_spell,"prepared") or integer(xml_spell,"level")==0:
            record["prepared_spells"].append(sid);record["spells"].append(sid)
    if unresolved: raise ValueError("Unresolved spells: " + str(unresolved))
    totals=[int(v) for v in c.findtext("slots").strip(",").split(",")]
    current=[int(v) for v in c.findtext("slotsCurrent").strip(",").split(",")]
    record["spell_slots_total"]=totals; record["spell_slots_spent"]=[max(0,a-b) for a,b in zip(totals,current)]
    for x in c.findall("race/spell"):
        name=x.findtext("name","")
        option=next((r for r in infusions if r.get("fightclub_name","").casefold()==name.casefold()),None)
        if not option and name.startswith("Infusion: Wand Of Secrets"):
            option=next(r for r in infusions if r["name"]=="Replicate Magic Item")
            option={**option,"plan_item_name":"Wand of Secrets"}
        if not option: raise ValueError("Unresolved infusion: "+name)
        record["optional_features_catalog"].append({k:option[k] for k in ["id","name","source","plan_item_name"] if k in option})
    categories=["magic_items","armor","weapons","tools","mundane_items"]
    record["coins"]={k:0 for k in ["cp","sp","ep","gp","pp"]}
    containers={id(item):container.findtext("name", "") for container in c.findall("container") for item in container.findall("item")}
    for index, item in enumerate(c.findall(".//item")):
        coin={"Gold (gp)":"gp","Electrum (ep)":"ep","Silver (sp)":"sp","Copper (cp)":"cp","Platinum (pp)":"pp"}.get(item.findtext("name", ""))
        if coin:
            record["coins"][coin]+=integer(item,"quantity",1)
            continue
        name=item.findtext("name","").strip(); found=None
        for cat in categories:
            found=next((v for v in catalog[cat] if v["name"].casefold()==name.casefold() and v.get("source") not in ["XPHB","XDMG"]),None)
            if found: break
        owned=copy.deepcopy(found) if found else dict(id="fightclub:item:"+str(index),name=name)
        owned.update(quantity=integer(item,"quantity",1),equipped_slots=[],equipped=False,active=True,attuned=False,entries=[item.findtext("text","")])
        if id(item) in containers:
            owned["entries"].insert(0,"Contenitore originale: " + containers[id(item)])
        code=integer(item,"type",-1); ac=integer(item,"ac",-1); slot=integer(item,"slot")
        if ac>=0 and code in [1,2,3,4]:
            owned.update(type={1:"LA",2:"MA",3:"HA",4:"S"}[code],ac=ac)
            if slot==5: owned["equipped_slots"]=["body"]
            elif slot in [3,4]: owned["equipped_slots"]=["off"]
        owned["equipped"]=bool(owned["equipped_slots"]) or slot==1
        if item.find("weight") is not None:owned["weight"]=float(item.findtext("weight"))
        if item.find("value") is not None:owned["value_gp"]=float(item.findtext("value"))
        for m in item.findall("mod"):
            if integer(m,"category")==0:
                field={7:"bonus_spell_attack",11:"bonus_ability_check",12:"bonus_saving_throw"}.get(integer(m,"type"))
                if field: owned[field]=integer(m,"value")
        # Fight Club has these items worn (slot 1); its attunement is implicit.
        if slot==1 and owned.get("req_attune"):
            owned["attuned"]=True
        if name=="Enanced Arcane Focus +1":
            owned.update(custom_item_type="magic",req_attune=True,attuned=True,equipped=True)
        record["inventory"].append(owned)
    for tracker in c.findall("tracker")+c.findall("class/tracker"):
        title=tracker.findtext("label",""); maximum=integer(tracker,"formula"); spent=max(0,maximum-integer(tracker,"value"))
        normalized={"Flash Of Genius":"Flash of Genius"}.get(title,title)
        if normalized in ["Flash of Genius","Defensive Field"]:
            tid="class:artificer:tce:"+normalized.lower().replace(" ","_")
        else:
            tid="fightclub:tracker:"+title.lower().replace(" ","_")
            record["resource_trackers"].append(dict(id=tid,name=title,max=maximum,recharge="long_rest"))
        record["resource_tracker_spent"][tid]=spent
    record["additional_traits"] += "\n\nFight Club money (gp): " + c.findtext("money", "0")
    companions=[]
    for index,m in enumerate(c.findall("monster")):
        stat=dict(name=m.findtext("name"),ac=[integer(m,"ac")],hp={"average":integer(m,"hpMax")},size=["T"],type=m.findtext("type"),speed={"walk":20,"fly":30} if m.findtext("name")=="Homunculus Servant" else {"walk":30})
        stat["alignment"]=[m.findtext("alignment", "unaligned")]
        for field in ["immune","resist","conditionImmune"]:
            if m.findtext(field):stat[field]=[v.strip() for v in m.findtext(field).split(",")]
        stat["languages"]=[m.findtext("languages", "")]
        stat["senses"]=[m.findtext("senses", "")]
        stat["passive"]=integer(m,"passive",10)
        stat["save"]={ABILITIES[integer(v,"ability")]:str(integer(v,"modifier")) for v in m.findall("savingThrow")}
        stat["skill"]={SKILLS[integer(v,"id")]:str(integer(v,"modifier")) for v in m.findall("skill")}
        stat.update(dict(zip(ABILITIES,[int(v) for v in m.findtext("abilities").strip(",").split(",")])))
        for section in ["trait","action","reaction"]:
            stat[section]=[{"name":n.findtext("name"),"entries":[n.findtext("text","")]} for n in m.findall(section)]
        companions.append(dict(format="vtt_creature_export_v1",version=1,creature=dict(id="fightclub:companion:"+str(index),kind="monster",name=m.findtext("label",m.findtext("name")),stat_block=stat,current_hp=integer(m,"hpCurrent"),max_hp=integer(m,"hpMax"),level=0)))
    return {"format":"vtt_creature_export_v1","version":1,"creature":record}, companions

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backup",type=Path);parser.add_argument("output",type=Path)
    args=parser.parse_args();payload,companions=build(args.backup)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding="utf-8")
    if companions:
        args.output.with_name(args.output.stem+"_companions.json").write_text(json.dumps(dict(format="vtt_creature_batch_export_v1",version=1,entries=companions),ensure_ascii=False,indent=2),encoding="utf-8")
    print("Exported",payload["creature"]["name"],len(payload["creature"]["inventory"]),"items;",len(companions),"companions")

if __name__ == "__main__":main()
