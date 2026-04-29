using Microsoft.Xna.Framework;

namespace IsometricRPG;

public static class UITheme
{
    // Backgrounds
    public static readonly Color Background   = new Color(12,  8,   5);
    public static readonly Color Panel        = new Color(35,  22,  12);
    public static readonly Color PanelBorder  = new Color(140, 100, 40);

    // Text
    public static readonly Color TextPrimary   = new Color(220, 195, 140);
    public static readonly Color TextSecondary = new Color(160, 130, 90);

    // Buttons
    public static readonly Color ButtonNormal  = new Color(50,  32,  16);
    public static readonly Color ButtonHover   = new Color(80,  55,  25);
    public static readonly Color ButtonPressed = new Color(30,  18,  8);

    // Stat bars
    public static readonly Color HealthBar = new Color(160, 30,  30);
    public static readonly Color ManaBar   = new Color(50,  80,  180);
    public static readonly Color XPBar     = new Color(40,  120, 180);

    // Rarity / accent
    public static readonly Color Gold  = new Color(210, 160, 40);
    public static readonly Color Rare  = new Color(100, 100, 255);
    public static readonly Color Epic  = new Color(160, 50,  200);

    // Overlay
    public static readonly Color Overlay = new Color(0, 0, 0, 180);
}
