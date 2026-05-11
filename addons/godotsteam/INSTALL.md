# GodotSteam GDExtension — Install Instructions

The GodotSteam plugin is **not vendored in this repo** because its release
includes platform-specific binaries (.so / .dll / .dylib) that we don't
want to track in git. You need to download it once per machine.

This is the MP-0 setup step. None of the other multiplayer milestones can
proceed until this works.

## What you're installing

GodotSteam wraps the Steamworks SDK as a Godot 4 GDExtension. It gives us:
- Steam P2P sockets (NAT-free networking via Steam relay)
- Steam lobbies + invites via Steam overlay
- Steam friends list
- Steam voice (deferred to MP-8)

GodotSteam 4.x targets Godot 4 and exposes a global `Steam` class once
the .gdextension is loaded.

## Steps

1. **Download the release**: https://godotsteam.com/ → Downloads → pick the
   GDExtension release matching Godot 4.6.x. Get the multi-platform zip
   (Linux + Windows + macOS).

2. **Unzip into this folder.** The final layout should be:

   ```
   addons/godotsteam/
   ├── INSTALL.md         (this file)
   ├── godotsteam.gdextension
   ├── linux/
   │   └── libgodotsteam.linux.template_release.x86_64.so   (and _debug)
   ├── win64/
   │   └── godotsteam.windows.template_release.x86_64.dll   (and _debug)
   └── macos/
       └── godotsteam.macos.template_release.framework/...
   ```

   Plus the Steamworks SDK redistributable (`libsteam_api.so` /
   `steam_api64.dll` / `libsteam_api.dylib`) which the GodotSteam zip
   already includes in the same platform subfolders.

3. **Verify `steam_appid.txt` is at the repo root** (it should already be
   there — value `480`, which is Spacewar, Steam's free test app ID).
   Without this file in the working directory when Godot launches,
   `Steam.steamInitEx()` will refuse to initialize.

4. **Make sure the Steam client is running** on your machine and you're
   logged in. GodotSteam piggybacks on the running Steam process.

5. **Open the project in Godot 4.6.2** and let it import the addon. Godot
   should automatically pick up `godotsteam.gdextension` and register the
   `Steam` global class. Watch the Output panel for:

   ```
   GodotSteam: Initialized successfully
   ```

   If you see "Steam class not found" — Godot didn't load the extension.
   Usually means the binary for your platform isn't in the right subfolder,
   or the .gdextension file's paths don't match your folder names.

6. **Run `scenes/_dev/HelloSteam.tscn`** (F5 with that scene focused, or
   set it as the main scene temporarily). You should see:
   - "Steam status: ONLINE — user: <your Steam name>"
   - Press "Create Lobby" → a lobby ID prints
   - On a second machine (different Steam account, on your friends list),
     run the same scene and press "List Friends Lobbies" → the lobby
     should appear.

   That's the MP-0 acceptance test. The MultiplayerManager work in MP-1
   builds on top of `Steam` being usable.

## Troubleshooting

- **"Failed to initialize Steam"** — Steam client isn't running, or
  `steam_appid.txt` isn't in the working directory.
- **Crashes on launch** — wrong platform binary or wrong Godot version.
  GDExtensions are tightly coupled to the Godot ABI; 4.5 binaries won't
  work on 4.6.
- **App ID 480 (Spacewar) limitation** — fine for dev, but lobby names
  will show as "Spacewar" in the Steam friends list. We swap this for
  our real App ID once we have one (Steamworks partner setup, not
  required for MVP).

## Why not auto-install via a build script?

Steamworks SDK has license terms that prohibit redistribution. Each
developer must download it themselves and accept the SSA. Vendoring would
also balloon the repo and break across Godot versions.

## Once installed: gitignore additions

The `.gitignore` at the repo root should already exclude the binaries.
If not, add:

```
addons/godotsteam/linux/
addons/godotsteam/win64/
addons/godotsteam/macos/
addons/godotsteam/*.so
addons/godotsteam/*.dll
addons/godotsteam/*.dylib
```

The `.gdextension` text file itself **is** checked in (it's just config).
