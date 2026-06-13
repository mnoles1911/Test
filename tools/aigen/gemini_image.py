#!/usr/bin/env python3
"""
gemini_image.py — generate/edit an image with Gemini 2.5 Flash Image (Nano Banana).

REST, stdlib only. https://ai.google.dev/gemini-api/docs/image-generation

  GEMINI_API_KEY=...  python3 tools/aigen/gemini_image.py "T-pose goblin, white bg" goblin.png
  ...  --image ref.png "make the armor rusted"        # image + text editing
  ...  --model gemini-2.5-flash-image  --dry-run       # print the request, send nothing

Key from GEMINI_API_KEY or GOOGLE_API_KEY. Writes the first returned image to <out>.
"""
import os, sys, json, base64, mimetypes, argparse, urllib.request, urllib.error

ENDPOINT = "https://generativelanguage.googleapis.com/v1/models/{model}:generateContent"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt")
    ap.add_argument("out", nargs="?", default="gemini_out.png")
    ap.add_argument("--image", action="append", default=[], help="input image(s) for editing")
    ap.add_argument("--model", default="gemini-2.5-flash-image")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not key and not a.dry_run:
        sys.exit("Set GEMINI_API_KEY (or GOOGLE_API_KEY).")

    parts = [{"text": a.prompt}]
    for img in a.image:
        with open(img, "rb") as f:
            data = f.read()
        mime = mimetypes.guess_type(img)[0] or "image/png"
        parts.append({"inline_data": {"mime_type": mime, "data": base64.b64encode(data).decode()}})

    body = {"contents": [{"parts": parts}], "generationConfig": {"responseModalities": ["TEXT", "IMAGE"]}}
    url = ENDPOINT.format(model=a.model)

    if a.dry_run:
        red = json.loads(json.dumps(body))
        for p in red["contents"][0]["parts"]:
            if "inline_data" in p:
                p["inline_data"]["data"] = "<%d b64 chars>" % len(p["inline_data"]["data"])
        print("POST", url)
        print("headers: x-goog-api-key: <GEMINI_API_KEY>, Content-Type: application/json")
        print(json.dumps(red, indent=2))
        return

    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"x-goog-api-key": key, "Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            out = json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit("Gemini API %d: %s" % (e.code, e.read().decode()[:800]))

    saved = False
    for cand in out.get("candidates", []):
        for p in cand.get("content", {}).get("parts", []):
            inl = p.get("inlineData") or p.get("inline_data")   # responses are camelCase
            if inl and (inl.get("mimeType") or inl.get("mime_type", "")).startswith("image"):
                raw = base64.b64decode(inl["data"])
                with open(a.out, "wb") as f:
                    f.write(raw)
                print("[gemini] wrote %s (%d bytes)" % (a.out, len(raw)))
                saved = True
            elif p.get("text"):
                print("[gemini text]", p["text"][:300])
    if not saved:
        sys.exit("No image in response. First 600 chars:\n" + json.dumps(out)[:600])


if __name__ == "__main__":
    main()
