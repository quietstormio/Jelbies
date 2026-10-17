# Base body (LOCKED)

> "Ensure the body I have on my phone now with this starting layout is LOCKED DOWN do not defer from this base ever again document that idk how you'll do that but this body is perfect this is the character it has to be consistent"
>
> (the user, 2026-10-14)

**Reference:** `reference/locked_body_phone.png` is the user's iPhone screenshot of the build that defines the body. It shows the Baby blue palette in the studio view.

**Source of that build:**
- commit `3499dc0` "Lock in base Blob body (round 6)";
- the pastel-colour change of 2026-10-14;
- the Release performance change of 2026-10-14.

## What is locked

This applies to every Blob, on every screen, in every future version. It changes only if the user explicitly asks for a change to the body.

- **Shape:**
  - the rounded egg body and its proportions (width ≈ 1.04 × height, depth ≈ 0.86 × height, rounded bottom);
  - the two teardrop arms: where they sit, their size, and how they grow smoothly out of the sides;
  - the two short, flat-soled stubby feet.
- **Face:**
  - two chocolate-brown bead eyes, with their size, spacing and height;
  - one short flat brow over each eye;
  - no mouth.
- **Rest pose:** how he stands when nothing is happening.
- **Material:** the matte soft-vinyl look with its fine crinkle texture. It is not glossy.
- **Colours:** the pastel palettes Blush, Pink, Butter and Baby blue, exactly as they are now.
  - **Game colour (2026-10-16):** the game now uses the existing **Baby blue** palette for Bob (`GameScreen.makeGameModel` sets `.blue`). The palettes themselves and the model default (`.blush`) are unchanged, so the lock tests and goldens are untouched. Reason (user): "pink is too close to Kirby".
  - **Starter colours:** blue, yellow, green and purple. Blue and yellow (Butter) already exist; green and purple are to be added later as new pastel options under the rule below (add new palettes, never edit the existing ones).
- **Feel:** 95% firmness and the same soft-body squish.
- **Feet change (2026-10-17):** 2026-10-17: foot shape (planted boot, lifted ball) and lower step lift changed on explicit user request; goldens re-recorded (BaseBodyDumpTests with `TEST_RUNNER_BOB_GOLDEN_DIR`, then `base_lock.json` blocks, full-res hashes and the half-res PNGs updated).

In code, the locked body is the `BobForm` constants and the rest shape (`Contracts.swift`), the rest sim mesh and render mesh built from them (`Geometry.swift`), the matte body shader (`Shaders.metal`), the palettes, and the firmness setting.

## What may change

- **Animations** may move and squish him for a moment (walk, wave, eat, drink, get thrown). Every animation must end with him back in exactly this rest shape.
- **Breeds** add a feature on top of this body, such as Mint's spikes, Honey's antenna or a marking. The body underneath stays the same.
- **Accessories** sit on top of the body.
- **New pastel colours** can be added. The existing ones don't change.
- **The mouth** appears only while he eats or drinks, then disappears completely.

## How it's enforced

1. **Tests:** `BaseBodyLockTests` (in `BobV1Tests`) fails with "BASE BODY CHANGED — see docs/BaseBody.md" if anything about the rest body changes. It checks:
   - hashes of the body constants, sim mesh, render mesh, eye rig, rest skinning, palettes and material defaults;
   - the body shader functions;
   - 20 reference renders made from the phone build (4 palettes × front, 3/4, both profiles, back), stored in `BobV1Tests/BaseBodyGolden/`;
   - that the hidden wave-arm capsules stay inside the body at rest.

   On 2026-10-14 the working tree matched the phone build exactly (20 of 20 renders pixel-identical).
2. **Code:** the body code carries a "LOCKED BASE BODY: see docs/BaseBody.md" banner.
3. **Process:** before any change that could affect the body, the lock tests must pass. If a feature would need a body change, stop and ask the user first.
