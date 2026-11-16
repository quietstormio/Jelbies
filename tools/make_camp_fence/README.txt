Jelmiko Camp yard props (step Y1 art): fence post, rail bay, gate post, tent. Blender headless, vertex colours + baked AO, no textures.
Same kit and .bin format as the park seesaw (tools/make_park_seesaw); loaded like park_<id>.bin via DecorMeshes.load(id, prefix: "park_").

Regenerate (from the repo root):
  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/make_camp_fence/build_fence.py
  python3 -I tools/make_camp_fence/convert_fence.py tools/make_camp_fence/export BobV1/Room/Resources
Previews (reads the converted .bin):
  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/make_camp_fence/render_fence.py -- BobV1/Room/Resources <out dir> [samples]

Files: BobV1/Room/Resources/park_camp_post.bin, park_camp_rail.bin, park_camp_gate_post.bin, park_camp_tent.bin (one part each: post, rail, gate_post, tent).
Game units, y up, +z toward the camera, origin on the ground at the footprint centre, drawn at scale 1 (no 1.4x).

Sizes
  post       0.20 wide (wood radius 0.085, cap radius 0.10), 0.608 high (wood 0.52, cream dome cap 0.494..0.608)   228 tris
  rail       ONE bay: 1.25 long along x (centre origin), two rails 0.075 high x 0.055 deep at y 0.17 and 0.35 (centres); for posts every 1.40
             (post wood 0.17 across: 1.40 - 0.17 = 1.23 gap, rails sunk 1 cm into each post). Another spacing s: scale x by (s - 0.15) / 1.25.   224 tris
  gate_post  0.20 wide (radius 0.10), 0.80 wood + cream ball radius 0.08, top 0.92   384 tris
  tent       1.63 wide (x), 1.17 deep (z, door faces +z), body 1.1 high, pole + pennant to 1.54   764 tris
Colours (sRGB hex): post wood #CC995C, rail #D6A363, cream cap / ball / tent stripes #EDE0C2, tent orange #DB7847, tent door #3D261F, pole #B88752, pennant #F594AD.
Tent: 7 stripes along the ridge, orange first and last (4 orange, 3 cream).

Yard use (plan 3.3: sides x +-4.2, back z -5.1, front z 5.9, gate at x 0.63 +- 0.95): about 28 bays -> ~27 posts + 2 gate posts + ~26 rail bays + 1 tent
  = 27*228 + 2*384 + 26*224 + 764 = ~13.6k triangles of static mesh (the seesaw alone is 1884). The preview yard (4.2 x 7.0, 3 x 5 bays) is 14 posts + 2 gate posts + 15 rails + tent = 8084.
