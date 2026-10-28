Wearable art pipeline (restored from the 2026-10 scratchpads, repo-relative).

    cd tools/make_wear4/work
    /Applications/Blender.app/Contents/MacOS/Blender -b -P build_all5.py -- [ids]     # items5 (face), items6 (new pieces), items7 (upgrades) -> ../art/export
    python3 add_catalog.py                                                            # registers new exports in ../art/wear_catalog.json
    cd ../../..; python3 tools/convert_wear_art.py tools/make_wear4/art BobV1/Wear     # writes wear_<id>.bin + WearGenerated.swift
    python3 tools/make_wear4/check_keepout.py                                         # mouth keep-out check of every export

art/export holds the Blender exports of every wearable; art/keep_bins.json lists bins that are kept byte for byte (the medal).
items.py / items2_* / items3 / items4 are the earlier batches (batch 3 = items4); build_all*.py rebuild them if needed.
