# Prison Life Macro Suite

A real native Windows app (C# / WPF, .NET Framework 4.8 - no AutoHotkey runtime needed) with the full macro suite:

- **Pressure Jump** - hold-to-run jump with camera spin
- **Freeze** - suspend/resume the Roblox process (Toggle or Hold)
- **Rotation** - wallhop camera flick
- **Sprint** - Shift-tap toggle sprint
- **Fast Gun Swap** - cycles gun slots + shoots (Hold or Toggle, with an On/Off arm key)
- **Shuffle Reload** - cycles gun slots pressing Reload after each
- **Global Suspend** - one key suspends/resumes all macros, works from any window
- **Update Detector** - checks this repo's GitHub releases on startup and hourly

Target process is fixed to `RobloxPlayerBeta.exe`.

## Build

```
dotnet publish PrisonLifeMacro.csproj -c Release -o artifacts
```

The `.exe` in the release needs nothing installed - it runs on any Windows 10/11.

## Releases

Tag a new version (`v4.0.0`) and push it - the GitHub Actions workflow
(`.github/workflows/build.yml`) builds the exe automatically and attaches it
to the release:

```
git tag v4.0.0
git push origin v4.0.0
```

## Settings

Stored at `%localappdata%\PrisonLifeMacro\settings.ini` (same file as the old AHK script, so your keybinds carry over).