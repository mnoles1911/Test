namespace IsometricRPG;

public struct Room
{
    public int X      { get; set; }
    public int Y      { get; set; }
    public int Width  { get; set; }
    public int Height { get; set; }

    public Room(int x, int y, int width, int height)
    {
        X = x; Y = y; Width = width; Height = height;
    }

    public int CenterX => X + Width  / 2;
    public int CenterY => Y + Height / 2;

    /// <param name="padding">Extra tile border around each room treated as occupied, preventing adjacent rooms from touching.</param>
    public bool Intersects(Room other, int padding = 1)
    {
        return X - padding < other.X + other.Width  &&
               X + Width  + padding > other.X        &&
               Y - padding < other.Y + other.Height  &&
               Y + Height + padding > other.Y;
    }
}

public static class DungeonGenerator
{
    /// <summary>
    /// Generates a dungeon layout into a TileType[,] grid of size (size x size).
    /// Grid is indexed as [row, col].
    /// </summary>
    public static List<Room> Generate(TileType[,] tiles, int size, SeededRNG rng)
    {
        int rows = tiles.GetLength(0);
        int cols = tiles.GetLength(1);

        // Fill with walls
        for (int r = 0; r < rows; r++)
            for (int c = 0; c < cols; c++)
                tiles[r, c] = TileType.Wall;

        var rooms = new List<Room>();

        for (int attempt = 0; attempt < Constants.RoomsPerChunk * 10; attempt++)
        {
            if (rooms.Count >= Constants.RoomsPerChunk) break;

            int w = Constants.RoomMinSize + (int)(rng.Next() % (ulong)(Constants.RoomMaxSize - Constants.RoomMinSize + 1));
            int h = Constants.RoomMinSize + (int)(rng.Next() % (ulong)(Constants.RoomMaxSize - Constants.RoomMinSize + 1));
            int x = 1 + (int)(rng.Next() % (ulong)(cols - w - 2));
            int y = 1 + (int)(rng.Next() % (ulong)(rows - h - 2));

            var candidate = new Room(x, y, w, h);

            bool overlaps = rooms.Any(r => r.Intersects(candidate));
            if (overlaps) continue;

            CarveRoom(tiles, candidate);
            rooms.Add(candidate);

            if (rooms.Count > 1)
            {
                var prev = rooms[rooms.Count - 2];
                ConnectRooms(tiles, prev, candidate, rng);
            }
        }

        return rooms;
    }

    private static void CarveRoom(TileType[,] tiles, Room room)
    {
        for (int r = room.Y; r < room.Y + room.Height; r++)
            for (int c = room.X; c < room.X + room.Width; c++)
                if (r >= 0 && r < tiles.GetLength(0) && c >= 0 && c < tiles.GetLength(1))
                    tiles[r, c] = TileType.Floor;
    }

    private static void ConnectRooms(TileType[,] tiles, Room a, Room b, SeededRNG rng)
    {
        // Randomly choose whether to go horizontal-first or vertical-first
        bool hFirst = (rng.Next() % 2UL) == 0UL;

        if (hFirst)
        {
            CarveCorridor(tiles, a.CenterX, a.CenterY, b.CenterX, a.CenterY, horizontal: true);
            CarveCorridor(tiles, b.CenterX, a.CenterY, b.CenterX, b.CenterY, horizontal: false);
        }
        else
        {
            CarveCorridor(tiles, a.CenterX, a.CenterY, a.CenterX, b.CenterY, horizontal: false);
            CarveCorridor(tiles, a.CenterX, b.CenterY, b.CenterX, b.CenterY, horizontal: true);
        }
    }

    private static void CarveCorridor(TileType[,] tiles, int x1, int y1, int x2, int y2, bool horizontal)
    {
        int rows = tiles.GetLength(0);
        int cols = tiles.GetLength(1);
        int half = Constants.CorridorWidth / 2;

        if (horizontal)
        {
            int minX = Math.Min(x1, x2);
            int maxX = Math.Max(x1, x2);
            for (int c = minX; c <= maxX; c++)
                for (int offset = -half; offset <= half; offset++)
                {
                    int r = y1 + offset;
                    if (r >= 0 && r < rows && c >= 0 && c < cols)
                        tiles[r, c] = TileType.Floor;
                }
        }
        else
        {
            int minY = Math.Min(y1, y2);
            int maxY = Math.Max(y1, y2);
            for (int r = minY; r <= maxY; r++)
                for (int offset = -half; offset <= half; offset++)
                {
                    int c = x1 + offset;
                    if (r >= 0 && r < rows && c >= 0 && c < cols)
                        tiles[r, c] = TileType.Floor;
                }
        }
    }
}
