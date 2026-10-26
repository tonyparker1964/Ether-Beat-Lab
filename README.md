# Ether Beat Lab

[Open Ether Beat Lab](https://tonyparker1964.github.io/Ether-Beat-Lab/)

A browser-based beat maker built for Ether's creative workflow. Every sound is synthesized in the browser, so there are no sample libraries to download.

## Features

**Beats and randomizing**
- Nine genres: Boom Bap, Lo-fi, Trap, Drill, House, Afrobeats, Dembow, Drum & Bass and Phonk.
- One-press **⚄ Randomize** for genre, tempo, key, scale, chords, sounds and patterns, with locks for anything you want to keep.
- **Mutate**, per-track re-roll, new chord progressions, **Wildness** (borrows from other genres) and Undo.
- Tempo, swing, energy, complexity, key, scale (including Hijaz, Bhairav, Pelog and other world scales) and Zero's Journey stage.

**Sounds**
- 53 instruments, each genre with its own palette, plus the Ether families:
  - **Ether Voices:** Ether Choir, Silk Vox, Prism Vox.
  - **Ether Presets:** Ascend, Midnight Keys, Bloom, Twin Lead, Analog Dream, Fusion Keys, Tape Glow, Earth Pad.
  - **Ether Atmos:** Dune Drone, Fable Pad, Haze, Glass, Dark Metal, Flux Mallet, Toybox.
  - **Ether World:** tin whistle, fiddle, Celtic harp, sitar, bansuri, oud, kora, balafon, tres, gamelan.
- Two chord layers with a blend control, chord voicings, chord rhythms (hold, stabs, arpeggio, 16th sequence), a melody track and nine bass sounds.
- World percussion (bodhrán, tabla, darbuka, djembe, talking drum, bongos, gong), rise-and-hit FX, reverb and tempo-synced echo.
- A sound picker for every drum track: kick, snare, hat, open hat, percussion, tom, crash, FX and vocal chop, with a reset to the genre's kit.
- **⚄ Roll sounds** picks a new instrument combination.

**Making music**
- Twelve-track step sequencer with a volume slider, mute, lock and re-roll on every track. Tap a track name to hear its sound.
- Sixteen pads (Kit and Notes banks) played with the mouse or keyboard, with recording into patterns.
- Load your own audio samples onto drum pads; the vocal chop pad follows the chords. Sample pads have one-shot or hold play modes, trim, tune, attack, release, filter, reverse and choke.
- MPC-style **Sampler**: load or drop an audio file, see the waveform, and chop it by Threshold (transients), Regions, Beat grid or Manual. Drag chop lines, split, merge and snap to zero crossings. The 16 chops play on the **Chops** pad bank and record into the Chops track; **⚄ Flip it** makes a random pattern from them.
- **Pad FX** on every pad: reverb, delays, chorus, flanger, phaser, tremolo, auto-pan, filters, filter gate, overdrive, fuzz, bitcrusher, lo-fi, telephone, compressor, EQ and ring mod, each with amount and mix.
- **Note repeat** (1/8 to 1/32 and triplets), **Vintage** mode (MPC60, MPC3000, SP-1200) and a live **Filter sweep**.
- Stop, Space or Esc silences everything, including samples, reverb and echo tails.
- Patterns A–D chained into a song, including random arrangements.
- Export a ZIP containing a 44.1 kHz stereo `beat.wav` and `beat-markers.json` with tempo, sounds, chords, sections, beat, bar, kick and snare timing for Ether Cut.

## Use

Open the live page in a modern browser, press Play, and explore the controls. Audio starts after a user gesture. The app runs in your browser; loaded samples are processed locally.

Patterns and samples are session-only in this version. Export your audio before closing or reloading the page; project save/load is not implemented.

## Hosting

GitHub Pages serves `index.html` from the `main` branch root. No build step or API key is required. Fonts load from Google Fonts, with system-font fallbacks.
