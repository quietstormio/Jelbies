# Jelbie shoes: Blender models bound to the foot bean

The nine shoes are modelled in Blender (headless) and bound to the foot bean, so they follow it exactly in every move (see `BobV1/Wear/ShoeArt.swift`).

1. Dump the bean (foot-local rest shape + the app's own vertex normals):
   `TEST_RUNNER_SHOE_DUMP_DIR=<dir> xcodebuild test ... -only-testing:BobV1Tests/ShoeDumpTests/testDumpFootBean` -> `tools/shoes/foot_bean.json`
2. Model: `/Applications/Blender.app/Contents/MacOS/Blender -b -P tools/shoes/model_shoes.py -- tools/shoes/foot_bean.json <json_out> [--preview <png_dir>] [--only name] [--counts]`
   (`shoekit.py` = the toolkit: sole slab, panels cut along iso-lines of the skin, ribbons, tubes, domes ...; `model_shoes.py` = the nine designs, keyed by `WearLook` raw value).
3. Bind + write the bins: `python3 -I tools/shoes/convert_shoe_art.py tools/shoes/foot_bean.json <json_out> BobV1/Wear/Resources`
   (`shoe_<look>.bin`; prints the binding error, <= 0.1 mm, and the largest offset from the foot).
Re-run 1 + 3 if the foot bean's shape ever changes (ShoeTests fail loudly if the art and the bean disagree).
