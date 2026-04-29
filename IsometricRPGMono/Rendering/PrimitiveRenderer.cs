using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace IsometricRPG;

public class PrimitiveRenderer
{
    private readonly GraphicsDevice _gd;
    private readonly BasicEffect _effect;
    private readonly VertexPositionColor[] _verts = new VertexPositionColor[1024];

    public PrimitiveRenderer(GraphicsDevice gd)
    {
        _gd = gd;
        _effect = new BasicEffect(gd)
        {
            VertexColorEnabled = true,
            LightingEnabled = false,
            TextureEnabled = false,
        };
    }

    /// Call once before all DrawDiamond / DrawQuad calls each frame.
    public void Begin(Vector2 cameraPos)
    {
        var vp = _gd.Viewport;
        float hw = vp.Width  / 2f;
        float hh = vp.Height / 2f;
        // Orthographic: origin at screen centre, Y-down
        _effect.Projection = Matrix.CreateOrthographicOffCenter(-hw, hw, hh, -hh, -1f, 1f);
        _effect.View       = Matrix.CreateTranslation(new Vector3(-cameraPos, 0f));
        _effect.World      = Matrix.Identity;
    }

    /// Draw an isometric diamond at the given screen-space centre.
    public void DrawDiamond(Vector2 centre, Color topColor, Color sideColor)
    {
        float hw = Constants.TileWidth  / 2f + 0.5f;  // +0.5 overlap to eliminate sub-pixel gaps
        float hh = Constants.TileHeight / 2f + 0.5f;

        // Top face: 2 triangles from 4 diamond vertices
        var top    = new Vector3(centre.X,      centre.Y - hh, 0f);
        var right  = new Vector3(centre.X + hw, centre.Y,      0f);
        var bottom = new Vector3(centre.X,      centre.Y + hh, 0f);
        var left   = new Vector3(centre.X - hw, centre.Y,      0f);

        // Triangle 1: top → right → bottom
        _verts[0] = new VertexPositionColor(top,    topColor);
        _verts[1] = new VertexPositionColor(right,  topColor);
        _verts[2] = new VertexPositionColor(bottom, topColor);
        // Triangle 2: top → bottom → left
        _verts[3] = new VertexPositionColor(top,    topColor);
        _verts[4] = new VertexPositionColor(bottom, topColor);
        _verts[5] = new VertexPositionColor(left,   topColor);

        ApplyAndDraw(6);
    }

    /// Draw a cliff quad (4 corners → 2 triangles).
    public void DrawQuad(Vector2 a, Vector2 b, Vector2 c, Vector2 d, Color color)
    {
        _verts[0] = new VertexPositionColor(new Vector3(a, 0f), color);
        _verts[1] = new VertexPositionColor(new Vector3(b, 0f), color);
        _verts[2] = new VertexPositionColor(new Vector3(c, 0f), color);
        _verts[3] = new VertexPositionColor(new Vector3(a, 0f), color);
        _verts[4] = new VertexPositionColor(new Vector3(c, 0f), color);
        _verts[5] = new VertexPositionColor(new Vector3(d, 0f), color);

        ApplyAndDraw(6);
    }

    private void ApplyAndDraw(int vertexCount)
    {
        foreach (var pass in _effect.CurrentTechnique.Passes)
        {
            pass.Apply();
            _gd.DrawUserPrimitives(PrimitiveType.TriangleList, _verts, 0, vertexCount / 3);
        }
    }

    public void Dispose() => _effect.Dispose();
}
