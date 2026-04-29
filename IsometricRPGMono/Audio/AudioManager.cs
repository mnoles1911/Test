using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Audio;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Media;

namespace IsometricRPG;

/// <summary>
/// Sound effect categories. Maps to the stub WAV files loaded on startup.
/// </summary>
public enum SoundType
{
    Shoot,
    Hit,
    EnemyDeath,
    ItemPickup,
    LevelUp,
    MenuClick,
    PlayerHurt
}

/// <summary>
/// Background music track categories.
/// </summary>
public enum MusicType
{
    MainMenu,
    Gameplay,
    GameOver
}

/// <summary>
/// Centralised audio manager.  Ported from AudioManager.swift.
///
/// Because there is no content-pipeline in this project all audio files are
/// generated programmatically as minimal silent WAV stubs the first time the
/// game runs.  The stubs are written to Content/Audio/ and then loaded with
/// SoundEffect.FromStream so the rest of the game can call PlaySound / PlayMusic
/// exactly as it would with real assets.
/// </summary>
public class AudioManager
{
    // ---- SFX cache ----
    private readonly Dictionary<SoundType, SoundEffect> _sounds
        = new Dictionary<SoundType, SoundEffect>();

    // ---- Music (Song + MediaPlayer) ----
    // MediaPlayer is a static class; _currentSong tracks what we loaded last.
    private Song?   _currentSong;
    private MusicType? _currentMusicType;

    // ---- Volume settings ----
    private float _masterVolume = 1f;
    private float _musicVolume  = 0.5f;
    private float _sfxVolume    = 0.8f;

    // ---- Enable toggles ----
    private bool _musicEnabled = true;
    private bool _sfxEnabled   = true;

    // ---- Fade-out timer (seconds remaining) ----
    private double _musicFadeTimer  = 0;
    private double _musicFadeDuration = 0;
    private float  _musicFadeStartVolume = 0f;

    // -------------------------------------------------------------------------
    // Initialisation

    /// <summary>
    /// Generate / load all stub sound effects.  Must be called once after
    /// MonoGame's GraphicsDevice is available (needed for the assembly path).
    /// </summary>
    public void Initialize(GraphicsDevice graphicsDevice)
    {
        // Ensure the audio directory exists alongside the Content folder.
        string contentDir = Path.Combine(
            AppDomain.CurrentDomain.BaseDirectory, "Content", "Audio");
        try { Directory.CreateDirectory(contentDir); } catch { /* read-only FS – ignore */ }

        // Map each SoundType to a short stub WAV.
        var sfxFiles = new Dictionary<SoundType, string>
        {
            [SoundType.Shoot]      = "sfx_shoot.wav",
            [SoundType.Hit]        = "sfx_hit.wav",
            [SoundType.EnemyDeath] = "sfx_enemy_death.wav",
            [SoundType.ItemPickup] = "sfx_item_pickup.wav",
            [SoundType.LevelUp]    = "sfx_level_up.wav",
            [SoundType.MenuClick]  = "sfx_menu_click.wav",
            [SoundType.PlayerHurt] = "sfx_player_hurt.wav",
        };

        foreach (var (soundType, fileName) in sfxFiles)
        {
            string filePath = Path.Combine(contentDir, fileName);
            TryEnsureStubWav(filePath, durationMs: 100);
            TryLoadSoundEffect(soundType, filePath);
        }

        // We do not load Song objects here because MonoGame's MediaPlayer /
        // Song.FromUri requires a real file URI and the stub WAVs are silent
        // anyway.  PlayMusic is a no-op stub for now.
    }

    // -------------------------------------------------------------------------
    // SFX

    /// <summary>Play a one-shot sound effect if SFX is enabled.</summary>
    public void PlaySound(SoundType type)
    {
        if (!_sfxEnabled) return;
        if (!_sounds.TryGetValue(type, out var sfx)) return;

        try
        {
            float volume = Math.Clamp(_sfxVolume * _masterVolume, 0f, 1f);
            sfx.Play(volume, pitch: 0f, pan: 0f);
        }
        catch
        {
            // Audio device not available (headless CI, etc.) – fail silently.
        }
    }

    // -------------------------------------------------------------------------
    // Music

    /// <summary>
    /// Start background music for the given type.
    /// With stub (silent) audio files this is effectively a no-op, but the
    /// infrastructure is in place for real tracks.
    /// </summary>
    public void PlayMusic(MusicType type)
    {
        if (!_musicEnabled) return;
        if (_currentMusicType == type) return;  // already playing
        _currentMusicType = type;

        // Stub: no Song is loaded, so we just record the intent.
        // When real music files are present, load via Song.FromUri and
        // start MediaPlayer here.
    }

    /// <summary>Stop music, optionally fading over <paramref name="fadeDuration"/> seconds.</summary>
    public void StopMusic(double fadeDuration = 0)
    {
        if (fadeDuration > 0 && MediaPlayer.State == MediaState.Playing)
        {
            _musicFadeDuration   = fadeDuration;
            _musicFadeTimer      = fadeDuration;
            _musicFadeStartVolume = MediaPlayer.Volume;
        }
        else
        {
            try { MediaPlayer.Stop(); } catch { }
            _musicFadeTimer = 0;
        }
        _currentMusicType = null;
    }

    // -------------------------------------------------------------------------
    // Volume control

    public void SetMasterVolume(float v)
    {
        _masterVolume = Math.Clamp(v, 0f, 1f);
        ApplyMusicVolume();
    }

    public void SetMusicVolume(float v)
    {
        _musicVolume = Math.Clamp(v, 0f, 1f);
        ApplyMusicVolume();
    }

    public void SetSfxVolume(float v)
    {
        _sfxVolume = Math.Clamp(v, 0f, 1f);
    }

    private void ApplyMusicVolume()
    {
        try
        {
            MediaPlayer.Volume = Math.Clamp(_musicVolume * _masterVolume, 0f, 1f);
        }
        catch { }
    }

    // -------------------------------------------------------------------------
    // Update

    /// <summary>
    /// Must be called every frame to handle music fade-out.
    /// </summary>
    public void Update(GameTime gameTime)
    {
        if (_musicFadeTimer <= 0) return;

        _musicFadeTimer -= gameTime.ElapsedGameTime.TotalSeconds;

        if (_musicFadeTimer <= 0)
        {
            _musicFadeTimer = 0;
            try { MediaPlayer.Stop(); } catch { }
        }
        else
        {
            float progress = (float)(_musicFadeTimer / _musicFadeDuration);
            float vol = Math.Clamp(_musicFadeStartVolume * progress, 0f, 1f);
            try { MediaPlayer.Volume = vol; } catch { }
        }
    }

    // -------------------------------------------------------------------------
    // Static WAV helper

    /// <summary>
    /// Generate a valid RIFF PCM WAV byte array containing silence.
    /// Format: 44100 Hz, 16-bit, mono.
    /// </summary>
    public static byte[] GenerateSilentWav(int durationMs)
    {
        const int sampleRate   = 44100;
        const int channels     = 1;
        const int bitsPerSample = 16;
        const int byteRate     = sampleRate * channels * (bitsPerSample / 8); // 88200
        const int blockAlign   = channels * (bitsPerSample / 8);              // 2

        int sampleCount = durationMs * sampleRate / 1000;
        int dataSize    = sampleCount * blockAlign;        // sampleCount * 2
        int chunkSize   = 36 + dataSize;                   // total RIFF chunk minus 8 bytes

        byte[] wav = new byte[44 + dataSize];
        int i = 0;

        // ---- RIFF header ----
        wav[i++] = (byte)'R'; wav[i++] = (byte)'I';
        wav[i++] = (byte)'F'; wav[i++] = (byte)'F';
        WriteInt32LE(wav, ref i, chunkSize);
        wav[i++] = (byte)'W'; wav[i++] = (byte)'A';
        wav[i++] = (byte)'V'; wav[i++] = (byte)'E';

        // ---- fmt  sub-chunk ----
        wav[i++] = (byte)'f'; wav[i++] = (byte)'m';
        wav[i++] = (byte)'t'; wav[i++] = (byte)' ';
        WriteInt32LE(wav, ref i, 16);          // sub-chunk size
        WriteInt16LE(wav, ref i, 1);           // PCM format
        WriteInt16LE(wav, ref i, channels);
        WriteInt32LE(wav, ref i, sampleRate);
        WriteInt32LE(wav, ref i, byteRate);
        WriteInt16LE(wav, ref i, blockAlign);
        WriteInt16LE(wav, ref i, bitsPerSample);

        // ---- data sub-chunk ----
        wav[i++] = (byte)'d'; wav[i++] = (byte)'a';
        wav[i++] = (byte)'t'; wav[i++] = (byte)'a';
        WriteInt32LE(wav, ref i, dataSize);
        // Remaining bytes are zero (silence) – array already zero-initialised.

        return wav;
    }

    // ---- Private helpers ----

    private static void WriteInt32LE(byte[] buf, ref int pos, int value)
    {
        buf[pos++] = (byte)(value & 0xFF);
        buf[pos++] = (byte)((value >> 8)  & 0xFF);
        buf[pos++] = (byte)((value >> 16) & 0xFF);
        buf[pos++] = (byte)((value >> 24) & 0xFF);
    }

    private static void WriteInt16LE(byte[] buf, ref int pos, int value)
    {
        buf[pos++] = (byte)(value & 0xFF);
        buf[pos++] = (byte)((value >> 8) & 0xFF);
    }

    /// <summary>
    /// If <paramref name="filePath"/> does not exist, write a silent stub WAV to it.
    /// Errors are swallowed so a read-only filesystem does not crash the game.
    /// </summary>
    private static void TryEnsureStubWav(string filePath, int durationMs)
    {
        if (File.Exists(filePath)) return;
        try
        {
            byte[] wav = GenerateSilentWav(durationMs);
            File.WriteAllBytes(filePath, wav);
        }
        catch { /* ignore – will fall back to in-memory load below */ }
    }

    /// <summary>
    /// Load a SoundEffect from <paramref name="filePath"/> if it exists, otherwise
    /// generate a silent WAV in memory.  Failures are caught and the slot is left empty.
    /// </summary>
    private void TryLoadSoundEffect(SoundType type, string filePath)
    {
        try
        {
            byte[] wavBytes;
            if (File.Exists(filePath))
                wavBytes = File.ReadAllBytes(filePath);
            else
                wavBytes = GenerateSilentWav(100);

            using var ms = new MemoryStream(wavBytes);
            var sfx = SoundEffect.FromStream(ms);
            _sounds[type] = sfx;
        }
        catch
        {
            // Audio device unavailable – leave slot empty; PlaySound will no-op.
        }
    }
}
