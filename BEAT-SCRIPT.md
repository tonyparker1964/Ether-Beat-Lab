# Beat Script

A Beat Script is a plain-text description of a whole beat. Ask Claude for a beat ("dusty lo-fi at 82 with lazy hats and Rhodes"), paste the script into **AI Producer → Beat Script** in Beat Lab (or open the .txt file), and press **Load script**. Undo takes it back. A new, untitled project takes the script's title.

Lines that start with `#` or `//` are notes. Capital letters don't matter except in step patterns (`X` vs `x`). Lines Beat Lab can't understand are skipped and listed with their line numbers; everything else still loads.

## Settings

| Line | Meaning |
|---|---|
| `title Late Night Ether` | Name shown when it loads; also the file name for Save as .txt |
| `genre lofi` | Boom Bap, Lo-fi, Trap, Drill, House, Afrobeats, Dembow, Drum & Bass, Phonk. Read first, so `sound` lines can change its defaults |
| `tempo 82` | 60–180 BPM |
| `swing 24` | 0–60 |
| `key A minor` | Any note (`C#`, `Bb`, `F♯`) plus major, minor, dorian, phrygian, lydian, mixolydian, harmonic minor, hijaz, bhairav, hungarian minor, pelog |
| `energy 60` `complexity 40` `wildness 20` | 0–100 |
| `space 35` `echo 15` | Reverb and echo, 0–100 |
| `vintage mpc60` | off, MPC60, MPC3000, SP-1200 |
| `steps 32` | 16 or 32 steps per pattern. Left out, it's 32 when any step line is longer than 16, otherwise 16 |

## Sounds

Names are matched loosely, so "rhodes", "Rhodes" and "Rhodes piano" all find Rhodes.

```
sound chords  Rhodes + Vibraphone 25%   # layer A + layer B, blend
sound voicing 7ths                      # Triads, 7ths, 9ths, Sus2, Sus4, Power, Open spread
sound rhythm  Stabs                     # Hold, Stabs, Arpeggio, Sequence
sound melody  Vibraphone
sound bass    808                       # Sub, 808, Distorted 808, Upright, Electric, Synth, Pluck, Acid, Reese
sound kick    Soft lo-fi                # 808 boom, Punchy, Deep house, Boom bap thump, Distorted, Soft lo-fi
sound snare   Lo-fi snare               # Acoustic, Clap, Trap, Lo-fi, Finger snap, Rimshot, Gated
sound hat     Lo-fi hat                 # Closed, 808, Lo-fi, Shaker, Tambourine
sound ohat    Open hat                  # Open, 808 open, Ride, Sizzle
sound tom     Congas                    # Tom, Congas, 808 tom, Floor tom, Electronic tom
sound crash   Splash                    # Crash, Splash, China, Swell hit, Gong
sound perc    Shaker                    # Rim, Shaker, Conga, Cowbell, Timbales, Bodhrán, Tabla, Darbuka, Djembe, Talking drum, Bongos, Gong
sound vox     Vox ooh                   # Vox ahh, Vox ooh, Vox ee, Hey shout, Choir chop
sound fx      Riser                     # Impact, Riser, Downlifter, Sub drop, Reverse swell
```

### Your Native Instruments sounds and plug-ins (Mac app)

```
sound chords  "Rhodes Classic · Sunset Expansion"   # an NI instrument: name · expansion, as in the NI Library
sound chords2 Synth pad 30%                          # the second chord layer and its blend
sound bass    "Deep Sub · Sunset Expansion"
kit "Sunset Expansion"                               # an NI drum kit on the kit pads
sample snare  "Snare Dusty"                          # one NI drum sound onto a kit pad (after kit, it replaces that pad)
plugin melody "Kontakt 8"                            # an Audio Unit plug-in on chords, chords2, melody or bass
```

**Your NI sounds by themselves.** With **Use my NI sounds** ticked (beside Load script; it's on unless you untick it), every sound a script asks for from Beat Lab's own list is swapped for the closest one on your NI drive. Beat Lab looks for the same kind of instrument, the most words in common ("Dark piano" finds a dark piano), the drum kit's expansion, and instruments with the most recorded notes. A drum kit that suits the genre, the title and the `#` notes goes on the kit pads. The report under the script lists what it picked. Anything the script names itself (an NI instrument, `kit`, `plugin`) is kept as written. Put `ni off` in a script to keep Beat Lab's own sounds for that script.

`kit synth` goes back to Beat Lab's own drums. A plug-in loads with its default sound: open its window (🎛 Plug-in window) to pick the Kontakt instrument or preset, and that choice is saved with your project, not in the script.

Instruments include piano, Rhodes, soft piano, dark piano, organ, music box, kalimba, vibraphone, marimba, synth bells, steel drum, electric and jazz guitar, harp, synth pluck, synth pad, strings, choir, voice ooh, violin, cello, sax, trumpet, flute, synth brass, synth lead, the Ether families (Ether Choir, Silk Vox, Prism Vox, Ascend, Midnight Keys, Bloom, Twin Lead, Analog Dream, Fusion Keys, Tape Glow, Earth Pad, Dune Drone, Fable Pad, Haze, Glass, Dark Metal, Flux Mallet, Toybox) and world instruments (tin whistle, fiddle, sitar, bansuri, oud, kora, balafon, tres, gamelan).

## Patterns

Up to four patterns, A to D. Each is a 4-bar loop played over the 4 chords. The steps are one bar of 16ths (16 steps) or two bars (32 steps), repeated.

```
pattern A
progression 1 6 4 5      # scale-degree chords, or roman numerals: i VI iv V
kick    X... ..x. ..x. ....
snare   .... X... .... X..x
hat     x.x. x.xr x.x. x.x.
bass    X... ..5. ..x. ...8
melody  .... 5.3. .... 2...
chords  X... .... X... ....

pattern B = A            # start B as a copy of A, then change it
crash   X... .... .... ....
mutate 15%               # change about 15% of the steps
reroll hat               # new hat part in the genre's style
clear perc

song A A B A             # play the patterns in this order (up to 32)
```

**Steps:** `X` accent, `x` soft hit, `.` rest. Spaces and `|` are ignored, so group by 4 for readability. Shorter lines repeat to fill the pattern (16 steps fill 32).
- `r` on the hat track is a triplet roll.
- On **bass** and **melody**, numbers 1–9 are notes: the scale degree counted from the current chord (1 root, 3 third, 5 fifth, 8 octave). `X`/`x` play the root.
- On **vox**, 1–4 pick the chop's pitch.
- On **chops** (your Sampler chops), `1`–`9` then `a`–`g` pick chops 1–16.

**Piano-roll notes** for melody, bass or chords: `notes melody 1:F4:2 3:Ab4:2:0.8 9:C5:4`. Each note is *step:note:length[:velocity]*. Steps count 16ths from 1 to 64 across the pattern's 4 bars, length is in 16ths, velocity is 0–1 (or 1–127). Notes are named like Logic and NI (C3 = middle C), or written as MIDI numbers. That track then plays exactly these notes, at any pitch, instead of following the chords.

**Tracks:** kick, snare (or clap), hat, ohat, perc, tom, crash, fx, vox, chops, melody, bass, chords.

A script with patterns describes the whole beat: patterns it doesn't mention are cleared, and it plays as a song only when there is a `song` line.

## Mix

```
volume hat 80            # 0–150
mute fx
effect snare reverb 40% 35%   # pad FX, amount %, mix %
```

Pad FX: reverb, delay, ping-pong delay, chorus, flanger, phaser, tremolo, auto-pan, low-pass filter, high-pass filter, auto filter, filter gate, overdrive, fuzz, bitcrusher, lo-fi, telephone, compressor, bass boost, air / bright, ring mod.

**Copy this beat as a script** writes whatever is in Beat Lab out in this format, so any beat can be saved, shared and edited.
