# Ash look mechanics

- Stable anchor: both talons, lower belly, and tail/wing base stay registered on one baseline; never spin or tilt the owl as a whole sprite.
- `000 up`: body remains frontal; the complete blue eye surfaces, pupils, eyelids, brow tufts, beak angle, and slight neck extension point toward the screen top.
- `090 screen-right`: head yaws toward viewer-right; beak and both pupils cross right of head center, screen-left facial disk becomes more visible, and the far disk edge and ear tuft partly occlude. Wings stay attached.
- `180 down`: body remains frontal; head tucks, eyelids and both complete eyes point toward the screen bottom, and beak lowers without becoming the failed state.
- `270 screen-left`: inverse of `090`; beak and pupils cross left of head center with matching facial-disk and tuft occlusion.
- Diagonals continuously interpolate eyes, facial disks, tufts, beak, neck, and small upper-body follow-through. Preserve blue iris construction, copper-brown plumage, cream belly, and orange talons without adding a second eye layer.
