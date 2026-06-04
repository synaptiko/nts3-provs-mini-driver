# NTS-3 MIDI Remapping Specification

This document defines the intended remapping behavior for the Korg NTS-3 Pro VS Mini driver. The remapper reads the NTS-3 input stream, keeps a small amount of controller state, and emits a new virtual MIDI stream for a DAW.

## Output Modes

The app supports two output value modes.

### Pair Mode

Pair Mode is the default. It preserves MIDI 14-bit CC pairs:

- Incoming updates are coalesced on a short timer.
- Each dirty mapped control is emitted as a complete MSB/LSB pair.
- The mapped MSB CC is sent first, immediately followed by its mapped LSB CC.
- If multiple raw updates arrive before the next flush, the latest value wins.
- No unrelated CC is interleaved inside a single MSB/LSB pair.

### Trim Mode

Trim Mode is enabled with `--trim`.

- The app emits only the mapped MSB CC.
- LSB output is not sent.
- Incoming LSB values may still be stored internally, but they do not produce MIDI output.
- The output value is the latest MSB value.

## Output CC Layout

All 14-bit output pairs use valid MIDI CC pairing. MSB controls are `10...25`; their LSB partners are `42...57`.

| Output control | MSB | LSB |
| --- | ---: | ---: |
| Master Volume | 10 | 42 |
| Global X | 11 | 43 |
| Global Y | 12 | 44 |
| Global Depth | 13 | 45 |
| FX 1 X | 14 | 46 |
| FX 1 Y | 15 | 47 |
| FX 1 Depth | 16 | 48 |
| FX 2 X | 17 | 49 |
| FX 2 Y | 18 | 50 |
| FX 2 Depth | 19 | 51 |
| FX 3 X | 20 | 52 |
| FX 3 Y | 21 | 53 |
| FX 3 Depth | 22 | 54 |
| FX 4 X | 23 | 55 |
| FX 4 Y | 24 | 56 |
| FX 4 Depth | 25 | 57 |

## MIDI Learn

The debug UI provides MIDI Learn buttons for every mapped output target: Master Volume, Global Depth/X/Y, and FX 1-4 Depth/X/Y.

When a MIDI Learn button is active:

- normal remapped output is temporarily suppressed
- only the selected target's mapped output is emitted
- Pair Mode emits that target as a repeated back-to-back MSB/LSB pair
- the learn pulse stops automatically after a short window, or when the same button is pressed again

## Input Events

The remapper uses these NTS-3 input events:

| Input control | MSB | LSB | Single CC |
| --- | ---: | ---: | ---: |
| Master Volume | 7 | 39 | |
| Total FX X | 12 | 44 | |
| Total FX Y | 13 | 45 | |
| Total FX Depth | 14 | 46 | |
| Input Mute | | | 15 |
| Total FX Touch | | | 102 |
| FX 1 Freeze | | | 105 |
| FX 1 On/Off | | | 106 |
| FX 2 Freeze | | | 109 |
| FX 2 On/Off | | | 110 |
| FX 3 Freeze | | | 113 |
| FX 3 On/Off | | | 114 |
| FX 4 Freeze | | | 117 |
| FX 4 On/Off | | | 118 |

All other incoming events are ignored by the remapper and are not forwarded.

## Startup State

At startup:

- No FX slots are active.
- No FX slots are individually frozen.
- Global freeze is off.
- Input Mute is treated as released, value `0`.
- Total FX Touch is treated as released, value `0`.
- All stored X, Y, and Depth values are `0`.

If the hardware was already in another state before the app started, the user may need to toggle controls once to synchronize the remapper state.

## Global Mode

Global Mode is active when no FX slots are active.

In Global Mode:

- Master Volume always maps to Master Volume output.
- Total FX X maps to Global X.
- Total FX Y maps to Global Y.
- Total FX Depth maps to Global Depth.
- Total FX Touch is state only and is not emitted.
- Input Mute is state only and is not emitted.

When Total FX Touch is released and global freeze is off, Global X and Global Y return to `0`.

Depth does not return to `0` on touch release.

## FX Mode

FX Mode is active when one or more FX slots are active.

FX slot active state is controlled by the corresponding FX On/Off CC:

- Value `127` means active.
- Value `0` means inactive.

When the first FX slot activates:

- The app enters FX Mode.
- Global X, Global Y, and Global Depth are emitted as `0`.
- Global freeze state is preserved but does not apply while FX Mode is active.
- Global outputs stop being updated while FX Mode remains active.

When an FX slot activates:

- It becomes the current FX freeze target for Input Mute.
- Its current Depth value is reset to `0`.
- Its current X/Y values are set to that slot's current release target.
- Its mapped X, Y, and Depth outputs are immediately emitted.
- If that slot has a stored freeze state, its initial X/Y output is the stored frozen X/Y value.
- If that slot does not have a stored freeze state, its initial X/Y output is `0`.

When an FX slot deactivates:

- Its mapped X, Y, and Depth outputs are emitted as `0`.
- Its current X, Y, and Depth output values are reset to `0`.
- Its stored freeze toggle and frozen X/Y values are preserved.
- If it was the current FX freeze target, the target falls back to the most recently activated FX slot that is still active.

When the last FX slot deactivates:

- The app returns to Global Mode.
- Global X/Y are emitted to the current Global Mode release target: the stored global frozen values if global freeze is active, otherwise `0`.

In FX Mode:

- Total FX X drives X for every active, unfrozen FX slot.
- Total FX Y drives Y for every active, unfrozen FX slot.
- Total FX Depth drives Depth for every active, unfrozen FX slot and the current FX freeze target.
- Total FX Touch controls release behavior for all active FX slots.
- Frozen FX slots stay parked on their frozen X/Y values unless they are the current FX freeze target.
- The current FX freeze target follows live X/Y while touched, even when frozen, and returns to its frozen X/Y on release.
- Frozen non-target FX slots keep their current Depth value while unfrozen active FX slots and the current FX freeze target receive new Depth values.
- Raw per-FX X/Y/Depth input is ignored.
- Per-FX Touch input is ignored.
- FX Selection input is ignored.

## Depth Behavior

Depth is independent from touch release. In FX Mode, Depth follows FX freeze state.

- Depth is updated when Total FX Depth input is received.
- In Global Mode, Total FX Depth updates Global Depth.
- In FX Mode, Total FX Depth updates every active, unfrozen FX slot and the current FX freeze target.
- Frozen non-target FX slots keep their current Depth output value.
- Depth is not affected by global freeze.
- FX Depth is affected by individual FX freeze and FX mute freeze.
- Depth does not reset on Total FX Touch release.
- FX Depth resets to `0` only when the corresponding FX slot is activated or deactivated.

## Global Freeze From Input Mute

Input Mute is a momentary button:

- Initial value is treated as `0`.
- Pressed and held value is `127`.
- Released value is `0`.

Global freeze affects X and Y only in Global Mode. It does not affect Depth and does not apply to FX Mode.

The app tracks four global freeze phases:

- `normal`: touch release returns X/Y to `0`.
- `armingFreeze`: the user has pressed and held Mute while the pad is touched.
- `frozen`: touch release returns X/Y to the stored frozen values.
- `armingUnfreeze`: the user has pressed and held Mute while already frozen.

If global freeze is off and Total FX Touch is `0`, pressing Input Mute does not arm freeze and does not emit output.

### Entering Freeze

When Total FX Touch is `127`, global freeze is off, and Input Mute changes to `127`:

- The app enters `armingFreeze`.
- Current X/Y output continues to follow the pad.
- The frozen X/Y candidate is updated from the latest incoming Total FX X/Y values while the pad remains touched and Mute remains held.

The freeze is committed when either Total FX Touch changes to `0` or Input Mute changes to `0`.

After freeze is committed:

- The app enters `frozen`.
- The stored frozen X/Y values are the latest collected Total FX X/Y values at commit time.
- If the pad is released, X/Y output returns to the stored frozen values instead of `0`.

### Behavior While Frozen

While frozen:

- If Total FX Touch is `127`, incoming Total FX X/Y values are still emitted live.
- If Total FX Touch changes to `0`, X/Y output returns to the stored frozen values.
- Stored frozen X/Y values do not change unless a new freeze operation is armed.

### Exiting Freeze

When global freeze is on and Input Mute changes to `127`:

- The app enters `armingUnfreeze`.
- Current X/Y output continues to follow the pad if Total FX Touch is `127`.

The unfreeze is committed when either Total FX Touch changes to `0` or Input Mute changes to `0`.

After unfreeze is committed:

- The app enters `normal`.
- Stored frozen X/Y values are cleared to `0`.
- If Total FX Touch is `0`, X/Y output is emitted as `0`.
- If Total FX Touch is still `127`, live X/Y output continues from the latest collected Total FX X/Y values.

## FX Mode Freeze

In FX Mode, Input Mute affects one current FX freeze target. It does not use or update the Global Mode frozen X/Y values.

The current FX freeze target is the most recently activated active FX slot.

When Total FX Touch is `127`, the target FX slot is not currently mute-frozen, and Input Mute changes to `127`:

- The app arms mute freeze for the target FX slot only.
- The target FX slot's frozen X/Y candidate is updated from its latest current X/Y output while the pad remains touched and Mute remains held.
- The freeze is committed when either Total FX Touch changes to `0` or Input Mute changes to `0`.

After FX mute freeze is committed:

- The target FX slot receives its own frozen X/Y value.
- The target FX slot can still follow live X/Y while touched.
- On Total FX Touch release, that FX slot returns to its own frozen X/Y value instead of `0`.
- Other active FX slots keep their own independent release targets.
- FX slot frozen return values are visualized using that FX slot's color.

When the target FX slot is mute-frozen and Input Mute changes to `127`:

- The app arms mute unfreeze for the target FX slot only.
- The unfreeze is committed when either Total FX Touch changes to `0` or Input Mute changes to `0`.
- The cleared target FX slot returns to `0` on release unless its own FX Freeze CC is still active.

FX mute freeze state is retained when an FX slot is deactivated. If that slot is reactivated later, it becomes the current freeze target again and immediately emits initial X/Y based on its stored freeze state.

### FX Long-Press Clear

In FX Mode only, holding Input Mute for at least `0.7` seconds and then releasing it clears all stored FX freeze states for every FX slot, including inactive slots.

After long-press clear:

- Active FX slots return to `0` on release.
- If Total FX Touch is currently `127`, active FX slots resume following the latest live X/Y values.
- Global Mode is unaffected; the long-press clear gesture does not apply in Global Mode.

## Individual FX Freeze CC

Each FX slot also has an individual freeze state controlled by its FX Freeze CC:

- Value `127` means frozen.
- Value `0` means unfrozen.

Individual FX freeze affects that FX slot's X, Y, and Depth updates.

FX Freeze input for an inactive slot is ignored for mapping state. Deactivating a slot does not clear its existing FX Freeze state.

When an active FX slot receives FX Freeze value `127`:

- Its individual freeze state is enabled.
- Its stored frozen X/Y values are captured from that slot's latest current X/Y output values.
- If Total FX Touch is `127`, live X/Y output continues to follow incoming Total FX X/Y values.

When an active FX slot receives FX Freeze value `0`:

- Its individual freeze state is disabled.
- Its stored frozen X/Y values are cleared to `0`.
- If Total FX Touch is `0`, the slot's X/Y output returns to its release target.

When an active FX slot is individually frozen:

- Its X/Y release target is its stored frozen X/Y value.
- While Total FX Touch is `127`, it follows live X/Y if it is the current FX freeze target; otherwise it stays parked on its frozen X/Y value.
- When Total FX Touch changes to `0`, that FX slot returns to its stored frozen X/Y value instead of `0`.

When an FX slot is individually unfrozen:

- Its stored frozen X/Y value is cleared to `0`.
- If Total FX Touch is `0`, its X/Y output returns to its FX Mode release target.

## Release Targets

When Total FX Touch changes to `0`, X/Y outputs are set to release targets.

In Global Mode:

- If global freeze is frozen, Global X/Y return to the stored global frozen X/Y values.
- Otherwise, Global X/Y return to `0`.

In FX Mode:

- Each active FX slot is handled independently.
- If the FX slot has individual FX Freeze CC state, it returns to that FX slot's frozen X/Y values.
- Else if the FX slot has Input Mute freeze state, it returns to that FX slot's mute-frozen X/Y values.
- Else it returns to `0`.

## Mapping Debug UI

The mapping debug UI visualizes the transformed mapping state, not just raw input.

The main visual area should resemble the NTS-3 control surface:

- A vertical FX Depth control on the left.
- A rectangular X/Y pad to the right, using the same approximate aspect ratio as the real NTS-3 pad.
- Four FX status indicators using distinct colors, such as red, green, blue, and yellow.
- Active FX indicators glow.
- Frozen FX indicators show a distinct frozen state, such as an outline, lock icon, or secondary glow.

X/Y values are shown as circles on the pad:

- Global X/Y is black.
- FX slot X/Y circles use the corresponding FX color.
- Active circles use stable, distinct radii so overlapping values remain visible.
- If several active FX slots share the same current X/Y value, their concentric circles should reveal each color.
- Current output values are shown as filled circles.
- Frozen return values should be shown as subtle rings or ghost circles, so the user can see where values will return on touch release.

Depth values are shown on the vertical depth control:

- Global Depth is black.
- FX Depth markers use the corresponding FX color.
- Active FX Depth markers are visible when the FX slot is active.
- Depth markers update even when X/Y is frozen.

The UI should also expose concise numeric state for debugging:

- Current Global X/Y/Depth output values.
- Current FX 1-4 X/Y/Depth output values.
- Active/inactive state per FX.
- Individual freeze state per FX.
- Global freeze phase.
- FX mute freeze phase.
- Current FX freeze target.
- Current Total FX Touch state.
- Current Input Mute state.
- Output mode: Pair Mode or Trim Mode.

## Implementation Notes

The remapper should treat `0` and `127` as the only expected values for switch-like controls. Other values should be ignored unless later hardware testing shows that the NTS-3 emits intermediate values.

For deterministic output, every explicit reset in Pair Mode should emit both MSB and LSB as `0`. Every explicit reset in Trim Mode should emit only the mapped MSB as `0`.
