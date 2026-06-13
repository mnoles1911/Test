#!/usr/bin/env python3
"""
fal_image_to_3d.py — turn an image into a 3D .glb via fal.ai (default fal-ai/trellis).

REST queue API, stdlib only.  https://fal.ai/models/fal-ai/trellis/api

  FAL_KEY=...  python3 tools/aigen/fal_image_to_3d.py --image goblin.png goblin.glb
  ...  --image-url https://host/img.png  --model fal-ai/hunyuan3d/v2
  ...  --set mesh_simplify=0.9 --set texture_size=2048
  ...  --image goblin.png --dry-run        # print the request, send nothing

Key from FAL_KEY or FAL_API_KEY. A local --image is sent as a base64 data URI
(most fal models accept it); if a model rejects it, pass a hosted --image-url.
"""
import os, sys, json, time, base64, mimetypes, argparse, urllib.request, urllib.error


def http(url, method="GET", body=None, headers=None, timeout=120):
    req = urllib.request.Request(url, data=(json.dumps(body).encode() if body is not None else None),
                                 headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, {"_error": e.read().decode()[:800]}


def find_glb(obj):
    """Recursively locate the output mesh URL (model_mesh.url or any *.glb url)."""
    if isinstance(obj, dict):
        mm = obj.get("model_mesh")
        if isinstance(mm, dict) and mm.get("url"):
            return mm["url"]
        for v in obj.values():
            u = find_glb(v)
            if u:
                return u
    elif isinstance(obj, list):
        for v in obj:
            u = find_glb(v)
            if u:
                return u
    elif isinstance(obj, str) and obj.startswith("http") and ".glb" in obj.lower():
        return obj
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out", nargs="?", default="model.glb")
    ap.add_argument("--image", help="local image file (sent as a data URI)")
    ap.add_argument("--image-url", help="public hosted image URL")
    ap.add_argument("--model", default="fal-ai/trellis")
    ap.add_argument("--set", action="append", default=[], help="extra input field k=v (numbers auto-parsed)")
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    key = os.environ.get("FAL_KEY") or os.environ.get("FAL_API_KEY")
    if not key and not a.dry_run:
        sys.exit("Set FAL_KEY.")

    if a.image_url:
        image_url = a.image_url
    elif a.image:
        with open(a.image, "rb") as f:
            data = f.read()
        mime = mimetypes.guess_type(a.image)[0] or "image/png"
        image_url = "data:%s;base64,%s" % (mime, base64.b64encode(data).decode())
    else:
        sys.exit("Provide --image <local file> or --image-url <hosted url>.")

    inp = {"image_url": image_url}
    for kv in a.set:
        k, _, v = kv.partition("=")
        try:
            v = float(v) if "." in v else int(v)
        except ValueError:
            pass
        inp[k] = v

    base = "https://queue.fal.run/" + a.model
    headers = {"Authorization": "Key " + (key or ""), "Content-Type": "application/json"}

    if a.dry_run:
        red = dict(inp)
        if str(red.get("image_url", "")).startswith("data:"):
            red["image_url"] = red["image_url"][:42] + "...<data uri>"
        print("POST", base)
        print("headers: Authorization: Key <FAL_KEY>, Content-Type: application/json")
        print(json.dumps({"input": red}, indent=2))
        return

    st, sub = http(base, "POST", {"input": inp}, headers)
    if st != 200 or "request_id" not in sub:
        sys.exit("submit failed %s: %s" % (st, json.dumps(sub)[:600]))
    rid = sub["request_id"]
    status_url = sub.get("status_url") or "%s/requests/%s/status" % (base, rid)
    result_url = sub.get("response_url") or "%s/requests/%s" % (base, rid)
    print("[fal] submitted", rid)

    t0 = time.time()
    while time.time() - t0 < a.timeout:
        _, stj = http(status_url, headers=headers)
        status = stj.get("status")
        print("[fal]", status or stj)
        if status == "COMPLETED":
            break
        if status in ("ERROR", "FAILED"):
            sys.exit("fal error: " + json.dumps(stj)[:600])
        time.sleep(4)
    else:
        sys.exit("timed out after %ds" % a.timeout)

    _, res = http(result_url, headers=headers)
    glb = find_glb(res)
    if not glb:
        sys.exit("no .glb in result: " + json.dumps(res)[:600])
    print("[fal] downloading", glb)
    urllib.request.urlretrieve(glb, a.out)
    print("[fal] wrote", a.out)


if __name__ == "__main__":
    main()
