# Ether Beat Lab

[Open Ether Beat Lab](https://tonyparker1964.github.io/Ether-Beat-Lab/)

A browser-based beat sequencer built for Ether's creative workflow.

- Generate and mutate rhythms across nine genres.
- Set tempo, swing, energy, complexity, key, scale and Journey stage.
- Edit step sequences, mute tracks and lock parts while randomizing.
- Play sixteen pads with the mouse or keyboard and record hits into patterns.
- Arrange patterns A–D into a song.
- Load custom audio samples.
- Export a ZIP containing a 44.1 kHz stereo `beat.wav` and `beat-markers.json` with tempo, chord, section, beat, bar, kick and snare timing for Ether Cut.

## Use

Open the live page in a modern browser, press Play, and explore the controls. Audio starts after a user gesture. The app runs in your browser; loaded samples are processed locally.

Patterns and samples are session-only in this version. Export your audio before closing or reloading the page; project save/load is not implemented.

## Hosting

GitHub Pages serves `index.html` from the `main` branch root. No build step or API key is required. Fonts load from Google Fonts, with system-font fallbacks.
