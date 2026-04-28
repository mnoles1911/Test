namespace IsometricRPG;

public static class StructureGenerator
{
    /// <summary>
    /// Generate structures for a chunk given its world-tile origin and an elevation map.
    /// </summary>
    /// <param name="chunkOriginX">World X tile of chunk origin.</param>
    /// <param name="chunkOriginY">World Y tile of chunk origin.</param>
    /// <param name="elevation">Elevation values indexed [row, col] within the chunk.</param>
    /// <param name="biome">Dominant biome of the chunk.</param>
    /// <param name="rng">Seeded RNG shared with the world generator.</param>
    public static List<Structure> GenerateForChunk(
        int chunkOriginX,
        int chunkOriginY,
        float[,] elevation,
        Biome biome,
        SeededRNG rng)
    {
        var structures = new List<Structure>();

        // Pick candidate templates allowed in this biome
        var candidates = StructureTemplates.All
            .Where(t => t.AllowedBiomes.Contains(biome))
            .ToList();

        if (candidates.Count == 0)
            return structures;

        // Attempt to place a small number of structures per chunk
        int maxAttempts = 5;
        for (int attempt = 0; attempt < maxAttempts; attempt++)
        {
            // Weighted random template selection
            var template = SelectWeightedTemplate(candidates, rng);
            if (template == null) break;

            // Find a suitable placement position
            var placement = FindHighGround(
                elevation,
                template.Size.Width,
                template.Size.Height,
                template.MinElevation,
                template.MaxElevation,
                rng);

            if (placement == null) continue;

            var (localX, localY) = placement.Value;
            int worldX = chunkOriginX + localX;
            int worldY = chunkOriginY + localY;

            // Avoid stacking on top of existing structures
            bool overlaps = structures.Any(s =>
                worldX < s.WorldX + s.Size.Width  &&
                worldX + template.Size.Width  > s.WorldX &&
                worldY < s.WorldY + s.Size.Height &&
                worldY + template.Size.Height > s.WorldY);

            if (overlaps) continue;

            structures.Add(new Structure(template, worldX, worldY));
        }

        return structures;
    }

    /// <summary>
    /// Generate a cluster of tree/natural structures around a focal point.
    /// Uses trigonometry to spread placements in a rough circle.
    /// </summary>
    public static List<Structure> GenerateCluster(
        int centerWorldX,
        int centerWorldY,
        float radius,
        Biome biome,
        SeededRNG rng,
        int count = 4)
    {
        var structures = new List<Structure>();

        var candidates = StructureTemplates.All
            .Where(t => t.AllowedBiomes.Contains(biome) && t.Category == StructureCategory.Natural)
            .ToList();

        if (candidates.Count == 0)
            return structures;

        for (int i = 0; i < count; i++)
        {
            var template = SelectWeightedTemplate(candidates, rng);
            if (template == null) continue;

            // Spread placements around the circle
            float angle = (float)rng.NextFloat() * MathF.PI * 2f;
            float dist  = (float)rng.NextFloat() * radius;

            int offsetX = (int)(MathF.Cos(angle) * dist);
            int offsetY = (int)(MathF.Sin(angle) * dist);

            int worldX = centerWorldX + offsetX;
            int worldY = centerWorldY + offsetY;

            bool overlaps = structures.Any(s =>
                worldX < s.WorldX + s.Size.Width  &&
                worldX + template.Size.Width  > s.WorldX &&
                worldY < s.WorldY + s.Size.Height &&
                worldY + template.Size.Height > s.WorldY);

            if (!overlaps)
                structures.Add(new Structure(template, worldX, worldY));
        }

        return structures;
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private static StructureTemplate? SelectWeightedTemplate(
        List<StructureTemplate> candidates, SeededRNG rng)
    {
        if (candidates.Count == 0) return null;

        float totalWeight = candidates.Sum(t => t.SpawnWeight);
        float roll = (float)rng.NextFloat() * totalWeight;

        float cumulative = 0f;
        foreach (var t in candidates)
        {
            cumulative += t.SpawnWeight;
            if (roll <= cumulative)
                return t;
        }

        return candidates[candidates.Count - 1];
    }

    /// <summary>
    /// Searches the elevation grid for a flat region large enough for the template.
    /// Returns (localX, localY) — top-left corner within the chunk — or null.
    /// </summary>
    private static (int x, int y)? FindHighGround(
        float[,] elevation,
        int width,
        int height,
        int minElev,
        int maxElev,
        SeededRNG rng)
    {
        int rows = elevation.GetLength(0);
        int cols = elevation.GetLength(1);

        // Scale thresholds to 0-1 float range
        float minF = minElev / 100f;
        float maxF = maxElev / 100f;

        // Gather valid flat regions
        var validPositions = new List<(int x, int y)>();

        for (int row = 0; row <= rows - height; row++)
        {
            for (int col = 0; col <= cols - width; col++)
            {
                bool valid = true;
                float baseElev = elevation[row, col];

                if (baseElev < minF || baseElev > maxF)
                    continue;

                for (int dr = 0; dr < height && valid; dr++)
                    for (int dc = 0; dc < width && valid; dc++)
                    {
                        float e = elevation[row + dr, col + dc];
                        if (e < minF || e > maxF) { valid = false; break; }
                        if (MathF.Abs(e - baseElev) > 0.05f) { valid = false; break; }
                    }

                if (valid)
                    validPositions.Add((col, row));
            }
        }

        if (validPositions.Count == 0) return null;

        int idx = (int)(rng.Next() % (ulong)validPositions.Count);
        return validPositions[idx];
    }
}
