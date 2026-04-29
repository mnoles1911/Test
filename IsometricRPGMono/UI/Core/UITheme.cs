using Microsoft.Xna.Framework;

namespace IsometricRPG;

public static class UITheme
{
    // Backgrounds
    public static readonly Color Background   = new Color(20,  15,  10);
    public static readonly Color Panel        = new Color(40,  30,  20);
    public static readonly Color PanelBorder  = new Color(100, 80,  50);

    // Text
    public static readonly Color TextPrimary   = new Color(220, 200, 160);
    public static readonly Color TextSecondary = new Color(160, 140, 100);

    // Buttons
    public static readonly Color ButtonNormal  = new Color(60,  45,  30);
    public static readonly Color ButtonHover   = new Color(80,  65,  45);
    public static readonly Color ButtonPressed = new Color(40,  30,  20);

    // Stat bars
    public static readonly Color HealthBar = new Color(180, 50,  50);
    public static readonly Color ManaBar   = new Color(50,  80,  180);
    public static readonly Color XPBar     = new Color(80,  160, 80);

    // Rarity / accent
    public static readonly Color Gold  = new Color(255, 215, 0);
    public static readonly Color Rare  = new Color(100, 100, 255);
    public static readonly Color Epic  = new Color(160, 50,  200);

    // Overlay
    public static readonly Color Overlay = new Color(0, 0, 0, 180);
}
