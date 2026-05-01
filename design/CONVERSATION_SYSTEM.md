# Conversation System Design

How dialogue is presented, voiced, and structured in Game One.

> For dialogue flag logic and branching mechanics, see `design/SYSTEMS_DESIGN.md`.
> For TTS script formatting rules, see `dialogue/STYLE.md`.
> For phonetic respellings of proper nouns, see `dialogue/PRONUNCIATION.md`.

---

## The Core Problem

Voxel characters cannot act. Their faces do not move. Their hands do not gesture expressively. Any attempt to animate full cut scenes with low-poly voxel models draws attention to the format's limits rather than the story's strengths.

The question is therefore not *how do we animate cut scenes* — it is **where does the emotional work happen if not the character model?**

The answer: **the emotional work is split across four visual layers**, each doing what it is best at.

- The **voxel world** is good at *place* — stone, forests, firelight, the weight of old buildings.
- **Portraits** are good at *character* — faces, grief, the specific look someone gives you when they know they're in trouble.
- **Tableau framing** is good at *gravity* — telling the player that this moment matters more than the last one.
- **Illustrated keyframes** are good at *myth* — moments that transcend the scene and should be remembered.

No layer tries to do another layer's job.

---

## The Four-Tier Conversation System

Every conversation in the game belongs to one of four tiers. The tier determines the visual presentation, the voice approach, and the authoring cost.

---

### Tier 1 — Barks

**Used for:** Companion reactions during exploration, Roland's internal monologue when he investigates objects, ambient NPC lines when the player passes close, combat callouts.

**Visual:** A small portrait + short text appears in a corner overlay. The game does not pause. The camera does not move. The player keeps walking.

**Voice:** Always voiced. Short lines. Spatial audio — the sound comes from the character's position in the world.

**Authoring cost:** ~5 minutes per line.

**Examples:**
- Corvus muttering about a magical anomaly as the party enters a room
- Roland's narration noting the smell of old vellum as he reaches the Archive door
- An Aldenholt street vendor saying something in passing

**Why this works:** Hades, Bastion, and Pyre built entire emotional relationships between player and companion through this tier alone. Players absorb far more ambient voice than they realize — it makes the world feel inhabited without breaking pacing.

---

### Tier 2 — Standard Conversations

**Used for:** Most NPC interactions, side quest dialogues, vendor exchanges, branching conversation trees, information gathering.

**Visual:** Dialogic 2 full dialogue UI. Portrait + name plate + text box. Game pauses. Companion observations appear as brief portrait interjections (per `design/SYSTEMS_DESIGN.md`).

**Voice:** NPCs always voiced. Roland's chosen responses — text only, no voice (see the Roland Voicing Policy below).

**Authoring cost:** ~30 minutes per conversation.

**Examples:**
- Tomlin denying the key exists (before `henrietta_dead = true`)
- Any "where can I find X" information exchange
- A vendor in Solgrade with contextual dialogue updates

**Why this works:** The portrait carries the emotional information the voxel model cannot. At 256×320 pixels with expression variants, a portrait communicates more in one glance than a voxel character could in a minute of animation.

---

### Tier 3 — Story Beat Scenes

**Used for:** Major character moments — confrontations, revelations, quiet turning points. The scenes that the player will remember.

**Visual:** Camera cuts to a curated angle framing both characters. Characters are *posed* (placed deliberately, not animated). The background dims slightly. A full portrait appears. Voice plays over text. Lighting shifts subtly — a lamp extinguished, a candle closer, a change in the ambient world environment. The game is paused but the world is visible.

**Voice:** Fully voiced — both NPCs and Roland's fixed (non-branching) lines.

**Authoring cost:** ~2 hours per scene.

**Examples:**
- The Roland / Dame Calla chapel negotiation (Act I)
- The Roland / Tomlin sorting room persuasion (Act I)
- Yaromir answering "what do you want to be remembered for" (Act II)
- Bromrin asking Roland to make him a promise in the descent (Game Two)

**Why this works:** Disco Elysium's conversations are Tier 3 scenes. Characters stand still. The camera holds. The writing and voice do all the work. The scene feels significant not because characters are animating — because the *framing* signals that this moment deserves the player's full attention.

Implementation: Godot `AnimationPlayer` drives a camera lerp to the staged angle, portrait fade-in, and lighting tweak. This is a reusable scene template — author it once, fill with content per scene.

---

### Tier 4 — Illustrated Keyframes

**Used for:** The handful of moments per act that transcend their setting. Flashbacks, myth-scale revelations, the emotional peaks of the trilogy.

**Visual:** Full-screen hand-illustrated artwork replaces the world entirely. Voice plays over the image. A slow camera pan across the artwork. Then back to gameplay.

**Voice:** Always fully voiced. No text unless accessibility options require it.

**Authoring cost:** ~1 day of authoring + illustration time per keyframe.

**Examples (planned across the trilogy):**
- Roland finding the hidden chapel in the Ashfields (Game One backstory)
- Henrietta pressing the notes into Roland's coat at the Archive door
- The first sight of Drûn-Khazad from the caldera ridge (Game Three)
- Aldric Vane at his forge, before he knows what he is

**Target volume:** 6–10 per game, no more. Rarity is what makes them land. A game with 40 illustrated keyframes has none — they blend into the wallpaper.

**Why this works:** One illustration carries a full minute of dramatic weight. Players remember Wildermyth's painted moments years later — not the isometric scenes around them. The visual split between the voxel world and the painted keyframe signals: *this is different, pay attention, you will not come back to this exact moment.*

---

## The Roland Voicing Policy

### The problem with voicing player character branches

In a branching dialogue tree, the player selects Roland's response from a list. If Roland is voiced, two problems follow:

1. **The mismatch problem.** The player reads the option summary, forms an expectation, clicks — and hears Roland deliver a line with different tone, pace, or emphasis than intended. The character becomes a stranger. Mass Effect's dialogue wheel ships with thousands of these moments.

2. **The volume problem.** A conversation with 3 options at 5 nodes generates 15 Roland lines, of which any player hears 5. The other 10 are generated and never played. Across a 30-hour RPG this triples the production cost for content no one hears.

There is also a subtler benefit to keeping Roland unvoiced in branches: players build their own internal voice for the protagonist. Roland's written voice is distinctive and strong. Players who read his choices in their own head feel a degree of ownership over the character that full voicing tends to erase.

### The policy

**Voice Roland:**
- All fixed-script story beat lines (Tier 3 scenes where Roland has no branching options)
- All Tier 4 illustrated keyframe narration
- Tier 1 internal monologue triggers (single committed line, no branches)

**Do not voice Roland:**
- Branching response options in any dialogue tree
- "What would you like to ask about?" menu selections
- Approach options (Persuade / Press / Honest / Empathetic etc.)

**The rhythm this creates:** Players spend most conversations hearing Roland as text — *their* Roland. Then a Tier 3 story beat arrives, Roland speaks aloud, and the voice lands with disproportionate weight. It is a tool reserved for moments that earn it.

This is what Disco Elysium does with the Detective. His branching responses are text. His Skills — Inland Empire, Volition, Logic — speak aloud as distinct characters. The result is that the voiced elements feel like characters while the Detective feels like the player.

---

## Text-to-Speech (TTS) Pipeline

TTS — Text-to-Speech — is the software that converts written dialogue scripts into spoken audio. A script file is fed to the TTS model; the model outputs an audio clip of the character speaking those lines. That audio is imported into Godot and attached to the Dialogic timeline.

The tags in scripts (`[tired]`, `[quietly]`, `[hesitates]`) are performance directions — the equivalent of a director's note to a voice actor, embedded in the text the model reads.

### What TTS enables

A solo or small-team production voicing a 30-hour RPG with professional actors is a $150,000–$200,000 problem. With a well-configured TTS pipeline and the tagged script format documented in `dialogue/STYLE.md`, it becomes a workflow problem — slower than flipping a switch, faster and cheaper than a recording studio.

### What TTS cannot do

- Improvise. Every line must be written before it exists in audio.
- Perform complex physical states convincingly. `[whispering]` mixed under game audio at normal volume will be inaudible. `[shouting]` in a quiet interior reads as broken performance.
- Pronounce lore-specific proper nouns reliably. See `dialogue/PRONUNCIATION.md` for phonetic respellings.

### The two-stage authoring workflow

Every voiced scene goes through two versions:

1. **Prose draft** (`dialogue/drafts/*.md`) — written for humans. Full subtext, stage directions, designer intent, character voice notes. The source of truth for what the scene means.

2. **TTS script** (`dialogue/scripts/*.txt`) — written for the model. No stage directions, no subtext, only spoken text with approved tags. The production artifact.

Revise the draft. Regenerate the script from it. Never edit the script for narrative reasons — it will drift from intent.

---

## Why This Approach Over the Alternatives

**Over fully animated cut scenes:** Animating voxel characters at the level required for emotional performance is disproportionately expensive and draws attention to format limits rather than story strengths. No tier of this system requires character animation beyond idle loops.

**Over pure text with no voice:** Voice carries emotional performance that text cannot. A well-tagged TTS line of Calla saying "I should have found another way" lands differently than reading it. For a game whose core strength is its writing and character work, voice amplifies rather than competes.

**Over full voice acting for every line:** Cost, volume, and the Roland branching problem. Tiering the voice approach means the production budget concentrates on the moments that earn it.

**Over a single visual mode for all conversations:** Different moments require different treatments. A vendor exchange and the summit of Drûn-Khazad do not deserve the same presentation. The tier system is the mechanical expression of the game's governing belief: *choices have weight because context is real.*

---

## Files and Reference

| File | Purpose |
|---|---|
| `dialogue/STYLE.md` | TTS script formatting rules, tag reference, authoring patterns |
| `dialogue/CHARACTER_VOICES.md` | Per-character voice notes for casting and TTS configuration |
| `dialogue/PRONUNCIATION.md` | Phonetic respellings for proper nouns |
| `dialogue/drafts/` | Prose drafts (source of truth) |
| `dialogue/scripts/` | TTS-ready clean scripts (production artifacts) |
| `design/SYSTEMS_DESIGN.md` | Dialogue flag logic, branching mechanics, companion observations |
| `design/DIALOGIC_SETUP.md` | Dialogic 2 installation and timeline configuration |
