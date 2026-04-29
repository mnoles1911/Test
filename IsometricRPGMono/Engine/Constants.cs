using Microsoft.Xna.Framework;

namespace IsometricRPG;

public static class Constants
{
    public const ulong WorldSeed = 42;
    public const int ChunkSize = 16;
    public const int LoadRadius = 3;
    public const int UnloadRadius = 5;
    public const float TileWidth = 64f;
    public const float TileHeight = 32f;
    public const float ElevationHeightMultiplier = 0.5f;
    public const int MaxWalkableElevationDiff = 5;
    public const int CliffThreshold = 10;
    public const int FlatnessThreshold = 3;
    public const int RoomMinSize = 4;
    public const int RoomMaxSize = 8;
    public const int RoomsPerChunk = 3;
    public const int CorridorWidth = 2;
    public const float PlayerSpeed = 150f;
    public const int PlayerMaxHealth = 100;
    public static readonly Vector2 PlayerSize = new Vector2(20f, 28f);
    public const float BulletSpeed = 400f;
    public const int BulletDamage = 25;
    public const double FireRate = 0.25;
    public const double BulletLifetime = 2.0;
    public const float EnemySpeed = 60f;
    public const int EnemyMaxHealth = 50;
    public static readonly Vector2 EnemySize = new Vector2(18f, 24f);
    public const float EnemyDetectionRange = 200f;
    public const float EnemyAttackRange = 30f;
    public const int EnemyAttackDamage = 10;
    public const double EnemyAttackCooldown = 1.0;
    public const int MaxEnemiesPerChunk = 3;
    public const int MaxTotalEnemies = 20;
    public const double EnemySpawnInterval = 2.0;
    public const float EnemyMinSpawnDistance = 4f;  // tiles — keep enemies from spawning on the player
    public const int MaxLevel = 50;
    public const float ItemPickupRange = 0.8f;
    public const float ItemAttractRange = 2.5f;
    public const float ItemAttractSpeed = 3.0f;
    public const int MaxItemsPerChunk = 4;
    public const float JoystickRadius = 50f;
    public const float JoystickKnobRadius = 20f;
    public const float JoystickDeadZone = 0.1f;

    public static class ZPosition
    {
        public const float Tile = 0f;
        public const float Item = 4f;
        public const float Shadow = 5f;
        public const float Entity = 10f;
        public const float Bullet = 15f;
        public const float Hud = 100f;
        public const float Overlay = 150f;
        public const float Modal = 200f;
        public const float ModalContent = 210f;
    }

    public static class PhysicsCategory
    {
        public const uint None   = 0u;
        public const uint Player = 0b0001u;
        public const uint Enemy  = 0b0010u;
        public const uint Bullet = 0b0100u;
        public const uint Wall   = 0b1000u;
    }
}
