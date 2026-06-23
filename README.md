# CEG Browser Widget for Beyond All Reason

**Author:** Steel
**Date:** December 2025  
**Type:** Developer / Artist Tool  
**Status:** Developer environment only (not compatible with the standard public BAR release)

---

## Overview

The **CEG Browser** is an in-game visual inspection and testing tool for **Core Effect Generators (CEGs)** in *Beyond All Reason*.  
It allows developers and VFX artists to browse, filter, and preview CEG effects **live in-game**, without modifying unit, weapon, or CEG definitions.

This tool is designed to support rapid iteration on visual effects by providing immediate feedback on projectile trails, impacts, and ground-based spawns.

---

## ⚠️ Important: Developer Environment Only ⚠️

This widget **will NOT work** in the normal downloadable BAR game.

It depends on **four runtime files**, only one of which is a UI widget.  
The remaining files require a **developer-enabled BAR environment** with LuaRules access.

If you install this into a stock BAR release:
- The widget will load incorrectly or not at all
- Required synced components will be missing
- CEG preview functionality will not work

This tool is intended for:
- BAR developers
- Modders
- Engine contributors
- VFX artists working in a dev setup

---

## Features

### Projectile Preview Mode
- Fires invisible test projectiles from the mouse ground position
- Attaches selected CEGs as **projectile trails**
- Optional **impact CEGs** per projectile
- Optional **Muzzle flash CEGs** per projectile
- Real-time tuning of:
  - Direction (yaw)
  - Pitch
  - Speed
  - Gravity
  - Time to live
  - Origin offset
  - Airburst toggle (based on TTL)
- Supports multi-select and batch firing

### Ground Preview Mode
- Spawns selected CEGs directly at the mouse cursor
- Supports multiple spawn patterns:
  - Line
  - Ring
  - Scatter
- Adjustable:
  - Spawn count
  - Spacing
  - Height offset

### UI & Workflow
- Alphabetical filtering and live search
- CTRL + click for multi-select
- CTRL + drag for fine slider adjustments
- ALT + hover to reveal full CEG names
- Clean separation between trail and impact selection
- Search fields use SDL text input mode (start/stop on focus/blur) to prevent chat interference from blocking keyboard input


### CEG INFO Panel

- The CEG INFO panel is a lightweight inspection overlay embedded in the CEG Browser. It provides a read-only view of the currently -   selected CEG definition and CEG file location to assist with understanding complex effects.

- Key Points
- Opened and closed via the CEG INFO button
- Displays definition data for the currently selected CEG and updates live as selections change
- Mode-agnostic (works in PROJECTILE and GROUND modes)
- UI-only and non-destructive
- Does not affect selection, spawning, or preview behavior
- The panel is intended as a supporting inspection tool and is not required for normal CEG browsing or preview workflows.

---

## Controls (Quick Reference)

- **Left-click CEG**: Select as projectile Trail
- **Right-click CEG**: Select as projectile Impact (PROJECTILE mode only)
- **Middle-Mouse-click CEG**: Select as Muzzle Flash (PROJECTILE mode only)
- **CTRL + click**: Multi-select
- **CTRL + drag sliders**: Fine adjustments
- **ALT + hover**: Show full CEG name tooltip
- **Click outside window**:
  - Fire projectile (PROJECTILE mode, when armed)
  - Spawn ground CEGs (GROUND mode)

---

## Reload CEGs button will repopulate the ceg list as well as reload the ceg definitions (file must exist at game start).
This allows for editing CEG files live, and seeing the changes after using the reload button without restarting 
the game after each change.

---

### Sound Panel (Added January 1st 2026)

-The **Sound Panel** is an auxiliary CEG Browser tool for **previewing and selecting audio** used with CEG spawns.

**What it does**

* Browse and search weapon sounds (search field uses SDL text input mode — same fix as CEG panel)
* Only looks in sound/weapons, sound/bombs, sounds/weapons-mult for weapon related sounds
* Select:

  * **Firing sound** (LMB, yellow highlight)
  * **Impact sound** (RMB, red highlight)
* Preview sounds instantly via **Play Firing Sound / Play Impact Sound** buttons
* RESET clears selections; panel is closeable via **X**

**Two sound paths (intentional)**

* **UI Preview**

  * Button-triggered
  * Unsynced, local-only
  * Does *not* spawn CEGs or projectiles

* **World Playback**

  * Triggered when spawning CEGs/projectiles
  * Sound IDs are appended to spawn messages
  * Gadget controls timing and world position

**Widget ↔ Gadget contract**
Sound selections are appended to spawn messages as optional suffixes:

```
|fireSound=<id>
|impactSound=<id>
```

The gadget:

* Parses these suffixes
* Normalizes sound paths (`sounds/... .wav`)
* Plays sounds at the correct world location and time

**Design rules**

* Widget = UI only (selection, preview, messaging)
* Gadget = authoritative gameplay timing & world audio
* No message formats were changed — sound support is additive
* Preview audio is isolated from gameplay logic

**Purpose**
Speed up audio/visual iteration without touching weapon or unit defs.

---

## File Structure & Dependencies

This widget is **UI-only**, but it relies on the following additional runtime components:

LuaUI/Widgets/gui_ceg_browser.lua (this widget)
LuaRules/ceg_lookup.lua (CEG name discovery)
LuaRules/Gadgets/game_ceg_preview.lua (synced CEG spawning logic, unsynced sound effects)
units/other/ceg_test_projectile.lua (dummy projectile carrier unit)


### Dependency Roles

- **luaui/Widgets/gui_ceg_browser.lua**
  - UI layer
  - Handles selection, filtering, tuning, and input
  - Sends commands to LuaRules

- **LuaRules/ceg_lookup.lua**
  - Provides the authoritative list of available CEG names
  - Must expose `GetAllNames()`

- **LuaRules/Gadgets/game_ceg_preview.lua**
  - Synced gadget
  - Spawns test projectiles and ground CEGs
  - Handles projectile physics, impact dispatch, and cleanup
  - Receives optional firing and impact sound IDs from the UI and triggers world-positioned audio playback in sync with CEG spawns

- **units/other/ceg_test_projectile.lua**
  - Non-interactive helper unit
  - Exists only to legally emit test projectiles
  - Never selectable, controllable, or persistent
  - Safe for repeated spawning and cleanup

---

## Installation (Developer Environment)

1. Clone or download this repository
2. Copy the contents into your BAR development directory, preserving paths:

LuaUI/
LuaRules/
units/

3. Start a game and enable the **CEG Browser** widget
4. Enable cheats and globallos (in CEG Browser)

---

## Safety & Scope

- This widget **does not modify**:
- Units
- Weapons
- CEG definitions
- All previews are **runtime-only**
- Safe to use in live games **when running a dev build**
- Designed to remain behavior- and layout-stable as a tooling baseline

---

## License

This project is provided as a development tool for the BAR community.  
License information may be added or updated by the author.

---

## Notes

This repository intentionally includes all required non-UI components so that
developers can clone it and immediately integrate it into a BAR dev workspace
without hunting for hidden dependencies.

