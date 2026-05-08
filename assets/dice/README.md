# Dice mini-game art assets

The Bones (tavern dice) prototype loads art from this directory. Until real
art lands, the scenes fall back to solid-color materials and labels.

Generation prompts for each asset live in
`.claude/plans/build-an-art-design-encapsulated-crab.md` §Part 2.

## Expected file layout

```
assets/dice/
├── die_face_atlas.png        # 384×256, 3×2 grid of 128px die faces
├── felt_burgundy.png         # 1024×1024 tileable
├── table_oak_rim.png         # 1024×256 tileable horizontally
├── lock_indicator.png        # 96×96 transparent
├── coin.png                  # 64×64 transparent
├── wager_card_bg.png         # 320×96 parchment
├── win_glow.png              # 1920×1080 transparent radial glow
├── reveal_banner.png         # 640×128 parchment ribbon
└── opponents/
    └── tomlin_stub.tres      # DiceOpponentData resource (already present)
```

```
assets/audio/dice/
├── dice_shake.ogg            # 1.2s loop
├── dice_throw.ogg            # 0.3s one-shot
├── dice_settle.ogg           # 0.6s one-shot
├── dice_lock.ogg             # 0.15s one-shot
├── coin_clink.ogg            # 0.4s one-shot
├── win_chime.ogg             # 1.0s one-shot
├── lose_thud.ogg             # 0.6s one-shot
└── tavern_ambient.ogg        # 30s loop (optional)
```

When art arrives, reassign `albedo_texture` on the Die material and the
felt/rim materials inside `scenes/dice/DiceTable3D.tscn`, and assign the
remaining textures to the matching `TextureRect` nodes inside
`DiceGameUI` (look for `_apply_optional_art()`).
