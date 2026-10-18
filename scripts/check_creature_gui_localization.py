#!/usr/bin/env python3
"""Audit Italian literals shown by creature-sheet controls.

This is deliberately scoped to UI display properties and constructors; item,
spell, feature and creature names are catalog/user data and are not translated.
Run from any working directory: python3 scripts/check_creature_gui_localization.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UI_SOURCES = (
    "vtt/creature_area.gd",
    "vtt/creature_spellcasting_tab.gd",
    "vtt/creature_spellcasting_view.gd",
    "vtt/creature_origin_spells_tab.gd",
    "vtt/creature_action_economy_tab.gd",
    "vtt/creature_inventory_tab.gd",
    "vtt/creature_bonus_tab.gd",
    "vtt/creature_proficiencies_tab.gd",
    "vtt/creature_trackers_tab.gd",
    "vtt/creature_traits_tab.gd",
    "vtt/creature_feats_tab.gd",
    "vtt/creature_damage_defenses_tab.gd",
    "vtt/creature_documents_tab.gd",
    "vtt/spell_selection_dialog.gd",
)
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
UI_EXPRESSION = re.compile(
    r"(?:\\.(?:text|placeholder_text|tooltip_text|title|dialog_text|"
    r"ok_button_text|cancel_button_text)\\s*=|"
    r"\\.(?:add_item|set_item_text|set_tab_title|set_text|set_tooltip)\\(|"
    r"\\b(?:_label|_column|_heading|_info_panel|_physics_field|"
    r"_add_sheet_tab|_add_stat_box|_set_status|show_message)\\(|"
    r"EditorUI\\.popup_form\\()"
)
ITALIAN_UI = re.compile(
    r"[àèéìòùÀÈÉÌÒÙ]|"
    r"\\b(?:Nessun|Nessuna|Mostra|Cerca|Scegli|Seleziona|Razza|Classe|"
    r"Sottorazza|Incantesimi|Salva|Cancella|Elimina|Aggiungi|Bonus|Usa|"
    r"Tiro|Attacco|Effetti|Lista|Scelta|Origine|Disponibili|Livello|"
    r"Azioni|Arma|Danno|Armi|Mano|Tratti|Attiva|Tutti|Risorse|Massimo|"
    r"Completa|Modifica|Caratteristiche|Competenze|Mancano|Prepara|"
    r"Altri|Altro|Disponibile|Lancia|Slot|Categoria|Punti|Dadi|Stato|"
    r"Scelta|Trucchetti|razza|talento|privilegi|incantesimo|miniatura)\\b",
    re.IGNORECASE,
)
INTERNAL = re.compile(
    r"^(?:res:|user:|https?:|[A-Za-z0-9_-]+\\.(?:gd|png|json|svg)|[a-z_]+)$"
)
NUMERIC = re.compile(r"^\\s*(?:[a-z0-9_.-]+|%\\d*[ds]|\\d+)\\s*$")


def decoded(quoted: str) -> str:
    try:
        return json.loads('"' + quoted + '"')
    except json.JSONDecodeError:
        return quoted


def localized_keys() -> set[str]:
    source = (ROOT / "vtt/creature_gui_locale.gd").read_text(encoding="utf-8")
    en = source.split("const EN: Dictionary = {", 1)[1].split("const IT: Dictionary", 1)[0]
    keys: set[str] = set()
    for line in en.splitlines():
        match = re.match(r'^\\s*("(?:[^"\\]|\\.)*")\\s*:', line)
        if match:
            keys.add(json.loads(match.group(1)))
    return keys


def main() -> int:
    translations = localized_keys()
    missing: list[str] = []
    audited = 0
    for path in UI_SOURCES:
        for lineno, line in enumerate((ROOT / path).read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("#") or not UI_EXPRESSION.search(line):
                continue
            for match in STRING.finditer(line):
                literal = decoded(match.group(0)[1:-1])
                if (
                    len(literal) < 3
                    or INTERNAL.fullmatch(literal)
                    or NUMERIC.fullmatch(literal)
                    or not ITALIAN_UI.search(literal)
                ):
                    continue
                audited += 1
                if literal not in translations:
                    missing.append(f"{path}:{lineno}: {literal!r}")
    if missing:
        print("Missing explicit English UI translations:")
        print("\\n".join(missing))
        return 1
    print(f"PASS: {audited} hardcoded creature GUI literals audited across {len(UI_SOURCES)} source files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
