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
- **16 or 32 steps** per pattern (buttons next to Copy to next and Clear). At 32 steps each pattern is two bars; switching up copies the first bar into the second with small changes (a few hats, percussion and melody notes, a snare fill at the end), switching back keeps the first bar, and Undo brings the second bar back.
- Twelve-track step sequencer with a volume slider, mute, lock and re-roll on every track. Tap a track name to hear its sound.
- Sixteen pads (Kit and Notes banks) played with the mouse or keyboard, with recording into patterns.
- Load your own audio samples onto drum pads; the vocal chop pad follows the chords. Sample pads have one-shot or hold play modes, trim, tune, attack, release, filter, reverse and choke.
- MPC-style **Sampler**: load or drop an audio file, see the waveform, and chop it by Threshold (transients), Regions, Beat grid or Manual. Drag chop lines, split, merge and snap to zero crossings. The 16 chops play on the **Chops** pad bank and record into the Chops track; **⚄ Flip it** makes a random pattern from them.
- **Pad FX** on every pad: reverb, delays, chorus, flanger, phaser, tremolo, auto-pan, filters, filter gate, overdrive, fuzz, bitcrusher, lo-fi, telephone, compressor, EQ and ring mod, each with amount and mix.
- **Note repeat** (1/8 to 1/32 and triplets), **Vintage** mode (MPC60, MPC3000, SP-1200) and a live **Filter sweep**.
- Stop, Space or Esc silences everything, including samples, reverb and echo tails.
- Patterns A–D chained into a song, including random arrangements.
- Export a ZIP containing a 44.1 kHz stereo `beat.wav` and `beat-markers.json` with tempo, sounds, chords, sections, beat, bar, kick and snare timing for Ether Cut.

## Studio view and visualizer

On a wide window (and always in the Mac app) Beat Lab opens in **Studio view**, a full-window workspace: a control bar with transport and a display (bar and beat, tempo, key, genre, what's playing), a **library** on the left (AI Producer, Native Instruments, beat settings), the **tracks** in the middle, and **editors** along the bottom (Pads, Sounds, Sampler, Visualizer, Export). The ◧ and ⬓ buttons show or hide the library and editors, the line above the editors drags to resize them, and **Classic view** goes back to the single page. Your layout is remembered.

The **Visualizer** has five scenes around the Zero Point, a luminous diamond that pulses on every kick (taken straight from the sequencer, so it lands exactly on the beat): **Frequency Portal**, **Cymatic Geometry**, **Quantum Spectrum**, **Cosmic Vortex** and **Liquid Frequency**. Sensitivity, Motion, Particles, Glow, Hue shift and Reduce motion tune the look; Reset restores it. ⛶ fills the screen, where 1–5 change the scene and F or Esc leaves.

## Mac app with your Native Instruments sounds

The Mac app is the same Beat Lab in its own window, plus two things the web page can't do:

- **Native Instruments library.** Add your NI drive (or folders) and Beat Lab scans it once. Drum one-shots from Maschine expansions and Battery kits are sorted into kick, snare, clap, hats, percussion, toms and cymbals by kit; melodic one-shots (keys, pads, synths, plucks, bells, strings, brass, guitars, bass) become playable instruments, tuned from the note in each file name. Everything is sorted into the **Sounds & Kits** menus. Drum menus: **Kick**; **Snare & clap** (snares, then claps, rims and snaps); **Hi-hat** (closed hats and shakers); **Open hat & ride**; **Percussion**; **Toms**; **Cymbals** (crashes and rides); **Vocal chop** (in the Mac app a natural voice: pick a word, Ahh, Ooh, Oh, Hey, Yeah, Uh, La, Hmm, Whoa or your own, and a **Chop singer** from the voices built into macOS; it's tuned so it sings the chord notes in key. Beat Lab's synth voices and your NI vocal one-shots are in the same menu). For more and better voices, add them in System Settings → Accessibility → Spoken Content → System voice → Manage Voices; Premium and Enhanced voices are marked ★. Each menu shows Beat Lab's own sounds, then one group per NI kit. Instrument menus use one set of categories for Beat Lab and NI sounds alike: Pianos & Keys, Organs, Pads & Atmospheres, Strings, Guitars, Synths, Plucks, Bells & Mallets, Brass & Woodwinds, Voices & Choirs, Synth Leads and World Instruments, each with Beat Lab's sounds followed by your NI sounds; the Melody menu starts with leads and bells, the Chords menus with keys and pads. Sounds made for Ether are marked ✦. **Favorites:** press the ♡ beside any menu (drum kit sounds, instruments, the NI kit picker) or beside any sound in Browse and assign. Favorites appear in a ♥ Favorites group at the top of every menu that offers them (an instrument you love shows up in Chords, Chords layer 2 and Melody), and **♥ Favorites** in Browse and assign lists just those. They're saved on your Mac, and the **♥ Favorites** list on the right side of Studio view (the ♥ button in the top bar shows or hides it) keeps them all in one place, grouped into kits, kicks, snares, hats, percussion, toms, cymbals, vocal chops, instruments and bass: ▶ to listen, **Use** to put one to work, ♥ to remove it. Click any Sounds menu and press **↑** or **↓** to step through the sounds one at a time and hear each, without opening the list. After updating the app, press **Rescan** once so your library gets the new sound types. Pick a **drum kit**, press **⚄ Kit for genre**, or **browse**, listen (▶) and put any sound on any drum track or on Chords A/B, Melody or Bass with **Use on…**. Everything plays in the step sequencer, on the pads and in the export. Kontakt libraries use NI's locked formats, so they're counted and skipped. With **Roll and Randomize use NI sounds** on, ⚄ Roll sounds and ⚄ Randomize pick from your library too.
- **AI Producer.** Type a vibe ("late-night jazzy boom bap, warm and dusty") and press **Produce**. It sets the genre, tempo, key, scale, swing, energy and complexity, and chooses your NI kit and instruments. It uses the model loaded in **LM Studio** on your Mac: no API key, and nothing leaves your computer. When LM Studio is off it falls back to the built-in producer, which reads genre, mood and speed words. The AI Producer's built-in mode also works on the web page.

Sound files are read straight from your drive and played inside the app; the app only serves files its own scan found.

**Install:** in Terminal, in this folder, run `./install-mac-app.sh`. It builds the app and puts **Ether Beat Lab.app** in Applications. It needs Xcode or the Command Line Tools (`xcode-select --install`). Run it again after pulling updates. Exports are saved to your Downloads folder.

## Use

Open the live page in a modern browser, press Play, and explore the controls. Audio starts after a user gesture. The app runs in your browser; loaded samples are processed locally.

Patterns and samples are session-only in this version. Export your audio before closing or reloading the page; project save/load is not implemented.

## Hosting

GitHub Pages serves `index.html` from the `main` branch root. No build step or API key is required. Fonts load from Google Fonts, with system-font fallbacks.
