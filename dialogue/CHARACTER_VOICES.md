# Character Voice Notes

Per-character voice direction for the TTS pipeline. These notes are reference material for casting and prompt-side voice configuration — they are NOT embedded in script files. Scripts must follow `dialogue/STYLE.md` and contain only spoken text plus approved `[tags]`.

> **Scope.** This file holds the *acting direction* (what the character sounds like) and the *render contract* (which ElevenLabs voice + which settings produce that sound). The render contract is the binding between this file and the audio in `audio/dialogue/`. Change a render setting here and the next regeneration will match. Edit a render setting in the ElevenLabs UI without updating this file and the next person to render the scene will get a different voice. The file is the source of truth.

---

## Render Contract — Field Reference

Each character section ends with a fenced **Render Contract** block. Fields:

| Field | Meaning | Notes |
|---|---|---|
| `voice_id` | ElevenLabs voice ID (UUID-style string) | Locked once a calibration clip lands. Never swap voice IDs casually — rerendering a 30-hour game is the cost. |
| `voice_name` | Human-readable label for the voice in your ElevenLabs library | For finding it in the UI. Not used by the API. |
| `model` | TTS model to use | Default: `eleven_v3` for cut scenes (best tag interpretation), `eleven_turbo_v2_5` for high-volume bark batches (cheaper, faster, slightly less nuance). |
| `stability` | 0.0–1.0. Lower = more emotional range, higher = more uniform | Cut scenes 0.30–0.45. Barks 0.50–0.65 (consistency matters more than range when you have 200 takes). |
| `similarity_boost` | 0.0–1.0. How tightly the model anchors to the source voice | 0.70–0.85 for most characters. Lower if the voice sounds locked/robotic; higher if it drifts. |
| `style` | 0.0–1.0. Style exaggeration | Default 0.0. Above 0.30 the model overacts; only nudge up for villains or extreme deliveries. |
| `speed` | 0.7–1.2. Playback rate | Default 1.0. Use the `[fast]` / `[slowly]` tags before reaching for this — speed changes pitch and reads as broken voice acting if pushed. |
| `use_speaker_boost` | bool | Default `true`. Disable only if the voice sounds processed/"loud". |
| `seed` | int or `null` | Lock to a specific int once a calibration clip is approved (per `STYLE.md` §7.3). `null` = non-deterministic, only acceptable during pre-calibration. |
| `calibration_clip` | Path to the approved calibration audio | The reference take. Compare every regeneration against it. |

**Locking rule.** Once a character has shipped voiced content, any change to `voice_id`, `seed`, `model`, or `stability ±0.05` triggers a rerender of all that character's existing audio. Treat changes as a retake, not a tweak.

---

## ROLAND (Roland Ashford)

- Low and unhurried. Practiced calm.
- Words chosen carefully — never more than the sentence requires.
- Ashfields cadence: flat vowels, clean consonants, slight broadening on certain words.
- When angry, gets quieter, not louder.
- One tell: a slight pause before saying something he has decided he must say and wishes he didn't.
- Default delivery tags: `[calm]`, `[quietly]`, `[matter-of-fact]`, `[tired]`, `[reflective]`.

```yaml
# Render Contract — ROLAND
voice_id: TBD                       # locked after Milestone 5 calibration
voice_name: TBD
model: eleven_v3
stability: 0.40                     # carries quiet→angry without overacting
similarity_boost: 0.78
style: 0.0
speed: 1.0
use_speaker_boost: true
seed: null                          # lock to int once calibration clip is approved
calibration_clip: audio/dialogue/_calibration/roland.ogg
```

## TOMLIN

- Archivist's voice — precise pronunciation, verbal footnotes ("which is to say," "that is").
- Slightly too much breath under the words.
- When frightened, the footnotes increase. When approaching a hard decision, they stop and he goes plain.
- Default delivery tags: `[nervous]`, `[stuttering]`, `[hesitates]`, `[quietly]`.
- For the moment of resolve, drop tags entirely or use `[serious tone]`.

```yaml
# Render Contract — TOMLIN
voice_id: TBD
voice_name: TBD
model: eleven_v3
stability: 0.32                     # lower — needs the footnote-anxiety range
similarity_boost: 0.80
style: 0.0
speed: 1.0
use_speaker_boost: true
seed: null
calibration_clip: audio/dialogue/_calibration/tomlin.ogg
```

## CALLA (Dame Calla Vane)

- Eldermark aristocracy, worn in. Not crisp, not performative.
- Has been giving orders for thirty years. Voice knows exactly how much force each sentence requires. Never raised.
- Warmth is in the register but arrives rarely.
- Stillness — she made her decisions long ago.
- Default delivery tags: `[authoritative]`, `[calm]`, `[serious tone]`, `[reflective]`, `[quietly]`.

```yaml
# Render Contract — CALLA
voice_id: TBD
voice_name: TBD
model: eleven_v3
stability: 0.50                     # higher — stillness reads as low variance
similarity_boost: 0.82
style: 0.0
speed: 0.97                         # one notch slow; she is unhurried by nature
use_speaker_boost: true
seed: null
calibration_clip: audio/dialogue/_calibration/calla.ogg
```

---

## Adding a New Character

1. Write the prose voice notes (same style as the three above) — what they sound like, what they default to, what shifts under pressure.
2. In ElevenLabs, audition voices against the calibration script (one line each of: baseline, an emotional extreme, a quiet line, a long sentence with a proper noun from `PRONUNCIATION.md`).
3. When a voice lands, create a `_calibration/{name}.ogg` reference clip and fill in the Render Contract block with the locked voice ID and settings.
4. From that point on, every render of that character uses the contract verbatim. If the voice drifts, rerender against the calibration clip — do not re-tune settings without updating this file.
