using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

public class InputManager
{
    private KeyboardState _prevKeyboard;
    private MouseState    _prevMouse;

    /// Normalized movement vector from WASD keys (zero if no input).
    public Vector2 MovementDirection { get; private set; }

    /// Normalized aim direction from mouse position relative to player screen pos.
    public Vector2 AimDirection { get; private set; }

    /// True on the frame the fire button was first pressed.
    public bool FirePressed { get; private set; }

    /// True while the fire button is held.
    public bool FireHeld { get; private set; }

    /// True on the frame Escape was pressed.
    public bool PausePressed { get; private set; }

    /// True on the frame I was pressed.
    public bool InventoryPressed { get; private set; }

    public void Update(KeyboardState kb, MouseState ms, Vector2 playerScreenPos)
    {
        // --- Movement ---
        float mx = 0f, my = 0f;
        if (kb.IsKeyDown(Keys.A)) mx -= 1f;
        if (kb.IsKeyDown(Keys.D)) mx += 1f;
        if (kb.IsKeyDown(Keys.W)) my -= 1f;
        if (kb.IsKeyDown(Keys.S)) my += 1f;

        var raw = new Vector2(mx, my);
        MovementDirection = raw.LengthSquared() > 0f ? Vector2.Normalize(raw) : Vector2.Zero;

        // --- Aim ---
        var mousePos = new Vector2(ms.X, ms.Y);
        var diff = mousePos - playerScreenPos;
        AimDirection = diff.LengthSquared() > 1f ? Vector2.Normalize(diff) : Vector2.Zero;

        // --- Fire: LMB or Space ---
        bool fireNow = ms.LeftButton == ButtonState.Pressed || kb.IsKeyDown(Keys.Space);
        bool firePrev = _prevMouse.LeftButton == ButtonState.Pressed || _prevKeyboard.IsKeyDown(Keys.Space);
        FirePressed = fireNow && !firePrev;
        FireHeld = fireNow;

        // --- Pause: Escape ---
        PausePressed = kb.IsKeyDown(Keys.Escape) && !_prevKeyboard.IsKeyDown(Keys.Escape);

        // --- Inventory: I ---
        InventoryPressed = kb.IsKeyDown(Keys.I) && !_prevKeyboard.IsKeyDown(Keys.I);

        _prevKeyboard = kb;
        _prevMouse    = ms;
    }
}
