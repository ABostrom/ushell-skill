# Launching a UE Project at a Specific Spawn Point from the Command Line

## TL;DR

To launch a UE project into a specific level at a specific `PlayerStart`, use the `#Portal` segment of the URL — **not** a `?` option:

```
UnrealEditor.exe MyProject.uproject /Game/Maps/Test#Arena -game
```

In the level, the target `PlayerStart` actor must have its `PlayerStartTag` property set to `Arena` (an `FName`).

No C++ or Blueprint required — this is stock engine behavior.

## URL grammar

UE's `FURL` (declared in `Engine/Source/Runtime/Engine/Classes/Engine/EngineBaseTypes.h`, defined in `URL.cpp`) parses URLs of the form:

```
Protocol://Host:Port/Map#Portal?Option1=Value1?Option2=Value2
```

For local launches you typically only use:

```
Map#Portal?Key=Value?Key=Value
```

The struct shape:

```cpp
struct FURL
{
    FString Protocol;   // "unreal"
    FString Host;
    int32   Port;
    FString Map;        // e.g. "/Game/Maps/Test"
    FString Portal;     // e.g. "Arena"  <-- spawn point selector
    TArray<FString> Op; // e.g. ["Name=Aaron", "SpectatorOnly=1"]
};
```

- `#` separates Map from Portal
- `?` introduces each option in `Op[]`

## Important gotcha: `?Name=` is NOT the spawn selector

`?Name=` sets the **player's display name** (truncated to 20 chars), not the spawn point. From `AGameModeBase::InitNewPlayer`:

```cpp
FString InName = UGameplayStatics::ParseOption(Options, TEXT("Name")).Left(20);
if (InName.IsEmpty())
{
    InName = FString::Printf(TEXT("%s%i"), *DefaultPlayerName.ToString(), NewPC->PlayerState->GetPlayerId());
}
ChangeName(NewPlayerController, InName, false);
```

The spawn point comes from `Portal`, which is a sibling field on `FURL`, parsed from the `#` segment.

## Call stack: URL → spawn point

Starting from `UWorld::SpawnPlayActor` (in `World.cpp`):

```
UWorld::SpawnPlayActor(NewPlayer, RemoteRole, InURL, ...)
  builds Options string from InURL.Op[]
  └─ AGameModeBase::Login(NewPlayer, RemoteRole, *InURL.Portal, Options, ...)
     └─ AGameModeBase::InitNewPlayer(NewPC, UniqueId, Options, Portal)
        └─ AGameModeBase::UpdatePlayerStartSpot(NewPC, Portal, ErrorMessage)
           └─ AGameModeBase::FindPlayerStart(NewPC, Portal)   // Portal == IncomingName
              └─ AGameModeBase::FindPlayerStart_Implementation
                 matches IncomingName against APlayerStart::PlayerStartTag
```

Note the split: `InURL.Op[]` becomes `Options` (the `?Key=Value` pairs), while `InURL.Portal` is passed separately as `*InURL.Portal`. They take different paths through `Login` / `InitNewPlayer`.

## Key code references

**`Engine/Source/Runtime/Engine/Private/World.cpp`** — `UWorld::SpawnPlayActor`:

```cpp
FString Options;
for (int32 i = 0; i < InURL.Op.Num(); i++)
{
    Options += TEXT('?');
    Options += InURL.Op[i];
}
if (AGameModeBase* const GameMode = GetAuthGameMode())
{
    APlayerController* const NewPlayerController =
        GameMode->Login(NewPlayer, RemoteRole, *InURL.Portal, Options, UniqueId, Error);
    ...
}
```

**`Engine/Source/Runtime/Engine/Private/GameModeBase.cpp`** — `AGameModeBase::InitNewPlayer`:

```cpp
FString AGameModeBase::InitNewPlayer(APlayerController* NewPlayerController,
    const FUniqueNetIdRepl& UniqueId, const FString& Options, const FString& Portal)
{
    ...
    // Find a starting spot
    FString ErrorMessage;
    if (!UpdatePlayerStartSpot(NewPlayerController, Portal, ErrorMessage))
    {
        UE_LOG(LogGameMode, Warning, TEXT("InitNewPlayer: %s"), *ErrorMessage);
    }
    ...
    FString InName = UGameplayStatics::ParseOption(Options, TEXT("Name")).Left(20);
    ...
}
```

**`AGameModeBase::FindPlayerStart_Implementation`** (paraphrased):

```cpp
AActor* AGameModeBase::FindPlayerStart_Implementation(
    AController* Player, const FString& IncomingName)
{
    UWorld* World = GetWorld();
    if (!IncomingName.IsEmpty())
    {
        const FName IncomingPlayerStartTag = FName(*IncomingName);
        for (TActorIterator<APlayerStart> It(World); It; ++It)
        {
            APlayerStart* Start = *It;
            if (Start && Start->PlayerStartTag == IncomingPlayerStartTag)
            {
                return Start;
            }
        }
    }
    if (Player->StartSpot.IsValid())
    {
        return Player->StartSpot.Get();
    }
    return ChoosePlayerStart(Player);
}
```

## Practical recipes

### Launch standalone game at a named spawn

```
UnrealEditor.exe "C:\Path\To\MyProject.uproject" /Game/Maps/Test#Arena -game
```

Requirements:
- A `PlayerStart` in `/Game/Maps/Test` with `PlayerStartTag = "Arena"`.
- The active `GameMode` doesn't override `FindPlayerStart_Implementation` in a way that ignores `IncomingName`. (Custom GameModes commonly do; check yours.)

### Combine with other useful flags

```
UnrealEditor.exe MyProject.uproject /Game/Maps/Test#Arena ^
    -game ^
    -windowed -ResX=1280 -ResY=720 ^
    -log ^
    -NoSplash
```

### Packaged build

Same URL grammar, just runs against the packaged exe:

```
MyGame.exe /Game/Maps/Test#Arena
```

### Combine Portal with options

```
MyGame.exe /Game/Maps/Test#Arena?Name=Aaron?SpectatorOnly=1
```

Portal = `Arena`, Op = `["Name=Aaron", "SpectatorOnly=1"]`.

## Things that bite

1. **Custom GameMode overrides.** If a project overrides `ChoosePlayerStart` or `FindPlayerStart` without calling Super or without honoring `IncomingName`, the Portal will be ignored. Worth checking the project's game mode before assuming the URL is broken.

2. **PIE doesn't use the command-line URL by default.** PIE constructs its own URL from the editor's "Play From Here" / start location logic. To exercise Portal in PIE, use Play Mode → Standalone with additional launch parameters set in Editor Preferences, or just launch the editor with `-game`.

3. **`PlayerStartTag` is an `FName`, comparison is case-sensitive at the `FName` level** (case-insensitive in practice because `FName` normalizes). Still, match the casing you authored.

4. **Net travel re-parses URLs.** During seamless travel, the URL is rebuilt; Portal will be preserved through `FURL` copying but custom seamless travel code can drop it.

5. **`StartSpot` fallback.** If `Portal` is empty or no `PlayerStart` matches, `FindPlayerStart_Implementation` falls back to `Player->StartSpot` then to `ChoosePlayerStart`, which means a failed match silently goes to the default spawn — easy to mistake for "Portal didn't work" when actually the tag just didn't match.

## Grep starting points

```
Engine/Source/Runtime/Engine/Classes/Engine/EngineBaseTypes.h   # FURL declaration
Engine/Source/Runtime/Engine/Private/URL.cpp                    # FURL::Parse
Engine/Source/Runtime/Engine/Private/World.cpp                  # SpawnPlayActor
Engine/Source/Runtime/Engine/Private/GameModeBase.cpp           # Login, InitNewPlayer, UpdatePlayerStartSpot, FindPlayerStart
Engine/Source/Runtime/Engine/Classes/GameFramework/PlayerStart.h
```

Useful search terms: `FURL::Parse`, `Portal`, `IncomingName`, `PlayerStartTag`, `UpdatePlayerStartSpot`.
