#!/usr/bin/env python3
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from creature_size_lookup import lookup_5etools_size

RECORDS = [
    {"name":"Giant Goat","source":"MM","edition":"2014","size_name":"Large","footprint":2},
    {"name":"Goblin","source":"MM","edition":"2014","size_name":"Small","footprint":1},
    {"name":"Adult Red Dragon","source":"MM","edition":"2014","size_name":"Huge","footprint":3},
    {"name":"Tarrasque","source":"MM","edition":"2014","size_name":"Gargantuan","footprint":4},
    {"name":"Goblin","source":"XMM","edition":"2024","size_name":"Small","footprint":1},
]


def expect(name, size_name, footprint):
    result = lookup_5etools_size(name, RECORDS)
    assert result is not None and not result.get("ambiguous"), (name, result)
    assert result["size_name"] == size_name, (name, result)
    assert result["footprint"] == footprint, (name, result)
    assert result["source"] == "MM", (name, result)


def main():
    expect("Giant Goat", "Large", 2)
    expect("Giant Goat Updated", "Large", 2)
    expect("Goblin.001", "Small", 1)
    expect("Adult Red Dragon Final", "Huge", 3)
    expect("Tarrasque", "Gargantuan", 4)
    assert lookup_5etools_size("Definitely Not A Creature", RECORDS) is None
    print("5eTools creature-size lookup tests: OK")


if __name__ == "__main__":
    main()
