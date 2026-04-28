using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace IsometricRPG;

public class SpriteManager
{
    public static SpriteManager Instance { get; private set; } = null!;
    private readonly GraphicsDevice _gd;
    private readonly Dictionary<string, Texture2D> _cache = new();

    public SpriteManager(GraphicsDevice gd)
    {
        _gd = gd;
        Instance = this;
    }

    public Texture2D GetCircle(int diameter, Color color)
    {
        string key = $"circle_{diameter}_{color.PackedValue}";
        if (_cache.TryGetValue(key, out var cached)) return cached;

        var tex = new Texture2D(_gd, diameter, diameter);
        var data = new Color[diameter * diameter];
        float cx = (diameter - 1) / 2f;
        float cy = (diameter - 1) / 2f;
        float r  = diameter / 2f - 0.5f;
        for (int y = 0; y < diameter; y++)
            for (int x = 0; x < diameter; x++)
            {
                float dx = x - cx, dy = y - cy;
                data[y * diameter + x] = (dx*dx + dy*dy <= r*r) ? color : Color.Transparent;
            }
        tex.SetData(data);
        _cache[key] = tex;
        return tex;
    }

    public Texture2D GetRect(int width, int height, Color color)
    {
        string key = $"rect_{width}_{height}_{color.PackedValue}";
        if (_cache.TryGetValue(key, out var cached)) return cached;

        var tex = new Texture2D(_gd, width, height);
        var data = new Color[width * height];
        Array.Fill(data, color);
        tex.SetData(data);
        _cache[key] = tex;
        return tex;
    }

    public Texture2D GetPixel(Color color)
    {
        string key = $"pixel_{color.PackedValue}";
        if (_cache.TryGetValue(key, out var cached)) return cached;

        var tex = new Texture2D(_gd, 1, 1);
        tex.SetData(new[] { color });
        _cache[key] = tex;
        return tex;
    }

    public void Dispose()
    {
        foreach (var t in _cache.Values) t.Dispose();
        _cache.Clear();
    }
}
