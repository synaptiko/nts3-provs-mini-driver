# NTS-3 to Pro VS Mini Mapping Specification

This document defines the implemented CoreMIDI bridge behavior.

## MIDI Endpoints

- Input source: first CoreMIDI source whose display name contains `--input`, default `NTS-3`.
- Output destination: first CoreMIDI destination whose display name contains `--output`, default `PRO VS`.
- Output channel: `--channel <1-16>`, default `1`.

The app sends directly with `MIDISend`. It does not publish a virtual source.

## NTS-3 Inputs

| NTS-3 control | MIDI |
| --- | --- |
| Master Volume | CC 7 MSB, CC 39 LSB |
| Total FX Pad X | CC 12 MSB, CC 44 LSB |
| Total FX Pad Y | CC 13 MSB, CC 45 LSB |
| Total FX Depth | CC 14 MSB, CC 46 LSB |
| Input Mute | CC 15, values 0/127 |
| Total FX Touch | CC 102, values 0/127 |
| FX 1 On/Off | CC 106, values 0/127 |
| FX 2 On/Off | CC 110, values 0/127 |
| FX 3 On/Off | CC 114, values 0/127 |
| FX 4 On/Off | CC 118, values 0/127 |

All other incoming controls are ignored.

## Value Conversion

- NTS-3 paired controls are stored internally as 14-bit values.
- Pro VS Mini CC output is always 7-bit.
- The emitted 7-bit value is the top seven bits of the 14-bit value.
- Debug display projection uses `0...99` as a label only; MIDI output remains `0...127`.
- A mapped CC is emitted only when its quantized 7-bit value changes.

## Banks

Banks are:

- Global
- FX 1
- FX 2
- FX 3
- FX 4

FX On/Off buttons control active FX banks:

- value `127`: mark the FX bank active and make it the current bank
- value `0`: mark the FX bank inactive

Routing rules:

- If no FX bank is active, the current bank is Global.
- If one or more FX banks are active, the current bank is the most recently activated active FX bank.
- X/Y/Depth input updates only the current bank.
- Switching banks does not emit zero, reset, restore, or replay messages.
- Each bank's last value is latched for debug display and later movement.

## Touch Behavior

Total FX Touch gates X/Y input:

- Touch `127`: incoming X/Y values update the current bank and may emit mapped output.
- Touch `0`: incoming X/Y values are ignored, and no reset is emitted.

Depth is not touch-gated. Depth values are stored for the current bank. FX 2 Depth has a mapped target; other depth targets are debug-only.

## Confirmed Pro VS Mini Targets

| Bank/control | Target | Output |
| --- | --- | --- |
| Global X | Modulation | CC 1 |
| Global Y | Portamento time | CC 5 |
| FX 1 X | Filter cutoff | CC 74 |
| FX 1 Y | Filter resonance | CC 71 |
| FX 2 X | Chorus rate | CC 92 |
| FX 2 Y | Chorus amount | CC 91 |
| FX 2 Depth | FX engine select | CC 9 |
| FX 3 X | LFO 1 rate | CC 72 |
| FX 3 Y | LFO 1 amount | CC 70 |
| FX 4 X | LFO 2 rate | CC 73 |
| FX 4 Y | LFO 2 amount | CC 28 |

FX 2 Depth is quantized to three representative CC 9 values:

| NTS-3 Depth 7-bit area | Pro VS FX engine | Emitted value |
| --- | --- | ---: |
| `0...42` | Chorus | `21` |
| `43...84` | Ensemble | `64` |
| `85...127` | Reverb | `106` |

The engine selector uses a two-value hysteresis around the `42/43` and `84/85` boundaries, so small depth jitter near a split does not flicker between engines.

FX 1, FX 3, FX 4, and Global Depth values are currently stored but unmapped.

## Intentionally Unmapped

True Pro VS Mini vector mix X/Y is not mapped. Published Pro VS Mini documentation does not identify a safe realtime MIDI CC/NRPN target for joystick/vector mix X/Y. This must remain disabled until hardware captures identify and verify a safe path.

Global Depth is not mapped. True octave control is not documented in the Pro VS Mini CC table.

Voice fine tuning, coarse tuning, and waveform select are not used as default mappings.

## Experimental Options

Experimental options are disabled by default.

| Option | Behavior |
| --- | --- |
| `--volume-cc7` | Master Volume emits CC 7 |
| `--volume-cc11` | Master Volume emits CC 11 |
| `--play-toggle` | Input Mute press alternates MIDI Start and Stop |

Input Mute play toggle is edge-detected:

- first press sends MIDI Start
- repeated held `127` values send nothing
- release sends nothing
- next press sends MIDI Stop

## Debug State

The debug snapshot exposes:

- current bank
- last active FX slot
- touch and mute values
- output channel
- experimental option state
- per-bank X/Y/Depth 14-bit values
- per-axis target labels
- recent outgoing MIDI messages

## Test Coverage

`swift run nts3-provs-mini-driver --self-test` covers:

- NTS-3 CC parsing and running status
- 14-bit to 7-bit scaling
- Global X/Y modulation and portamento output
- confirmed FX target mappings
- FX 2 Depth FX engine selection and hysteresis
- last activated FX wins
- bank switching emits no reset
- touch release latches values
- unmapped depth storage
- experimental volume flags
- Input Mute Start/Stop edge detection
- transformer output channel routing
