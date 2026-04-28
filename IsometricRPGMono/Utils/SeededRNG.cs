namespace IsometricRPG;

// Making SeededRNG a class so it can be passed by reference easily
// and mutated across method calls (mirrors Swift's mutating struct behaviour).
public class SeededRNG
{
    private ulong _state;

    public SeededRNG(ulong seed)
    {
        _state = seed;
    }

    public ulong Next()
    {
        unchecked
        {
            _state += 0x9E3779B97F4A7C15UL;
            ulong z = _state;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
            return z ^ (z >> 31);
        }
    }

    public float NextFloat()
    {
        return (float)(Next() % 1000UL) / 1000.0f;
    }
}
