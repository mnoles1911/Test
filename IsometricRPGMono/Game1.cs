using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

public class Game1 : Game
{
    private GraphicsDeviceManager _graphics;
    private SpriteBatch           _spriteBatch = null!;
    private PrimitiveRenderer     _primRenderer = null!;
    private SpriteManager         _spriteManager = null!;
    private GameScene             _gameScene = null!;

    public Game1()
    {
        _graphics = new GraphicsDeviceManager(this);
        Content.RootDirectory = "Content";
        IsMouseVisible = true;
        _graphics.PreferredBackBufferWidth  = 1280;
        _graphics.PreferredBackBufferHeight = 720;
        Window.Title = "Isometric RPG";
    }

    protected override void Initialize()
    {
        base.Initialize();
    }

    protected override void LoadContent()
    {
        _spriteBatch   = new SpriteBatch(GraphicsDevice);
        _primRenderer  = new PrimitiveRenderer(GraphicsDevice);
        _spriteManager = new SpriteManager(GraphicsDevice);

        _gameScene = new GameScene();
        _gameScene.Initialize(GraphicsDevice);
        _gameScene.LoadContent(_spriteManager);
    }

    protected override void Update(GameTime gameTime)
    {
        var keyboard = Keyboard.GetState();
        var mouse    = Mouse.GetState();

        _gameScene.Update(gameTime, keyboard, mouse);

        if (_gameScene.InputManager.PausePressed)
            Exit();

        base.Update(gameTime);
    }

    protected override void Draw(GameTime gameTime)
    {
        GraphicsDevice.Clear(new Color(20, 20, 30));

        _gameScene.Draw(
            gameTime,
            _spriteBatch,
            _primRenderer,
            _spriteManager,
            _gameScene.CameraPos);

        base.Draw(gameTime);
    }
}
