# NTS-3 to Behringer Pro VS Mini Driver Plan

Research date: 2026-06-04.

## Goal

Build a small macOS menu-bar CoreMIDI bridge that listens to the Korg NTS-3, translates selected NTS-3 controls, and sends MIDI directly to the Behringer Pro VS Mini.

The current repo is only a README. The reference app at `~/Projects/nts3-midi-remapper` has useful code on its `origin/master` branch even though the local worktree is behind and empty. It is a SwiftPM app with:

- CoreMIDI source discovery and packet parsing.
- A menu-bar app shell.
- Mapping/debug SwiftUI windows.
- An `NTS3MappingTransformer` and self-test harness.
- A newer `origin/synaptiko/macro-board-pad-mode` branch with last-active-bank behavior worth borrowing from selectively.

## Research Findings

### Korg NTS-3

The NTS-3 MIDI implementation confirms the controller source side is usable:

| NTS-3 control | MIDI |
| --- | --- |
| Master Volume | CC 7 MSB, CC 39 LSB |
| Total FX Pad X | CC 12 MSB, CC 44 LSB |
| Total FX Pad Y | CC 13 MSB, CC 45 LSB |
| Total FX Depth | CC 14 MSB, CC 46 LSB |
| Input Mute | CC 15, off/on values 0/127 |
| Total FX Touch | CC 102, off/on values 0/127 |
| FX 1 On/Off | CC 106 |
| FX 2 On/Off | CC 110 |
| FX 3 On/Off | CC 114 |
| FX 4 On/Off | CC 118 |

This is enough to implement the requested "global or last activated FX" routing model.

### Behringer Pro VS Mini

The Pro VS Mini docs confirm many target CCs:

| Pro VS Mini target | MIDI | Status |
| --- | --- | --- |
| Modulation | CC 1, range 0-127 | Confirmed |
| Portamento time | CC 5, documented range 0-31 in current manual; firmware notes say CC 5 | Confirmed in firmware 2.x |
| FX engine | CC 9, Chorus 0-42, Ensemble 43-84, Reverb 85-127 | Confirmed |
| Voice A-D wave selection | CC 24-27, range 0-127 | Confirmed, selects oscillator waveforms rather than vector mix |
| LFO 2 amount | CC 28, documented display range 0-99 | Confirmed |
| Filter envelope amount | CC 47, range 0-127 | Confirmed |
| LFO 1 waveform | CC 54, range 0-127, triangle/square/saw | Confirmed |
| LFO 2 waveform | CC 55, range 0-127, triangle/square/saw | Confirmed |
| LFO 1 destination | CC 56, range 0-127, VCF/OSC | Confirmed in ManualsLib V2.0 table; missing from Manuals+ mirror's extracted CC list |
| LFO 1 amount | CC 70, documented display range 0-99 | Confirmed |
| Filter resonance | CC 71, documented display range 0-99 | Confirmed |
| LFO 1 rate | CC 72, documented display range 0-99 | Confirmed |
| LFO 2 rate | CC 73, documented display range 0-99 | Confirmed |
| Filter cutoff | CC 74, documented display range 0-99 | Confirmed |
| Amplitude envelope ADSR | CC 81-84, documented display range 0-99 | Confirmed |
| Filter envelope ADSR | CC 85-88, documented display range 0-99 | Confirmed |
| Chorus depth/amount | CC 91, documented display range 0-99 | Confirmed |
| Chorus rate | CC 92, documented display range 0-99 | Confirmed |
| Voice A-D fine tuning | CC 111-114, documented display range 0-99 | Confirmed |
| Voice A-D coarse tuning | CC 115-118, documented display range 0-99 | Confirmed; current manual labels CC 118 as Voice C again, likely a typo for Voice D |

Additional non-CC MIDI/external-control paths:

- MIDI notes over DIN MIDI In or USB MIDI can play the synth; MIDI receive channel and MIDI velocity receive are configurable in the menu.
- Program Change can change presets. Firmware 1.1.2 release notes say Program Change messages can change presets from `0-32`; because the synth has 32 programs, hardware should verify whether the practical usable range is `0...31`, `1...32`, or an inclusive off-by-one document typo.
- MIDI/USB sync is documented via `Sync Source` and `Sync Type` settings. A Reddit hardware report on firmware 2.0.0 also confirms incoming MIDI transport/sync starts the internal sequencer/arpeggiator when Sync Source listens to MIDI, but the official manual does not provide a dedicated transport on/off setting.
- SysEx send/receive is menu-documented for program bulk, current program, pattern bulk, and current pattern. The full SysEx patch format is not documented well enough for realtime control, but it is a documented path for preset/pattern transfer.

Important gaps:

- I did not find a documented Pro VS Mini CC for live joystick/vector waveform mix X/Y.
- I did not find a documented Pro VS Mini CC for output volume. Standard MIDI Channel Volume CC 7 can be tested, but it is not listed in the Pro VS Mini CC table.
- I did not find a documented Pro VS Mini CC for octave up/down. The front-panel `+/- PROG/OCTAVE` buttons are documented, but no MIDI control is listed. Coarse tuning CCs 115-118 may be an approximation, not true octave switching.
- I did not find a documented Pro VS Mini CC for Play/Active. The docs confirm Play/Active as a physical control and MIDI/USB sync settings, so MIDI realtime Start/Stop should be tested as the likely route.
- The Pro VS Mini has a menu setting for whether external MIDI CC control is on/off; the hardware setup checklist must include enabling it.

### Deeper Vector Mix Research

The current V3.0 / firmware 2.x material keeps vector mix as the important special case.

What is confirmed:

- The current manual describes vector synthesis as a 2D balance between oscillators A-D, controlled by the joystick and by the mix envelope.
- The current manual's CC table still does not list joystick X/Y, oscillator A-D levels, or mix-envelope point coordinates.
- Firmware 2.0.0/2.0.2 release notes add five-voice polyphony, arp hold/chord modes, portamento via CC 5, FX engine selection via CC 9, and fixes to MIX Loop behavior. They do not mention new realtime vector mix CCs or NRPNs.
- Firmware 1.1.2 release notes mention a fix for SysEx parsing of LFO and MIX ENV settings. That strongly suggests mix-envelope/vector data exists in SysEx patch data, but does not prove that individual realtime parameter messages exist.
- Third-party editors support the same split:
  - Stage Engine says almost all parameters are realtime MIDI CC, with some parameters changed by SysEx. Its UI has a `MIX Setup` panel rather than exposed joystick X/Y CC controls.
  - Momo's editor advertises automatable controls and X/Y modulation of parameters, but this appears to be an editor-side macro pad for modulating exposed parameters, not proof that the Pro VS Mini exposes its internal vector joystick as MIDI X/Y.

Forum findings:

- Gearspace users captured Stage Engine editor SysEx for the `Mix` subpanel and reported that mix-envelope/vector settings were not accessible as individual remote CC/SysEx parameters; the whole patch had to be sent and written/stored.
- A Gearspace user on firmware 2.0.2 later noted that the MIDI implementation chart still does not list joystick/vector movement or oscillator volumes.
- Electra One users testing firmware 2.0.2 report that the Pro VS Mini does not echo front-panel knob movement as MIDI CC. That does not prove the joystick is silent, but it makes a "capture the hardware joystick output" test a long shot rather than the expected path.
- A Hispasonic forum post claims CC/NRPN can control the oscillators, filters, and mix joystick from a DAW, but the post does not provide CC/NRPN numbers and conflicts with the published V3.0 CC table plus the Gearspace capture reports. Treat it as a lead to test, not confirmation.

Working conclusion:

- Published/latest evidence does not confirm true realtime Pro VS Mini vector X/Y over CC/NRPN.
- The most promising path is SysEx: reverse or capture the current program SysEx format, identify the mix-envelope/vector bytes, and test whether a modified single-program SysEx changes the current edit buffer without requiring a flash write.
- Do not stream full-patch SysEx as a default control path until hardware proves it is edit-buffer-only. If it writes program memory, repeated NTS-3 pad movement could cause flash wear and audible glitches.

### Vector Mix Reverse-Engineering Plan

Treat Global X/Y as an experimental target until the hardware tests below prove a safe realtime path.

1. Update the Pro VS Mini to firmware 2.0.2 and confirm the V3.0 manual behavior on the unit.
2. Enable MIDI CC receive on the Pro VS Mini.
3. Connect both USB MIDI directions and capture the Pro VS Mini output in MIDI Monitor or Snoize while moving the physical waveform-mix joystick. If it emits CC, NRPN, or SysEx, document the exact bytes in `.context/vector-midi-captures.md` and implement that direct mapping first.
4. Capture Stage Engine while changing its `MIX Setup` controls. Save one capture per deliberate edit, with the before/after UI values, in `.context/vector-stage-engine-captures.md`.
5. If possible, capture Momo's editor while changing the mix/vector controls. Its public "X-Y modulation" claim looks like editor-side modulation, so the capture must distinguish between editor macros and actual Pro VS mix/vector messages.
6. Dump a single current program SysEx from the Pro VS Mini at known mix-envelope states:
   - Center point.
   - A-only, B-only, C-only, D-only points.
   - Several intermediate X/Y points.
   - Mix loop off and at least one loop mode.
7. Diff the SysEx dumps byte-by-byte and identify which offsets change. Record candidate offsets, value ranges, checksums, and device/model header bytes in `.context/vector-sysex-reverse-notes.md`.
8. Test sending a modified single-program SysEx while the synth is not in `SYSEX RECEIVE / LISTENING` mode. If it changes only the edit buffer, it may be viable for live-ish control. If the synth ignores it, only test receive/listening mode on a disposable patch.
9. If the only working path writes program memory, do not use it for NTS-3 pad streaming. Use it only for explicit preset editing/import tools, if at all.
10. If edit-buffer SysEx works, add a conservative throttle before enabling it in the bridge:
    - Send only when the quantized X/Y value changes.
    - Start at 10 Hz, then test 20 Hz if the synth remains stable.
    - Prefer sending on pad movement or touch release over continuous idle repeats.
    - Provide a kill switch and keep the mapping off by default until tested across several patches.

## Proposed Mapping

Use the NTS-3 FX On/Off CCs as bank selectors:

- No NTS-3 FX active: X/Y/Depth are in Global bank.
- One or more NTS-3 FX active: X/Y/Depth route only to the most recently activated active FX bank.
- Switching away from a bank automatically latches that bank's last sent values. We should not emit zero/reset values when leaving a bank.
- Pad touch release should hold the latest sent values by default, not snap target parameters back to zero.

| NTS-3 control | Intended Pro VS Mini action | Implementation status |
| --- | --- | --- |
| Master Volume | Pro VS output volume | Experimental: test CC 7 and CC 11; otherwise leave unmapped or offer a host/DAW volume target |
| Global X/Y | Waveform mix joystick replacement | Experimental: no published CC found; investigate SysEx/SynthTribe/editor behavior before committing |
| Global Depth | Octave | Experimental: no published octave CC; possible fallback is quantized coarse-tune CCs 115-118 |
| FX 1 X/Y | Analog filter cutoff/resonance | Confirmed: X -> CC 74, Y -> CC 71 |
| FX 2 X/Y | Chorus rate/amount | Confirmed for Chorus: X -> CC 92, Y -> CC 91; other FX engines need more discovery |
| FX 3 X/Y | LFO 1 rate/amount | Confirmed: X -> CC 72, Y -> CC 70 |
| FX 4 X/Y | LFO 2 rate/amount | Confirmed: X -> CC 73, Y -> CC 28 |
| Input Mute | Toggle Play | Experimental: edge-detect press and send MIDI Start/Stop or Continue/Stop after hardware test |

Value conversion:

- NTS-3 paired controls are 14-bit. Keep the combined value internally.
- Pro VS Mini CCs are 7-bit. Emit MIDI values 0...127 for full travel unless hardware proves a specific target expects 0...99.
- The Pro VS display often labels parameter ranges as 0...99. Recent firmware 2.0.2 user testing reports that sending 0...127 covers that display range, while sending only 0...99 compresses the result. The Debug UI can show Pro VS display values separately from raw MIDI values.
- Send only when the quantized Pro VS value changes, to avoid flooding the synth.

## Bring In The Reference App

Do not modify the old checkout. Import from its git object database:

```sh
git -C ~/Projects/nts3-midi-remapper archive origin/master | tar -x
```

Then rename and adapt:

- `Package.swift`: rename package and executable to `nts3-provs-mini-driver`.
- `Sources/NTS3MIDIRemapper`: rename module directory to something like `Sources/NTS3ProVSDriver`.
- Replace `NTS3MIDIRemapper` naming in types/window titles/status item text.
- Keep the CLI shape: `--list`, `--input`, `--quiet`, `--show-realtime`, `--self-test`, `--ui`.
- Add `--output <text>` for the Pro VS Mini destination and `--channel <1-16>` for emitted CCs.
- Remove or hide MIDI Learn UI in the menu bar because the target synth mapping is fixed.
- Keep menu-bar items that still fit: Debug, Start/Restart, Stop, Quit.
- Consider adding a small debug-only "Send Test Sweep" command after the bridge can target destinations safely.

Also inspect and selectively borrow from:

```sh
git -C ~/Projects/nts3-midi-remapper diff origin/master..origin/synaptiko/macro-board-pad-mode
```

That branch already documents and implements a "most recently activated bank" idea for Macro Board mode. We should not import Macro Board as a user-facing mode, but the bank-switching and debug-state patterns are relevant.

## Implementation Plan

1. Scaffold the SwiftPM app from `nts3-midi-remapper`.
2. Replace virtual-source-only output with a real MIDI destination output:
   - Create a CoreMIDI output port.
   - Match destination names by `--output`, defaulting to `PRO VS`.
   - Send with `MIDISend` to the matched destination.
   - Optionally keep a virtual mirror source for debugging later, but not in the MVP.
3. Replace the generic remapping layout with a `ProVSMappingEngine`:
   - Parse the same NTS-3 input CCs.
   - Track active FX slots and most recently activated slot.
   - Track latched values per bank.
   - Emit only the current bank's mapped Pro VS CCs.
   - Never emit automatic zero/reset when leaving a bank or releasing touch.
4. Add explicit mapping models:
   - `NTS3InputControl`
   - `ProVSParameter`
   - `ProVSControlTarget`
   - `MappingBank` for Global, FX 1, FX 2, FX 3, FX 4.
5. Implement confirmed target mappings first:
   - FX 1 filter.
   - FX 2 chorus.
   - FX 3 LFO 1.
   - FX 4 LFO 2.
6. Add experimental targets behind config flags or clearly marked mapping entries:
   - Volume test target.
   - Waveform mix investigation target.
   - Octave/coarse-tune approximation.
   - Input Mute Play toggle via MIDI realtime Start/Stop.
7. Update self-tests:
   - NTS-3 CC parsing.
   - 14-bit to 0...127 MIDI CC scaling.
   - Optional Pro VS display-value projection for 0...99 debug labels.
   - Global vs FX bank selection.
   - Last activated FX wins.
   - Bank switching latches previous values and emits no reset.
   - Touch release latches current values.
   - Input Mute sends one toggle event per press, not repeated events while held.
8. Build the Debug UI around the Pro VS Mini layout:
   - Simplified top-panel drawing.
   - Waveform mix joystick area for Global mapping status.
   - Filter cutoff/resonance controls.
   - FX engine / Chorus rate and amount controls.
   - LFO 1 and LFO 2 rate/amount controls.
   - Volume, octave, and Play indicators marked as experimental until hardware confirms them.
   - Show active NTS-3 bank, last active FX, current pad touch, Input Mute, incoming values, outgoing CCs, and latched values.
9. Hardware validation checklist:
   - Confirm NTS-3 source appears in `--list`.
   - Confirm Pro VS Mini destination appears in `--list`.
   - Enable external MIDI CC receive on the Pro VS Mini.
   - Confirm filter/chorus/LFO mappings move the expected parameters.
   - Confirm whether sending 0...127 maps to the full displayed 0...99 parameter range.
   - Test whether CC 7 or CC 11 affects volume.
   - Test whether MIDI Start/Stop toggles Play when Sync Source is MIDI or USB.
   - Execute the Vector Mix Reverse-Engineering Plan above before enabling Global X/Y by default.
   - Decide whether experimental mappings become defaults, remain opt-in, or are removed.

## Open Questions

- Does the Pro VS Mini expose live vector mix X/Y through undocumented SysEx or NRPN?
- Does MIDI Start/Stop reliably control Play/Active in the desired mode?
- Should Global X/Y be disabled until real vector mix control is found, or should it be assigned to a different confirmed macro?
- If true octave control is unavailable, is changing all four oscillator coarse tuning CCs an acceptable approximation?
- If true volume control is unavailable, should the app provide a DAW/virtual MIDI volume output instead of a Pro VS hardware target?

## Sources

- Korg NTS-3 MIDI implementation download page: https://www.korg.com/us/support/download/manual/0/934/5270/
- Korg NTS-3 MIDI implementation TXT, downloaded locally to `.context/nts3-midi-implementation.txt`.
- Behringer/Music Tribe Pro VS Mini Quick Start Guide mirror, extracted locally to `.context/pro-vs-mini-qsg.pdf`: https://gzhls.at/blob/ldb/4/3/f/9/8f6807381b0d217869bc44b01a4624195712.pdf
- Pro VS Mini V3.0 user-guide mirror with firmware 2.0.0 CC table: https://manuals.plus/behringer/pro-vs-mini-portable-5-voice-hybrid-synthesizer-manual
- ManualsLib current Pro VS Mini page 75 CC table, used to cross-check CC 56 and the full V3.0 table: https://www.manualslib.com/manual/3430666/Behringer-Pro-Vs-Mini.html?page=75
- B&H current quick-start PDF search extract, used to cross-check CC 56 and the full V3.0 table where direct PDF download was Cloudflare-blocked locally: https://www.bhphotovideo.com/lit_files/1145286.pdf
- Pro VS Mini downloads page, listing firmware 2.0.2 and the current manual: https://www.provsmini.com/pro-vs-mini-downloads.html
- Pro VS Mini firmware 2.0.2 release notes, downloaded locally to `.context/provsmini-release-notes-2.0.2.pdf`: https://www.provsmini.com/downloads/Release-Notes_BE_0722-ABF_PRO%20VS%20MINI_v2-0-0_2025-01-10_Rev-0.pdf
- Pro VS Mini firmware 1.1.2 release notes, specifically the LFO/MIX ENV SysEx parsing fix: https://www.provsmini.com/downloads/Release-Notes_BE_0722-ABF_PRO%20VS%20MINI_v1.1.2
- Stage Engine Pro VS Mini editor page, downloaded locally to `.context/stage-engine.html`: https://stage-engine.com/
- Momo Pro VS Mini editor page: https://pro-vs-mini-editor.jimdofree.com/
- Gearspace Pro VS Mini thread, page 34, with captured Stage Engine mix SysEx and discussion of whole-patch writes: https://gearspace.com/board/electronic-music-instruments-and-electronic-music-production/1374240-behringer-pro-vs-99-prophet-vs-style-mini-synth-34.html
- Gearspace Pro VS Mini thread, page 36, noting no joystick/oscillator-volume entries in the MIDI implementation chart: https://gearspace.com/board/electronic-music-instruments-and-electronic-music-production/1374240-behringer-pro-vs-99-prophet-vs-style-mini-synth-36.html
- Electra One Pro VS Mini CC discussion, including firmware 2.0.2 value-scaling and front-panel MIDI output observations: https://forum.electra.one/t/pro-vs-mini-midi-cc-mess/3751
- Hispasonic Pro VS Mini user thread, with an unverified CC/NRPN joystick-control claim to test: https://www.hispasonic.com/foros/usuarios-behringer-mini-sintes/565638/pagina6
- LlamaMusic Pro VS Mini SysEx preset reader release notes, downloaded locally to `.context/provsmini-reader-release-notes.html`: https://llamamusic.com/behringer/PRO-VS_MINI_Reader_Release_Notes.html
- MIDI Guide Pro VS Mini CC/NRPN database, last updated March 31, 2026, useful as a secondary CC cross-check: https://midi.guide/d/behringer/pro-vs-mini/
- Reference app source tree: `~/Projects/nts3-midi-remapper` `origin/master` and `origin/synaptiko/macro-board-pad-mode`.
