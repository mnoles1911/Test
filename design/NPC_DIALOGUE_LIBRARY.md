# NPC & Companion Dialogue Library

Reusable conversation frames for any NPC and any companion, in any region. Lore-agnostic.

> **NPC dialogue = Tier 2 conversation per `design/CONVERSATION_SYSTEM.md`.** A structured branching tree. Game pauses. Portrait + text + (NPC-only) voice. Player picks Roland's responses from a list as text — Roland is not voiced in branches (see Roland Voicing Policy in CONVERSATION_SYSTEM.md).

> **Authoring rules:** all dialogue scripts must conform to `dialogue/STYLE.md`. Production scripts go under `dialogue/scripts/conversations/{region_or_act}/{npc_id}.txt`.

---

## Why a Library

Every interactive NPC needs a conversation tree. Every companion needs deepening dialogue across the trilogy. Without a library, writers reinvent topic categories per character and important branches get missed — or worse, get included for the first companion and forgotten for the rest.

The library is a **production checklist**: when assigning conversation content to a new NPC or companion, walk every applicable section and decide whether they need content for it. A villager and a king share the same skeleton; what differs is which branches are filled and how richly.

---

## Two Skeletons: NPCs vs. Companions

NPCs the player meets in the world get one skeleton. Active party companions the player travels with get a richer second skeleton on top. The skeletons share a common base.

```
┌─────────────────────────────────────┐
│ COMMON BASE                         │
│ - Greeting                          │
│ - Information topics                │
│ - Persuasion approaches             │
│ - Refusal / locked content          │
│ - Farewell                          │
└─────────────────────────────────────┘
            │
    ┌───────┴────────┐
    ▼                ▼
┌─────────┐    ┌──────────────┐
│ NPC     │    │ COMPANION    │
│ - Trade │    │ - Personal   │
│ - Quest │    │ - Opinion    │
│ - Rumor │    │ - Approval   │
│ hook    │    │ - Banter     │
│         │    │ - Silence    │
└─────────┘    └──────────────┘
```

---

## COMMON BASE — Used for Every Speaking Character

### Section 1 — Greeting Variants

The first line of any conversation. Choose one variant per speaker per state. State is determined by relationship, story flags, recent player actions, and the meeting count.

| State | When | Tone |
|---|---|---|
| First meeting (cold) | NPC has never spoken to player | Reserved, neutral |
| First meeting (warm) | NPC has reason to expect / welcome the player | Friendly, curious |
| First meeting (hostile) | NPC has reason to dislike the player on sight | Cold, suspicious |
| Returning (default) | Subsequent meetings | Familiar |
| Returning (warm) | Above relationship threshold | Pleased |
| Returning (cold) | After a recent disagreement / approval drop | Curt |
| Returning (hostile) | Below relationship threshold | Dismissive |
| Plot-state reactive | After a major story event the NPC knows about | Varies |

### Authoring template (first meeting, cold)

```
{NPC}: [serious tone] Yes.
{NPC}: [matter-of-fact] Something I can help you with.
{NPC}: [dismissive] If this is about the {LOCAL_ISSUE} you should talk to {OTHER_NPC}.
```

### Authoring template (returning, warm)

```
{NPC}: [lighthearted] Back already.
{NPC}: [happy] Good to see you again.
{NPC}: [reflective] I was hoping you would come by.
```

### Section 2 — Information Topics

The "Tell me about..." tree. Standard topic categories that nearly every NPC should support some subset of. The branching tree lets the player pick a topic; the NPC's response is voiced.

**Topic categories:**

| Topic | Asked of | Variant by NPC type |
|---|---|---|
| `ABOUT_THIS_PLACE` | Anyone in or near a settlement | Innkeeper knows gossip; guard knows trouble; scholar knows history |
| `ABOUT_THIS_REGION` | Anyone in a region | Locals know geography and rumors; travelers know roads and dangers |
| `ABOUT_THIS_FACTION` | Anyone affiliated with or near a faction | Members know politics; outsiders know reputation |
| `ABOUT_A_PERSON` | Anyone who knows the named person | Family knows history; coworkers know habits; rivals know weaknesses |
| `ABOUT_NEWS` | Anyone in a settlement | What has happened recently in the world |
| `ABOUT_RUMORS` | Anyone in a tavern, market, or social space | Hearsay, half-truth, speculation |
| `ABOUT_SELF` | Anyone willing to talk about themselves | Backstory, role, opinions |
| `ABOUT_QUEST_HOOK` | Anyone with a problem | Volunteers a request, side quest, or lead |

Each branch should support at least 2–3 topic depth — the player asks the topic, the NPC's response includes hooks for follow-up branches. A vendor's "ABOUT_THIS_PLACE" might surface a rumor branch; a guard's might surface a trouble branch.

### Authoring template (ABOUT_THIS_PLACE)

```
PLAYER OPTION: Tell me about this place.

{NPC}: [reflective] {LOCATION_NAME}. We have been here longer than the maps say.
{NPC}: [matter-of-fact] {LOCATION_NAME}. Quiet enough until the trouble started.
{NPC}: [lighthearted] You have not been here before. It shows.
```

Each variant should give the player a different hook — history, current trouble, social dynamics. The player learns about the place AND about the NPC by which version they get.

### Authoring template (ABOUT_NEWS — branching to a quest hook)

```
PLAYER OPTION: What has been happening here?

{NPC}: [serious tone] {EVENT}. Two weeks ago. We are still feeling it.

PLAYER OPTION: Tell me more.
PLAYER OPTION: Was anyone hurt?
PLAYER OPTION: I have not heard about that.

{NPC}: [reflective] Most have not. {EVENT_DETAIL}. The road is quieter for it.
```

The branch leads naturally into a follow-up. Information topics are the primary discovery mechanism — every "tell me about" should plant something.

### Section 3 — Persuasion Approaches

When an NPC has something the player wants and is reluctant to give it. The player picks an approach as a labeled branch; the NPC reacts based on character + approach + state.

| Approach | Character lens | Best for |
|---|---|---|
| `[PRESS]` | Direct, threatening, leveraged | NPCs who respect strength |
| `[APPEAL]` | Emotional, relational, asking a favor | NPCs who respect relationships |
| `[HONEST]` | Tell the truth, name the stakes | NPCs who respect candor |
| `[DECEIVE]` | Lie or omit | NPCs who can be misled |
| `[EMPATHIZE]` | Acknowledge their position before asking | NPCs who feel unseen |
| `[BARGAIN]` | Offer something concrete in trade | NPCs who think transactionally |

Not every NPC supports every approach. A frightened informant may only respond to `[APPEAL]` and `[EMPATHIZE]`; a corrupt official may respond only to `[BARGAIN]` and `[DECEIVE]`.

### Authoring template (PRESS approach)

```
PLAYER OPTION: [PRESS] You know what I am asking. Stop wasting my time.

{NPC}: [hesitates] You think I am the only one watching this conversation.
{NPC}: [angry] And what if I do not.
{NPC}: [fearful] Fine. Fine.
```

Each variant assumes a different NPC reaction. Build all three; pick the one that fits the NPC's character.

### Section 4 — Refusal / Locked Content

Some branches are gated by flags, items, relationship level, or knowledge. When a player tries to access locked content, the NPC must refuse without breaking immersion.

| Lock type | Refusal style |
|---|---|
| Story flag not set | Defer: "I am not ready to talk about that" |
| Wrong companion present | Indirect: NPC refuses while companion is in earshot |
| Insufficient knowledge | Confused: "I do not know what you mean" |
| Insufficient relationship | Cold: "Why would I tell you that" |
| Item / proof not held | Skeptical: "If you had {THING}, I would believe you" |
| Quest-state mismatch | Redirect: "Come back when {OTHER_THING}" |

### Authoring template (story-flag refusal)

```
PLAYER OPTION: I want to ask about {LOCKED_TOPIC}.

{NPC}: [reflective] Not now.
{NPC}: [serious tone] Some things I do not discuss with strangers.
{NPC}: [quietly] Ask me again when you have done what you said you would.
```

The refusal should hint at the unlock condition without spelling it out. The player is meant to discover the path.

### Section 5 — Farewell Variants

Closing line. Tone depends on how the conversation went.

| State | Tone |
|---|---|
| Default | Neutral |
| Warm (helped) | Grateful, friendly |
| Cold (refused) | Curt, dismissive |
| Wary (suspicious) | Watchful |
| Reactive (something specific just happened) | Tied to the moment |

### Authoring template (default farewell)

```
{NPC}: [matter-of-fact] Safe travels.
{NPC}: [reflective] Until next time.
{NPC}: [quietly] Be careful out there.
```

---

## NPC-ONLY BRANCHES

These branches are added on top of the common base for NPCs who provide services or surface plot hooks.

### Section 6 — Trade / Service Interactions

For shopkeepers, innkeepers, smiths, healers, transport providers.

| Service type | Required branches |
|---|---|
| Shop | Browse / Buy / Sell / Haggle (optional) / Special stock |
| Inn | Rent room / Buy meal / Listen for rumors / Inquire about other guests |
| Smith | Repair / Upgrade / Commission / Inspect player gear |
| Healer | Treat injury / Cure ailment / Buy supplies / Diagnostic |
| Transport | Travel to {DESTINATION} / Schedule / Cost / Refuse |

Each service should also support the **common base** branches above — a shopkeeper is a person, not just a vending machine. They have a region, a faction (maybe), opinions, and rumors.

### Authoring template (shop browse opener)

```
{NPC}: [lighthearted] Take a look. I just got new stock yesterday.
{NPC}: [matter-of-fact] Anything in particular.
{NPC}: [tired] Browse if you want. I am closing in an hour.
```

### Section 7 — Quest Hook Volunteer

Some NPCs have a problem they want the player to address. The hook lives behind a player-initiated branch (often `ABOUT_THIS_PLACE` or `ABOUT_NEWS`) and offers an opt-in quest.

**Standard structure:**

1. NPC alludes to the problem in an information topic
2. Player can ask for details
3. NPC explains
4. Player can accept, decline, or defer ("come back to me")

### Authoring template

```
{NPC}: [serious tone] I have a problem. If you have a moment.

PLAYER OPTION: Tell me.
PLAYER OPTION: Not now.
PLAYER OPTION: What is in it for me?

{NPC}: [reflective] {PROBLEM}. I would do it myself if I could.

PLAYER OPTION: I will help.
PLAYER OPTION: I will think about it.
PLAYER OPTION: This is not my fight.
```

---

## COMPANION-ONLY BRANCHES

These branches are added on top of the common base for active party companions. They are what make a companion a *character* rather than a follower.

### Section 8 — Personal / Backstory Questions

The companion's history, family, beliefs, motivations. Gated by relationship progression — early-game branches are surface, late-game branches are vulnerable.

**Standard topic categories:**

| Topic | Unlock condition | Tone progression |
|---|---|---|
| Origin / where they are from | Always available | Surface → personal |
| Family | Relationship tier 1+ | Reluctant → open |
| Why they joined the party | Relationship tier 1+ | Practical → honest |
| Their craft / role | Always available | Professional → reflective |
| Their beliefs / faith | Relationship tier 2+ | Cautious → open |
| Their fears | Relationship tier 3+ | Deflected → admitted |
| Their regrets | Relationship tier 3+ | Refused → confessed |
| What they want | Relationship tier 4+ | Vague → specific |

The progression matters. A companion who answers vulnerable questions on first meeting feels written-thin. The same companion who deflects early and opens late feels real.

### Authoring template (Origin, surface)

```
PLAYER OPTION: Where are you from?

{COMPANION}: [matter-of-fact] {ORIGIN}. Small place. You would not have heard of it.
{COMPANION}: [reflective] {REGION}. I have not been back in some years.
{COMPANION}: [dismissive] North. It does not matter.
```

### Authoring template (Origin, deepened — same character later in trilogy)

```
PLAYER OPTION: Tell me about where you grew up. Really.

{COMPANION}: [quietly] {SPECIFIC_PLACE_NAME}. We had a {SPECIFIC_DETAIL}. My {RELATIVE} taught me {SKILL} on it.
{COMPANION}: [wistful] You can still see it from the road, if you know where to look.
{COMPANION}: [hesitates] I would rather not. Not tonight.
```

The same topic, the same companion, two different relationship states. The player is rewarded for time invested.

### Section 9 — Opinion Prompts

The player asks the companion what they think of a topic, person, place, or recent event.

| Prompt type | When |
|---|---|
| What do you think of {LOCATION}? | Always available in any location |
| What do you think of {NPC}? | Once player has met both companion and NPC |
| What did you think of {RECENT_EVENT}? | Triggered by recent quest events |
| What do you think of {OTHER_COMPANION}? | When both are in the party |
| Are you alright? | Triggered by recent emotional beats |

### Authoring template (opinion of another companion)

```
PLAYER OPTION: What do you think of {OTHER_COMPANION}?

{COMPANION}: [reflective] {OTHER_COMPANION} is...
{COMPANION}: [matter-of-fact] We are not friends. We work together. That is different.
{COMPANION}: [lighthearted] Better than I expected. Do not tell them I said that.
```

These branches reveal companions through how they see each other. Often the most-loved party banter in any RPG.

### Section 10 — Approval / Disapproval Reactions

When the player makes a choice, the companion silently reacts. The reaction lives in their disposition meter (background) but should also surface in a barked or branched line at the next available moment.

| Reaction strength | Surface as |
|---|---|
| Strong approval | Bark on next exchange + raised disposition |
| Mild approval | Quiet bark or look |
| Neutral | No surfacing |
| Mild disapproval | Cold bark or comment |
| Strong disapproval | Confrontation branch unlocks at next conversation |

### Authoring template (strong disapproval confrontation)

```
{COMPANION}: [serious tone] We need to talk about what you did at {LOCATION}.

PLAYER OPTION: I made the only choice I could.
PLAYER OPTION: I know. I am sorry.
PLAYER OPTION: Drop it.

{COMPANION}: [angry] You did not. There was another way.
{COMPANION}: [quietly] I am not asking for an apology. I am telling you it cost me something.
```

These confrontations are how relationships deepen *or break*. They should be rare and earned.

### Section 11 — Banter Prompts

See `BARK_LIBRARY.md` Category 5 for the bark-side trigger system. The companion dialogue tree should also include **player-initiated banter prompts** — the player asks a companion to comment on something the other companion said or did.

```
PLAYER OPTION: {OTHER_COMPANION} said something earlier. Did you hear?

{COMPANION}: [matter-of-fact] I heard.
{COMPANION}: [reflective] They are not wrong.
{COMPANION}: [dismissive] {OTHER_COMPANION} talks too much.
```

### Section 12 — Silence / Decline to Talk

Sometimes a companion is not in the mood. After a heavy story beat, after a recent fight with the player, after entering a personally significant location — the companion declines to engage.

### Authoring template (post-event silence)

```
{COMPANION}: [tired] Not now.
{COMPANION}: [quietly] Give me some time.
{COMPANION}: [hesitates] I cannot. Not tonight.
```

The silence is the line. Do not write a "deeper" branch trying to coax them. The player who pushes hits a hard wall; the player who waits gets the next conversation richer for it.

### Section 13 — Relationship Gates

Major reveals — the companion's deepest secret, the trauma that drives them, the thing they have never told anyone — live behind relationship gates. The gate is a flag set by accumulated approval and specific shared experiences.

Each companion should have exactly **one** locked-tier conversation. It is the relationship arc's payoff. It should never trigger by approval-grinding alone — it requires a specific event the player must have witnessed or an item they must have found.

### Authoring template (gated reveal)

```
{COMPANION}: [reflective] You found {ITEM} in {LOCATION}, did you not.

PLAYER OPTION: I did.
PLAYER OPTION: I did not understand what it was.

{COMPANION}: [quietly] I have not told anyone what that means. I am going to tell you now.
```

This conversation is the dramatic peak of that companion's arc. Treat it as a Tier 3 story beat per `CONVERSATION_SYSTEM.md`, not a Tier 2 standard conversation. Camera, framing, voiced player lines — the works.

---

## Authoring Checklist Per Character

When commissioning content for a new NPC or companion, walk this list:

**For every NPC:**
- [ ] Greeting variants (default, plus 1–2 contextual)
- [ ] Farewell variants (default, plus 1–2 contextual)
- [ ] At least 2 information topics from Section 2 (always: ABOUT_THIS_PLACE, plus one more)
- [ ] At least 1 persuasion approach if the NPC gates content
- [ ] Refusal lines for any locked branches
- [ ] If they sell or service: full Section 6 trade tree
- [ ] If they have a problem: Section 7 quest hook structure

**For every companion (in addition to NPC checklist):**
- [ ] All 8 personal-question topics from Section 8, with surface and deepened tiers
- [ ] At least 4 opinion prompts (location, two NPCs, one event)
- [ ] Approval reactions for at least 6 major story choices
- [ ] Banter pool with each other companion (paired files in `barks/banter/`)
- [ ] Silence lines for at least 2 specific story beats
- [ ] One relationship-gate locked conversation as their arc payoff

---

## File Layout

```
dialogue/
└── scripts/
    └── conversations/
        ├── {region_or_act}/
        │   ├── {npc_id}.txt          ← per-NPC conversation tree
        │   └── ...
        └── companions/
            ├── {companion_id}/
            │   ├── personal.txt       ← Section 8
            │   ├── opinion.txt        ← Section 9
            │   ├── approval.txt       ← Section 10
            │   ├── silence.txt        ← Section 12
            │   └── gated_reveal.txt   ← Section 13 (Tier 3, also gets a draft in dialogue/drafts/)
            └── ...
```

Trigger IDs in scripts (e.g. `# ABOUT_THIS_PLACE`) are the contract between the library and the in-game branching system. Use the IDs from this document verbatim so any future writer or programmer can wire scripts to triggers without ambiguity.

---

## Cross-References

- `dialogue/STYLE.md` — TTS formatting and tag rules
- `design/CONVERSATION_SYSTEM.md` — tier system; Tier 2 (this document) and Tier 3 (gated reveals)
- `design/BARK_LIBRARY.md` — barks (Tier 1) including paired companion banter
- `design/SYSTEMS_DESIGN.md` — branching flag logic, companion observation system, journal integration
