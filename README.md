# CEG Browser Widget for Beyond All Reason

**Author:** Steel  
**Type:** Developer / Artist Tool

**Date:** 2025.12.18

**Status:** Developer environment only (not compatible with the standard public BAR release)

---

## Overview

The **CEG Browser** is an in-game visual inspection and testing tool for **Core Effect Generators (CEGs)** in *Beyond All Reason*.  
It allows developers and VFX artists to browse, filter, and preview CEG effects **live in-game**, without modifying unit, weapon, or CEG definitions.

This tool is designed to support rapid iteration on visual effects by providing immediate feedback on projectile trails, impacts, and ground-based spawns.

---

## ⚠️ Important: Developer Environment Only

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
- Real-time tuning of:
  - Direction (yaw)
  - Pitch
  - Speed
  - Gravity
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

---

## Controls (Quick Reference)

- **Left-click CEG**: Select as projectile trail
- **Right-click CEG**: Select as projectile impact (PROJECTILE mode only)
- **CTRL + click**: Multi-select
- **CTRL + drag sliders**: Fine adjustments
- **ALT + hover**: Show full CEG name tooltip
- **Click outside window**:
  - Fire projectile (PROJECTILE mode, when armed)
  - Spawn ground CEGs (GROUND mode)

---

## File Structure & Dependencies

This widget is **UI-only**, but it relies on the following additional runtime components:

LuaUI/Widgets/gui_ceg_browser.lua (this widget)
LuaRules/ceg_lookup.lua (CEG name discovery)
LuaRules/Gadgets/game_ceg_preview.lua (synced CEG spawning logic)
units/other/ceg_test_projectile.lua (dummy projectile carrier unit)


### Dependency Roles

- **gui_ceg_browser.lua**
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

- **ceg_test_projectile.lua**
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

---

## Notes

This repository intentionally includes all required non-UI components so that
developers can clone it and immediately integrate it into a BAR dev workspace
without hunting for hidden dependencies.

