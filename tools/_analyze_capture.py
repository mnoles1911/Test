import json, sys
from collections import defaultdict

P = r"C:\Users\Matt Noles\AppData\Roaming\Godot\app_userdata\Game One\profile_capture_118708.json"

with open(P, 'r', encoding='utf-8') as f:
    data = json.load(f)

print(f"version={data.get('version')} duration_ms={data.get('duration_ms')} frames_meta={data.get('frames')}")
records = data['records']
print(f"records len: {len(records)}")
print(f"record0 keys: {list(records[0].keys())}")
print(f"record0 frame={records[0].get('frame')} total_us={records[0].get('total_us')}")
print(f"record0 engine={records[0].get('engine')}")
print(f"record0 zylann={records[0].get('zylann')}")
print(f"record0 viewers={records[0].get('viewers')}")
print(f"record0 attribution sample: {dict(list(records[0]['attribution'].items())[:6])}")
print()

# Each record: frame, total_us (us, wall), engine, zylann, viewers, attribution dict (cat.name -> us)
# wall_ms ≈ total_us / 1000

def wall_ms(rec):
    return (rec.get('total_us') or 0) / 1000.0

def real_us(rec):
    return (rec.get('engine') or {}).get('real_us', 0) or 0

def detect_us(rec):
    return (rec.get('zylann') or {}).get('detect_us', 0) or 0

# Helper: get us for a given attribution key
def att(rec, key):
    return (rec.get('attribution') or {}).get(key, 0) or 0

# ===== 1. Top 20 worst frames =====
worst = sorted(records, key=wall_ms, reverse=True)[:20]
print("=" * 100)
print("1. TOP 20 WORST FRAMES (by total_us/wall)")
print("=" * 100)
print(f"{'frame':>7} {'wall_ms':>8} {'real_us':>8} {'det_us':>8}  top3 attribution")
for r in worst:
    fi = r.get('frame')
    wm = wall_ms(r)
    ru = real_us(r); du = detect_us(r)
    attr = r.get('attribution') or {}
    top3 = sorted(attr.items(), key=lambda kv: kv[1], reverse=True)[:3]
    s = ", ".join(f"{k}={v/1000:.1f}ms" for k,v in top3)
    print(f"{fi:>7} {wm:>8.2f} {ru:>8} {du:>8}  {s}")

# ===== 2. Aggregate per-script =====
total_us = defaultdict(int)
appear = defaultdict(int)
spike10 = defaultdict(int)
for r in records:
    for k, v in (r.get('attribution') or {}).items():
        total_us[k] += v
        appear[k] += 1
        if v > 10000:
            spike10[k] += 1

print()
print("=" * 100)
print("2. TOP 15 PER-SCRIPT AGGREGATE")
print("=" * 100)
print(f"{'key':<50} {'total_ms':>10} {'appear':>8} {'>10ms_frames':>12}")
for k, v in sorted(total_us.items(), key=lambda kv: kv[1], reverse=True)[:15]:
    print(f"{k:<50} {v/1000:>10.1f} {appear[k]:>8} {spike10[k]:>12}")

# Also: top spike-frame counts (independent ranking)
print()
print("Top 15 by frames with >10ms work:")
for k, c in sorted(spike10.items(), key=lambda kv: kv[1], reverse=True)[:15]:
    print(f"  {k:<50} >10ms: {c} (total {total_us[k]/1000:.1f}ms over {appear[k]} appearances)")

def pct(arr, p):
    if not arr: return 0
    s = sorted(arr); n = len(s)
    i = min(n-1, int(n*p))
    return s[i]

# ===== 3. EmissiveLightManager =====
print()
print("=" * 100)
print("3. WORLD.EmissiveLightManager distribution")
print("=" * 100)
ELM_KEY = "WORLD.EmissiveLightManager"
elm_all = [att(r, ELM_KEY) for r in records]
elm_spike = [(r.get('frame'), att(r, ELM_KEY)) for r in records if att(r, ELM_KEY) > 10000]
elm_only = [v for _, v in elm_spike]
print(f"appearances: {sum(1 for v in elm_all if v>0)}")
print(f"frames > 10ms: {len(elm_only)}")
if elm_only:
    s = sorted(elm_only); n = len(s)
    print(f"  min={s[0]/1000:.1f}  median={s[n//2]/1000:.1f}  p90={pct(elm_only,0.9)/1000:.1f}  p99={pct(elm_only,0.99)/1000:.1f}  max={s[-1]/1000:.1f}  (ms)")
elm_30 = [(fi,v) for fi,v in elm_spike if v > 30000]
print(f"frames > 30ms: {len(elm_30)}")
for fi, v in sorted(elm_30, key=lambda x: x[1], reverse=True)[:25]:
    print(f"  frame {fi}: {v/1000:.1f}ms")

# ===== 4. PHYS.Player3D =====
print()
print("=" * 100)
print("4. PHYS.Player3D* distribution (sum across Player3D subkeys)")
print("=" * 100)
# Find every key starting with 'PHYS.Player3D'
phys_keys = set()
for r in records:
    for k in (r.get('attribution') or {}):
        if k.startswith('PHYS.Player3D'):
            phys_keys.add(k)
print(f"matched keys: {sorted(phys_keys)}")

# Also do move_and_slide individually if present
ms_key = "PHYS.Player3D_move_and_slide"
ms_present = ms_key in phys_keys
print(f"'{ms_key}' present: {ms_present}")

def player_sum(r):
    a = r.get('attribution') or {}
    return sum(v for k,v in a.items() if k.startswith('PHYS.Player3D'))

player_us_per_frame = [(r.get('frame'), player_sum(r)) for r in records]
positive = [v for _,v in player_us_per_frame if v > 0]
print(f"frames with PHYS.Player3D work: {len(positive)}")
if positive:
    s = sorted(positive); n = len(s)
    print(f"  ALL: min={s[0]/1000:.2f} med={s[n//2]/1000:.2f} p90={pct(positive,0.9)/1000:.2f} p99={pct(positive,0.99)/1000:.2f} max={s[-1]/1000:.2f} ms")
spike = [v for v in positive if v > 10000]
print(f"frames > 10ms: {len(spike)}")
if spike:
    s = sorted(spike); n=len(s)
    print(f"  >10ms: min={s[0]/1000:.1f} med={s[n//2]/1000:.1f} p90={pct(spike,0.9)/1000:.1f} p99={pct(spike,0.99)/1000:.1f} max={s[-1]/1000:.1f} ms")
print("Worst 10 PHYS.Player3D frames:")
for fi, v in sorted(player_us_per_frame, key=lambda x: x[1], reverse=True)[:10]:
    # Also show breakdown
    rec = next(r for r in records if r.get('frame')==fi)
    breakdown = {k:val for k,val in (rec.get('attribution') or {}).items() if k.startswith('PHYS.Player3D')}
    bd = ", ".join(f"{k.split('.',1)[1]}={val/1000:.1f}" for k,val in sorted(breakdown.items(), key=lambda x:-x[1]))
    print(f"  frame {fi}: total={v/1000:.1f}ms  [{bd}]")

# ===== 5. Co-occurrence =====
print()
print("=" * 100)
print("5. CO-OCCURRENCE — EmissiveLightManager vs PHYS.Player3D")
print("=" * 100)
both = elm_only_c = phy_only_c = both_quiet = 0
for r in records:
    e = att(r, ELM_KEY) > 10000
    p = player_sum(r) > 10000
    if e and p: both += 1
    elif e: elm_only_c += 1
    elif p: phy_only_c += 1
    else: both_quiet += 1
print(f"total frames: {len(records)}")
print(f"both > 10ms (same frame): {both}")
print(f"ELM only > 10ms: {elm_only_c}")
print(f"PHY only > 10ms: {phy_only_c}")
print(f"both <= 10ms: {both_quiet}")
print(f"either > 10ms: {both + elm_only_c + phy_only_c}")

# ===== 6. Zylann sanity =====
print()
print("=" * 100)
print("6. ZYLANN STREAMING SANITY")
print("=" * 100)
zfields = ['detect_us', 'io_us', 'mesh_us', 'update_us', 'blocked_lods', 'dropped_loads', 'dropped_meshs']
for fld in zfields:
    arr = [(r.get('zylann') or {}).get(fld, 0) or 0 for r in records]
    s = sorted(arr); n=len(s); total = sum(arr)
    print(f"  {fld:>14}: max={s[-1]:>8}  p99={pct(arr,0.99):>6}  p90={pct(arr,0.9):>5}  med={s[n//2]:>5}  sum={total}")

print()
real_us_arr = [real_us(r) for r in records]
s=sorted(real_us_arr);n=len(s)
print(f"engine.real_us: max={s[-1]} p99={pct(real_us_arr,0.99)} p90={pct(real_us_arr,0.9)} med={s[n//2]}")

wm_arr = [wall_ms(r) for r in records]
s=sorted(wm_arr);n=len(s)
print(f"wall_ms: max={s[-1]:.2f} p99={pct(wm_arr,0.99):.2f} p90={pct(wm_arr,0.9):.2f} med={s[n//2]:.2f}")
print(f"  > 30ms: {sum(1 for x in wm_arr if x>30)}  > 50ms: {sum(1 for x in wm_arr if x>50)}  > 100ms: {sum(1 for x in wm_arr if x>100)}")

# Bonus: what's the corr between wall_ms and ELM us?
print()
print("Worst 20 wall_ms frames — what dominated?")
for r in worst[:20]:
    a = r.get('attribution') or {}
    elm_v = a.get(ELM_KEY,0)
    phy_v = sum(v for k,v in a.items() if k.startswith('PHYS.Player3D'))
    other = sum(a.values()) - elm_v - phy_v
    z = r.get('zylann') or {}
    zsum = (z.get('detect_us',0) or 0) + (z.get('io_us',0) or 0) + (z.get('mesh_us',0) or 0) + (z.get('update_us',0) or 0)
    print(f"  frame {r.get('frame'):>5} wall={wall_ms(r):>6.1f}ms real={real_us(r)/1000:>5.1f}ms ELM={elm_v/1000:>5.1f} PHY.Player={phy_v/1000:>5.1f} other_attr={other/1000:>5.1f} zylann={zsum/1000:>5.1f}ms")
