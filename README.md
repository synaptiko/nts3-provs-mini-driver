# NTS-3 Pro VS Mini Driver

macOS MIDI remapper for the Korg NTS-3 kaoss pad kit.

The app connects to the NTS-3 MIDI source, creates a virtual MIDI source named `NTS-3 Pro VS Mini Driver`, and emits only the mapped CC stream defined in [MAPPING_SPEC.md](MAPPING_SPEC.md). Unmapped incoming MIDI is ignored.

## Requirements

- macOS 13 or newer
- Swift toolchain / Xcode command line tools
- Korg NTS-3 connected over USB

## Run

List the MIDI endpoints CoreMIDI can see:

```sh
swift run nts3-provs-mini-driver --list
```

Run the default pair-mode remapper:

```sh
swift run nts3-provs-mini-driver
```

Run 7-bit trim mode:

```sh
swift run nts3-provs-mini-driver --trim
```

Open the menu-bar app:

```sh
swift run nts3-provs-mini-driver --ui
```

Run deterministic mapping checks without hardware:

```sh
swift run nts3-provs-mini-driver --self-test
```

If CoreMIDI exposes the device under a different name:

```sh
swift run nts3-provs-mini-driver --input "kaoss"
```

Change the virtual source name shown in a DAW:

```sh
swift run nts3-provs-mini-driver --virtual-name "NTS-3 Ableton Control"
```

Build a release binary:

```sh
swift build -c release
```

The release binary will be at:

```sh
.build/release/nts3-provs-mini-driver
```

## CLI Options

- `--input <text>`: connect only to source names containing this text. Default: `NTS-3`.
- `--virtual-name <name>`: set the virtual MIDI source name. Default: `NTS-3 Pro VS Mini Driver`.
- `--ui`: launch the menu-bar app and auto-start the bridge.
- `--trim`: emit only mapped MSB CCs as 7-bit values.
- `--all`: connect every available MIDI source except the app's own virtual source.
- `--quiet`: remap MIDI without per-message logs.
- `--show-realtime`: include timing clock and active sensing in logs.
- `--self-test`: run deterministic mapping checks and exit.
- `--list`: print available sources and destinations.

## Output Modes

Pair Mode is the default. It preserves 14-bit CC pairs:

- incoming updates are coalesced on a short timer
- each dirty mapped control is emitted as a back-to-back MSB/LSB pair
- the MSB CC is sent first, followed immediately by the LSB CC
- latest-value-wins coalescing avoids flooding DAW MIDI learn with raw X/Y pad traffic

Trim Mode is enabled with `--trim`:

- incoming MSB values are emitted on mapped MSB CCs
- incoming LSB values are stored but not emitted
- explicit resets and held values emit only the mapped MSB CC

## Output CC Layout

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

## Menu-Bar App

The `--ui` mode starts the CoreMIDI bridge as a menu-bar-only app. It does not appear in the Dock or Cmd-Tab switcher.

The status menu includes:

- `Debug`: open or reopen the mapping debugger window.
- `Learn MIDI`: open the floating MIDI Learn popup.
- `Restart` or `Start`: restart or start the CoreMIDI bridge.
- `Stop`: stop the CoreMIDI bridge.
- `Quit`: stop the bridge and terminate the app.

Closing the Debug window does not quit the app. Use the status menu to reopen Debug or quit.

## Debug Window

The window shows:

- a vertical Depth strip and rectangular X/Y pad
- active FX indicators with distinct colors
- current transformed X/Y output circles
- frozen return-value rings
- transformed Depth markers
- numeric Global and FX output state
- global freeze phase, FX mute freeze phase, current FX freeze target, Total FX Touch, Input Mute, and output mode

## Learn MIDI Popup

Open Learn MIDI from the status menu or press `Cmd+Option+L`. The popup is a floating panel configured for fullscreen DAW spaces.

Targets are arranged as a compact table:

- rows: Volume, Depth, X, Y
- columns: Global, FX 1, FX 2, FX 3, FX 4

Volume is available in the Global column. Each target cell shows its mapped CC pair.

Selecting a target hides the popup, temporarily solos that mapped output, and sends a short CC pulse sequence for DAW MIDI learn. When the pulse sequence finishes, solo mode clears automatically. If the bridge is stopped, the popup remains visible but target controls are disabled.

## DAW Setup

1. Start `nts3-provs-mini-driver` and keep it running.
2. Open the DAW MIDI settings.
3. Enable Track and/or Remote for the input named `NTS-3 Pro VS Mini Driver`, or the custom `--virtual-name`.
4. Use that virtual input for MIDI mapping or a MIDI track.

For Ableton Live mapping, run `swift run nts3-provs-mini-driver --ui`, open Learn MIDI from the status item or `Cmd+Option+L`, and select the target you want Live to learn. Each target temporarily sends only that target's CC pair, which prevents Live from learning the wrong control during X/Y pad movement.

## Actual Device Test Checklist

1. Connect the NTS-3 over USB.
2. Run `swift run nts3-provs-mini-driver --list` and confirm a source matching `NTS-3` appears. If the source has another name, add `--input "<source substring>"` to later commands.
3. Run `swift run nts3-provs-mini-driver --self-test` and confirm it passes.
4. Start the bridge with `swift run nts3-provs-mini-driver --ui` for menu-bar Debug/Learn MIDI checking, or `swift run nts3-provs-mini-driver` for terminal-only testing. Add `--trim` if testing 7-bit mode.
5. In a DAW or MIDI monitor, listen to the virtual source `NTS-3 Pro VS Mini Driver`.
6. Move Master Volume. Pair Mode should emit CC `10/42`; Trim Mode should emit CC `10` only.
7. With no FX active, touch and move the X/Y pad. Global X/Y should emit CC `11/43` and `12/44`. Release the pad; Global X/Y should return to `0`. Depth should emit CC `13/45` and should not reset on pad release.
8. While touching the X/Y pad, hold Input Mute, move to a value, then release either the pad or Input Mute. X/Y should return to the frozen value instead of `0`. Touch the pad again; live X/Y should emit while touched and return to the frozen value on release. Press and release Input Mute again to unfreeze; released X/Y should return to `0`.
9. Turn FX 1 on. Global X/Y/Depth should emit `0`, then FX 1 X/Y/Depth should emit `0` on CC `14/46`, `15/47`, and `16/48`. Moving the pad should update FX 1, not Global.
10. Turn on additional FX slots and verify their ranges: FX 2 `17/49` to `19/51`, FX 3 `20/52` to `22/54`, FX 4 `23/55` to `25/57`.
11. The most recently activated FX is the current FX freeze target. With FX 1 and FX 2 active, FX 2 should be the target. Touch X/Y, hold Input Mute, move to a value, then release either the pad or Input Mute. FX 2 should return to its frozen X/Y on pad release; FX 1 should return to its own previous freeze value or `0`.
12. Activate another FX slot and repeat Input Mute freeze. The newly activated FX should become the only slot whose freeze toggle changes. Previously frozen FX should stay parked on their stored values while the current target FX can still move live and return to its frozen value on release.
13. Press and release Input Mute again while the same target FX is active. Only that target FX mute-freeze should clear, and released X/Y for that target should return to `0` unless that FX has its own FX Freeze CC active.
14. Hold Input Mute for at least `0.7` seconds while FX Mode is active, then release it. All FX freeze states should clear, including stored freezes for inactive slots. Active FX should return to `0` when the pad is released.
15. Turn a frozen FX slot off. Its X/Y/Depth should emit `0`, but its freeze toggle and frozen X/Y should be remembered unless the long-press clear gesture was used. Turn it back on; it should become the freeze target and immediately emit its stored frozen X/Y plus Depth `0`.
16. When the last FX is off, the app returns to Global Mode; Global X/Y should resume the parked global frozen value if global freeze was active, otherwise `0`.
17. With an FX active, send that FX Freeze value `127`, move the pad, then release it. That FX should move live if it is the current freeze target, then return to its captured frozen X/Y on release. Its Depth should also move live if it is the target. Non-target frozen FX should keep X/Y/Depth parked. Send Freeze `0` to clear the individual freeze.
18. Watch the debug UI during the same checks: active FX indicators should glow, the target FX indicator should show the target marker, current X/Y circles should use each FX color, frozen return positions should show as rings in FX-related colors, and Depth markers should update for unfrozen FX plus the current target FX.

## References

- Mapping specification: [MAPPING_SPEC.md](MAPPING_SPEC.md)
- Korg MIDI implementation download page: <https://www.korg.com/us/support/download/manual/0/934/5270/>
