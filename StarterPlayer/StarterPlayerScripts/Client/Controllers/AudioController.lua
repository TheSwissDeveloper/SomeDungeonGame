--[[
    AudioController.lua
    Zentrales Audio-Management
    Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/AudioController
    
    Verantwortlich für:
    - Musik-Wiedergabe mit Crossfade
    - Sound-Effekte
    - Lautstärke-Management
    - Audio-Pooling für Performance
    
    WICHTIG: Respektiert Spieler-Einstellungen!
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

-- Shared Modules
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ModulesPath = SharedPath:WaitForChild("Modules")
local ConfigPath = SharedPath:WaitForChild("Config")

local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))

local AudioController = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Lautstärke-Defaults
    MasterVolume = 1.0,
    MusicVolume = 0.5,
    SFXVolume = 0.8,
    
    -- Fading
    MusicFadeTime = 1.5,
    SFXFadeTime = 0.3,
    
    -- Pooling
    MaxPooledSounds = 20,
    
    -- Debug
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- AUDIO ASSETS
-------------------------------------------------
local MUSIC_TRACKS = {
    MainTheme = "rbxassetid://1837849285",      -- Placeholder - Epische Fantasy
    RaidBattle = "rbxassetid://1836677843",     -- Placeholder - Action Combat
    Victory = "rbxassetid://1837100234",        -- Placeholder - Triumphant
    Defeat = "rbxassetid://1836778432",         -- Placeholder - Melancholic
    Shop = "rbxassetid://1838776543",           -- Placeholder - Relaxed
    Build = "rbxassetid://1837654321",          -- Placeholder - Creative
}

local SFX_SOUNDS = {
    -- UI Sounds
    ButtonClick = "rbxassetid://6895079853",
    ButtonHover = "rbxassetid://6895079590",
    Success = "rbxassetid://6895079726",
    Error = "rbxassetid://6895079308",
    Warning = "rbxassetid://6895079445",
    
    -- Currency
    CoinCollect = "rbxassetid://6895079976",
    GemCollect = "rbxassetid://6895080123",
    Purchase = "rbxassetid://6895080256",
    
    -- Dungeon
    TrapPlace = "rbxassetid://6895080389",
    MonsterPlace = "rbxassetid://6895080512",
    RoomBuild = "rbxassetid://6895080645",
    Upgrade = "rbxassetid://6895080778",
    
    -- Combat
    HeroAttack = "rbxassetid://6895080901",
    MonsterAttack = "rbxassetid://6895081034",
    TrapTrigger = "rbxassetid://6895081167",
    HeroDeath = "rbxassetid://6895081289",
    MonsterDeath = "rbxassetid://6895081412",
    
    -- Rewards
    Reward = "rbxassetid://6895081545",
    LevelUp = "rbxassetid://6895081678",
    Prestige = "rbxassetid://6895081801",
    Achievement = "rbxassetid://6895081934",
    
    -- Misc
    Alert = "rbxassetid://6895082067",
    Notification = "rbxassetid://6895082189",
    Whoosh = "rbxassetid://6895082312",
}

-------------------------------------------------
-- AUDIO STATE
-------------------------------------------------
local audioState = {
    -- Settings
    MusicEnabled = true,
    SFXEnabled = true,
    MasterVolume = CONFIG.MasterVolume,
    MusicVolume = CONFIG.MusicVolume,
    SFXVolume = CONFIG.SFXVolume,
    
    -- Current Music
    CurrentTrack = nil,
    CurrentMusic = nil,
    
    -- Sound Pool
    SoundPool = {},
    ActiveSounds = {},
}

-------------------------------------------------
-- SOUND GROUPS
-------------------------------------------------
local musicGroup = nil
local sfxGroup = nil

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
AudioController.Signals = {
    MusicChanged = SignalUtil.new(),        -- (trackName)
    VolumeChanged = SignalUtil.new(),       -- (volumeType, value)
    SettingsChanged = SignalUtil.new(),     -- (settings)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

local function debugPrint(...)
    if CONFIG.Debug then
        print("[AudioController]", ...)
    end
end

--[[
    Erstellt Sound-Gruppen
]]
local function createSoundGroups()
    -- Music Group
    musicGroup = Instance.new("SoundGroup")
    musicGroup.Name = "MusicGroup"
    musicGroup.Volume = audioState.MusicVolume * audioState.MasterVolume
    musicGroup.Parent = SoundService
    
    -- SFX Group
    sfxGroup = Instance.new("SoundGroup")
    sfxGroup.Name = "SFXGroup"
    sfxGroup.Volume = audioState.SFXVolume * audioState.MasterVolume
    sfxGroup.Parent = SoundService
end

--[[
    Aktualisiert Sound-Group Volumes
]]
local function updateGroupVolumes()
    if musicGroup then
        musicGroup.Volume = audioState.MusicEnabled 
            and (audioState.MusicVolume * audioState.MasterVolume) 
            or 0
    end
    
    if sfxGroup then
        sfxGroup.Volume = audioState.SFXEnabled 
            and (audioState.SFXVolume * audioState.MasterVolume) 
            or 0
    end
end

--[[
    Erstellt einen neuen Sound
    @param soundId: Asset-ID
    @param parent: Parent-Instance
    @param soundGroup: SoundGroup
    @return: Sound Instance
]]
local function createSound(soundId, parent, soundGroup)
    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.SoundGroup = soundGroup
    sound.Parent = parent or SoundService
    return sound
end

--[[
    Holt Sound aus Pool oder erstellt neuen
    @param soundId: Asset-ID
    @return: Sound Instance
]]
local function getSoundFromPool(soundId)
    -- Prüfe Pool
    if audioState.SoundPool[soundId] and #audioState.SoundPool[soundId] > 0 then
        local sound = table.remove(audioState.SoundPool[soundId])
        return sound
    end
    
    -- Neuen Sound erstellen
    return createSound(soundId, SoundService, sfxGroup)
end

--[[
    Gibt Sound zurück in Pool
    @param sound: Sound Instance
    @param soundId: Asset-ID
]]
local function returnToPool(sound, soundId)
    if not audioState.SoundPool[soundId] then
        audioState.SoundPool[soundId] = {}
    end
    
    -- Pool-Limit prüfen
    if #audioState.SoundPool[soundId] >= CONFIG.MaxPooledSounds then
        sound:Destroy()
        return
    end
    
    -- Reset und zurück in Pool
    sound:Stop()
    sound.TimePosition = 0
    sound.Volume = 1
    sound.PlaybackSpeed = 1
    
    table.insert(audioState.SoundPool[soundId], sound)
end

--[[
    Tween-Helper für Sounds
    @param sound: Sound Instance
    @param properties: Ziel-Properties
    @param duration: Dauer
    @return: Tween
]]
local function tweenSound(sound, properties, duration)
    local tweenInfo = TweenInfo.new(
        duration or CONFIG.SFXFadeTime,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )
    
    local tween = TweenService:Create(sound, tweenInfo, properties)
    tween:Play()
    return tween
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert den AudioController
]]
function AudioController.Initialize()
    debugPrint("Initialisiere AudioController...")
    
    -- Sound-Gruppen erstellen
    createSoundGroups()
    
    -- Preload häufig verwendete Sounds
    for name, soundId in pairs(SFX_SOUNDS) do
        task.spawn(function()
            local sound = createSound(soundId, nil, sfxGroup)
            sound:Destroy()  -- Nur zum Preloading
        end)
    end
    
    debugPrint("AudioController initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - MUSIK
-------------------------------------------------

--[[
    Spielt Musik-Track ab
    @param trackName: Name des Tracks
    @param fadeIn: Einblenden (default true)
]]
function AudioController.PlayMusic(trackName, fadeIn)
    if not audioState.MusicEnabled then
        debugPrint("Musik deaktiviert")
        return
    end
    
    local trackId = MUSIC_TRACKS[trackName]
    if not trackId then
        debugPrint("Track nicht gefunden: " .. tostring(trackName))
        return
    end
    
    -- Gleicher Track bereits aktiv?
    if audioState.CurrentTrack == trackName and audioState.CurrentMusic then
        return
    end
    
    fadeIn = fadeIn ~= false
    
    -- Alte Musik ausblenden
    if audioState.CurrentMusic then
        local oldMusic = audioState.CurrentMusic
        
        if fadeIn then
            tweenSound(oldMusic, { Volume = 0 }, CONFIG.MusicFadeTime)
            task.delay(CONFIG.MusicFadeTime, function()
                oldMusic:Stop()
                oldMusic:Destroy()
            end)
        else
            oldMusic:Stop()
            oldMusic:Destroy()
        end
    end
    
    -- Neue Musik erstellen
    local newMusic = createSound(trackId, SoundService, musicGroup)
    newMusic.Name = "Music_" .. trackName
    newMusic.Looped = true
    newMusic.Volume = fadeIn and 0 or 1
    
    audioState.CurrentMusic = newMusic
    audioState.CurrentTrack = trackName
    
    -- Abspielen
    newMusic:Play()
    
    -- Einblenden
    if fadeIn then
        tweenSound(newMusic, { Volume = 1 }, CONFIG.MusicFadeTime)
    end
    
    AudioController.Signals.MusicChanged:Fire(trackName)
    debugPrint("Musik gestartet: " .. trackName)
end

--[[
    Stoppt aktuelle Musik
    @param fadeOut: Ausblenden (default true)
]]
function AudioController.StopMusic(fadeOut)
    if not audioState.CurrentMusic then return end
    
    fadeOut = fadeOut ~= false
    local music = audioState.CurrentMusic
    
    if fadeOut then
        tweenSound(music, { Volume = 0 }, CONFIG.MusicFadeTime)
        task.delay(CONFIG.MusicFadeTime, function()
            music:Stop()
            music:Destroy()
        end)
    else
        music:Stop()
        music:Destroy()
    end
    
    audioState.CurrentMusic = nil
    audioState.CurrentTrack = nil
    
    debugPrint("Musik gestoppt")
end

--[[
    Pausiert/Setzt Musik fort
    @param paused: boolean
]]
function AudioController.SetMusicPaused(paused)
    if not audioState.CurrentMusic then return end
    
    if paused then
        audioState.CurrentMusic:Pause()
    else
        audioState.CurrentMusic:Resume()
    end
end

--[[
    Gibt aktuellen Track-Namen zurück
    @return: Track-Name oder nil
]]
function AudioController.GetCurrentTrack()
    return audioState.CurrentTrack
end

-------------------------------------------------
-- PUBLIC API - SOUND EFFEKTE
-------------------------------------------------

--[[
    Spielt Sound-Effekt ab
    @param soundName: Name des Sounds
    @param options: Optionen { Volume, PlaybackSpeed, Position }
    @return: Sound Instance
]]
function AudioController.PlaySound(soundName, options)
    if not audioState.SFXEnabled then
        return nil
    end
    
    local soundId = SFX_SOUNDS[soundName]
    if not soundId then
        debugPrint("Sound nicht gefunden: " .. tostring(soundName))
        return nil
    end
    
    options = options or {}
    
    -- Sound aus Pool holen
    local sound = getSoundFromPool(soundId)
    
    -- Optionen anwenden
    sound.Volume = options.Volume or 1
    sound.PlaybackSpeed = options.PlaybackSpeed or 1
    
    -- 3D Position (falls angegeben)
    if options.Position then
        local attachment = Instance.new("Attachment")
        attachment.WorldPosition = options.Position
        attachment.Parent = workspace.Terrain
        sound.Parent = attachment
        
        sound.RollOffMode = Enum.RollOffMode.InverseTapered
        sound.RollOffMinDistance = 10
        sound.RollOffMaxDistance = 100
    end
    
    -- Abspielen
    sound:Play()
    
    -- Cleanup nach Abspielen
    sound.Ended:Once(function()
        if options.Position then
            local parent = sound.Parent
            sound.Parent = SoundService
            if parent:IsA("Attachment") then
                parent:Destroy()
            end
        end
        
        returnToPool(sound, soundId)
    end)
    
    return sound
end

--[[
    Spielt Sound mit Pitch-Variation
    @param soundName: Name des Sounds
    @param pitchVariation: Variation (z.B. 0.1 für ±10%)
]]
function AudioController.PlaySoundVaried(soundName, pitchVariation)
    pitchVariation = pitchVariation or 0.1
    
    local speed = 1 + (math.random() * 2 - 1) * pitchVariation
    
    return AudioController.PlaySound(soundName, {
        PlaybackSpeed = speed
    })
end

--[[
    Spielt Sound an 3D Position
    @param soundName: Name des Sounds
    @param position: Vector3 Position
    @param options: Zusätzliche Optionen
]]
function AudioController.PlaySoundAt(soundName, position, options)
    options = options or {}
    options.Position = position
    
    return AudioController.PlaySound(soundName, options)
end

--[[
    Spielt UI-Sound (immer 2D)
    @param soundName: Name des Sounds
]]
function AudioController.PlayUISound(soundName)
    return AudioController.PlaySound(soundName, {
        Volume = 0.7
    })
end

-------------------------------------------------
-- PUBLIC API - LAUTSTÄRKE
-------------------------------------------------

--[[
    Setzt Master-Lautstärke
    @param volume: Lautstärke (0-1)
]]
function AudioController.SetMasterVolume(volume)
    audioState.MasterVolume = math.clamp(volume, 0, 1)
    updateGroupVolumes()
    
    AudioController.Signals.VolumeChanged:Fire("Master", audioState.MasterVolume)
    debugPrint("Master Volume: " .. audioState.MasterVolume)
end

--[[
    Setzt Musik-Lautstärke
    @param volume: Lautstärke (0-1)
]]
function AudioController.SetMusicVolume(volume)
    audioState.MusicVolume = math.clamp(volume, 0, 1)
    updateGroupVolumes()
    
    AudioController.Signals.VolumeChanged:Fire("Music", audioState.MusicVolume)
    debugPrint("Music Volume: " .. audioState.MusicVolume)
end

--[[
    Setzt SFX-Lautstärke
    @param volume: Lautstärke (0-1)
]]
function AudioController.SetSFXVolume(volume)
    audioState.SFXVolume = math.clamp(volume, 0, 1)
    updateGroupVolumes()
    
    AudioController.Signals.VolumeChanged:Fire("SFX", audioState.SFXVolume)
    debugPrint("SFX Volume: " .. audioState.SFXVolume)
end

--[[
    Gibt aktuelle Lautstärken zurück
    @return: { Master, Music, SFX }
]]
function AudioController.GetVolumes()
    return {
        Master = audioState.MasterVolume,
        Music = audioState.MusicVolume,
        SFX = audioState.SFXVolume,
    }
end

-------------------------------------------------
-- PUBLIC API - EINSTELLUNGEN
-------------------------------------------------

--[[
    Aktiviert/Deaktiviert Musik
    @param enabled: boolean
]]
function AudioController.SetMusicEnabled(enabled)
    audioState.MusicEnabled = enabled
    updateGroupVolumes()
    
    if not enabled and audioState.CurrentMusic then
        AudioController.StopMusic(true)
    end
    
    AudioController.Signals.SettingsChanged:Fire({
        MusicEnabled = audioState.MusicEnabled,
        SFXEnabled = audioState.SFXEnabled,
    })
    
    debugPrint("Musik " .. (enabled and "aktiviert" or "deaktiviert"))
end

--[[
    Aktiviert/Deaktiviert SFX
    @param enabled: boolean
]]
function AudioController.SetSFXEnabled(enabled)
    audioState.SFXEnabled = enabled
    updateGroupVolumes()
    
    AudioController.Signals.SettingsChanged:Fire({
        MusicEnabled = audioState.MusicEnabled,
        SFXEnabled = audioState.SFXEnabled,
    })
    
    debugPrint("SFX " .. (enabled and "aktiviert" or "deaktiviert"))
end

--[[
    Gibt Audio-Einstellungen zurück
    @return: { MusicEnabled, SFXEnabled }
]]
function AudioController.GetSettings()
    return {
        MusicEnabled = audioState.MusicEnabled,
        SFXEnabled = audioState.SFXEnabled,
    }
end

--[[
    Prüft ob Musik aktiviert ist
    @return: boolean
]]
function AudioController.IsMusicEnabled()
    return audioState.MusicEnabled
end

--[[
    Prüft ob SFX aktiviert sind
    @return: boolean
]]
function AudioController.IsSFXEnabled()
    return audioState.SFXEnabled
end

-------------------------------------------------
-- PUBLIC API - UTILITY
-------------------------------------------------

--[[
    Stoppt alle Sounds
]]
function AudioController.StopAll()
    AudioController.StopMusic(false)
    
    -- Alle aktiven Sounds stoppen
    for _, sound in ipairs(audioState.ActiveSounds) do
        if sound and sound.Parent then
            sound:Stop()
        end
    end
    
    audioState.ActiveSounds = {}
    debugPrint("Alle Sounds gestoppt")
end

--[[
    Preloaded einen Sound
    @param soundName: Name des Sounds
]]
function AudioController.Preload(soundName)
    local soundId = SFX_SOUNDS[soundName] or MUSIC_TRACKS[soundName]
    if not soundId then return end
    
    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    
    game:GetService("ContentProvider"):PreloadAsync({sound})
    sound:Destroy()
    
    debugPrint("Preloaded: " .. soundName)
end

--[[
    Preloaded mehrere Sounds
    @param soundNames: Array von Sound-Namen
]]
function AudioController.PreloadMultiple(soundNames)
    for _, name in ipairs(soundNames) do
        AudioController.Preload(name)
    end
end

--[[
    Gibt verfügbare Tracks zurück
    @return: Array von Track-Namen
]]
function AudioController.GetAvailableTracks()
    local tracks = {}
    for name, _ in pairs(MUSIC_TRACKS) do
        table.insert(tracks, name)
    end
    return tracks
end

--[[
    Gibt verfügbare Sounds zurück
    @return: Array von Sound-Namen
]]
function AudioController.GetAvailableSounds()
    local sounds = {}
    for name, _ in pairs(SFX_SOUNDS) do
        table.insert(sounds, name)
    end
    return sounds
end

return AudioController
