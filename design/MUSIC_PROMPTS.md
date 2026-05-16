# Music Prompts — Mira-Thal Soundtrack (Suno)

The full music portfolio for Game One, written as Suno prompts. **The score is
instrumental, epic-film-orchestral**, in the tradition of Howard Shore's *Lord
of the Rings* and Jeremy Soule's *Skyrim* and *Morrowind*. No solo voices, no
sung lyrics, no spoken word anywhere. The only vocal element permitted is a
**light massed choir** — and only on the named high-energy battle / climax
cues listed in §3. Every track is a **style prompt + a lyrics/structure
prompt** pair (the structure box drives form and length even when there is no
text).

> Cross-reference: `design/AUDIO_DESIGN.md` — where music plays, transition
> rules, the "music knows where it is, not what you're doing" philosophy, and
> the bus layout. This doc is the **content**; that doc is the **system**.

---

## 1. Two problems this doc solves

**Problem A — sameness.** The old portfolio (`Main Theme`, `World Map _
Travel`, `Sea _ Sailing`) blurred together because every prompt opened with the
same words, reached for the same leads (legato strings, four horns, choir),
sat in the same modes (Aeolian/Dorian) and the same 72–96 BPM band, and used
the same arc. Suno renders the prompt's center of gravity; identical centers
produce one long cue. Shore did not score Rohan, Gondor, Moria and Mordor the
same way — each got its own instrument, mode, meter and recording space, then a
shared motivic spine. This doc enforces that with a variation matrix (§2) plus
cultural palettes (§4) and a leitmotif system (§3).

**Problem B — length.** Tracks were rendering short (some under a minute).
Every cue here targets **3:00–5:00 minimum**. The fix is structural: each
structure box has **6–9 developed sections** with restatements and variation,
and every style box ends with an explicit "full-length, developed,
through-composed, no early fade" instruction. See §6 for the Suno length
workflow (sections + extend + two-pass stitching for the 5:00 set-pieces).

---

## 2. The nine variation levers

Every track gets deliberately different values. The §5 table shows the grid.
Rule: **no two tracks in the same category may share more than three lever
values.**

1. **Tonal center & mode** — rotate hard: Aeolian, Dorian, Phrygian, Lydian,
   Mixolydian, octatonic/whole-tone for the corrupt, Ionian for joy, free
   atonal drone for dead places. Never default to D Aeolian.
2. **Tempo** — explicit BPM, spread 40 (funeral/drone) to 168 (charge). Never
   cluster three tracks in 72–96.
3. **Lead voice** — the single most distinctive *instrument*, named first in
   the style box. Rotate across the palette list in §4.
4. **Ensemble density** — solo instrument / chamber trio / small consort /
   string orchestra / full orchestra / percussion-only / drone-only.
5. **Percussion family** — none / heartbeat frame drum / hand percussion /
   military field drums & timpani / taiko & dhol war battery / anvils &
   stomps / metallic ritual / arrhythmic stone.
6. **Vocal treatment** — **instrumental (default for ~45 of 59)** / **light
   massed choir (battle & high-energy cues ONLY — the §3 list)**. Never a solo
   voice, never sung verses, never spoken word.
7. **Recording space** — dry chamber / intimate close / open field / great
   stone hall / cathedral / cavern with long slap / storm-air no reverb /
   tiny "music box".
8. **Structural arc** — vary section count and order; 6–9 sections so the cue
   reaches length. Some are a single sustained mood (ambient beds, camp, the
   Archive) developed over time; some are through-composed set-pieces.
9. **Cultural palette** — fixed sonic identity per region/faction (§4) decides
   levers 3–6 before mood does.

---

## 3. Leitmotif system — what keeps the variety coherent

Five recurring instrumental cells, small (3–7 notes) so Suno can carry them
across very different arrangements. The structure box names the motif in plain
language; to lock pitch identity across tracks, seed from a clean stem (§6).

| Motif | Whose | Shape | Mode/feel |
|---|---|---|---|
| **The Endurance cell** | Roland, the Iron Chalice, humankind | rising step, falling third, held | Aeolian, noble, stepwise |
| **The Song / Eighth Star** | Aelorin, the Aeluvain | high, slow, open — a phrase that stops one note short (the missing eighth) | Lydian, weightless |
| **The Hollowing** | Mordvar, the Sundered Crown | the Song inverted and emptied — descending open fifths that never close | octatonic/whole-tone, airless |
| **The Crown** | the seven pieces | a seven-note cell, each note a different timbre; heard fractured, reassembling | chromatic, brittle |
| **The Hearth** | companions, home, rest | a warm four-note folk fragment, the only motif that ever sounds *complete* | Mixolydian, plain |

**The choir is a color, not a voice.** Choir appears **only** on these 14
high-energy cues, always massed (full SATB or low men's section), never solo,
used like a percussion/brass section — texture and impact, not melody:

> **02, 24, 33, 34, 38, 40, 41, 42, 43, 44, 45, 47, 48, 57.**

On the human/heroic side the choir chants Latin as a rhythmic war-cry:
*Lux per umbram / ferrum per ignem / sanguis per saecula / terra nos vocat*.
On Mordvar's side it chants the **mirror** of that text:
*Nihil per nihil / cor per inane / nemo per saecula / nihil nos tenet*. Where
a non-Latin texture is wanted (the Shroud storm, the Ashlord) the choir is
**wordless massed vowels only**. Every other track in the score has **no
choir at all** — its identity comes from instrumentation.

---

## 4. Cultural sonic palettes (the Shore method, instrumental)

Decide the palette first; it pre-sets levers 3–6 so two cultures can't
converge.

| Culture / place | Lead instruments | Mode | Percussion | Choir? | Space |
|---|---|---|---|---|---|
| **Human heartland** (Eldermark, Aldenholt, the road) | French horn, solo cello, oboe | Aeolian/Dorian, Mixolydian heroic | frame drum, timpani | battle cues only | open field / cathedral |
| **Iron Chalice** (Brightwatch, the chapel, Roland) | low strings, muted trumpet, lone war horn, organ | Aeolian, austere | one deep field drum | last-stand cues only | dry stone |
| **Aelorin** (Greatwood, Lirien-Thal, the Aeluvain) | glass harmonica, harp, high divisi strings, celesta | Lydian, weightless | none / finger crotales | no | shimmering long reverb |
| **Dwarven** (Karaz-Dûn, the Underway, the holds) | contrabassoon, low brass, hammered dulcimer, **anvil** | Dorian/Phrygian | anvils, boot-stomps, 6/8 toms | siege/battle only (wordless low massed) | great stone hall |
| **Naergrim** (Mor-Vethrin, Weeping Wood) | detuned/prepared strings, bowed metal, contrabass clarinet | cluster / no center | arrhythmic stone, struck chains | no | airless, close, wrong |
| **Mordvar / Ashen Hand** (Sundered Isles, the Hollowing) | dissonant low brass, contrabassoon, war battery | octatonic/whole-tone | taiko + dhol war battery | yes — massed curse-chant | huge, brutal |
| **Sailor's Guild / sea** | concertina, fiddle, low whistle, accordion | Dorian/Mixolydian, rolling 6/8 | hand drum, deck-stomp, rope creak | no | salt-air, medium room |
| **Tavern / folk** | fiddle, lute, recorder, hurdy-gurdy, hand drum | Mixolydian/Dorian, major | tabor, foot, claps | no | small warm room |
| **Dead places** (Sorrowmarsh, Ashfields) | bowed psaltery, cor anglais, breath-tone winds, bowed metal | drone, no functional harmony | none / one far struck bowl | no | vast empty, ghost slap |

---

## 5. Track inventory (59)

Naming follows the existing convention (`Main Theme`, `Sea _ Sailing` — title
case, ` _ ` for sub-category; `.ogg` once converted per `AUDIO_DESIGN.md`).
**All lengths are 3:00 minimum.** "Choir" = light massed choir on a battle/
high-energy cue; everything else is fully instrumental.

| # | Title | Category | Palette | Mode | BPM | Lead | Choir | Len |
|---|---|---|---|---|---|---|---|---|
| 01 | Prelude _ The Eighth Star | Identity | Aelorin | Lydian | 54 | glass harmonica | — | 3:00 |
| 02 | Main Title _ Mira-Thal | Identity | Human | Mixolydian→Aeolian | 84 | French horn | battle | 4:30 |
| 03 | End Credits _ The Long Twilight | Identity | suite | modulating | 76 | solo cello | — | 5:00 |
| 04 | Open Road _ The Central Plains | Exploration | Human | Mixolydian | 92 | oboe | — | 4:00 |
| 05 | The Greatwood _ Under Old Leaves | Exploration | Aelorin | Lydian | 60 | harp + high strings | — | 4:30 |
| 06 | The Spine _ Stone and Sky | Exploration | Dwarven-adj. | Dorian | 66 | horn + low strings | — | 4:00 |
| 07 | The Underway _ Beneath the Mountain | Exploration | Dwarven | Phrygian | 54 | contrabassoon | — | 4:30 |
| 08 | The Ashfields _ Grey Soil | Exploration | Dead | drone | 44 | cor anglais | — | 4:00 |
| 09 | The Western Coast _ Caer Drowned | Exploration | Sea/dead | Aeolian | 58 | low whistle | — | 4:00 |
| 10 | The Copper Isles _ Salt and Sun | Exploration | Sailor | Mixolydian | 104 | fiddle | — | 4:00 |
| 11 | The Sorrowmarsh _ The Mud Remembers | Exploration | Dead | atonal drone | 40 | bowed psaltery | — | 4:00 |
| 12 | The Weeping Wood _ Watched | Exploration | Naergrim | cluster | 48 | prepared strings | — | 4:00 |
| 13 | Aldenholt _ Market and Bell | Settlement | Human | Mixolydian | 100 | lute + recorder | — | 4:00 |
| 14 | Caer Brannoch _ The Cliff City | Settlement | Human/sea | Dorian | 72 | solo cello + harp | — | 4:00 |
| 15 | Vosskar _ Iron and Listening | Settlement | Iron Chalice-adj. | Aeolian | 64 | muted trumpet | — | 4:00 |
| 16 | Solgrade _ The Unwalled City | Settlement | Tavern/cosmo | Dorian | 96 | hurdy-gurdy | — | 4:00 |
| 17 | Lirien-Thal _ The Silverwood | Settlement | Aelorin | Lydian | 52 | glass harmonica | — | 4:30 |
| 18 | Karaz-Dûn _ Forges Never Cold | Settlement | Dwarven | Dorian | 78 (6/8) | hammered dulcimer | — | 4:00 |
| 19 | Mor-Vethrin _ The Obsidian City | Settlement | Naergrim | no center | 46 | contrabass clarinet | — | 4:00 |
| 20 | Brightwatch _ The Frontier Garrison | Settlement | Iron Chalice | Aeolian | 70 | lone war horn | — | 4:00 |
| 21 | The Archive _ Dust and Lamplight | Interior | Human (near-non-music) | static modal | 50 | bowed vibraphone | — | 5:00 |
| 22 | The Iron Chalice _ Chapel of Endurance | Sacred | Iron Chalice | Aeolian | 56 | organ + low strings | — | 4:00 |
| 23 | The Aeluvain _ The Song With an Edge | Sacred | Aelorin | Lydian (unresolved) | 58 | solo violin harmonics | — | 4:00 |
| 24 | The Crown Assembled _ Seven Metals | Sacred | mixed | chromatic | 64 | seven timbres | battle | 4:00 |
| 25 | Tavern _ The Limping Reel | Tavern | Folk | Mixolydian | 132 | fiddle | — | 4:00 |
| 26 | The Widow's Lament _ A Quiet Room | Tavern | Folk | Dorian | 68 | lute + viola | — | 4:00 |
| 27 | The Deep Cups _ A Dwarven Dance | Tavern | Dwarven | Dorian | 88 (6/8) | dulcimer + anvil | — | 4:00 |
| 28 | The Dockside _ Salt and Strings | Tavern | Sailor | Mixolydian | 120 | concertina | — | 4:00 |
| 29 | The Hearth _ An Aelorin Air | Tavern | Aelorin | Lydian | 56 | harp + celesta | — | 4:00 |
| 30 | The Capstan _ Heave Her Round | Sea | Sailor | Dorian | 96 | hand drum + low whistle | — | 4:00 |
| 31 | Leaving Port _ The Tide Turns | Sea | Sailor | Mixolydian | 84 (6/8) | fiddle + low whistle | — | 4:00 |
| 32 | At Sea _ Open Water | Sea | Sailor | Dorian | 70 | accordion + cello | — | 4:30 |
| 33 | The Shroud _ The Storm That Never Ends | Sea | Mordvar-adj. | octatonic | 72→132 | full orch + battery | wordless | 4:00 |
| 34 | The Eastern Crossing _ Into the Storm | Sea | mixed (epic) | modulating | 80 | full orch | battle | 5:00 |
| 35 | Campfire _ The Sound of Rest | Camp | Folk/intimate | Mixolydian | 60 | solo lute-guitar | — | 4:00 |
| 36 | Night Rest _ Sleeping Under Stars | Camp | intimate | Lydian | 48 | music box + harp | — | 4:30 |
| 37 | The Quiet After _ Wounds and Breath | Camp | Iron Chalice-adj. | Aeolian | 52 | solo cello | — | 4:00 |
| 38 | Enemies Gathering Strength _ The Muster of the Hand | War | Mordvar | octatonic | 60→88 | low brass | curse | 4:00 |
| 39 | A Minor Skirmish _ Blades in the Brush | War | Iron Chalice-adj. | Phrygian | 116 | low strings ostinato | — | 3:30 |
| 40 | Charge Into Battle _ Sound the Horns | War | Human | Mixolydian | 152 | war horns + trumpets | Latin | 4:00 |
| 41 | The Large Battle _ The Field of Iron | War | mixed (suite) | Aeolian/octatonic | 96→168 | full orch + battery | both | 5:00 |
| 42 | The Siege _ Hold the Walls | War | Dwarven | Phrygian | 100 | anvils + low brass | wordless low | 4:30 |
| 43 | Vaeroth the Pale _ The Hierarch | Boss | Mordvar | whole-tone | 108 | contrabassoon | curse | 4:00 |
| 44 | The Ashlord _ The Mask of Caerith | Boss | Naergrim/Aelorin | Lydian→cluster | 92 | corrupted glass harmonica | wordless | 4:30 |
| 45 | Mordvar _ The Hollowing | Boss | Mordvar | inverted Song | 50 | dissonant low brass | curse | 4:30 |
| 46 | The Fighting Retreat _ The Ashfields | War | Iron Chalice | Aeolian | 116 | war horn + strings | — | 4:00 |
| 47 | The Last Stand _ No Ground Behind | War | Iron Chalice/Human | Aeolian→Mixolydian | 84→144 | full orch | Latin | 4:30 |
| 48 | The Muster of the Alliance _ Many Banners | War | mixed (suite) | Mixolydian | 100 | rotating culture leads | layered | 5:00 |
| 49 | The Vigil _ The Night Before | Cinematic | Iron Chalice | Aeolian | 52 | solo cello + low whistle | — | 4:00 |
| 50 | Heroes Reunited _ The Fellowship Whole | Cinematic | mixed (motif weave) | Mixolydian | 76 | leitmotif weave | — | 4:00 |
| 51 | A Marriage _ Two Hands Bound | Cinematic | Folk/Human | Ionian (major) | 88 | harp + oboe + fiddle | — | 4:00 |
| 52 | Grief _ What the Archive Lost | Cinematic | Human | Aeolian | 46 | solo viola | — | 4:00 |
| 53 | Noble Sacrifice _ The Blow at the Marsh | Cinematic | mixed | Aeolian→Lydian | 60 | cello → full strings | — | 4:30 |
| 54 | Betrayal _ The Mole Revealed | Cinematic | Naergrim-adj. | minor→cluster | 64 | low strings + clock tick | — | 3:30 |
| 55 | Hope Rekindled _ The Turn | Cinematic | Human | Aeolian→Mixolydian | 72→104 | solo oboe → full orch | — | 4:00 |
| 56 | Epilogue _ The Road Home | Cinematic | Folk/Human | Mixolydian | 80 | solo cello + oboe | — | 4:00 |
| 57 | The Return _ Released | Ending | Aelorin/Human | Lydian resolving | 58 | full strings | wordless swell | 5:00 |
| 58 | The Hold _ Carried Forever | Ending | Iron Chalice | Aeolian, unresolving | 54 | solo cello + low strings | — | 5:00 |
| 59 | The Fracture _ The Price of Refusal | Ending | Mordvar-adj. | shattered, no cadence | 60 | broken orchestra | — | 5:00 |

Existing on disk → **02 replaces `Main Theme`**, **32 / 30 supersede
`Sea _ Sailing`**. `World Map _ Travel` already exists — regenerate from #04's
recipe if a replacement is wanted.

---

## 6. How to use these in Suno

**Style box.** ~350–500 characters. Suno weights the *first clause* hardest, so
each prompt below leads with its single most distinctive element (lead
instrument or mode/meter), never the generic "cinematic medieval fantasy
orchestral." Always state an explicit BPM and mode.

**Length.** Suno often stops short on thin prompts. Three things fix it,
applied to every prompt here: (1) the structure box has **6–9 developed
sections** with explicit restatements/variations so there's enough material;
(2) every style box ends with *"full-length cue, developed and through-
composed, sustain and vary the themes, no early fade, long outro"*; (3) for
the **5:00 set-pieces (03, 21, 34, 41, 48, 57, 58, 59)** generate in two
passes and stitch, or use Suno **Extend** on the best take until it reaches
length, then add a manual fade. Treat the §5 lengths as floors.

**Instrumental enforcement.** Every track uses the `[Instrumental …]` section
tag and carries *"no solo vocals, no sung lyrics, no spoken word, no lead
voice"* in its negative list. The 14 choir cues add a single
`[Choir - massed, light, …]` section and otherwise stay instrumental; all
other tracks add *"no choir"* as well.

**Seeding motifs.** Generate the clean motif statements first (22, 23, 45, 35,
02), then use Suno's audio-upload / cover / persona with those stems as the
seed for tracks that quote them.

**Batch / audition workflow.**
1. Motif anchors: **02, 22, 23, 45, 35**.
2. One per culture: **04, 05, 18, 12, 30, 25, 38** — listen back-to-back; if
   any two blur, push levers 1–3 apart and re-roll those two.
3. Range extremes: **36 (quietest), 40 (loudest), 52 (most intimate),
   41 (biggest)**.
4. Then category order; audition each new track against the previous one in
   its category before accepting the take.
5. Render best take to stereo 44.1 kHz, convert to `.ogg`, drop in
   `assets/audio/music/` with the §5 title.

---

## 7. The prompts

Each entry: **filename → lever key → style prompt → structure prompt.** Copy
the two blocks straight into Suno's two boxes.

---

### A. Identity & Frame

---

**01 — Prelude _ The Eighth Star**
*Lever key: Aelorin · Lydian · 54 BPM · glass harmonica · instrumental · 3:00*

Style prompt:
```
Solo glass harmonica opening a fragile, weightless Lydian theme — the world's first music heard from far away — answered by harp and a slow bed of high divisi strings and celesta. The Song motif forms and reaches but never quite resolves. 54 BPM, free time, no strong pulse. Vast crystalline cathedral reverb, soft attacks. Epic-fantasy prelude in the tradition of Howard Shore's Lothlórien and Jeremy Soule's Skyrim. Full-length cue, developed and through-composed, sustain and vary the theme, no early fade, long outro. No percussion, no brass, no choir, no solo vocals, no sung lyrics, no spoken word, no synth, no drums, no electric guitar, no EDM, no melody resolution.
```
Structure prompt:
```
[Instrumental Intro - solo glass harmonica, one rising Lydian phrase, no pulse]
[Instrumental A - harp enters, the Song motif begins to form, weightless]
[Instrumental B - high divisi strings swell underneath, celesta colour, the phrase widens]
[Instrumental Development - the motif is varied and inverted gently, still unresolved]
[Instrumental Peak - strings and harmonica together at their fullest, reaching upward]
[Instrumental Hush - back to solo glass harmonica and one held string note]
[Instrumental Outro - the Song deliberately left one note short, very long shimmering fade]
```

---

**02 — Main Title _ Mira-Thal** *[replaces existing `Main Theme`]*
*Lever key: Human · Mixolydian→Aeolian · 84 BPM · French horn · light Latin choir (climax) · 4:30*

Style prompt:
```
Four French horns in open fifths stating a noble Mixolydian theme — the Endurance cell — answered by warm solo cello and sweeping legato strings, frame-drum heartbeat, distant wooden flute. A light massed Latin choir enters only at the battle climax as a rhythmic war-cry, never solo. Modal, never harmonic minor. 84 BPM, 4/4, briefly 6/8 at the cello bridge. Cathedral reverb, pianissimo to fortissimo, epic-film quality in the lineage of Howard Shore's LOTR and Jeremy Soule's Skyrim and Morrowind. Full-length cue, developed and through-composed, restate and vary the theme, no early fade, long outro. No solo vocals, no sung verses, no spoken word, no drum kit, no electric guitar, no synth, no EDM, no autotune.
```
Structure prompt:
```
[Instrumental Intro - quiet, solo wooden flute over distant frame-drum heartbeat]
[Instrumental Build - frame drums set 4/4, low strings ostinato in open fifths, horns enter on pedal D]
[Instrumental Main Theme - four French horns state the heroic Endurance cell, strings answer]
[Instrumental Bridge - solo cello variation in 6/8, sparse harp, intimate and melancholic]
[Instrumental Solo - heroic solo violin restates the Endurance cell an octave higher]
[Choir - massed Latin war-cry, light, no solo, joining the building strings]

Lux per umbram
ferrum per ignem
sanguis per saecula
terra nos vocat

[Instrumental Battle Climax - 108 BPM, taiko, low-string eighth-note ostinato, trombones, choir massed underneath]
[Instrumental Lift - brief D major, trumpets restate the Endurance cell in triumph]
[Instrumental Outro - solo cello, three-note descending Endurance tag, frame-drum heartbeat, long fade]
```

---

**03 — End Credits _ The Long Twilight**
*Lever key: suite · modulating · 76 BPM · solo cello · instrumental · 5:00*

Style prompt:
```
A through-composed end-credits suite that visits every culture's instrumental colour in turn: opens solo cello (Endurance, Aeolian), passes to Aelorin glass harmonica and harp (Lydian), to a dwarven 6/8 hall with hammered dulcimer and anvil, to a grand brass-and-strings anthem, settling back to solo cello. 76 BPM, modulating between sections, 4/4 and 6/8. Full orchestra, cathedral reverb, epic-film quality, Shore-style "all themes return," Soule-style warmth. Full-length 5-minute suite, developed and through-composed, no early fade, long outro. No choir, no solo vocals, no sung lyrics, no spoken word, no drum kit, no synth, no electric guitar, no EDM, no autotune.
```
Structure prompt:
```
[Instrumental Intro - solo cello, the full Endurance theme, unaccompanied]
[Instrumental Section A - strings swell under it, frame drum, French horns answer]
[Instrumental Section B - Aelorin colour: harp, glass harmonica, celesta, Lydian, the Song motif]
[Instrumental Section C - dwarven 6/8, hammered dulcimer, anvil, low brass]
[Instrumental Section D - full orchestral anthem, the Endurance cell fortissimo on brass and strings]
[Instrumental Section E - a quiet reprise of the Hearth fragment on solo oboe]
[Instrumental Coda - everything falls away to the solo cello, the Endurance tag, very long fade]
```

---

### B. Exploration

---

**04 — Open Road _ The Central Plains**
*Lever key: Human · Mixolydian · 92 BPM · oboe · instrumental · 4:00*

Style prompt:
```
Solo oboe carrying a walking Mixolydian melody over light pizzicato strings and a soft frame drum — open, breathing, hopeful, lots of air between phrases — with distant French horn pads on long notes. 92 BPM, 4/4, relaxed. Bright open-field reverb, not cathedral. Pastoral travelling music in the spirit of Jeremy Soule's Skyrim overworld and Shore's Shire, melancholic underneath. Full-length cue, developed with multiple variations and a contrasting bridge, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no heavy brass, no drum kit, no synth, no electric guitar, no EDM.
```
Structure prompt:
```
[Instrumental Intro - solo oboe alone, free, one long phrase]
[Instrumental A - pizzicato strings and soft frame drum enter, oboe states the walking theme]
[Instrumental B - solo clarinet takes a variation, horn pad underneath, warmer]
[Instrumental Bridge - strings only, the melody slows, a melancholic minor turn, no percussion]
[Instrumental C - a new pastoral variation, flute doubling the oboe, gentle lift]
[Instrumental A' - oboe returns to the walking theme, fuller strings, building]
[Instrumental Outro - pizzicato thins out, solo oboe alone again, long fade on a held note]
```

---

**05 — The Greatwood _ Under Old Leaves**
*Lever key: Aelorin · Lydian · 60 BPM · harp + high strings · instrumental · 4:30*

Style prompt:
```
Harp arpeggios under shimmering Lydian high divisi strings and celesta, the Song motif rising and never quite resolving — ancient, weightless, faintly sad. Finger-struck crotales for colour, no real percussion. 60 BPM, free-floating, no strong downbeat. Very long shimmering reverb, a forest older than memory. Aelorin exploration in the lineage of Shore's Lothlórien and Soule's quietest Skyrim wilderness. Full-length cue, developed through several variations of the motif, no early fade, very long outro. Instrumental. No brass, no drums, no choir, no solo vocals, no sung lyrics, no spoken word, no synth, no electric guitar, no EDM.
```
Structure prompt:
```
[Instrumental Intro - solo harp, slow Lydian arpeggio, alone]
[Instrumental A - high divisi strings enter softly, the Song motif rises, unresolved]
[Instrumental B - celesta threads a counter-figure, crotales shimmer, strings double in fifths]
[Instrumental Development - the motif is varied higher, the harmony opens further]
[Instrumental Peak - strings at their fullest shimmer, harp cascading]
[Instrumental Hush - everything drops to solo harp and one held string note]
[Instrumental Outro - the Song phrase left unfinished, very long reverb tail]
```

---

**06 — The Spine _ Stone and Sky**
*Lever key: Dwarven-adjacent · Dorian · 66 BPM · horn + low strings · instrumental · 4:00*

Style prompt:
```
A lone French horn over slow low-string swells in Dorian — vast, cold, mountainous, the scale of a range you cannot cross — with occasional deep timpani rolls like distant rockfall. 66 BPM, 4/4, spacious. Big open-air reverb with a long mountain slap-back. Grand and severe, Soule's Skyrim peaks crossed with Shore's mountain scale. Full-length cue, developed with a canon section and a full-brass peak, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no hand percussion, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - low-string drone, a single distant timpani roll]
[Instrumental A - lone French horn states a wide slow theme, low strings swell beneath]
[Instrumental B - second horn answers in canon, strings thicken, altitude rising]
[Instrumental Development - the theme expands across the brass, timpani marking the scale]
[Instrumental Peak - full low brass on a sustained chord, timpani roll, then sudden space]
[Instrumental Reprise - lone horn restates the theme, smaller, the range behind]
[Instrumental Outro - one horn alone, drone underneath, long fade into wind]
```

---

**07 — The Underway _ Beneath the Mountain**
*Lever key: Dwarven · Phrygian · 54 BPM · contrabassoon · instrumental · 4:30*

Style prompt:
```
Contrabassoon and low strings moving in slow Phrygian steps, occasional struck anvil ringing into long darkness, a deep tom marking distant time — old, deep, patient, oppressive but not evil. 54 BPM, heavy 4/4. Huge cavern reverb with a very long slap. Dwarven underground in the lineage of Shore's Moria, restrained, with Soule's subterranean gloom. Full-length cue, developed with a descending sequence and a deep climax, no early fade, long outro. Instrumental. No bright brass, no choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no hand drum, no synth, no electric guitar, no EDM.
```
Structure prompt:
```
[Instrumental Intro - cavern tone, one struck anvil ringing away into the dark]
[Instrumental A - contrabassoon enters low and slow, Phrygian, low strings shadow it]
[Instrumental B - the line descends step by step, a deep tom marks the depth]
[Instrumental Development - low brass joins, the descent sequenced lower, anvil strikes the bottom]
[Instrumental Peak - the fullest low chord, cavern ringing, then sudden space]
[Instrumental Hush - contrabassoon alone over the cavern ring]
[Instrumental Outro - one last anvil far off, long fade into stone silence]
```

---

**08 — The Ashfields _ Grey Soil**
*Lever key: Dead · drone · 44 BPM · cor anglais · instrumental · 4:00*

Style prompt:
```
A barely-moving drone of detuned low strings, a distant solo cor anglais playing short fragments that never connect into a melody, far breath-tone winds with no pitch. 44 BPM, no real pulse, dead air. Vast empty reverb, a landscape where nothing grows. Bleak ambient non-music — Shore's Dead Marshes and Soule's bleakest tundra. Full-length cue that develops only by slow drone shifts and recurring fragments, no early fade, long outro. Instrumental. No percussion, no choir, no solo vocals, no sung lyrics, no spoken word, no brass section, no synth pad, no drum kit, no electric guitar, no melody resolution, no EDM.
```
Structure prompt:
```
[Instrumental Intro - low detuned string drone, motionless]
[Instrumental A - distant cor anglais plays a three-note fragment, stops, silence, plays it again]
[Instrumental B - the drone shifts down a semitone, breath-tone winds far off]
[Instrumental Development - the fragment recurs, transposed, still never completing]
[Instrumental Sink - the drone descends, everything thinning]
[Instrumental Outro - cor anglais fragment one last time, unanswered, very long fade into emptiness]
```

---

**09 — The Western Coast _ Caer Drowned**
*Lever key: Sea/dead · Aeolian · 58 BPM · low whistle · instrumental · 4:00*

Style prompt:
```
A low whistle keening an Aeolian lament over slow grey string swells and a bell tolling as if underwater, a distant cor anglais answering. 58 BPM, 4/4 but tidal and loose. Damp wide reverb, salt and stone, a city under the water. Mournful coastal music — Shore's elegies and Soule's melancholic coast. Full-length cue, developed with a rising central climax and a reprise, no early fade, long outro. Instrumental. No drums, no choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no bright brass, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - grey string swell, one slow bell tone as if underwater]
[Instrumental A - low whistle states a falling Aeolian lament]
[Instrumental B - cor anglais answers the whistle, strings thickening]
[Instrumental Development - the lament is varied and rises, the bell tolls again]
[Instrumental Peak - strings reach a single aching crest]
[Instrumental Hush - back to one whistle line and the underwater bell]
[Instrumental Outro - whistle holds its last note, bell fades beneath the water, long tail]
```

---

**10 — The Copper Isles _ Salt and Sun**
*Lever key: Sailor · Mixolydian · 104 BPM · fiddle · instrumental · 4:00*

Style prompt:
```
A bright instrumental fiddle reel in Mixolydian over strummed cittern, hand drum and a skipping low whistle counter-line — sunlit, busy, a trading port that never sleeps. 104 BPM, 4/4 with a lilt. Medium warm room, lively. The portfolio's most upbeat exploration cue — folk-forward, Soule's friendlier towns crossed with a sea-port jig. Full-length cue with multiple tunes, a percussion break, and a final full statement, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no heavy brass, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - solo fiddle kicks off a bright Mixolydian phrase]
[Instrumental A - cittern strum and hand drum lock the groove, fiddle states the reel]
[Instrumental B - low whistle takes a second tune, fiddle drops to a counter-line]
[Instrumental C - a third related tune, both leads trading every two bars]
[Instrumental Break - hand drum and claps only for four bars]
[Instrumental Lift - full band back, double-time feel, port at full bustle]
[Instrumental Outro - one last full statement, sharp ensemble stop, short ring]
```

---

**11 — The Sorrowmarsh _ The Mud Remembers**
*Lever key: Dead · atonal drone · 40 BPM · bowed psaltery · instrumental · 4:00*

Style prompt:
```
Bowed psaltery and bowed metal scraping a slow atonal drone, no key, the occasional far struck bowl, breath-tone winds rising and sinking like ghost-lights. 40 BPM, no pulse, water that does not move. Vast haunted reverb with an unsettling ghost slap. Pure dread atmosphere — the unmaking happened here; Shore's Dead Marshes, darker. Full-length cue that develops only by drone density and the recurring bowl, no early fade, long outro. Instrumental. No melody, no percussion groove, no choir, no solo vocals, no sung lyrics, no spoken word, no brass, no synth, no electric guitar, no drum kit, no EDM, no resolution.
```
Structure prompt:
```
[Instrumental Intro - bowed psaltery, one long atonal scrape, no key]
[Instrumental A - bowed metal joins, a far struck bowl rings once]
[Instrumental B - breath-tone winds rise like marsh-lights, no pitch]
[Instrumental Development - the drone clusters tighter, the bowl rings again closer]
[Instrumental Swell - the texture briefly crowds in, then sinks back]
[Instrumental Outro - psaltery alone, one bowl far off, very long fade into still water]
```

---

**12 — The Weeping Wood _ Watched**
*Lever key: Naergrim · cluster · 48 BPM · prepared strings · instrumental · 4:00*

Style prompt:
```
Prepared and detuned strings playing tight tone-clusters that never resolve, contrabass clarinet groaning beneath, a dry bowed-metal scrape circling close — the feeling of being watched from every tree. 48 BPM, no real pulse, wrong. Close airless space, almost no reverb, itself unsettling. Naergrim dread — alien, not loud; Shore's Mirkwood unease. Full-length cue that develops by cluster density and recurring snapped harmonics, no early fade, long outro. Instrumental. No melody, no warm harmony, no percussion, no choir, no solo vocals, no sung lyrics, no spoken word, no brass fanfare, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - one detuned string note bent slowly out of tune]
[Instrumental A - prepared-string cluster builds, contrabass clarinet groans under it]
[Instrumental B - a dry bowed-metal scrape circles, getting closer]
[Instrumental Development - the cluster tightens, a string snaps a harsh harmonic]
[Instrumental Crowd - the texture multiplies, pressing in]
[Instrumental Cut - everything stops at once but one detuned note]
[Instrumental Outro - that note held in the airless room, slow uneasy fade]
```

---

### C. Settlements

---

**13 — Aldenholt _ Market and Bell**
*Lever key: Human · Mixolydian · 100 BPM · lute + recorder · instrumental · 4:00*

Style prompt:
```
Lute and recorder trading a warm Mixolydian tune over a tabor and tambourine, a city bell marking phrase ends — busy, friendly, background market energy without urgency. 100 BPM, 4/4 with a skip. Small warm room reverb. The largest human city at work; Soule's town themes, lighter. Full-length cue with multiple tunes and a quieter bridge, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no heavy brass, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - solo lute, a turning Mixolydian figure, a single bell tone]
[Instrumental A - recorder takes the melody, tabor and tambourine set the bustle]
[Instrumental B - lute and recorder in cheerful counterpoint, the bell every four bars]
[Instrumental Bridge - just lute and tabor, quieter, a quick warm minor turn]
[Instrumental C - a second brighter tune, fiddle doubling the recorder]
[Instrumental A' - full little ensemble back, market at peak]
[Instrumental Outro - thins to solo lute and one last bell, gentle stop]
```

---

**14 — Caer Brannoch _ The Cliff City**
*Lever key: Human/sea · Dorian · 72 BPM · solo cello + harp · instrumental · 4:00*

Style prompt:
```
Solo cello singing a noble Dorian melody over harp and slow string pads, a distant sea-swell suggested in the low strings — a proud city on the cliffs above the ocean, dignified and a little lonely. 72 BPM, 4/4, stately. Medium hall with an airy sea-wind tail. Aristocratic and maritime; Shore's quieter Gondor register. Full-length cue, developed with an octave lift and an intimate bridge, no early fade, long outro. Instrumental. No drums, no choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no bright fanfare, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - harp alone, a slow rolling figure like the sea below]
[Instrumental A - solo cello states the noble Dorian theme, string pad enters]
[Instrumental B - violins lift the theme an octave, harp continues, dignified swell]
[Instrumental Bridge - cello and harp alone, intimate, the lonely register]
[Instrumental Development - the theme varied, low strings suggest the sea-swell]
[Instrumental A' - full strings restate the theme, proud but restrained]
[Instrumental Outro - cello holds the last note, harp rolls once, long fade on sea-wind]
```

---

**15 — Vosskar _ Iron and Listening**
*Lever key: Iron Chalice-adjacent · Aeolian · 64 BPM · muted trumpet · instrumental · 4:00*

Style prompt:
```
A muted trumpet over spare low strings in Aeolian, severe and watchful, a low clarinet shadowing it — a fortress city built on silence and suspicion. 64 BPM, slow 4/4. Dry stone reverb, no warmth. Austere and martial-adjacent, restrained; Shore's grim cities. Full-length cue developed by slow accumulation and a single restrained peak, no early fade, long outro. Instrumental. No taiko, no hand percussion, no choir, no solo vocals, no sung lyrics, no spoken word, no bright brass, no synth, no electric guitar, no drum kit, no EDM, no major-key lift.
```
Structure prompt:
```
[Instrumental Intro - one muted trumpet note, dry, alone]
[Instrumental A - low strings enter beneath in slow Aeolian steps, watchful]
[Instrumental B - a low clarinet shadows the trumpet a fifth below]
[Instrumental Development - the phrase tightens, low strings thicken, pressure without release]
[Instrumental Peak - a single restrained tutti swell, then withdrawn]
[Instrumental Hush - everything pares back to the muted trumpet — the city listening]
[Instrumental Outro - trumpet repeats its phrase once, dry stop, short tail]
```

---

**16 — Solgrade _ The Unwalled City**
*Lever key: Tavern/cosmopolitan · Dorian · 96 BPM · hurdy-gurdy · instrumental · 4:00*

Style prompt:
```
A hurdy-gurdy drone and melody in Dorian with a foreign lilt, hand percussion, plucked oud-like strings and a tambourine — a wealthy crossroads city, many cultures, slightly exotic, never threatening. 96 BPM, 4/4 with an off-beat sway. Medium lively room. Cosmopolitan market music, the most "outsider"-flavoured settlement cue. Full-length cue with several variations and a percussion-and-drone break, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no heavy brass, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - hurdy-gurdy drone fades in, a single sustained chord]
[Instrumental A - hurdy-gurdy melody starts in Dorian, hand drum and tambourine join]
[Instrumental B - plucked oud-like strings take a variation with a foreign lilt]
[Instrumental Bridge - percussion and drone only, a swaying off-beat groove]
[Instrumental C - a second ornamented tune over the drone, busier]
[Instrumental A' - full ensemble, the first tune embellished]
[Instrumental Outro - instruments drop out one by one, hurdy-gurdy drone last, long fade]
```

---

**17 — Lirien-Thal _ The Silverwood**
*Lever key: Aelorin · Lydian · 52 BPM · glass harmonica · instrumental · 4:30*

Style prompt:
```
Glass harmonica and harp in slow Lydian over a bed of high sustained strings and celesta — a canopy city among ancestor-trees, sacred and grieving for a fading people. 52 BPM, free, no downbeat. Enormous shimmering cathedral-of-leaves reverb. The Aelorin's holiest place; Shore's Lothlórien at its most reverent. Full-length cue, developed with the Song motif varied and a long unresolved climax, no early fade, very long outro. Instrumental. No percussion, no brass, no choir, no solo vocals, no sung lyrics, no spoken word, no drums, no synth, no electric guitar, no EDM, no sharp attack.
```
Structure prompt:
```
[Instrumental Intro - glass harmonica alone, slow Lydian, weightless]
[Instrumental A - harp and high strings enter, the Song motif rises but does not resolve]
[Instrumental B - celesta laces a counter-figure, strings double in fifths]
[Instrumental Development - the motif varied higher, harmony opening further]
[Instrumental Peak - strings and harmonica at their fullest, a held unresolved chord]
[Instrumental Hush - back to glass harmonica and harp]
[Instrumental Outro - the Song phrase left open, shimmer fading upward, very long tail]
```

---

**18 — Karaz-Dûn _ Forges Never Cold**
*Lever key: Dwarven · Dorian · 78 BPM (6/8) · hammered dulcimer · instrumental · 4:00*

Style prompt:
```
Hammered dulcimer and low brass in a rolling 6/8 Dorian work-rhythm, anvils struck on the strong beats, boot-stomp percussion — a hold whose forges never go cold, proud and warm despite the weight. 78 BPM, 6/8, driving. Great stone-hall reverb with a long slap. Dwarven craft-pride; Shore's dwarves at work. Full-length cue with a brass-fuller middle, a percussion break, and a final statement, no early fade, long outro. Instrumental. No bright strings lead, no choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - one anvil strike, then the 6/8 boot-stomp pattern alone]
[Instrumental A - hammered dulcimer states the rolling Dorian work-theme, anvils on the strong beats]
[Instrumental B - low brass joins the dulcimer, fuller, the forge at full heat]
[Instrumental Development - the theme varied, dulcimer trading with brass]
[Instrumental Break - anvils and stomps only, four bars]
[Instrumental A' - full ensemble back, the work-theme at its proudest]
[Instrumental Outro - dulcimer figure slows, one last anvil strike, long ring into the hall]
```

---

**19 — Mor-Vethrin _ The Obsidian City**
*Lever key: Naergrim · no tonal center · 46 BPM · contrabass clarinet · instrumental · 4:00*

Style prompt:
```
Contrabass clarinet and bowed metal in a slow centreless drift, struck chains and a single stone-on-stone arrhythmic pulse — a windowless obsidian city that has held its silence two thousand years. 46 BPM, no key, no real pulse. Close, airless, wrong. Alien and ancient, never bombastic. Full-length cue developing only by texture density and the recurring chains, no early fade, long outro. Instrumental. No melody, no warm harmony, no choir, no solo vocals, no sung lyrics, no spoken word, no bright brass, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - contrabass clarinet, one long centreless note]
[Instrumental A - bowed metal joins, a chain struck once, arrhythmic stone pulse begins]
[Instrumental B - the texture thickens without resolving, chains closer]
[Instrumental Development - bowed metal layers, the stone pulse irregular and nearer]
[Instrumental Crowd - the texture presses in, chains repeated]
[Instrumental Cut - the stone pulse stops dead]
[Instrumental Outro - one clarinet note, one last chain, abrupt airless fade]
```

---

**20 — Brightwatch _ The Frontier Garrison**
*Lever key: Iron Chalice · Aeolian · 70 BPM · lone war horn · instrumental · 4:00*

Style prompt:
```
A lone war horn over a single deep field drum and spare low strings in Aeolian, a cor anglais shadowing the horn — a frontier fort holding the line, weary endurance rather than glory. 70 BPM, slow 4/4. Dry stone, cold air. Iron Chalice austerity; Roland's home register. Full-length cue developed by the Endurance cell stated, varied, and restated, no early fade, long outro. Instrumental. No taiko, no hand percussion, no choir, no solo vocals, no sung lyrics, no spoken word, no bright brass section, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - one deep field-drum hit, slow, then a lone war horn call]
[Instrumental A - low strings enter beneath in bare Aeolian, the Endurance cell hinted]
[Instrumental B - cor anglais shadows the horn, the cell stated plainly]
[Instrumental Development - strings thicken, the cell varied, the slow tread continuing]
[Instrumental Peak - a single restrained swell, the war horn at its fullest]
[Instrumental Hush - strings hold one low chord, the drum stops]
[Instrumental Outro - the war horn calls once more, unanswered, long dry fade]
```

---

### D. Interiors & Sacred

---

**21 — The Archive _ Dust and Lamplight**
*Lever key: Human / near-non-music · static modal · 50 BPM · bowed vibraphone · instrumental · 5:00*

Style prompt:
```
Almost non-music: a static modal hum of bowed vibraphone and sustained low strings, a distant bell resonance every minute, faint room tone — a vast library, lamplight, dust, the sound of a quiet room thinking. 50 BPM, no pulse, no melody. Dry interior with a faint long resonance. Ambient texture in the spirit of Shore's quietest interiors and Soule's library ambiences; designed to disappear. Full 5-minute bed, developing only by near-imperceptible harmonic shifts, no early fade, very long outro. Instrumental. No percussion, no choir, no solo vocals, no sung lyrics, no spoken word, no brass, no melodic line, no synth pad, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - bowed vibraphone, one slow shimmering tone]
[Instrumental A - sustained low strings join very quietly, a distant single bell]
[Instrumental B - the harmony shifts once, almost imperceptibly]
[Instrumental Drift - room tone, a far bell again, the hum continues unchanged]
[Instrumental C - a second barely-there harmonic shift, slightly warmer]
[Instrumental Drift 2 - the bell once more, the hum settling back]
[Instrumental Outro - everything thins to a single held vibraphone tone, very long slow fade]
```

---

**22 — The Iron Chalice _ Chapel of Endurance**
*Lever key: Iron Chalice · Aeolian · 56 BPM · organ + low strings · instrumental · 4:00*

Style prompt:
```
A church organ and low strings in solemn Aeolian stating the Endurance cell as a hymn, a muted trumpet doubling it at the peak — austere, devotional, the doctrine of endurance made sound. 56 BPM, slow 4/4. Stone-chapel reverb, medium tail. The Iron Chalice's theological core; a primary motif anchor — keep the Endurance melody clean and central. Full-length cue, developed by hymn-statement, organ-full variation, and reprise, no early fade, long outro. Instrumental. No taiko, no hand percussion, no choir, no solo vocals, no sung lyrics, no spoken word, no bright brass, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - organ alone, a low sustained Aeolian chord]
[Instrumental A - organ states the Endurance cell as a hymn line]
[Instrumental B - low strings join the organ, the cell harmonised in bare octaves]
[Instrumental Development - the hymn varied, organ registration widening]
[Instrumental Swell - organ full, muted trumpet doubles the Endurance cell fortissimo]
[Instrumental Hush - sudden drop to organ pedal and one low string note]
[Instrumental Outro - the Endurance tag once more on the organ, long slow stone fade]
```

---

**23 — The Aeluvain _ The Song With an Edge**
*Lever key: Aelorin · Lydian, unresolved · 58 BPM · solo violin harmonics · instrumental · 4:00*

Style prompt:
```
Solo violin in high natural harmonics, glass harmonica and celesta circling the Song motif in Lydian but never closing it — a sword that is a piece of the world's first music, beautiful and faintly painful. 58 BPM, free. Vast crystalline reverb. A motif anchor: the Song / Eighth Star theme in its purest instrumental form. Full-length cue, the motif stated, varied, reaching, and deliberately left one note short, no early fade, very long outro. Instrumental. No percussion, no brass, no choir, no solo vocals, no sung lyrics, no spoken word, no drums, no synth, no electric guitar, no EDM, no resolution.
```
Structure prompt:
```
[Instrumental Intro - solo violin harmonic, one pure high note, hanging]
[Instrumental A - glass harmonica enters, the Song motif begins to form, Lydian]
[Instrumental B - celesta doubles the violin, the phrase widens]
[Instrumental Development - the motif varied higher, harmony opening, still no cadence]
[Instrumental Peak - violin and harmonica reach for the final note and stop one step short]
[Instrumental Hush - violin and glass harmonica alone on a held harmonic]
[Instrumental Outro - the Song deliberately unfinished, shimmering, very long fade]
```

---

**24 — The Crown Assembled _ Seven Metals**
*Lever key: mixed · chromatic · 64 BPM · seven timbres · light massed choir (climax) · 4:00*

Style prompt:
```
Seven distinct timbres enter one at a time over a chromatic low drone — low strings, struck metal, horn, harp, glass harmonica, anvil, contrabass clarinet — the seven-note Crown cell assembling, awe shot through with dread. A light massed choir enters only at the climax, the Latin war-text against its whispered mirror, no solo. 64 BPM, slow 4/4. Huge cold reverb. Through-composed, no repeat; Shore's "object of power" scale. Full-length cue, no early fade, long outro. No solo vocals, no sung verses, no spoken word, no drum kit, no synth, no electric guitar, no EDM, no comfort.
```
Structure prompt:
```
[Instrumental Intro - chromatic low drone, one struck metal tone — iron]
[Instrumental Build 1 - horn adds a note of the Crown cell, then harp]
[Instrumental Build 2 - glass harmonica, anvil, contrabass clarinet each add a note]
[Instrumental Development - the partial Crown cell circles, brittle, gathering]
[Choir - massed, light, no solo: the Latin war-text against its mirror]

sanguis per saecula
nihil per saecula

[Instrumental Climax - all seven timbres sound the full Crown cell at once, vast and brittle]
[Instrumental Outro - everything snaps off but the obsidian clarinet, it bends down alone, cold fade]
```

---

### E. Tavern & Folk (instrumental)

---

**25 — Tavern _ The Limping Reel**
*Lever key: Folk · Mixolydian · 132 BPM · fiddle · instrumental · 4:00*

Style prompt:
```
A fast instrumental fiddle reel in Mixolydian with a deliberate limp in the rhythm, lute, hand drum, foot-stomps and claps — a packed tavern, ale, bad dancing. 132 BPM, 4/4 with a dropped beat every phrase. Small warm boozy room. Diegetic folk, deliberately unpolished, the opposite of cathedral. Full-length set of three linked tunes with a stomp break and a wild final round, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no orchestra, no taiko, no brass, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - fiddle scrapes off a fast reel, foot-stomp sets the limping time]
[Instrumental A - lute and hand drum lock in, fiddle states the first tune]
[Instrumental B - a second tune, fiddle wilder, claps doubling]
[Instrumental C - a third related tune, lute taking the lead]
[Instrumental Break - stomps and claps only, four bars]
[Instrumental A' - first tune back, full and frantic, double-time feel]
[Instrumental Outro - one ragged ensemble stop, a single fiddle flourish, short ring]
```

---

**26 — The Widow's Lament _ A Quiet Room**
*Lever key: Folk · Dorian · 68 BPM · lute + viola · instrumental · 4:00*

Style prompt:
```
A lone lute and a solo viola in slow Dorian, plain and unhurried — a quiet tavern gone still, a melody that grieves without a word. 68 BPM, free rubato, no percussion. Intimate close room, almost no reverb. Diegetic instrumental lament, the sad counterpart to the reel. Full-length cue, the air stated by lute, answered by viola, varied, and reprised lower, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no orchestra, no drums, no brass, no synth, no electric guitar, no EDM.
```
Structure prompt:
```
[Instrumental Intro - solo lute, a slow falling Dorian figure]
[Instrumental A - solo viola enters, states the lament over the lute]
[Instrumental B - lute and viola trade the phrase, no other instrument]
[Instrumental Development - the air varied, the viola lower and slower]
[Instrumental Hush - viola alone for one phrase, unaccompanied]
[Instrumental A' - lute returns under the viola, the lament one last time]
[Instrumental Outro - the final note left unresolved, lute fading, silence]
```

---

**27 — The Deep Cups _ A Dwarven Dance**
*Lever key: Dwarven · Dorian · 88 BPM (6/8) · dulcimer + anvil · instrumental · 4:00*

Style prompt:
```
A roaring instrumental dwarven dance in 6/8 Dorian: hammered dulcimer and low brass on the tune, anvil and tankard-on-table percussion, boot-stomps — ale, defiance, joy that sounds like a war chant with no words. 88 BPM, 6/8, heavy swing. Big stone-hall reverb. Diegetic and proud, not refined. Full-length cue, several rowdy variations, a stomp break, a final round, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no strings lead, no taiko, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - tankards pounded on the table set the 6/8, one anvil clang]
[Instrumental A - hammered dulcimer states the rowdy Dorian tune, anvil on the beat]
[Instrumental B - low brass doubles the tune, louder, fuller]
[Instrumental C - a second variation, dulcimer trading with brass]
[Instrumental Break - stomps and tankard hits only, four bars]
[Instrumental A' - the tune back at its rowdiest, everyone in]
[Instrumental Outro - one last anvil clang, a final dulcimer flourish, a roar of the hall]
```

---

**28 — The Dockside _ Salt and Strings**
*Lever key: Sailor · Mixolydian · 120 BPM · concertina · instrumental · 4:00*

Style prompt:
```
A driving instrumental concertina and fiddle jig in Mixolydian, hand drum and a boot on the deck for percussion, a low whistle counter-line — a portside tavern, salt, smoke, sailors home for a night. 120 BPM, 4/4 with a roll. Medium boozy room with a little wood ring. Diegetic sea-folk; distinct from the dwarven and human tavern cues by the concertina. Full-length cue with several tunes and a percussion break, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no orchestra, no taiko, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - concertina kicks off, a boot stamps the deck-time]
[Instrumental A - fiddle joins, hand drum locks the groove, concertina states the jig]
[Instrumental B - low whistle takes a second tune, concertina dropping to chords]
[Instrumental C - a third tune, fiddle and concertina trading]
[Instrumental Break - deck-stomp and hand drum only, four bars]
[Instrumental A' - full band back, the jig at full bustle]
[Instrumental Outro - concertina holds a chord, one last fiddle flourish, short ring]
```

---

**29 — The Hearth _ An Aelorin Air**
*Lever key: Aelorin · Lydian · 56 BPM · harp + celesta · instrumental · 4:00*

Style prompt:
```
A single Aelorin harp and celesta in gentle Lydian, a soft flute taking the tune — not a grand cue but a hearth air, the rare warm small-scale Aelorin register, tender and old. 56 BPM, free, no percussion. Soft medium reverb, intimate not vast. The folk counterpart to the grand Aelorin cues — human-scaled. Full-length cue, the air stated, answered, varied, and reprised, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no orchestra, no brass, no drums, no synth, no electric guitar, no EDM.
```
Structure prompt:
```
[Instrumental Intro - solo Aelorin harp, a slow tender Lydian figure]
[Instrumental A - a soft flute states an intimate melody over the harp]
[Instrumental B - celesta answers the flute phrase for phrase, like two by a fire]
[Instrumental Development - the air gently varied, harp arpeggios widening]
[Instrumental Hush - flute alone for one phrase]
[Instrumental A' - harp and celesta return under the flute, warmer]
[Instrumental Outro - harp holds the last chord, the air fading on an open note]
```

---

### F. Sea (instrumental)

---

**30 — The Capstan _ Heave Her Round**
*Lever key: Sailor · Dorian · 96 BPM · hand drum + low whistle · instrumental · 4:00*

Style prompt:
```
An instrumental work-rhythm: a hand drum and the rhythmic creak of rope and capstan keeping the pull, a low whistle and fiddle stating a muscular Dorian tune on the heave, the rhythm is the work. 96 BPM, 4/4, every other bar is the haul. Open deck, salt-air, little reverb. Sailor's Guild labour music; strophic by design but developed across the pull. Full-length cue building from slow start to full effort and easing off, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no orchestra, no taiko, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - rope creak and a slow hand drum, the capstan starting to turn]
[Instrumental A - low whistle states the muscular Dorian tune on the heave]
[Instrumental B - fiddle joins, the pull settles into rhythm, drum steadier]
[Instrumental Development - the tune varied, the work harder, percussion fuller]
[Instrumental Lift - everything at full effort, the anchor breaking free]
[Instrumental Ease - the pull slows, drum thinning]
[Instrumental Outro - the capstan stops, rope settles, one last whistle note, silence]
```

---

**31 — Leaving Port _ The Tide Turns**
*Lever key: Sailor · Mixolydian · 84 BPM (6/8) · fiddle + low whistle · instrumental · 4:00*

Style prompt:
```
A hopeful instrumental sea-air: low whistle and fiddle over rolling 6/8 strings, gulls and a far harbour bell — a ship leaving harbour, the bittersweet lift of departure. 84 BPM, 6/8, rolling like a wake. Medium open reverb, salt-air. The optimistic sea cue; melodic where #30 is functional. Full-length cue, the air stated, lifted an octave, varied, and reprised, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no heavy brass, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - low whistle alone, a rising Mixolydian phrase, a far harbour bell]
[Instrumental A - rolling 6/8 strings enter, fiddle joins the whistle, the ship pulls away]
[Instrumental B - fiddle takes the tune up an octave, fuller, hopeful]
[Instrumental Development - the air varied, strings swelling, the land falling behind]
[Instrumental Peak - whistle and fiddle together at the swell's crest]
[Instrumental Hush - back to low whistle and one string line]
[Instrumental Outro - whistle alone again, the bell once more, long fade on open water]
```

---

**32 — At Sea _ Open Water** *[supersedes existing `Sea _ Sailing`]*
*Lever key: Sailor · Dorian · 70 BPM · accordion + cello · instrumental · 4:30*

Style prompt:
```
A slow majestic Dorian theme on accordion answered by solo cello over long rolling string swells — no crew, no work, a ship alone on a vast calm sea, grand and a little lonely. 70 BPM, 4/4, tidal and broad. Wide open-ocean reverb. The cinematic sailing cue; replaces the old generic sea track with a clear lead pairing and roomier dynamics, Soule-broad. Full-length cue, the theme stated, answered, lifted by full strings, and reprised intimately, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no drum kit, no synth, no electric guitar, no EDM.
```
Structure prompt:
```
[Instrumental Intro - long low string swell, the sea breathing]
[Instrumental A - accordion states a broad Dorian theme, unhurried]
[Instrumental B - solo cello answers the accordion phrase, strings swell under both]
[Instrumental Development - the theme varied, the horizon widening]
[Instrumental Build - the full string section lifts the theme, grand, open water]
[Instrumental Hush - back to accordion and one cello line, the loneliness of it]
[Instrumental Outro - cello holds the last note, the swell recedes, very long fade]
```

---

**33 — The Shroud _ The Storm That Never Ends**
*Lever key: Mordvar-adj./sea · octatonic · 72→132 BPM · full orch + battery · wordless massed choir · 4:00*

Style prompt:
```
An octatonic storm: churning low strings, dissonant brass stabs, a war battery of toms and timpani building from a heave to a frenzy, a wordless massed choir as terror-texture only (no solo, no words) — the permanent storm that swallows every ship. Starts 72 BPM, accelerates to 132. 4/4 into chaos. Vast wet roaring reverb. The sea as enemy; Shore's storm scale, no resolution. Full-length cue, long build, sustained frenzy, unresolved tail, no early fade. No solo vocals, no sung lyrics, no spoken word, no folk instruments, no synth, no electric guitar, no drum kit, no EDM, no triumph.
```
Structure prompt:
```
[Instrumental Intro - low strings churn, distant timpani, 72 BPM, dread building]
[Instrumental Build - dissonant brass stabs, toms enter, tempo creeps up]
[Choir - massed wordless terror-texture, no words, no solo, rising with the storm]

(massed wordless vowels only — texture, not melody)

[Instrumental Storm - 132 BPM, full battery, brass screaming octatonic, total chaos]
[Instrumental Surge - the chaos peaks, choir swallowed by the orchestra]
[Instrumental Cutoff - a single brass note left ringing in the wet dark]
[Instrumental Outro - low string churn returns, unresolved, the storm goes on, long fade]
```

---

**34 — The Eastern Crossing _ Into the Storm**
*Lever key: mixed (epic) · modulating · 80 BPM · full orch · light Latin choir · 5:00*

Style prompt:
```
The grand crossing: the Endurance cell on full strings and horns against the Shroud's octatonic storm, a light massed Latin choir (no solo) holding the war-text as the orchestra fights the sea, modulating upward toward defiant resolve. 80 BPM, 4/4, broad and building. Huge cinematic reverb. Through-composed set-piece — Shore's largest seafaring register; ends resolved but costly. Full 5-minute cue, no early fade, long outro. No solo vocals, no sung verses, no spoken word, no drum kit, no synth, no electric guitar, no EDM, no folk lead.
```
Structure prompt:
```
[Instrumental Intro - low storm churn under a lone horn stating the Endurance cell]
[Instrumental A - full strings take the Endurance theme, defiant against the rising sea]
[Choir - massed Latin war-text, light, no solo, over the storm]

Lux per umbram
ferrum per ignem

[Instrumental B - the storm surges, brass and battery, the choir pushes through, key lifts]
[Instrumental Development - Endurance and storm traded, modulating higher]
[Climax - full orchestra and massed choir, the Endurance cell fortissimo, the crossing made]

sanguis per saecula
terra nos vocat

[Instrumental Cost - sudden hush, solo cello alone with the Endurance tag]
[Instrumental Outro - strings return softly, resolved but weary, long fade]
```

---

### G. Camp & Rest (instrumental)

---

**35 — Campfire _ The Sound of Rest**
*Lever key: Folk/intimate · Mixolydian · 60 BPM · solo lute-guitar · instrumental · 4:00*

Style prompt:
```
A solo lute-guitar, finger-picked, in gentle Mixolydian, the Hearth motif stated plainly and completely — the only fully-resolved theme in the score — a soft low whistle answering. 60 BPM, free, no percussion. Very close intimate reverb, fire-side. A motif anchor: keep the Hearth fragment warm and simple; designed to feel safe; Soule's camp warmth. Full-length cue, the motif stated, answered, gently varied, and reprised, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no orchestra, no drums, no brass, no synth, no electric guitar, no EDM.
```
Structure prompt:
```
[Instrumental Intro - solo lute-guitar, a quiet finger-picked figure]
[Instrumental A - the Hearth motif stated plainly, warm, complete]
[Instrumental B - a soft low whistle answers the Hearth phrase, then is gone]
[Instrumental Development - the lute varies the motif gently, unhurried]
[Instrumental C - whistle and lute together once, the warmest moment]
[Instrumental A' - lute alone again, the Hearth motif, a touch slower]
[Instrumental Outro - the last chord allowed to ring, fire-close, long gentle fade]
```

---

**36 — Night Rest _ Sleeping Under Stars**
*Lever key: intimate · Lydian · 48 BPM · music box + harp · instrumental · 4:30*

Style prompt:
```
A music box and harp in slow Lydian, a single sustained string note far underneath like a held breath — barely music, the sound of sleep under an open sky. 48 BPM, no pulse, no melody to follow. Tiny "music box" close reverb over a vast soft tail. The quietest cue in the score; it should almost disappear; Soule's night ambiences. Full-length cue, developing only by simplification and drift, no early fade, very long outro. Instrumental. No percussion, no choir, no solo vocals, no sung lyrics, no spoken word, no brass, no synth, no electric guitar, no drum kit, no EDM, no build.
```
Structure prompt:
```
[Instrumental Intro - music box alone, a slow Lydian turning figure]
[Instrumental A - harp doubles it very softly, a low string note holds underneath]
[Instrumental B - the figure simplifies, fewer notes, slower]
[Instrumental Drift - music box only, winding down, almost stopping]
[Instrumental C - harp returns once, the figure barely there]
[Instrumental Outro - one last music-box note, the low string note fades after it, very long tail]
```

---

**37 — The Quiet After _ Wounds and Breath**
*Lever key: Iron Chalice-adj. · Aeolian · 52 BPM · solo cello · instrumental · 4:00*

Style prompt:
```
A solo cello alone in Aeolian, slow, breathing, the Endurance cell played as exhaustion rather than heroism, one low sustained string note for a floor — the silence after a hard fight, survival not victory. 52 BPM, rubato, no percussion. Dry close room, a little air. The decompression cue, silence-adjacent. Full-length cue, the cell stated tired, sinking, paused, and barely restated, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no brass, no drums, no second melody, no synth, no electric guitar, no EDM, no swell.
```
Structure prompt:
```
[Instrumental Intro - solo cello, one long breath of a note, alone]
[Instrumental A - the Endurance cell played slowly, tired, not triumphant]
[Instrumental B - a low sustained string note enters as a floor, the cello sinks lower]
[Instrumental Development - the cell barely varied, even slower]
[Instrumental Hush - the cello stops; only the low note and room air]
[Instrumental C - cello returns for one faint phrase]
[Instrumental Outro - one final cello note, unresolved, allowed to die away, long tail]
```

---

### H. War & Combat

---

**38 — Enemies Gathering Strength _ The Muster of the Hand**
*Lever key: Mordvar · octatonic · 60→88 BPM · low brass · massed curse-chant · 4:00*

Style prompt:
```
A slow octatonic dread-build: a single low brass note, a distant war drum that multiplies, a low massed curse-chant (no solo) accreting under the orchestra, tempo creeping 60 to 88 — not a battle, the patient assembly of something terrible. 4/4, relentless acceleration. Vast cold reverb. The Ashen Hand massing; menace by accumulation, never release; Shore's Isengard build. Full-length cue, long accumulation to a poised, unresolved peak, no early fade, long uneasy outro. No solo vocals, no sung verses (chant is massed only), no spoken word, no folk, no bright brass, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - one low brass note, 60 BPM, a single far war drum]
[Instrumental Build - more drums answer from further off, the brass note bends down]
[Choir - massed low curse-chant, no solo, the mirror text under the orchestra]

nihil per nihil
cor per inane

[Instrumental B - tempo 76, low strings add an octatonic ostinato, drums closing in]
[Choir - the massed chant hardens, still no melody, no solo]

nemo per saecula
nihil nos tenet

[Instrumental Peak - 88 BPM, full low brass and battery, massed and waiting]
[Instrumental Outro - it does not resolve; it simply stops, poised — long uneasy fade]
```

---

**39 — A Minor Skirmish _ Blades in the Brush**
*Lever key: Iron Chalice-adj. · Phrygian · 116 BPM · low strings ostinato · instrumental · 3:30*

Style prompt:
```
A tight Phrygian low-string ostinato, a snare-less field drum, short stabbing horn figures — a brief, contained fight, no glory, lean and nervy. 116 BPM, 4/4. Dry medium room, no cathedral. A 3:30 combat texture with two escalations and a quick comedown; small-stakes, deliberately not a set-piece. Full-length, no early fade. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no big brass theme, no synth, no electric guitar, no drum kit, no EDM, no triumphant climax.
```
Structure prompt:
```
[Instrumental Intro - low-string Phrygian ostinato starts immediately, no ramp]
[Instrumental A - field drum enters, short horn stabs punctuate, tension tight]
[Instrumental B - the ostinato shifts up a step, strings sharper, the fight quickens]
[Instrumental Escalation - a second gear, horn stabs doubling, drum harder]
[Instrumental Peak - one hard tutti hit, then the ostinato alone, thinning]
[Instrumental Comedown - drum drops out, ostinato slowing]
[Instrumental Outro - the ostinato stops mid-phrase — it's over, short ring]
```

---

**40 — Charge Into Battle _ Sound the Horns**
*Lever key: Human · Mixolydian · 152 BPM · war horns + trumpets · massed Latin choir · 4:00*

Style prompt:
```
War horns and trumpets blazing the Endurance cell in bright Mixolydian, full strings galloping, timpani and frame drums hammering a charge, a massed Latin choir (no solo) roaring the war-text as a rhythmic battle-cry. 152 BPM, 4/4, headlong. Big heroic field reverb. Pure forward momentum; Shore's Rohan charge. Full-length cue, two charge waves with a brief regroup and a bigger final wave, no early fade, hard final tag. No solo vocals, no sung verses (choir massed only), no spoken word, no drum kit, no synth, no electric guitar, no EDM, no slow section, no minor wallow.
```
Structure prompt:
```
[Instrumental Intro - a single rising war-horn call, then the full battery slams in at 152]
[Instrumental A - trumpets blaze the Endurance cell, strings gallop beneath]
[Choir - massed Latin battle-cry, no solo, with the brass]

Ferrum per ignem!
Terra nos vocat!

[Instrumental B - horns answer the trumpets in canon, the charge accelerating feel]
[Instrumental Regroup - a two-bar drop to drums and low strings, tension coiling]
[Instrumental Final Wave - everything at once, the Endurance cell fortissimo, choir massed]

Vocat! Vocat! Terra nos vocat!

[Instrumental Outro - one last horn blast and a hard tutti stop, short ring — no comedown]
```

---

**41 — The Large Battle _ The Field of Iron**
*Lever key: mixed (suite) · Aeolian/octatonic · 96→168 BPM · full orch + battery · both choirs · 5:00*

Style prompt:
```
A full battle suite: the Endurance cell (Aeolian, massed Latin choir) versus the Hollowing (octatonic, massed curse-chant) traded across the orchestra, taiko and dhol war battery, multiple tempo gears 96 to 168, a desperate mid-battle hush, then a brutal return. All choir massed, no solo. 4/4 through 6/8. Vast cinematic reverb. Through-composed, Shore's Pelennor scale — the score's biggest set-piece. Full 5-minute cue, no early fade, long outro. No solo vocals, no sung verses, no spoken word, no drum kit, no synth, no electric guitar, no EDM, no clean victory.
```
Structure prompt:
```
[Instrumental Intro - distant battery, the Endurance cell on horns, 96 BPM, the lines meet]
[Choir - massed Latin, no solo, the light side pressing]

ferrum per ignem!

[Instrumental B - the Hollowing answers, octatonic brass, tempo 132]
[Choir - massed curse-chant, no solo]

nihil per nihil!

[Instrumental Hush - sudden near-silence, a solo cello plays the Endurance tag, the cost]
[Instrumental Return - 168 BPM, full battery, both massed choirs at once, total collision]

Terra nos vocat! / Nihil nos tenet!

[Instrumental Cutoff - a single timpani roll cut dead]
[Instrumental Outro - solo cello, the Endurance tag unfinished, smoke clearing, long fade]
```

---

**42 — The Siege _ Hold the Walls**
*Lever key: Dwarven · Phrygian · 100 BPM · anvils + low brass · wordless low massed choir · 4:30*

Style prompt:
```
A defensive grind: anvils and low brass in heavy Phrygian, a relentless boot-stomp like ram-blows on a gate, a low wordless massed choir (no solo, no words — syllabic ah/oh texture) of defiance — attrition, walls, holding not charging. 100 BPM, heavy 4/4, no acceleration, just endurance. Great stone-hall reverb with a long slap. Distinct from the charge: this digs in; Shore's Helm's Deep defense. Full-length cue, assault / lull / harder assault / hold, no early fade, long outro. No solo vocals, no sung words, no spoken word, no bright trumpets, no taiko frenzy, no synth, no electric guitar, no drum kit, no EDM, no rout.
```
Structure prompt:
```
[Instrumental Intro - one massive low-brass hit like a ram on the gate, then the stomp begins]
[Instrumental A - anvils mark the beat, low brass states a grim Phrygian figure]
[Choir - low wordless massed voices, no solo, no words, a defiant ah/oh texture]

(massed low vowels only — texture, not language)

[Instrumental B - the ram-blows quicken, the figure tightens, the wall strains]
[Instrumental Lull - one breath where the stomp stops — between assaults]
[Instrumental Return - the stomp slams back harder, choir massed beneath, the line holds]
[Instrumental Outro - the ram-blows slow, one last anvil rings over the held hall, long tail]
```

---

**43 — Vaeroth the Pale _ The Hierarch**
*Lever key: Mordvar · whole-tone · 108 BPM · contrabassoon · massed curse-chant · 4:00*

Style prompt:
```
A cold whole-tone boss theme: contrabassoon and muted low brass over a precise mechanical pulse, a controlled massed curse-chant (no solo) — a brilliant, fragile zealot, not a brute; menace is intellect and certainty. 108 BPM, 4/4, clinical. Large cold reverb. Distinct from Mordvar (slow, vast) and the Ashlord (tragic) — Vaeroth is sharp and exact. Full-length cue, theme stated, tightened, climaxed, and fractured, no early fade, long outro. No solo vocals, no sung verses (chant massed only), no spoken word, no warm strings, no folk, no triumphant brass, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - a precise mechanical low pulse, contrabassoon enters whole-tone, cold]
[Instrumental A - muted low brass states Vaeroth's clipped theme, exact, controlled]
[Choir - a measured massed curse-chant, no solo, no passion, total certainty]

cor per inane
nemo per saecula

[Instrumental B - the pulse tightens, brittle whole-tone string shimmer, pressure rising]
[Instrumental Development - the theme sequenced upward, mechanical and relentless]
[Instrumental Climax - brass and massed chant snap to full force, still controlled, then a fracture]
[Instrumental Cutoff - the mechanical pulse stutters and stops — the fragility shows]
[Instrumental Outro - contrabassoon alone, one bent note, long cold fade]
```

---

**44 — The Ashlord _ The Mask of Caerith**
*Lever key: Naergrim/Aelorin · Lydian→cluster · 92 BPM · corrupted glass harmonica · wordless massed choir · 4:30*

Style prompt:
```
A tragedy wearing armour: the Aelorin Song motif on glass harmonica, beautiful for two phrases, then rotting into Naergrim clusters and detuned strings, a wordless massed choir (no solo) curdling with it — a Second Age Vigil-Keeper turned; the music remembers what he was. 92 BPM, 4/4 decaying into no pulse. Vast reverb curdling to airless close. The most tragic villain cue; never purely monstrous. Full-length cue, beauty / turn / warped return / collision, no early fade, long outro. No solo vocals, no sung words, no spoken word, no taiko frenzy, no folk, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - the Aelorin Song motif, glass harmonica, achingly beautiful, Lydian]
[Instrumental A - high strings carry the Song, pure, for one more phrase]
[Instrumental Turn - the harmony curdles, strings detune, the Song warps]
[Choir - wordless massed voices, no solo, curdling from pure to cluster]

(massed wordless vowels, decaying — texture only)

[Instrumental B - the Song returns warped, low brass beneath it, grief and menace at once]
[Instrumental Climax - the beauty and the rot collide, full and dissonant, the mask holding]
[Instrumental Cutoff - everything drops to one detuned harmonic — what's left of him]
[Instrumental Outro - a single broken fragment of the Song, unresolved, long airless fade]
```

---

**45 — Mordvar _ The Hollowing**
*Lever key: Mordvar · the inverted Song · 50 BPM · dissonant low brass · massed curse-chant · 4:30*

Style prompt:
```
The franchise's dark anchor: the Song motif inverted and emptied — descending open fifths on dissonant low brass and contrabassoon that refuse to close, a vast slow massed curse-chant (no solo), war battery felt more than heard. 50 BPM, immense 4/4, glacial. Enormous airless reverb, no warmth anywhere. A motif anchor — keep the Hollowing's inverted shape exact and recognisable. Full-length cue, statement / stacking / widest climax / silence / endless descent, no early fade, very long outro. No solo vocals, no sung verses (chant massed only), no spoken word, no folk, no bright brass, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - one immense low-brass open fifth, descending, refusing to resolve]
[Instrumental A - contrabassoon states the Hollowing — the Song inverted and emptied]
[Choir - the vast slow massed curse-chant, no solo, the mirror text]

Nihil per nihil
cor per inane
nemo per saecula
nihil nos tenet

[Instrumental B - the descending fifths stack, war battery felt under the floor]
[Instrumental Climax - the full Hollowing fortissimo, massed chant at its widest]
[Instrumental Cutoff - total silence for a beat]
[Instrumental Outro - one low note bends downward forever, airless, very long fade]
```

---

**46 — The Fighting Retreat _ The Ashfields**
*Lever key: Iron Chalice · Aeolian · 116 BPM · war horn + strings · instrumental · 4:00*

Style prompt:
```
Heroic loss: the Endurance cell on a strained war horn over driving Aeolian strings and a hard field-drum tread — a retreat that is also a victory, ground given so people live. 116 BPM, 4/4, urgent but disciplined, never a rout. Big cold field reverb. Defiant melancholy; Shore's noble-defeat register. Full-length cue, the cell under pressure, a near-break, a defiant restatement, a recede, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no triumphant fanfare, no taiko frenzy, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - hard field-drum tread, a strained war-horn call, no triumph in it]
[Instrumental A - driving Aeolian strings, the Endurance cell on the horn under pressure]
[Instrumental B - the strings press harder, the tread quickens, discipline not panic]
[Instrumental Near-break - one bar where it nearly fails — solo horn alone, then strings catch it]
[Instrumental Defiance - the Endurance cell restated, the line still ordered, falling back]
[Instrumental Development - the cell varied lower, the tread relentless]
[Instrumental Outro - the tread recedes into distance, horn last, long fade — they got out]
```

---

**47 — The Last Stand _ No Ground Behind**
*Lever key: Iron Chalice/Human · Aeolian→Mixolydian · 84→144 BPM · full orch · massed Latin choir · 4:30*

Style prompt:
```
From dread to defiance: a low Aeolian dread-bed and a slow Endurance statement that gathers the full orchestra and a massed Latin choir (no solo), accelerating 84 to 144 as it modulates Aeolian to Mixolydian — backs to the wall, then everything given at once. 4/4. Vast cinematic reverb. Through-composed; desperate-courage set-piece, distinct from the charge by starting in despair. Full-length cue, long build, full climax, withheld outcome, no early fade, long outro. No solo vocals, no sung verses, no spoken word, no drum kit, no synth, no electric guitar, no EDM, no autotune.
```
Structure prompt:
```
[Instrumental Intro - low Aeolian dread-bed, 84 BPM, a lone cello with the Endurance tag]
[Instrumental A - strings gather under it, drums enter slow, the orchestra low and heavy]
[Instrumental Build - tempo lifts, the Endurance cell strengthens]
[Choir - massed Latin, no solo, finding the war-text]

ferrum per ignem

[Instrumental Turn - modulation to Mixolydian, 144 BPM, defiance breaking through]
[Climax - full orchestra and massed choir, the Endurance cell at full cry]

Terra nos vocat!

[Instrumental Cutoff - one tutti chord held, then cut — outcome unsaid]
[Instrumental Outro - a single horn holds the Endurance tag over silence, long fade]
```

---

**48 — The Muster of the Alliance _ Many Banners**
*Lever key: mixed (suite) · Mixolydian · 100 BPM · rotating culture leads · layered massed choirs · 5:00*

Style prompt:
```
A muster suite where each culture's instrumental palette enters in turn and then layers — human horns, Aelorin glass harmonica, dwarven 6/8 dulcimer and anvil, sea concertina — all converging on the Endurance cell, a layered massed choir (no solo) only at the convergence. 100 BPM, modulating, 4/4 over 6/8. Huge field reverb. Through-composed; "the world stands together," every palette distinct then unified. Full 5-minute cue, no early fade, long outro. No solo vocals, no sung verses, no spoken word, no drum kit, no synth, no electric guitar, no EDM, no autotune.
```
Structure prompt:
```
[Instrumental Intro - lone human war horn states the Endurance cell over a field drum]
[Instrumental Human - horns and strings take it, banners of the kingdoms]
[Instrumental Aelorin - glass harmonica and high strings layer the Song motif over it]
[Instrumental Dwarven - 6/8 hammered dulcimer and anvil join, the holds answer]
[Instrumental Sea - a concertina figure rides in over the top]
[Choir - layered massed choir, no solo, only as the palettes converge]

Terra nos vocat!

[Instrumental Convergence - all palettes lock onto the Endurance cell at once]
[Instrumental Outro - the leads peel away to the lone war horn that began it, long proud fade]
```

---

### I. Cinematic & Story (instrumental)

---

**49 — The Vigil _ The Night Before**
*Lever key: Iron Chalice · Aeolian · 52 BPM · solo cello + low whistle · instrumental · 4:00*

Style prompt:
```
The night before the battle: a solo cello and a far low whistle in Aeolian, a single field drum like a slow heartbeat — dread and resolve held very quietly, no swelling. 52 BPM, rubato, almost still. Cold open-camp reverb, fires and dark. Designed restraint; the calm before, not the storm; Shore's pre-battle hush. Full-length cue, the Endurance cell questioned, answered from afar, paused, barely restated, no early fade, long outro. Instrumental. No big brass, no choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no synth, no electric guitar, no drum kit, no EDM, no climax.
```
Structure prompt:
```
[Instrumental Intro - one slow field-drum beat like a heart, a solo cello enters Aeolian]
[Instrumental A - the Endurance cell played softly, questioning, not heroic]
[Instrumental B - a low whistle answers the cello from across the camp, lonely]
[Instrumental Development - the cell varied, the drum-heart steady and slow]
[Instrumental Hush - cello alone, the drum stops, the longest silence in the cue]
[Instrumental C - the whistle returns for one faint phrase]
[Instrumental Outro - the Endurance tag unfinished, the drum-heart once more, long fade to dark]
```

---

**50 — Heroes Reunited _ The Fellowship Whole**
*Lever key: mixed (motif weave) · Mixolydian · 76 BPM · leitmotif weave · instrumental · 4:00*

Style prompt:
```
A motif-weave reunion: the Hearth fragment opens, then the Endurance cell on solo cello, the Aelorin Song on glass harmonica, a dwarven dulcimer figure and a sea phrase all braid warmly in Mixolydian — companions back together, the score's themes embracing. 76 BPM, 4/4, glowing. Warm medium hall. The emotional pay-off cue; recognisably every theme at once; Shore's reunion warmth. Full-length cue, themes introduced and braided to a glowing peak, then back to the Hearth, no early fade, long outro. Instrumental. No battle battery, no choir, no solo vocals, no sung lyrics, no spoken word, no synth, no electric guitar, no drum kit, no EDM, no dissonance.
```
Structure prompt:
```
[Instrumental Intro - the Hearth fragment, solo lute, warm and complete]
[Instrumental A - solo cello adds the Endurance cell over it, gently, like a greeting]
[Instrumental B - glass harmonica laces the Aelorin Song through]
[Instrumental C - a dwarven dulcimer figure and a sea phrase join the weave]
[Instrumental Weave - all the motifs braid together, strings warm underneath]
[Instrumental Peak - the full ensemble, every theme audible at once, glowing not loud]
[Instrumental Outro - back to the Hearth fragment, lute alone, a held warm chord, long fade]
```

---

**51 — A Marriage _ Two Hands Bound**
*Lever key: Folk/Human · Ionian (major) · 88 BPM · harp + oboe + fiddle · instrumental · 4:00*

Style prompt:
```
Unambiguous joy — the score's only pure major-key cue: harp, oboe and a warm fiddle dancing an Ionian processional, hand drum and a single bright bell. 88 BPM, 4/4 with a lift. Warm bright room, a hall full of people. Folk-ceremonial, light; deliberately not orchestral-grand — a real wedding, not a coronation. Full-length cue, processional, a dancing middle, a tender bridge, a glad reprise, no early fade, long outro. Instrumental. No minor wallow, no choir, no solo vocals, no sung lyrics, no spoken word, no Latin dirge, no taiko, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - solo harp, a bright rising Ionian figure, one clear bell]
[Instrumental A - oboe takes a glad processional melody, fiddle and hand drum lift it]
[Instrumental B - fiddle leads a dancing variation, the room clapping along]
[Instrumental Bridge - harp and oboe alone, tender, a held warm moment]
[Instrumental C - the processional fuller, recorder doubling the oboe]
[Instrumental Reprise - the brightest statement, everyone in, glad]
[Instrumental Outro - harp and bell as at the start, a warm settled major chord, long glad fade]
```

---

**52 — Grief _ What the Archive Lost**
*Lever key: Human · Aeolian · 46 BPM · solo viola · instrumental · 4:00*

Style prompt:
```
Pure loss: a solo viola in slow Aeolian, almost no accompaniment, a solo cello answering — intimate grief, no orchestra to hide behind. 46 BPM, rubato, no percussion ever. Close dry room, the sound of one person mourning. The sadness cue; small on purpose; Shore at his most bereft. Full-length cue, the lament stated, answered, unbearably bare, restated lower, unresolved, no early fade, long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no Latin, no brass, no drums, no swell, no synth, no electric guitar, no EDM, no comfort.
```
Structure prompt:
```
[Instrumental Intro - solo viola alone, a slow falling Aeolian phrase, bare]
[Instrumental A - a solo cello enters beneath, a low counter-line, grieving]
[Instrumental B - viola and cello trade the lament, no other instrument]
[Instrumental Hush - the viola alone for one phrase, unbearable and quiet]
[Instrumental Development - the lament restated lower, slower]
[Instrumental C - cello holds one low note as the viola sinks]
[Instrumental Outro - the viola does not resolve the final note; it simply stops. Silence.]
```

---

**53 — Noble Sacrifice _ The Blow at the Marsh**
*Lever key: mixed · Aeolian→Lydian · 60 BPM · cello → full strings · instrumental · 4:30*

Style prompt:
```
A death that means something: a solo cello (Endurance, Aeolian) carried up by gathering strings into the Aelorin Song (Lydian) on glass harmonica and high strings — grief turned to transcendence, the cost paid and accepted. 60 BPM, 4/4, a slow inexorable rise. Vast cathedral reverb. The noble-death cue, distinct from pure Grief by its upward resolution into the Song; Shore's redemptive elegy. Full-length cue, statement / gathering / transformation / release / peace, no early fade, long outro. Instrumental. No battery, no choir, no solo vocals, no sung lyrics, no spoken word, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - solo cello, the Endurance cell, alone and tired]
[Instrumental A - strings gather under it slowly, harmony lifting Aeolian toward Lydian]
[Instrumental B - the Endurance cell begins to transform into the Aelorin Song]
[Instrumental Turn - glass harmonica takes the Song, the key opens fully to Lydian]
[Instrumental Climax - full strings and harmonica, the Song allowed to nearly resolve]
[Instrumental Release - everything drops to one held Lydian chord — the cost accepted]
[Instrumental Outro - solo cello returns at peace, one last Endurance tag, long warm fade]
```

---

**54 — Betrayal _ The Mole Revealed**
*Lever key: Naergrim-adj. · minor→cluster · 64 BPM · low strings + clock tick · instrumental · 3:30*

Style prompt:
```
Cold realisation: low strings in tightening minor over a dry mechanical clock tick, a trusted-warm motif fragment heard once then soured into a Naergrim cluster — the moment a friend turns out to be the knife. 64 BPM, 4/4, clinical and dropping. Close airless room. Through-composed; the "trust breaks" cue, no comfort, no bombast. Full 3:30 cue, tick / warm fragment / souring / drop / dead stop, no early fade, short cold outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no taiko, no warm resolution, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - a dry mechanical tick, alone, like a clock in a quiet room]
[Instrumental A - low strings enter minor, a familiar warm motif fragment heard once, trusting]
[Instrumental Turn - the fragment sours, detunes, curdles toward a Naergrim cluster]
[Instrumental B - the strings tighten downward, the tick speeds slightly]
[Instrumental Development - the cluster thickens, the floor going out]
[Instrumental Cutoff - the tick stops dead — the realisation lands]
[Instrumental Outro - one airless cluster held, no resolution, hard short fade]
```

---

**55 — Hope Rekindled _ The Turn**
*Lever key: Human · Aeolian→Mixolydian · 72→104 BPM · solo oboe → full orch · instrumental · 4:00*

Style prompt:
```
The turn from despair: a lone oboe in fragile Aeolian, a fragment of the Endurance cell finding its feet, strings and brass gathering as the key opens to Mixolydian and the tempo lifts 72 to 104 — not victory yet, but the moment it becomes possible. 4/4. Warm growing reverb. Through-composed arc from doubt to resolve; Shore's "dawn" cue. Full-length cue, fragile / finding / build / turn / open lift, no early fade, long outro. Instrumental. No battle battery, no choir, no solo vocals, no sung lyrics, no spoken word, no synth, no electric guitar, no drum kit, no EDM, no premature triumph.
```
Structure prompt:
```
[Instrumental Intro - solo oboe, fragile Aeolian, a broken piece of the Endurance cell]
[Instrumental A - the oboe finds the whole cell, hesitant; soft strings agree underneath]
[Instrumental B - clarinet and strings answer, the key warming toward Mixolydian]
[Instrumental Build - tempo lifts, horns enter low, hope catching]
[Instrumental Turn - 104 BPM, the Endurance cell stated whole and strong for the first time]
[Instrumental Climax - full strings and horns, bright but not yet triumphant — possibility]
[Instrumental Outro - it does not over-resolve; it lifts and holds, open, hopeful, long fade up]
```

---

**56 — Epilogue _ The Road Home**
*Lever key: Folk/Human · Mixolydian · 80 BPM · solo cello + oboe · instrumental · 4:00*

Style prompt:
```
Quiet closure: solo cello and oboe trading the Endurance cell and the Hearth fragment, gently, in warm Mixolydian over light strings — the war over, the road leading home, earned peace not fanfare. 80 BPM, 4/4, unhurried. Warm open-field reverb at dusk. The denouement; recognisable themes at rest; Soule's warm send-off. Full-length cue, both themes stated, varied, an intimate bridge, a settled reprise, no early fade, long outro. Instrumental. No battery, no choir, no solo vocals, no sung lyrics, no spoken word, no Latin, no taiko, no synth, no electric guitar, no drum kit, no EDM, no swell.
```
Structure prompt:
```
[Instrumental Intro - solo cello, the Endurance cell, calm now, no weight on it]
[Instrumental A - oboe answers with the Hearth fragment, the two themes at peace]
[Instrumental B - light strings join warmly, the road opening ahead]
[Instrumental Development - the themes gently varied, dusk light]
[Instrumental Bridge - cello and oboe alone again, intimate, almost home]
[Instrumental Reprise - the themes restated together, settled, complete]
[Instrumental Outro - one warm held chord at dusk, very long peaceful fade]
```

---

### Endings (Game Three — authored finale cues, instrumental)

---

**57 — The Return _ Released**
*Lever key: Aelorin/Human · Lydian resolving · 58 BPM · full strings · light wordless massed swell · 5:00*

Style prompt:
```
Resolution and release: the Aelorin Song motif, unfinished for the entire trilogy, finally completes — full strings and glass harmonica, a light wordless massed choir swell (no solo) only at the climax, the missing eighth note at last sounded. 58 BPM, 4/4, a slow opening-out. Vast warm cathedral reverb. The "Mordvar dissolved, the fear resolved" ending; the only cue where the Song is allowed to close. Full 5-minute cue, no early fade, very long outro. No solo vocals, no sung verses, no spoken word, no battery, no dissonance, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - glass harmonica, the Song motif, still unfinished, fragile]
[Instrumental A - full strings gather it up, warm, the Endurance cell entwined beneath]
[Instrumental B - the Song varied, rising, the harmony opening to Lydian]
[Instrumental Turn - the Song reaches its final note — and this time it resolves, the eighth sounded]
[Choir - light wordless massed swell, no solo, only here at the resolution]

(massed wordless vowels — a swell, not a melody)

[Instrumental Climax - full strings on the resolved Song, release not triumph]
[Instrumental Outro - everything settles onto the home chord, glass harmonica last, very long warm fade]
```

---

**58 — The Hold _ Carried Forever**
*Lever key: Iron Chalice · Aeolian, unresolving · 54 BPM · solo cello + low strings · instrumental · 5:00*

Style prompt:
```
Love as permanent cost: the Endurance cell on solo cello and a low string section, dignified and warm but the harmony never fully resolves — the weight is carried, not put down, forever. 54 BPM, slow 4/4. Deep stone reverb. The "contained within the bloodline" ending; beautiful and unresolved on purpose, distinct from The Return by its withheld cadence. Full 5-minute cue, statement / gathering / withheld cadence / noble peak / still-carried close, no early fade, very long outro. Instrumental. No choir, no solo vocals, no sung lyrics, no spoken word, no battery, no bright brass, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - solo cello, the Endurance cell, steady, accepting]
[Instrumental A - a low string section enters beneath, warm, dignified]
[Instrumental B - the harmony rises as if to resolve — and holds back, the cadence withheld]
[Instrumental Development - the cell varied, the weight named in the low strings]
[Instrumental Climax - cello and strings at their fullest, noble, but never closing the chord]
[Instrumental Hush - back to solo cello, the Endurance cell, the weight still there]
[Instrumental Outro - the final note held, unresolved, carried — very long fade, no cadence]
```

---

**59 — The Fracture _ The Price of Refusal**
*Lever key: Mordvar-adj. · shattered, no cadence · 60 BPM · broken orchestra · instrumental · 5:00*

Style prompt:
```
The price of refusal: the Endurance cell and the Hollowing fragment each broken, neither winning, an orchestra that keeps almost cohering and shattering — survival without resolution, the cost on the world. 60 BPM, 4/4 destabilising. Vast cold reverb. The bleak ending; deliberately denied catharsis, distinct from both others by having no settled chord at all. Full 5-minute cue, broken statements / failed gathering / collapse / suspended non-ending, no early fade, abrupt close. Instrumental. No clean victory, no choir, no solo vocals, no sung lyrics, no spoken word, no synth, no electric guitar, no drum kit, no EDM.
```
Structure prompt:
```
[Instrumental Intro - a broken fragment of the Endurance cell, strings, it doesn't complete]
[Instrumental A - the Hollowing answers, also broken, neither motif able to finish]
[Instrumental B - the two fragments overlap and interfere, no key, no centre]
[Instrumental Build - the orchestra gathers as if toward a climax — and shatters before it lands]
[Instrumental Collapse - fragments of every theme scattered, unmoored]
[Instrumental Suspension - a single unresolved note, suspended, wrong]
[Instrumental Outro - it does not resolve and does not fade cleanly — it just stops. Silence.]
```

---

## 8. Production & maintenance notes

- **Lengths are floors, 3:00 minimum.** For the 5:00 set-pieces (03, 21, 34,
  41, 48, 57, 58, 59) generate in two passes and stitch, or use Suno **Extend**
  on the best take until it reaches length, then add a manual fade. The
  6–9-section structure boxes give Suno enough material to avoid short renders;
  if a take still stops early, regenerate with the structure box only (drop the
  style box to one line) — Suno respects long structures more than long styles.
- **Instrumental is non-negotiable** except the 14 choir cues in §3, and there
  the choir is massed only — never a soloist, never lead melody, no language
  beyond the massed Latin war-cry / its mirror / wordless vowels.
- **Audition in pairs.** Always listen to a new track against the previous one
  in its category before accepting; if they blur, push levers 1–3 further and
  re-roll those two only.
- **`.ogg`, stereo, 44.1 kHz** per `AUDIO_DESIGN.md §Audio File Conventions`;
  drop into `assets/audio/music/` with the §5 title.
- **Wiring** is out of scope here — `AUDIO_DESIGN.md` covers the MusicPlayer
  autoload, crossfade and ducking. This doc only supplies content.
- **When this doc changes:** add the row to §5 with a distinct lever key; if a
  new cue needs choir, add its number to the §3 list and justify it as a
  battle/high-energy cue; update `CLAUDE.md`'s maintenance reference if the
  track set's scope shifts.
