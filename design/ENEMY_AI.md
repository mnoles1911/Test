# Enemy AI Design

How enemies perceive the world, decide what to do, and fight.

> Cross-reference: `design/COMBAT_DESIGN_3D.md` for the full combat mechanic spec (attack types, parry windows, health/endurance).
> `design/SYSTEMS_DESIGN.md` for the enemy roster and design principles.
> `design/SKILLS_AND_PROGRESSION.md` for how Roland's progression affects enemy difficulty.
> `design/COMBAT_NEXT_PHASES.md` for what's actually implemented today vs. what remains, plus the prioritized order for building Ashfallen / Wolf / Bear and the group AI / attack-token system described below.

> **Implementation status:** `Enemy3D` base class (state machine + damage / death + corpse looting) and `Goblin` v1 are live as of May 2026. Goblin uses a stripped-down "walk toward player + contact damage" loop — full attack pool, group alerts, swarm override, and fleeing all per spec but not yet built. Ashfallen, Wolf, Bear specs below are unimplemented.

---

## Design Philosophy

**Every enemy is a real threat.** Even a lone goblin can hurt a careless Roland. Enemies are not bags of HP to drain — they are opponents with behavior patterns the player learns to read. The game is not easy, but it is legible.

**Enemies do not scale.** A goblin at the end of the game is the same goblin as at the beginning. Roland's growth makes him more capable — it does not inflate the enemies to compensate. This means early enemies stay easy once mastered, which is itself a form of feedback: the player can feel their own improvement.

**Behavior over stats.** An Ashfallen knight is dangerous not because it has high HP but because it blocks effectively, telegraphs differently, and punishes careless aggression. The design of each enemy type is expressed in their movement and attack patterns, not their number values.

**No invisible complexity.** The player should be able to predict enemy behavior after a few encounters. An enemy that does surprising things in a predictable, learnable pattern is good design. An enemy that randomly does something different each time is not.

---

## Detection System

Enemies exist in one of four states: **Idle**, **Alerted**, **Searching**, and **Combat**.

### Detection Values

Each enemy type has tunable properties that govern awareness:

| Property | Description |
|---|---|
| `vision_range` | Maximum line-of-sight distance to spot Roland (checked each physics tick) |
| `vision_angle` | Field of view cone (forward arc in degrees) |
| `hearing_range` | Distance at which loud sounds (sprinting, combat) trigger alert |
| `alert_threshold` | Number of "alert ticks" required before entering Combat state |
| `disengage_distance` | Distance Roland must reach for the enemy to begin disengaging |
| `disengage_time` | Seconds the enemy must fail to close the gap before returning to Idle/Patrol |
| `group_alert_radius` | Distance within which nearby enemies of the same type are notified when one enters Combat |

### State Transitions

**Idle → Alerted:** Roland enters `vision_range` within `vision_angle`, or a sound event within `hearing_range` fires. The enemy faces Roland, alert ticks begin.

**Alerted → Combat:** Alert ticks reach `alert_threshold`. No grace period — once committed, the enemy attacks.

**Alerted → Idle:** Roland leaves detection range or breaks line-of-sight before alert threshold is reached. Tick count resets.

**Combat → Searching:** Roland breaks line-of-sight and puts enough distance to trigger disengage check. Enemy moves to Roland's last known position, patrols briefly.

**Searching → Idle:** Enemy cannot find Roland within `disengage_time`. Returns to patrol route.

**Combat → Dead:** HP reaches 0. Death animation plays.

### Group Alert

When one enemy enters Combat, all enemies within `group_alert_radius` of the same faction immediately enter Alerted state (not Combat — they require their own alert threshold, but it starts filling). This simulates a shout. Goblins have a large group alert radius — they are pack animals. Ashfallen have a medium radius. Wolves alert their pack immediately.

---

## Behavior States in Detail

### Patrol

Idle enemies follow a patrol route defined by a sequence of `SpawnPoint3D` nodes in the scene (or patrol waypoints distinct from SpawnPoints — whichever is simpler to author in the editor). Routes loop. Patrol is slow and the enemy can be avoided by a patient player.

An enemy on patrol has reduced detection — their vision angle is narrower and their hearing range is slightly lower. This models an enemy whose attention is elsewhere.

### Combat AI Loop

Each enemy runs a simple decision loop in `_physics_process()`:

1. **Close gap:** Move toward Roland at combat speed unless already within attack range.
2. **Attack decision:** When within attack range, select an attack from the enemy's attack pool based on weighted probability. Factor in: Roland's current state (blocking, recovering, charging), current cooldown, and any special conditions (flanked by another enemy = coordinate attack).
3. **React to Roland:** If Roland initiates a power attack, check if enemy can block or dodge. If Roland is staggered, increase aggression.
4. **Recovery:** After attacking, enter a recovery window. Cannot attack again until recovery is complete.
5. **Group tactics:** If other enemies of the same group are also in combat, use group spacing logic (no two enemies should occupy the same attack position — see Group Combat below).

### Group Combat

When multiple enemies fight Roland simultaneously, they use a simple token system:

- One enemy at a time holds the **attack token**. That enemy is actively pressing the fight.
- Other enemies **orbit** at mid-range, waiting for the token, or performing feints.
- The token transfers when: the current attacker completes a recovery window, is staggered, is killed, or a timeout expires.
- This prevents the "six enemies all swinging at once" scenario that makes group combat feel impossible. Typically two or three enemies press at a time while others orbit.

**Flanking:** An enemy that reaches Roland's rear arc (behind 120° cone) gets a flanking bonus: +20% damage, removes Roland's ability to parry (can only dodge). This rewards enemies for surrounding Roland and rewards Roland for maintaining positioning.

---

## Enemy Types — Game One

### Goblin

**Role:** Numerous, individually weak, dangerous in packs.

| Property | Value |
|---|---|
| vision_range | 12m |
| vision_angle | 100° |
| hearing_range | 10m |
| alert_threshold | 2 ticks |
| group_alert_radius | 15m |
| disengage_distance | 25m |

**Attack pool:**
- **Jab** (50% weight) — fast, low damage. Rapid recovery. The constant pressure move.
- **Swing** (35%) — slightly slower, slightly more damage. Can be parried cleanly.
- **Leap** (15%) — short forward lunge. Unblockable but telegraphed (crouch before leap). Must dodge. Only triggers at mid-range.

**Behavior notes:** Goblins swarm. Their individual behavior is simple; their danger is coordination. They will not wait for the attack token politely — at high numbers (4+), multiple goblins attempt simultaneous attacks. This is intentional: handling multiple goblins requires Roland to reposition constantly, use terrain, and use throwables. A Roland standing still against six goblins will die.

**Fleeing:** Goblins without support (last one standing) have a 60% chance to attempt flight. This is not cowardice — it is the design intent. A fleeing goblin that escapes may return with reinforcements (if scripted for that encounter).

---

### Ashfallen

**Role:** The signature elite enemy. Slow, deliberate, well-armored. A former knight like Roland.

| Property | Value |
|---|---|
| vision_range | 18m |
| vision_angle | 90° |
| hearing_range | 8m |
| alert_threshold | 3 ticks |
| group_alert_radius | 12m |
| disengage_distance | 20m |

**Attack pool:**
- **Measured swing** (40%) — a deliberate, telegraphed attack. Green parry window — rewarded with a parry, Roland gets a riposte opportunity. Punishes waiting too long.
- **Heavy blow** (25%) — yellow flash. Block at stamina cost, or dodge. Staggers Roland if it lands.
- **Unblockable thrust** (20%) — red flash. Must dodge. Thrust forward with very short wind-up. Catches players who over-rely on blocking.
- **Shield bash** (15%, only if Ashfallen carries a shield variant) — knocks Roland back, creates opening for follow-up.

**Behavior notes:** Ashfallen are patient. Their attack token hold time is longer than goblins — they will wait for an opening, feint with a heavy blow setup, then follow with a thrust. Fighting two Ashfallen is significantly harder than fighting four goblins because they do not rush recklessly.

The **design pressure** of Ashfallen: some wear gear matching Chalice Order knights the player may have seen in flashbacks or mentioned NPCs. This is not a mechanical distinction — it is tonal. The recognition should cause hesitation. That hesitation is the intent.

**Fleeing:** Ashfallen do not flee. They disengage strategically (back off to reset, re-approach). Dying in combat is acceptable to them in a way it is not to goblins.

---

### Wolf

**Role:** Fast, agile, flanker. Punishes static fighting style.

| Property | Value |
|---|---|
| vision_range | 20m |
| vision_angle | 120° |
| hearing_range | 15m |
| alert_threshold | 1 tick |
| group_alert_radius | 20m |
| disengage_distance | 30m |

**Attack pool:**
- **Lunge** (60%) — short-range leap attack. Unblockable. Must dodge left or right. Very fast wind-up.
- **Bite** (30%) — close range, fast. Can be parried with a narrow window.
- **Flank circle** (10%) — wolf repositions to Roland's flank or rear without attacking. Sets up subsequent lunge for flanking bonus.

**Behavior notes:** Wolves do not orbit with the token system — they are too fast. Instead, wolf packs use a loose relay: one wolf lunges while others reposition. The effect is constant movement pressure. A Roland who stays still will be flanked.

Wolves can be heard before they are seen (panting, movement in undergrowth). This is the audio system's contribution to encounter legibility.

---

### Bear

**Role:** Solo mini-boss. Overwhelming force. Rewards patience over aggression.

| Property | Value |
|---|---|
| vision_range | 15m |
| vision_angle | 80° (but detects sound from 20m) |
| hearing_range | 20m |
| alert_threshold | 2 ticks |
| group_alert_radius | 0 (bears are solitary) |
| disengage_distance | 30m |

**Attack pool:**
- **Charge** (40%) — telegraphed run directly at Roland. Unblockable. Must dodge perpendicular. Very high damage if it connects.
- **Claw swipe** (35%) — close range, wide arc. Yellow flash. Block at heavy stamina cost, or dodge.
- **Bite** (25%) — fast, close range. Green flash, but narrow window.
- **Rear** — special behavior when below 30% HP: bear rears on hind legs. Brief vulnerable window (increased damage taken). Then comes down with a slam — unblockable, must dodge.

**Behavior notes:** Bears are not encountered in groups. One bear is a full encounter. The correct play is: dodge the charge, get in one or two swings, back off, reset. Aggressive players who try to trade swings with a bear learn quickly that bear damage output is severe.

Bears respawn over time unless a quest flag marks the area cleared.

---

## Death, Loot, and Despawn

**On death:**
- Death animation plays (unique per enemy type — a goblin dies differently than an Ashfallen)
- Body becomes a lootable container for ~60 real-time seconds, then despawns
- Loot is what the enemy visibly carried — no random drop table. An unarmored goblin drops no armor. An Ashfallen in mail drops a degraded mail piece.

**Area clear flags:**
- Scripted encounters (story-tied groups) set a `GameState` flag when cleared: `"cleared_" + encounter_id`. These do not respawn.
- World patrol groups respawn after a `WorldClock`-based timer (typically 3–5 in-game days).

---

## GDScript Notes

### EnemyAI state machine skeleton

```gdscript
class_name EnemyAI
extends CharacterBody3D

enum State { IDLE, PATROL, ALERTED, SEARCHING, COMBAT }
var state: State = State.IDLE

var alert_ticks: int = 0
var disengage_timer: float = 0.0

func _physics_process(delta: float) -> void:
    match state:
        State.IDLE:      _tick_idle(delta)
        State.PATROL:    _tick_patrol(delta)
        State.ALERTED:   _tick_alerted(delta)
        State.SEARCHING: _tick_searching(delta)
        State.COMBAT:    _tick_combat(delta)
```

### Group alert broadcast

```gdscript
func _enter_combat() -> void:
    state = State.COMBAT
    # Notify nearby allies
    var space := get_world_3d().direct_space_state
    var query := PhysicsShapeQueryParameters3D.new()
    # sphere at self position, radius = group_alert_radius
    for ally in _get_nearby_allies(group_alert_radius):
        if ally.state == State.IDLE or ally.state == State.PATROL:
            ally.alert_ticks = max(ally.alert_ticks, ally.alert_threshold - 1)
            ally.state = State.ALERTED
```

### Attack token system

```gdscript
# EnemyGroup.gd — manages token passing for a set of enemies in the same encounter
var current_attacker: EnemyAI = null

func request_attack_token(requester: EnemyAI) -> bool:
    if current_attacker == null or not is_instance_valid(current_attacker):
        current_attacker = requester
        return true
    return false

func release_attack_token(requester: EnemyAI) -> void:
    if current_attacker == requester:
        current_attacker = null
```
