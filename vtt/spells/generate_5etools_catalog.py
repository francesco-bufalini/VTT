#!/usr/bin/env python3
"""Regenerate spell_catalog_5etools.gd from a complete 5etools-src checkout.

The generator reads every file referenced by data/spells/index.json and class
membership from data/generated/gendata-spell-source-lookup.json. Duplicate spell
names are collapsed, preferring XPHB and then PHB. Canonical English class names
are kept in generated data; spell_catalog.gd localizes them for the UI.

Usage:
    python vtt/spells/generate_5etools_catalog.py /path/to/5etools-src
"""
from __future__ import annotations
import json, re, sys, unicodedata
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "vtt" / "spells" / "spell_catalog_5etools.gd"
RUNTIME_MAP = ROOT / "assets" / "spell_area_geometry.json"
PRIORITY = ["XPHB","PHB","FRHoF","EFA","AU","TCE","XGE","FTD","SCC","EGW","BMT","AAG","AI","GGR","IDRotF","SatO","LLK","AitFR-AVT"]
SCHOOLS = {"A":"Abjuration","C":"Conjuration","D":"Divination","E":"Enchantment","V":"Evocation","I":"Illusion","N":"Necromancy","T":"Transmutation","P":"Psionic"}
META = {
    "id","name","source","level","school","casting_time","range","target",
    "area","components","duration","classes","description","higher_levels",
    "condition_inflict","saving_throw","misc_tags",
}
GENERATED_TARGET_FIELDS = {
    "target_mode",
    "projectile_style",
    "projectile_travel_seconds",
    "base_target_clicks",
    "target_clicks_per_slot_above_base",
    "allow_repeat_targets",
    "allow_point_target",
    "summon_count",
    "summon_count_min",
    "summon_count_max",
    "summon_count_options",
    "summon_count_per_slot_above_base",
    "summon_count_max_by_slot",
    "summon_count_multiplier_rules",
    "summon_requires_ground",
}

def slug(s: str) -> str:
    s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    return re.sub(r"^_+|_+$","",re.sub(r"[^a-z0-9]+","_",s.lower().replace("'","").replace("’","")))

def tags(x: Any) -> str:
    s=str(x or "")
    pat=re.compile(r"\{@[A-Za-z]+\s+([^{}]+)\}")
    for _ in range(8):
        n=pat.sub(lambda m: (m.group(1).split("|")[2] if len(m.group(1).split("|"))>=3 and m.group(1).split("|")[2] else m.group(1).split("|")[0]),s)
        if n==s: break
        s=n
    return re.sub(r"\s+"," ",re.sub(r"\{@[^{}]*\}","",s)).strip()

def flat(x: Any) -> str:
    if x is None:return ""
    if isinstance(x,(str,int,float)):return tags(x)
    if isinstance(x,list):return " ".join(filter(None,(flat(v) for v in x)))
    if isinstance(x,dict):
        p=([tags(x["name"])+":"] if x.get("name") else [])
        for k in ("entry","entries","items"):
            if k in x:p.append(flat(x[k]))
        for row in x.get("rows",[]):p.append(flat(row))
        return re.sub(r"\s+"," "," ".join(filter(None,p))).strip()
    return ""

def ftime(s):
    t=(s.get("time") or [None])[0]
    if not t:return ""
    unit={"bonus":"bonus action"}.get(str(t.get("unit","")),str(t.get("unit","")))
    out=f"{t.get('number',1)} {unit}"
    return out+(f" ({tags(t['condition'])})" if t.get("condition") else "")

def frange(s):
    r=s.get("range",{});d=r.get("distance",{});k=str(d.get("type",r.get("type","")))
    return {"self":"Self","touch":"Touch","sight":"Sight","unlimited":"Unlimited","special":"Special"}.get(k,(f"{d['amount']} {k}" if d.get("amount") is not None else ""))

def fcomp(s):
    c=s.get("components",{});o=[]
    if c.get("v"):o.append("V")
    if c.get("s"):o.append("S")
    if c.get("m"):
        m=c["m"];txt=m if isinstance(m,str) else m.get("text","material component")
        o.append(f"M ({tags(txt)})")
    if c.get("r"):o.append("R")
    return ", ".join(o)

def fdur(s):
    d=(s.get("duration") or [None])[0]
    if not d:return ""
    if d.get("type")=="instant":return "Instantaneous"
    if d.get("type")=="permanent":return "Until dispelled"
    if d.get("type")=="special":return "Special"
    p="Concentration, up to " if d.get("concentration") else ""
    t=d.get("duration",{})
    return f"{p}{t.get('amount','')} {t.get('type','')}".strip() if d.get("type")=="timed" else p+str(d.get("type",""))

def class_names(entry):
    out=set()
    for field in ("class","classVariant"):
        for group in entry.get(field,{}).values():
            if isinstance(group,dict):out.update(group.keys())
    return out

def runtime_map():
    if not RUNTIME_MAP.exists():return {}
    try:
        value=json.loads(RUNTIME_MAP.read_text(encoding="utf-8"))
        return value if isinstance(value,dict) else {}
    except Exception:
        return {}

def runtime_target_fields(spell_id: str, name: str, source: str, runtime: dict) -> dict:
    spec=runtime.get(f"{source}::{name}",{})
    if not isinstance(spec,dict):return {}
    targeting=spec.get("targeting",{})
    if not isinstance(targeting,dict) or not targeting.get("projectile"):return {}

    target_type=str(targeting.get("type",""))
    if target_type not in {"token","multi_token"}:return {}

    result={
        "target_mode": "token_then_token" if target_type=="token" else "token_then_multi_token",
        "projectile_style": spell_id,
        "projectile_travel_seconds": 0.65,
    }
    range_data=spec.get("range",{})
    if isinstance(range_data,dict) and isinstance(range_data.get("feet"),(int,float)):
        result["range_feet"]=range_data["feet"]

    for key in (
        "base_target_clicks",
        "target_clicks_per_slot_above_base",
        "allow_repeat_targets",
        "allow_point_target",
    ):
        if key in targeting:result[key]=targeting[key]
    return result

_NUMBER_WORDS = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    "eleven": 11, "twelve": 12,
}

def _number_value(value: str) -> int | None:
    normalized=str(value).strip().lower()
    if normalized.isdigit():return int(normalized)
    return _NUMBER_WORDS.get(normalized)

def _summon_count_scaling(spell: dict[str, Any]) -> int:
    higher=flat(spell.get("entriesHigherLevel",[])).lower()
    if not higher:return 0
    number=r"(a|an|one|two|three|four|five|six|seven|eight|nine|ten|\d+)"
    match=re.search(
        rf"\b(?:animate|conjure|summon|create)"
        rf"(?:\s+or\s+reassert\s+control\s+over)?\s+"
        rf"(?:up\s+to\s+)?{number}\s+additional\s+"
        rf"(?:corpses?|creatures?|familiars?|spirits?|demons?|objects?|undead)"
        rf"\b[^.]{0,120}\bfor\s+each\s+(?:spell\s+)?slot\s+level\s+above\b",
        higher,
    )
    if not match:return 0
    raw=match.group(1)
    if raw in {"a","an"}:return 1
    return _number_value(raw) or 0

def _summon_slot_maxima(spell: dict[str, Any]) -> dict[str, int]:
    higher=flat(spell.get("entriesHigherLevel",[])).lower()
    if not higher:return {}
    creature_number=r"(one|two|three|four|five|six|seven|eight|nine|ten|\d+)"
    creature_noun=(
        r"(?:ghouls?|ghasts?|wights?|mummies?|corpses?|creatures?|"
        r"familiars?|spirits?|demons?|objects?|undead)"
    )
    result={}
    for sentence in re.split(r"[.!?]",higher):
        slot_match=re.search(
            r"\blevel\s+(\d+)\s+spell\s+slot\b"
            r"|\b(\d+)(?:st|nd|rd|th)-level\s+spell\s+slot\b",
            sentence,
        )
        if not slot_match:continue
        slot=int(slot_match.group(1) or slot_match.group(2))
        counts=[]
        for count_match in re.finditer(
            rf"\b{creature_number}\s+{creature_noun}\b",
            sentence,
        ):
            parsed=_number_value(count_match.group(1))
            if parsed:counts.append(parsed)
        if counts:result[str(slot)]=max(counts)
    return result

def _summon_multiplier_rules(spell: dict[str, Any]) -> list[dict[str, int]]:
    higher=flat(spell.get("entriesHigherLevel",[])).lower()
    if not higher:return []
    multiplier_words={
        "twice":2,
        "three times":3,
        "four times":4,
    }
    rules=[]
    pattern=re.compile(
        r"\bspell\s+slot\s+of\s+(\d+)(?:st|nd|rd|th)"
        r"(?:\s+or\s+(\d+)(?:st|nd|rd|th))?\s+level\b"
        r"[^.]{0,140}\b(twice|three\s+times|four\s+times)\s+as\s+many\b"
    )
    for match in pattern.finditer(higher):
        first=int(match.group(1))
        second=int(match.group(2) or first)
        phrase=re.sub(r"\s+"," ",match.group(3))
        multiplier=multiplier_words.get(phrase,1)
        if multiplier>1:
            rules.append({
                "min_slot":min(first,second),
                "max_slot":max(first,second),
                "multiplier":multiplier,
            })
    return rules

def _summon_range_feet(spell: dict[str, Any]) -> float:
    r=spell.get("range",{})
    if not isinstance(r,dict):return 5.0
    d=r.get("distance",{})
    if not isinstance(d,dict):d={}
    dtype=str(d.get("type",r.get("type",""))).lower()
    amount=d.get("amount")
    if dtype=="feet" and isinstance(amount,(int,float)):
        return float(amount)
    if dtype in {"touch","self"}:
        return 5.0
    return 5.0

def summon_runtime_fields(spell: dict[str, Any], runtime: dict) -> dict:
    misc={str(v).strip() for v in spell.get("miscTags",[]) if str(v).strip()}
    if "SMN" not in misc:return {}

    source=str(spell.get("source",""))
    name=str(spell.get("name",""))
    spec=runtime.get(f"{source}::{name}",{})
    if isinstance(spec,dict):
        targeting=spec.get("targeting",{})
        # SMN is also used by 5eTools for conditional creation or
        # transformation spells. Existing explicit targeting wins.
        if isinstance(targeting,dict) and targeting:
            return {}

    text=flat(spell.get("entries",[])).lower()
    result={
        "target_mode":"summon",
        "range_feet":_summon_range_feet(spell),
        "summon_count":1,
    }
    per_slot=_summon_count_scaling(spell)
    if per_slot>0:
        result["summon_count_per_slot_above_base"]=per_slot
    slot_maxima=_summon_slot_maxima(spell)
    if slot_maxima:
        result["summon_count_max_by_slot"]=slot_maxima
    multiplier_rules=_summon_multiplier_rules(spell)
    if multiplier_rules:
        result["summon_count_multiplier_rules"]=multiplier_rules
    if re.search(
        r"\b(?:appears?|manifests?|springs(?:\s+into\s+existence)?)\b"
        r"[^.]{0,160}\bon\s+the\s+ground\b"
        r"|\bon\s+the\s+ground\b[^.]{0,100}"
        r"\b(?:appears?|manifests?)\b",
        text,
    ):
        result["summon_requires_ground"]=True

    number=r"(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d+)"
    up_to=re.search(
        rf"\bup to\s+{number}\s+(?:small\s+or\s+medium\s+)?"
        rf"(?:corpses?|creatures?|familiars?|spirits?|demons?|objects?)\b",
        text,
    )
    if up_to:
        prefix=text[max(0,up_to.start()-80):up_to.start()]
        maximum=_number_value(up_to.group(1))
        if (
            maximum
            and maximum>1
            and "reassert" not in prefix
            and "control over" not in prefix
        ):
            result.pop("summon_count",None)
            result["summon_count_min"]=1
            result["summon_count_max"]=maximum
            return result

    # Some legacy summon spells determine one of several possible group
    # sizes from a table (for example 2/4/8 lesser demons). The VTT asks for
    # the resolved group size rather than trying to roll the table itself.
    table_counts=[]
    for match in re.finditer(rf"\b{number}\s+challenge\s+rating",text):
        parsed=_number_value(match.group(1))
        if parsed and parsed not in table_counts:
            table_counts.append(parsed)
    if len(table_counts)>1:
        result.pop("summon_count",None)
        result["summon_count_options"]=sorted(table_counts)
        return result

    fixed_patterns=[
        rf"\b(?:temporarily\s+)?summon(?:ing)?\s+{number}\s+",
        rf"\bconjure\s+{number}\s+",
        rf"\bcall\s+forth\s+{number}\s+",
    ]
    for pattern in fixed_patterns:
        match=re.search(pattern,text)
        if match:
            parsed=_number_value(match.group(1))
            if parsed and parsed>0:
                result["summon_count"]=parsed
                break
    return result

def old_records():
    if not OUTPUT.exists():return {}
    text=OUTPUT.read_text(encoding="utf-8");mark="const SPELLS: Dictionary = "
    return json.loads(text.split(mark,1)[1].strip()) if mark in text else {}

def main():
    if len(sys.argv)!=2:raise SystemExit("Pass a complete 5etools-src checkout.")
    root=Path(sys.argv[1]).resolve();sd=root/"data"/"spells"
    index=json.loads((sd/"index.json").read_text(encoding="utf-8"))
    lookup=json.loads((root/"data"/"generated"/"gendata-spell-source-lookup.json").read_text(encoding="utf-8"))
    spells=[]
    for fn in index.values():spells.extend(json.loads((sd/fn).read_text(encoding="utf-8")).get("spell",[]))
    groups={}
    for s in spells:
        if s.get("name"):groups.setdefault(str(s["name"]).lower(),[]).append(s)
    old=old_records();runtime=runtime_map();out={}
    def score(src): return len(PRIORITY)-PRIORITY.index(src) if src in PRIORITY else 0
    for vs in groups.values():
        s=max(vs,key=lambda x:score(str(x.get("source",""))));sid=slug(str(s["name"]));classes=set()
        for v in vs:
            e=lookup.get(str(v.get("source","")).lower(),{}).get(str(v.get("name","")).lower(),{})
            classes.update(class_names(e))
        rec={
            "id":sid,
            "name":s["name"],
            "source":s.get("source",""),
            "level":int(s.get("level",0)),
            "school":SCHOOLS.get(str(s.get("school","")),str(s.get("school",""))),
            "casting_time":ftime(s),
            "range":frange(s),
            "target":"",
            "area":"",
            "components":fcomp(s),
            "duration":fdur(s),
            "classes":sorted(classes),
            "description":flat(s.get("entries",[])),
            "higher_levels":flat(s.get("entriesHigherLevel",[])),
            "condition_inflict":sorted({
                str(v).strip().lower()
                for v in s.get("conditionInflict",[])
                if str(v).strip()
            }),
            "saving_throw":sorted({
                str(v).strip().lower()
                for v in s.get("savingThrow",[])
                if str(v).strip()
            }),
            "misc_tags":sorted({
                str(v).strip()
                for v in s.get("miscTags",[])
                if str(v).strip()
            }),
        }
        for k,v in old.get(sid,{}).items():
            if k not in META and k not in GENERATED_TARGET_FIELDS:
                rec[k]=v
        rec.update(runtime_target_fields(
            sid,
            str(s.get("name","")),
            str(s.get("source","")),
            runtime,
        ))
        summon_fields=summon_runtime_fields(s,runtime)
        if summon_fields:
            rec.update(summon_fields)
        out[sid]=rec
    out=dict(sorted(out.items(),key=lambda kv:kv[1]["name"].lower()))
    OUTPUT.write_text("extends RefCounted\n\n# Generated from the complete 5eTools spell source index.\n# Canonical class names are localized by spell_catalog.gd.\nconst SPELLS: Dictionary = "+json.dumps(out,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"Wrote {len(out)} unique spells")
if __name__=="__main__":main()
