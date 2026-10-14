# Blob Animations (from the reference video)

Reference: 10 s clip of the Blob (frames at 2 fps in `docs/reference/video_frames/`). Rubbery, cartoon-y limbs that stretch; soft-body jelly body squashes and sways.

| Animation | What happens in the reference |
|---|---|
| Idle / step in place | Lifts one foot forward, then the other, with a small side-to-side waddle of the body. |
| Turn around | Turns a full circle on the spot with small steps; arms stay tucked at the sides. |
| Point / stretch | Stretches one arm straight out sideways, the arm lengthening into a long tube. |
| Look around | Turns body/head a little to each side; eyes glance left and right; brows tilt a few degrees. |
| Content / sleepy eyes | Eyes close into soft arcs (happy, relaxed), brows lift slightly. |
| Walk | Side-on steps, alternating feet, body bobbing. |
| Wave | Raises one arm straight up above the head (stretches to roughly 0.6–0.7 × body height), body leans toward that side, then waves; eyes look up/sideways; ends with happy closed eyes, then back to neutral. |

Implementation notes: arms and feet need to be poseable (driven sim particles / attractor targets) while staying smooth rounded tubes blended into the body; eyes need gaze offset + openness (closed-arc) + brow rotation.
