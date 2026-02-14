import CoreGraphics

/// 2D Perlin-style noise generator for procedural terrain.
/// Uses a gradient-based approach with smoothstep interpolation.
struct PerlinNoise {
    private let permutation: [Int]
    private let gradients: [(CGFloat, CGFloat)]

    init(seed: UInt64) {
        var rng = SeededRNG(seed: seed)

        // Build a shuffled permutation table (0..<256, doubled for wrapping)
        var perm = Array(0..<256)
        for i in stride(from: 255, through: 1, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            perm.swapAt(i, j)
        }
        permutation = perm + perm

        // Precompute unit-circle gradient vectors
        var grads: [(CGFloat, CGFloat)] = []
        for _ in 0..<256 {
            let angle = CGFloat(rng.next() % 3600) / 3600.0 * .pi * 2
            grads.append((cos(angle), sin(angle)))
        }
        gradients = grads
    }

    /// Sample noise at a point. Returns a value roughly in -1...1.
    func sample(x: CGFloat, y: CGFloat) -> CGFloat {
        let xi = Int(floor(x)) & 255
        let yi = Int(floor(y)) & 255
        let xf = x - floor(x)
        let yf = y - floor(y)

        let u = fade(xf)
        let v = fade(yf)

        let aa = permutation[permutation[xi] + yi]
        let ab = permutation[permutation[xi] + yi + 1]
        let ba = permutation[permutation[xi + 1] + yi]
        let bb = permutation[permutation[xi + 1] + yi + 1]

        let x1 = lerp(grad(hash: aa, x: xf, y: yf),
                       grad(hash: ba, x: xf - 1, y: yf), t: u)
        let x2 = lerp(grad(hash: ab, x: xf, y: yf - 1),
                       grad(hash: bb, x: xf - 1, y: yf - 1), t: u)

        return lerp(x1, x2, t: v)
    }

    /// Multi-octave fractal noise for more natural terrain.
    func fractal(x: CGFloat, y: CGFloat, octaves: Int = 4,
                 persistence: CGFloat = 0.5, lacunarity: CGFloat = 2.0) -> CGFloat {
        var total: CGFloat = 0
        var amplitude: CGFloat = 1
        var frequency: CGFloat = 1
        var maxAmplitude: CGFloat = 0

        for _ in 0..<octaves {
            total += sample(x: x * frequency, y: y * frequency) * amplitude
            maxAmplitude += amplitude
            amplitude *= persistence
            frequency *= lacunarity
        }

        return total / maxAmplitude
    }

    private func fade(_ t: CGFloat) -> CGFloat {
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
        return a + t * (b - a)
    }

    private func grad(hash: Int, x: CGFloat, y: CGFloat) -> CGFloat {
        let idx = hash & 255
        let (gx, gy) = gradients[idx]
        return gx * x + gy * y
    }
}
