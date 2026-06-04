# NTS-3 Pro VS Mini Driver

macOS menu-bar CoreMIDI bridge for controlling a Behringer Pro VS Mini from a Korg NTS-3.

The app listens to the NTS-3, keeps NTS-3 pad values internally as 14-bit controls, converts confirmed Pro VS targets to 7-bit MIDI CC, and sends directly to a matched Pro VS Mini MIDI destination. It does not create a DAW virtual source.

True Pro VS Mini vector mix X/Y is intentionally not implemented for now. Global X/Y instead use documented performance targets: Modulation and Portamento time.

## Requirements

- macOS 13 or newer
- Swift toolchain or Xcode command line tools
- Korg NTS-3 connected over USB
- Behringer Pro VS Mini connected over USB or MIDI
- Pro VS Mini external MIDI CC receive enabled

## Commands

List CoreMIDI sources and destinations:

```sh
swift run nts3-provs-mini-driver --list
```

Run the bridge in the terminal:

```sh
swift run nts3-provs-mini-driver
```

Open the menu-bar app and Debug window support:

```sh
swift run nts3-provs-mini-driver --ui
```

Run deterministic tests without hardware:

```sh
swift run nts3-provs-mini-driver --self-test
```

Use custom endpoint filters or MIDI channel:

```sh
swift run nts3-provs-mini-driver --input "NTS-3" --output "PRO VS" --channel 1
```

Build a release binary:

```sh
swift build -c release
```

The release binary is:

```sh
.build/release/nts3-provs-mini-driver
```

## CLI Options

- `--input <text>`: source name substring. Default: `NTS-3`.
- `--output <text>`: destination name substring. Default: `PRO VS`.
- `--channel <1-16>`: output MIDI channel. Default: `1`.
- `--ui`: launch as a menu-bar app and auto-start the bridge.
- `--all`: connect every available MIDI source.
- `--quiet`: suppress per-message terminal logs.
- `--show-realtime`: include MIDI clock and active sensing in logs.
- `--self-test`: run mapping tests and exit.
- `--list`: print available MIDI endpoints and exit.
- `--volume-cc7`: experimental, map NTS-3 Master Volume to CC 7.
- `--volume-cc11`: experimental, map NTS-3 Master Volume to CC 11.
- `--play-toggle`: experimental, make Input Mute press alternate MIDI Start and Stop.

## Confirmed Mappings

FX On/Off buttons select banks. If no FX is active, the active bank is Global. If one or more FX are active, X/Y/Depth route only to the most recently activated active FX bank.

Switching banks latches the previous bank values. The app does not emit zero or reset values when leaving a bank. Pad touch release also holds the latest values.

| NTS-3 bank/control | Pro VS Mini target | MIDI |
| --- | --- | --- |
| Global X | Modulation | CC 1 |
| Global Y | Portamento time | CC 5 |
| Global Depth | Stored for debug only | none |
| FX 1 X | Chorus/Ensemble/Reverb primary control | CC 92 |
| FX 1 Y | Chorus/Ensemble/Reverb secondary control | CC 91 |
| FX 1 Depth | FX engine select: Chorus, Ensemble, Reverb | CC 9 |
| FX 2 X | Filter cutoff | CC 74 |
| FX 2 Y | Filter resonance | CC 71 |
| FX 2 Depth | Stored for debug only | none |
| FX 3 X | LFO 1 rate | CC 72 |
| FX 3 Y | LFO 1 amount | CC 70 |
| FX 3 Depth | Stored for debug only | none |
| FX 4 X | LFO 2 rate | CC 73 |
| FX 4 Y | LFO 2 amount | CC 28 |
| FX 4 Depth | Stored for debug only | none |
| Master Volume | Disabled by default | optional CC 7 or CC 11 |
| Input Mute | Disabled by default | optional MIDI Start/Stop |

## Debug App

`--ui` starts a menu-bar-only app. The status menu contains:

- `Debug`: open or reopen the Pro VS Mini debug window.
- `Restart` or `Start`: restart or start the CoreMIDI bridge.
- `Stop`: stop the bridge.
- `Quit`: stop the bridge and terminate the app.

The Debug window shows a 3x2 grid: one live X/Y pad, Global modulation/portamento, the currently selected FX engine, Filter, LFO 1, and LFO 2. Click cards to switch the active bank, drag the pad to edit X/Y, or drag a card meter to edit that value directly.

## Hardware Verification

1. Connect the NTS-3 and Pro VS Mini.
2. Enable external MIDI CC receive on the Pro VS Mini.
3. Run `swift run nts3-provs-mini-driver --list`.
4. Confirm an NTS-3 source and a Pro VS destination appear. If names differ, use `--input "<source substring>"` and `--output "<destination substring>"`.
5. Run `swift run nts3-provs-mini-driver --self-test` and confirm all tests pass.
6. Start `swift run nts3-provs-mini-driver --ui --input "NTS-3" --output "PRO VS" --channel 1`.
7. Open Debug from the menu-bar item.
8. With no NTS-3 FX active, move the X/Y pad. Global X should send Modulation CC `1`, and Global Y should send Portamento time CC `5`.
9. Turn on NTS-3 FX 1. X/Y should move the current Chorus/Ensemble/Reverb controls. Move Depth through low/mid/high areas and confirm CC `9` selects Chorus, Ensemble, and Reverb.
10. Turn on FX 2. X/Y should now move filter cutoff/resonance; FX 1 should stay latched.
11. Turn off FX 2. X/Y should route back to FX 1 with no reset burst.
12. Repeat for FX 3 and FX 4 to verify LFO 1 and LFO 2 targets.
13. Release the pad after moving a mapped bank. The app should emit no zero/reset message.
14. Optional: run with `--volume-cc7` or `--volume-cc11` and test whether Master Volume affects the Pro VS.
15. Optional: run with `--play-toggle` and test whether Input Mute presses Start/Stop playback in the desired Pro VS sync mode.

Do not map Global X/Y to true vector mix until a safe vector mix MIDI path is confirmed on hardware.

## References

- Mapping specification: [MAPPING_SPEC.md](MAPPING_SPEC.md)
- Korg NTS-3 MIDI implementation download page: <https://www.korg.com/us/support/download/manual/0/934/5270/>
