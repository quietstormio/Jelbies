> **Feature lock (2026-10-25):** Jelbies 1.0 is the first release; no new features, fixes and polish only. See [RELEASE-1.0.md](RELEASE-1.0.md).

# Blob Species

## Species signature rule (user decision, 2026-10-26)

Signature features belong to a colour **species**, not to individual characters. A signature **never appears on another colour**.

| Species (colour) | Signature |
|---|---|
| Purple / lavender (incl. park plum) | Wings (fold under worn items, flap-hops, short flights) |
| Yellow | Pointed body-mesh tail plus 7 rounded orange spikes down the back onto the tail, none on the head (Pip's approved "pro8"; hidden under enclosing hats). Enum case `JellyFeature.spines`. |
| Green (incl. park mint, lime) | Head daisy, sits on the hat band under hats |
| Blue and every other colour | None |

Code: starters in `JellyRoster.feature`; park visitors, guests and volleyball opponents derive it from colour via `ParkColour.speciesFeature` (Park/ParkModels.swift).

## Species names and lore (2026-10-26)

World: Jelbies are baby jellies from Wobble Isle, the little floating island in the sky. Every morning, dewdrops gather in the Jelly Spring at the middle of the island, and when a drop catches the sound of someone laughing, it wobbles awake as a Jelbie. Jelbies never grow up, which is why they need someone to look after them. Each one takes after the first colour of sky it ever saw.

Shown in the species picker (`BobV1/Start/AdoptionCenter.swift`, content in `BobV1/Start/SpeciesInfo.swift`), in the order blue, yellow, purple, green. The default name is the character's name (Bob / Pip / Lavender / Moss); the player can change it when adopting. Signature features follow the rule above.

| Species | Colour (character) | Epithet | Signature | Best at | Loves |
|---|---|---|---|---|---|
| **Blueberry** | Blue (0, default name Bob) | The unbothered one | Side-eye (no body feature) | Cool | Sushi roll |
| **Lemon Drop** | Yellow (1, Pip) | The sunny one | Tail wag (pointed tail + orange spikes) | Sporty | Donut |
| **Taro** | Purple (3, Lavender) | The dreamy one | Little wings | Sparkly | Bedtime cookie |
| **Matcha** | Green (2, Moss) | The sleepy one | Head daisy | Sweet | Onigiri |

- **Blueberry:** "Cool as a cucumber. Acts like they don't care, then follows you everywhere." Lore: Woke up in a rain puddle at dusk, under a blue-grey sky. Blueberries take life slow and steady. Nothing rattles them, but they always sit a little closer to their favourite person. Starting jars: Cute 50, Sweet 45, Sparkly 30, Cool 85, Sporty 55.
- **Lemon Drop:** "Sunshine on legs. First one up, last one to nap, and it wags that spiky tail at everyone." Lore: Woke up inside a sunbeam. The little orange spikes down its back are sun-sparks that cooled off and went soft. Lemon Drops can't sit still: zooming, bouncing and chasing are their love language. Jars: Cute 58, Sweet 60, Sparkly 46, Cool 28, Sporty 85.
- **Taro:** "Head in the clouds, and nearly the rest of it too. Flaps, floats, dances and nuzzles." Lore: Woke up in the very last drop of twilight, just as the first stars came out. That's why Taros can almost fly: their little wings lift them for a moment or two, and they always land smiling. Jars: Cute 70, Sweet 55, Sparkly 84, Cool 40, Sporty 45.
- **Matcha:** "Calm and cosy. Loves a long sit, a big stretch and a look out the window. Never far from a nap." Lore: Woke up under a tea bush in the shade. A daisy seed landed on its head that very morning and simply never left. Matchas say the daisy tells them when it's nap time. It is always nap time. Jars: Cute 62, Sweet 82, Sparkly 40, Cool 50, Sporty 30.

**Naming (2026-10-16, updated 2026-10-20):** the app is called **Jelbies**, and that is the species name: Jelbies are "baby jellies". There is one size and no growth stages. "Blob" in these docs and the code is the old working name.

**2026-10-20: one size, called Jelbies; no growth stages.**

Every species has one **signature silhouette feature**, so you can tell it apart even as a shadow. Each individual Blob in the kennel varies that feature (size, count, curl, etc.) along with shade, size, marking and personality.

**Every Blob shares one LOCKED base body.** See [BaseBody.md](BaseBody.md). Breeds only add a feature and colour on top of it.

**Colour note (2026-10-16):** the game's Bob is now **Baby blue** (existing palette) instead of blush pink, because pink read too close to Kirby. Starter colours are blue, yellow, green and purple; green and purple are still to be added as new pastel palettes. The species colours in the table below are the older kennel concept and are not what the game renders.

## The Jelbies in the game (2026-10-21)

Four characters exist, all on Bob's locked body (`JellyRoster`): **Bob** (baby blue, no feature), **Pip** (yellow, gummy spines), **Moss** (green, head daisy), **Lavender** (pastel lavender, wings + flap-hop). At most **three** live in the room at once (`JellyRoster.maxCount = 3`). The room is a *roster*: an ordered list of characters saved under `BlobRoster.v1`; everything in the game indexes by slot (0...2) and asks the roster which character sits there. Saved needs / dirt / words / stats / perks stay with the character (Bob on the legacy keys, the others on `.jelly<id>` keys), so a Jelbie can leave and return without losing anything.

- A fresh install starts with **Bob, Pip and Moss** (the roster before the characters round), with their features attached.
- Developer launch argument `-SetRoster pip,moss,lavender` replaces the saved roster with exactly those (in that order), keeping each one's saved data and initialising a newcomer fresh; it persists and is idempotent, so it is safe to leave in or drop. `-BlobCount 1|2|3` still cuts the roster for captures.

## Adoption (planned, not built)

How the roster is meant to fill once there is a start-of-game flow. Nothing of this exists in code yet; the roster machinery above is what it will drive.

- **Max 3 at a time.** The room, the dining places, the race lanes and the widget are all sized for three.
- **New players start with only Bob (blue).** Pip, Moss and Lavender are met in the game (rivals on the Jelly Circuit, entrants in the Jelly Show) before they can be adopted.
- **Earn Drops in competitions to adopt Pip, Moss and Lavender.** Drops are earn-only (no purchase). Adoption is bought like a trick page, from the store or an "Adopt" card on the roster.
- **Suggested prices: 120 / 180 / 240 Drops** for the first, second and third adoption (a range of roughly 120–250). Rationale: a race pays 12–22 for first place and the show is designed to pay the same, so 120 is about 6–8 wins (a couple of sessions), well above the dearest trick page (55) and the biggest decor piece (90), so a new Jelbie feels like the biggest thing you can earn without becoming a grind. Escalating prices let the roster fill over weeks rather than one evening and keep the third adoption as a long-term goal. The order is the player's choice; Lavender need not be last.
- When the third Jelbie is adopted the room is full; swapping or re-homing is out of scope for now (one roster, no outings).

## Shipping in v1

| Species | Colour | Signature feature | Per-individual variation |
|---|---|---|---|
| **Berry** | Pastel berry-pink (#F2B6CC) | None (the classic Blob) | Shade, marking, size, personality |
| **Mint** | Pastel mint (#BDEBDD) | Soft gummy spikes down the centre of the head and back | Spike size (0.8–1.25×), 5–7 spikes, spacing |
| **Honey** | Pastel honey/butter (#FBE0A0) | Springy curly antenna with a round bobble on top | Length/bobble size, 1–2 antennae, curl direction/tightness |

All Blobs use pastel colours in the matte soft-vinyl finish; no neon/saturated jelly (user, 2026-10-14).

Shared markings: none, spot on head, star on head, heart on cheek, freckles, spot on back, white belly.

## Future species (backlog)

| Species | Colour | Signature feature | Variation ideas |
|---|---|---|---|
| Cocoa | Brown | Small rounded bear ears | Ear size, one floppy ear |
| Lemon | Yellow | Seedling leaf sprout on top | 1–3 leaves, leaf size |
| Grape | Purple | Cluster of little jelly bubbles on the head | Bubble count and size |
| Sky | Pale blue | Cloud-puff tail | Puff size |
| Peach | Orange-pink | Soft dimple crease down the middle | Crease depth, fuzzy freckles |
| Lime | Green | Frog-style mouth line and bumpy cheeks | Cheek size |
| Cotton | White | Floppy bunny ears | Length, one up / one down |
| Plum | Deep purple | Tiny bat wings that flap on hops | Wing size |
| Mango | Orange | Pointy mohawk fin | Fin height |
| Bubblegum | Light pink | Blows a bubble when happy | Bubble size |
| Ember | Red-orange | Little flame flicker on the head | Flame height |
| Frost | Icy, extra see-through | Crystal shards on the back | Shard count |

Favourites for the next batch: **Cocoa, Grape, Cotton**.

## Special editions (in-app purchase, later)

Premium variants with special materials, sold separately from the normal kennel. Ideas:

- **Glitter**: suspended sparkle flakes inside the jelly that catch the light.
- (More to be decided: e.g. holographic/iridescent, glow-in-the-dark, galaxy swirl.)

Not in v1. When built, a special edition should be a material/finish layered on an existing species (e.g. Glitter Berry), not a new body.

## 1.0 updates (2026-10-25)
- **Pip:** spikes are smaller by default (60% height). Enclosing hats go over them and cover them; perch items show them. Signature (approved, "pro8"): a pointed body-mesh tail plus 7 rounded orange spikes down the back flowing onto the tail, none on the head; enclosing hats cover the spikes. (Enum case `JellyFeature.spines`.)
- **Moss:** the daisy sits on the hat band when a hat is worn.
- **Lavender:** wings fold rather than vanish under worn items, with periodic flap bursts and short flights.
- Features are never hidden outright by wearables.
