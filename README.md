# MoonVFXCompiler (HamVFX)

A Roblox Studio plugin I built to cut down the time it takes to port cutscenes and VFX into a game.
It reads a **Moon Animator 2** save or an **Eclipse Animator** project and turns it into a script that's ready to use in-game, in one click.

> Latest version: **v3.4.0** — now supports Eclipse Animator, plus a new Moon → Eclipse save converter (see below)

---

## The problem

My main front-end job is taking the effects the team has prepared and porting them into the game, mostly cutscenes.
The effects play fine in Moon Animator 2's preview but can't be used in the real game as they are. The problems I kept running into:

- Writing scripts by hand to fire every effect on the right frame
- Keeping several Roblox Studio windows open at once to watch the preview and check timing side by side
- Spending around **4–6 hours** on average for a 30-second to 1-minute effect

## The solution

So I built a Roblox Studio plugin that works alongside Moon Animator 2 (a popular animation plugin),
and it now supports Eclipse Animator as well.

VFXCompiler reads the animator's save and turns it into a Model plus a ready-to-use `VFXPlayer` ModuleScript, **in one click**.

## How it works

1. **Read the save** — Pull out of the Moon Animator 2 save (or Eclipse project) which objects and events exist at each keyframe,
   at what time, which properties change, and the easing of each segment.
2. **Keep only what's actually animated** — Convert frames to seconds (`frame / FPS`) and store only properties that have keyframes
   in a table, so the data stays small with no duplication. CFrames are made relative to the character's RootPart, so the effect plays wherever the player is.
3. **Build the timeline** — Sort events by their saved time, e.g. "at time X, emit this particle",
   and turn them into `task.delay(time, function() ... end)`. Event code that references `workspace.` is remapped to the cloned model.
4. **Generate the VFXPlayer** — Put each property's timeline into
   `playKeyframes(Object, Property, PropertyType, TimelineTable)` and combine everything into the `VFXPlayer` module.
5. **Group every object together** — Clone every object the script needs (Parts, Beams, ParticleEmitters, rigs, camera rigs, etc.)
   into one `<SaveName>_VFX` model, ready to use right away.

## What it supports

- BaseParts, Beams, ParticleEmitters, Trails, Lights, and any other tweenable property
- Lighting / camera effects (ColorCorrection, Atmosphere, etc.) — original values are restored automatically when the effect ends
- Camera: FieldOfView, and cutscenes through a CameraRig (the camera follows `CamPart`)
- Character rigs (Humanoid / AnimationController) — add the animation ID and it plays automatically
- Vignette / Screen Cover UI
- Event code from Moon (`codeBegin` / `codeEnd`) and Eclipse (`CodeBegin` / `CodeEnd`, VFX emits, sounds)
- **No Cutscene** mode for world-only effects (leaves the camera, Lighting and UI alone)

---

## New in v3.4.0: Eclipse Animator

**1. VFXCompiler now reads Eclipse projects**
Select a project folder in `ServerStorage › Eclipse Animator Saves › EclipseAnimator_Saves` (or anything inside it) and press Generate VFX as usual.
An Eclipse project converted from a Moon save produces a `VFXPlayer` identical, line for line, to the one from the Moon save.

- Eclipse's camera is already a rig, so it works as a CameraRig straight away (open the project in Eclipse once so Eclipse builds the camera, then export and upload the camera animation, just like a Moon CameraRig)
- Eclipse's emit and sound events are turned into code on the timeline

**2. New plugin: Moon → Eclipse (`MoonToEclipse.rbxmx`)**
Eclipse can't open Moon Animator 2 saves, so this plugin converts a Moon save directly into an Eclipse project:

- Every rig joint keyframe (poses match Moon on every frame), with full easing (including Back / Elastic settings)
- Part / Model / Lighting / effect properties, and the camera (CFrame + FOV)
- Markers / events with their `codeBegin` / `codeEnd` code, sounds, and action tracks (such as Emit)
- Never edits the original Moon save, and can be undone (Ctrl+Z)

Limitations: objects in CoreGui (such as the old-style vignette) are skipped because they aren't saved with the place,
and two objects with the same name can't go in the same project (Eclipse requires unique names). The plugin warns about both in the Output window.

---

## Installation

1. Download `VFXComplier.rbxmx` (and `MoonToEclipse.rbxmx` if you want the converter)
2. Put the files in Roblox Studio's Plugins folder
   - Windows: `%LOCALAPPDATA%\Roblox\Plugins`
   - macOS: `~/Documents/Roblox/Plugins`
   (or in Studio: Plugins tab › Plugins Folder)
3. Restart Roblox Studio

## Usage

1. Press **Settings** and set the path of your `ForgeVFX` module and the folder your VFX are stored in (defaults: `ReplicatedStorage.ForgeVFX` / `ReplicatedStorage.VFX`)
2. Press **Get Module** once to install `Payload` (`VFXPayload` + the `VFX` caller) next to ForgeVFX
3. Select a Moon Animator 2 save (`ServerStorage.MoonAnimator2Saves`) or an Eclipse project
4. Press **Generate VFX** (or **Generate VFX (No Cutscene)**) to get a `<Name>_VFX` model in Workspace
5. Fill in the rig / camera rig animation IDs in the `VFXPlayer`'s `module.Animations`, then move the model into your VFX folder

Playing it in-game (client side):

```lua
local VFX = require(game.ReplicatedStorage.Payload.VFX)

-- VFX.Play(name or model, rootPart, offset, lifeTime, config)
VFX.Play("Slash", character.HumanoidRootPart, CFrame.new(), 5, {
	PlayCutscene = true,       -- defaults to true
	AutoPlayAnimations = true, -- defaults to true
})
```

Converting Moon → Eclipse: **Moon to Eclipse** toolbar › **Convert Moon Saves** › pick saves › **Convert Selected** / **Convert All**,
then open the project from Eclipse › Projects.

## Files

| File | What it is |
|---|---|
| `VFXComplier.rbxmx` | The VFXCompiler plugin (HamVFX v3.4.0), ready to install |
| `VFXComplier/` | Plugin source (`init.server.luau`) + the Vignette / Screen Cover UI |
| `MoonToEclipse.rbxmx` | The Moon → Eclipse converter plugin, ready to install |
| `MoonToEclipse/` | Converter source |
| `exampleGenerated.lua` | An example generated `VFXPlayer` (from an earlier version) |
