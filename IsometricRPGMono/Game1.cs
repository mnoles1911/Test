using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

public class Game1 : Game
{
    private GraphicsDeviceManager _graphics;
    private SpriteBatch _spriteBatch = null!;
    private PrimitiveRenderer _primRenderer = null!;
    private SpriteManager _spriteManager = null!;
    private WorldManager _worldManager = null!;
    private WorldRenderer _worldRenderer = null!;
    private Vector2 _cameraPos;

    public Game1()
    {
        _graphics = new GraphicsDeviceManager(this);
        Content.RootDirectory = "Content";
        IsMouseVisible = true;
        _graphics.PreferredBackBufferWidth = 1280;
        _graphics.PreferredBackBufferHeight = 720;
        Window.Title = "Isometric RPG";
    }

    protected override void Initialize()
    {
        base.Initialize();
    }

    protected override void LoadContent()
    {
        _spriteBatch = new SpriteBatch(GraphicsDevice);
        _primRenderer = new PrimitiveRenderer(GraphicsDevice);
        _spriteManager = new SpriteManager(GraphicsDevice);
        _worldManager = new WorldManager();
        _worldRenderer = new WorldRenderer(_primRenderer);
        _worldManager.InitialLoad(Vector2.Zero);
        _cameraPos = Vector2.Zero;
    }

    protected override void Update(GameTime gameTime)
    {
        if (Keyboard.GetState().IsKeyDown(Keys.Escape))
            Exit();
        base.Update(gameTime);
    }

    protected override void Draw(GameTime gameTime)
    {
        GraphicsDevice.Clear(Color.CornflowerBlue);
        _worldRenderer.Draw(_worldManager, _cameraPos);
        base.Draw(gameTime);
    }
}
