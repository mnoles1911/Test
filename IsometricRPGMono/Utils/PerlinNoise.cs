namespace IsometricRPG;

public class PerlinNoise
{
    private readonly int[] _permutation;
    private readonly (float gx, float gy)[] _gradients;

    public PerlinNoise(ulong seed)
    {
        var rng = new SeededRNG(seed);

        // Build permutation table
        var perm = Enumerable.Range(0, 256).ToArray();
        for (int i = 255; i >= 1; i--)
        {
            int j = (int)(rng.Next() % (ulong)(i + 1));
            (perm[i], perm[j]) = (perm[j], perm[i]);
        }
        // Double the table to avoid boundary checks
        _permutation = new int[512];
        for (int i = 0; i < 512; i++)
            _permutation[i] = perm[i & 255];

        // Build gradient table
        _gradients = new (float, float)[256];
        for (int i = 0; i < 256; i++)
        {
            float angle = (float)(rng.Next() % 3600UL) / 3600.0f * MathF.PI * 2f;
            _gradients[i] = (MathF.Cos(angle), MathF.Sin(angle));
        }
    }

    public float Sample(float x, float y)
    {
        int xi = (int)MathF.Floor(x) & 255;
        int yi = (int)MathF.Floor(y) & 255;

        float xf = x - MathF.Floor(x);
        float yf = y - MathF.Floor(y);

        float u = Fade(xf);
        float v = Fade(yf);

        int aa = _permutation[_permutation[xi]     + yi];
        int ab = _permutation[_permutation[xi]     + yi + 1];
        int ba = _permutation[_permutation[xi + 1] + yi];
        int bb = _permutation[_permutation[xi + 1] + yi + 1];

        float x1 = Lerp(Grad(aa, xf,       yf),       Grad(ba, xf - 1f, yf),       u);
        float x2 = Lerp(Grad(ab, xf,       yf - 1f), Grad(bb, xf - 1f, yf - 1f), u);

        return Lerp(x1, x2, v);
    }

    public float Fractal(float x, float y, int octaves = 4, float persistence = 0.5f, float lacunarity = 2.0f)
    {
        float total = 0f;
        float frequency = 1f;
        float amplitude = 1f;
        float maxValue = 0f;

        for (int i = 0; i < octaves; i++)
        {
            total += Sample(x * frequency, y * frequency) * amplitude;
            maxValue += amplitude;
            amplitude *= persistence;
            frequency *= lacunarity;
        }

        return total / maxValue;
    }

    private float Fade(float t) => t * t * t * (t * (t * 6f - 15f) + 10f);

    private float Lerp(float a, float b, float t) => a + t * (b - a);

    private float Grad(int hash, float x, float y)
    {
        int idx = hash & 255;
        var (gx, gy) = _gradients[idx];
        return gx * x + gy * y;
    }
}
