--------------------------------------------------------------------------------
-- CEG Lookup Helper written by Steel
--
-- Overview:
--   This module scans the game's effects directory and builds a lookup table
--   of available Core Effect Generator (CEG) definitions.
--
--   It is designed to provide a fast, centralized, and BAR-friendly way for
--   tools and gadgets to discover which CEGs exist, without hardcoding names
--   or duplicating scan logic.
--
-- Responsibilities:
--   - Enumerate all *.lua files under effects/
--   - Safely include each file and extract CEG definitions
--   - Build indexed lookup tables:
--       * byName   : CEG name → source file information
--       * byFile   : effect file → list of CEG names
--       * nameList : sorted list of all CEG names
--
-- Usage:
--   This module is primarily consumed by developer tooling such as the
--   CEG Browser widget and related preview gadgets.
--
-- Public API:
--   CEGLookup.GetAllNames()
--     - Returns a sorted list of all discovered CEG names
--
--   CEGLookup.GetByFile()
--     - Returns a table mapping effect files to their CEG definitions
--
--   CEGLookup.Resolve(name)
--     - Resolves a CEG name to its source file metadata
--
--   CEGLookup.Reload()
--     - Rescans the effects directory and rebuilds the cache
--
-- Notes:
--   - This file performs read-only inspection of effect definitions
--   - It does NOT modify or register CEGs
--   - Failed includes are reported via Spring.Echo when available
--
--------------------------------------------------------------------------------

local CEGLookup = {}

local EFFECTS_DIR = "effects"

--------------------------------------------------------------------------------
-- Recursive directory scan
--------------------------------------------------------------------------------
local function scanDirRecursive(dir, files)
  -- collect lua files in this directory
  local luaFiles = VFS.DirList(dir, "*.lua") or {}
  for _, path in ipairs(luaFiles) do
    table.insert(files, path)
  end

  -- recurse into sub-directories
  local subDirs = VFS.SubDirs(dir) or {}
  for _, subDir in ipairs(subDirs) do
    scanDirRecursive(subDir, files)
  end
end

--------------------------------------------------------------------------------
-- Scan effects (recursive)
--------------------------------------------------------------------------------
local function scanEffects()
  local byName   = {}
  local byFile   = {}
  local nameList = {}
  local files    = {}

  -- recursive scan (FIX)
  scanDirRecursive(EFFECTS_DIR, files)

  for _, path in ipairs(files) do
    local short = path:match("([^/]+)%.lua$") or path

    local ok, defs = pcall(VFS.Include, path)
    if ok and type(defs) == "table" then
      byFile[short] = byFile[short] or {}

      for cegName, def in pairs(defs) do
        if type(cegName) == "string" and not byName[cegName] then
          byName[cegName] = {
            file      = path,
            shortFile = short,
          }
          table.insert(byFile[short], cegName)
          table.insert(nameList, cegName)
        end
      end
    elseif Spring and Spring.Echo then
      Spring.Echo(string.format(
        "[ceg_lookup] Failed to include %s: %s",
        path,
        tostring(defs)
      ))
    end
  end

  table.sort(nameList)
  for _, list in pairs(byFile) do
    table.sort(list)
  end

  return {
    byName   = byName,
    byFile   = byFile,
    nameList = nameList,
  }
end

--------------------------------------------------------------------------------
-- Cache + API
--------------------------------------------------------------------------------
local cache = scanEffects()

function CEGLookup.GetAllNames()
  return cache.nameList
end

function CEGLookup.GetByFile()
  return cache.byFile
end

function CEGLookup.Resolve(name)
  return cache.byName[name]
end

function CEGLookup.Reload()
  cache = scanEffects()
  return cache
end

return CEGLookup
