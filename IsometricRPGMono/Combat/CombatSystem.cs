using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace IsometricRPG;

public class CombatSystem
{
    private readonly List<Bullet> _bullets = new List<Bullet>();

    public IReadOnlyList<Bullet> Bullets => _bullets;

    public void FireBullet(Vector2 fromWorldPos, Vector2 direction, double currentTime)
    {
        if (direction.LengthSquared() < 1e-6f) return;
        _bullets.Add(new Bullet(fromWorldPos, direction, currentTime, Constants.BulletDamage));
    }

    public void Update(double deltaTime, double currentTime, List<Enemy> enemies, Player player)
    {
        // Advance all bullets
        foreach (var bullet in _bullets)
            bullet.Update(deltaTime, currentTime);

        // Bullet-enemy collisions
        foreach (var bullet in _bullets)
        {
            if (bullet.IsExpired) continue;
            foreach (var enemy in enemies)
            {
                if (!enemy.IsAlive) continue;
                if (bullet.CheckHit(enemy))
                {
                    enemy.TakeDamage(bullet.Damage);
                    bullet.IsExpired = true;

                    if (!enemy.IsAlive && player != null)
                        player.AddXP(enemy.XPReward);

                    break;
                }
            }
        }

        _bullets.RemoveAll(b => b.IsExpired);
    }

    public void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, Vector2 cameraPos)
    {
        foreach (var bullet in _bullets)
            bullet.Draw(spriteBatch, spriteManager, cameraPos);
    }

    public void Clear() => _bullets.Clear();
}
