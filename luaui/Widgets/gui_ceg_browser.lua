--------------------------------------------------------------------------------
-- CEG Browser
-- LuaUI Widget for Beyond All Reason made by Steel Date: December 2025
--
-- Overview:
--   The CEG Browser is a visual testing and inspection tool for Core Effect
--   Generator (CEG) effects. It allows artists and developers to browse,
--   filter, and preview CEGs directly in-game, without modifying unit or
--   weapon definitions.
--
--   Two primary preview modes are supported:
--
--     PROJECTILE mode:
--       - Fires invisible test projectiles from the mouse ground position
--       - Selected CEGs are attached as projectile trails
--       - Independent Impact and Muzzle CEGs can be assigned
--       - Direction, pitch, speed, gravity, Time to Live, projectile origin offsets and airburst are adjustable in real time
--	 - Supports simultaneous Trail / Muzzle / Impact selection
--
--     GROUND mode:
--       - Spawns selected CEGs directly on the ground under the mouse cursor
--       - Supports line, ring, and scatter spawn patterns
--       - Spawn count, spacing, and height offset are adjustable
--       - Intended for testing area effects, environmental CEGs, and ambience
--
-- Usage highlights:
--   - Left-click on a CEG: select as projectile Trail
--   - Right-click on a CEG: select as Impact (PROJECTILE mode only) * Right-click has no effect in GROUND mode
--   - Middle-click on a CEG: select Muzzle effect (PROJECTILE mode only) * Middle-click has no effect in GROUND mode
--   - CTRL + click: multi-select
--   - CTRL + drag on sliders: fine adjustment (reduced slider sensitivity)
--   - ALT + hover on CEG list: show full CEG name tooltip
--   - Search and alphabet filters allow fast navigation of large CEG sets

--     Embedded Tools:
--       - CEG Forge panel (CEG INFO button)
--         * Embedded inspection panel, also shows CEG file location
--         * Opens as a mode-agnostic overlay
--         * Does not affect browser selection or spawn logic
--
-- File dependencies:
--   This widget is UI-only and relies on the following runtime components:
--
--   LuaRules/ceg_lookup.lua
--     - Provides the authoritative list of available CEG names
--     - Provides CEG Info panel with selected ceg definition and file location
--     - Must expose GetAllNames()
--
--   LuaRules/Gadgets/game_ceg_preview.lua
--     - Synced gadget that receives messages from this widget
--     - Responsible for spawning test projectiles and ground CEGs
--     - Handles projectile physics, impact dispatch, and cleanup
--
--   units/other/ceg_test_projectile.lua
--     - Lightweight helper unit used for projectile-based CEG previews
--     - Defines a lightweight weapon used to emit test projectiles
--     - Never selectable, controllable, or persistent
--     - Exists only to carry projectile and impact CEGs during preview
--
-- Design Notes:
--   - This widget never mutates gameplay definitions
--   - All previews are non-authoritative
--   - UI rendering, input handling, and spawning are strictly separated
--   - Filtering, paging, and sorting never destroy user intent
--   - Intended as a stable tooling baseline for long-term iteration
--
--------------------------------------------------------------------------------



function widget:GetInfo()
    return {
        name    = "CEG Browser",
        desc    = "In-game browser and preview tool for Core Effect Generators (CEGs)",
        author  = "Steel",
	date    = "December 2025",
        layer   = 1001,
        enabled = true,
    }
end

function widget:WantsMouse()    return true end
function widget:WantsKeyboard() return true end

--------------------------------------------------------------------------------
-- Engine refs
--------------------------------------------------------------------------------

local spEcho            = Spring.Echo
local spTraceScreenRay  = Spring.TraceScreenRay
local spSendLuaRulesMsg = Spring.SendLuaRulesMsg
local spSendCommands    = Spring.SendCommands
local spGetViewGeometry = Spring.GetViewGeometry
local spGetConfigInt    = Spring.GetConfigInt
local spSetConfigInt    = Spring.SetConfigInt
local spGetMouseState   = Spring.GetMouseState
local spGetModKeyState  = Spring.GetModKeyState

local glColor        = gl.Color
local glRect         = gl.Rect
local glText         = gl.Text
local glLineWidth    = gl.LineWidth
local glBeginEnd     = gl.BeginEnd
local glVertex       = gl.Vertex
local glGetTextWidth = gl.GetTextWidth

local GL_TRIANGLE_FAN   = GL.TRIANGLE_FAN
local GL_TRIANGLE_STRIP = GL.TRIANGLE_STRIP

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function Snap(x)
    return math.floor(x + 0.5)
end


local function RoundToStep(v, step)
    if not step or step <= 0 then return v end
    return math.floor((v / step) + 0.5) * step
end

local function DegToRad(d) return d * math.pi / 180 end

--------------------------------------------------------------------------------
-- Theme (copied to match gui_ceg_browser.lua)
--------------------------------------------------------------------------------

local theme = {}

theme.window = {
    bg        = {0.03, 0.03, 0.03, 0.92},
    border    = {0.10, 0.10, 0.10, 1.00},
    titleBg   = {0.00, 0.00, 0.00, 0.55},
    titleText = {1.00, 1.00, 1.00, 1.00},
}

theme.button = {
    bg         = {0.18, 0.18, 0.18, 1.00},
    bgActive   = {0.31, 0.63, 0.27, 1.00},
    text       = {0.90, 0.90, 0.90, 1.00},
    textActive = {1.00, 1.00, 1.00, 1.00},
    border     = {0.35, 0.35, 0.35, 1.00},
}

theme.badButton = {
    bg     = {0.40, 0.10, 0.10, 1.00},
    text   = {1.00, 1.00, 1.00, 1.00},
    border = {0.20, 0.02, 0.02, 1.00},
}

theme.alphaBtn = {
    bg       = {0.10, 0.10, 0.10, 0.95},
    bgActive = {0.31, 0.63, 0.27, 1.00},
    text     = {0.88, 0.88, 0.88, 1.00},
    border   = {0.35, 0.35, 0.35, 1.00},
}

theme.tuningPanel = {
    bg     = {0.05, 0.05, 0.05, 0.96},
    border = {0.40, 0.40, 0.40, 1.00},
    text   = {0.90, 0.90, 0.90, 1.00},
}

theme.list = {
    bg         = {0.06, 0.06, 0.06, 1.00},
    rowBg      = {0.19, 0.19, 0.19, 1.00},
    rowBgSel   = {0.31, 0.63, 0.27, 1.00},
    rowBgSelImpact = {0.25, 0.45, 0.75, 1.00},
    border     = {0.35, 0.35, 0.35, 1.00},
    rowText    = {0.96, 0.96, 0.96, 1.00},
    rowTextSel = {1.00, 1.00, 1.00, 1.00},
}

theme.slider = {
    track = {0.16, 0.16, 0.16, 1.00},
    fill  = {0.31, 0.63, 0.27, 1.00},
    knob  = {0.95, 0.95, 0.95, 1.00},
}

theme.search = {
    bg       = {0.18, 0.18, 0.18, 1.00},
    border   = {0.35, 0.35, 0.35, 1.00},
    text     = {0.95, 0.95, 0.95, 1.00},
    hintText = {0.55, 0.55, 0.55, 1.00},
}

theme.text = {
    normal = {0.95, 0.95, 0.95, 1.00},
    dim    = {0.70, 0.70, 0.70, 1.00},
}

theme.fontSize = {
    title  = 18,
    normal = 12,
    list   = 14,
    button = 14,
}

local PADDING_OUTER        = 10
local CORNER_WINDOW_RADIUS = 6
local CORNER_BUTTON_RADIUS = 4

--------------------------------------------------------------------------------
-- Rounded rect helpers (copied style)
--------------------------------------------------------------------------------

local function DrawRoundedRectFilled(x0, y0, x1, y1, r)
    x0, y0, x1, y1 = Snap(x0), Snap(y0), Snap(x1), Snap(y1)
    r = math.max(0, math.min(r or 0, math.min((x1-x0)/2, (y1-y0)/2)))
    if r == 0 then
        glRect(x0, y0, x1, y1)
        return
    end
    glRect(x0 + r, y0,     x1 - r, y1)
    glRect(x0,     y0 + r, x1,     y1 - r)

    local function corner(cx, cy, a0, a1)
        local steps = 6
        glBeginEnd(GL_TRIANGLE_FAN, function()
            glVertex(cx, cy)
            for i = 0, steps do
                local a = a0 + (a1 - a0) * (i / steps)
                glVertex(cx + math.cos(a)*r, cy + math.sin(a)*r)
            end
        end)
    end

    corner(x0 + r, y0 + r, math.pi, 1.5*math.pi)
    corner(x1 - r, y0 + r, 1.5*math.pi, 2.0*math.pi)
    corner(x1 - r, y1 - r, 0.0,        0.5*math.pi)
    corner(x0 + r, y1 - r, 0.5*math.pi, math.pi)
end

local function DrawRoundedRectBorder(x0, y0, x1, y1, r, width)
    x0, y0, x1, y1 = Snap(x0), Snap(y0), Snap(x1), Snap(y1)
    r = math.max(0, math.min(r or 0, math.min((x1-x0)/2, (y1-y0)/2)))
    width = width or 1
    glLineWidth(width)
    if r == 0 then
        glBeginEnd(GL_TRIANGLE_STRIP, function()
            glVertex(x0, y0); glVertex(x1, y0)
            glVertex(x0, y1); glVertex(x1, y1)
        end)
        return
    end
    local steps = 12
    glBeginEnd(GL_TRIANGLE_STRIP, function()
        for i = 0, steps do
            local a = math.pi + (math.pi/2)*(i/steps)
            glVertex(x0 + r + math.cos(a)*r, y0 + r + math.sin(a)*r)
        end
        for i = 0, steps do
            local a = 1.5*math.pi + (math.pi/2)*(i/steps)
            glVertex(x1 - r + math.cos(a)*r, y0 + r + math.sin(a)*r)
        end
        for i = 0, steps do
            local a = 0.0 + (math.pi/2)*(i/steps)
            glVertex(x1 - r + math.cos(a)*r, y1 - r + math.sin(a)*r)
        end
        for i = 0, steps do
            local a = 0.5*math.pi + (math.pi/2)*(i/steps)
            glVertex(x0 + r + math.cos(a)*r, y1 - r + math.sin(a)*r)
        end
    end)
end

--------------------------------------------------------------------------------
-- Button helpers (copied style)
--------------------------------------------------------------------------------
local function drawSlider(x, y, value, minVal, maxVal)
    local w = 220
    local h = 10

    local t = Clamp((value - minVal) / (maxVal - minVal), 0, 1)

    local x0 = Snap(x)
    local y0 = Snap(y)
    local x1 = Snap(x + w)
    local y1 = Snap(y + h)

    -- track
    glColor(theme.slider.track[1], theme.slider.track[2], theme.slider.track[3], theme.slider.track[4])
    glRect(x0, y0, x1, y1)

    -- fill
    glColor(theme.slider.fill[1], theme.slider.fill[2], theme.slider.fill[3], theme.slider.fill[4])
    glRect(x0, y0, Snap(x0 + w * t), y1)

    -- knob
    local kx = Snap(x0 + w * t)
    glColor(theme.slider.knob[1], theme.slider.knob[2], theme.slider.knob[3], theme.slider.knob[4])
    glRect(kx - 2, y0 - 3, kx + 2, y1 + 3)

    return {
        x0 = x0,
        y0 = y0 - 6,
        x1 = x1,
        y1 = y1 + 6,
    }
end

local function DrawButton(x0, y0, x1, y1, label, isActive, isBad, fontSize)
    x0, y0, x1, y1 = Snap(x0), Snap(y0), Snap(x1), Snap(y1)
    fontSize = fontSize or theme.fontSize.normal

    local colSet = isBad and theme.badButton or theme.button
    local bg = isActive and colSet.bgActive or colSet.bg

    glColor(bg[1], bg[2], bg[3], bg[4])
    DrawRoundedRectFilled(x0, y0, x1, y1, CORNER_BUTTON_RADIUS)

    glColor(colSet.border[1], colSet.border[2], colSet.border[3], colSet.border[4])
    DrawRoundedRectBorder(x0, y0, x1, y1, CORNER_BUTTON_RADIUS, 1)

    if label and label ~= "" then
        local textW = glGetTextWidth(label) * fontSize
        local tx = x0 + (x1 - x0 - textW) * 0.5
        local ty = y0 + (y1 - y0 - fontSize) * 0.5 + 1
        local col = isActive and colSet.textActive or colSet.text
        glColor(col[1], col[2], col[3], col[4])
        glText(label, Snap(tx), Snap(ty), fontSize, "o")
    end
end

local function DrawAlphaButton(x0, y0, x1, y1, label, isActive)
    x0, y0, x1, y1 = Snap(x0), Snap(y0), Snap(x1), Snap(y1)
    local t = theme.alphaBtn
    local bg = isActive and t.bgActive or t.bg

    glColor(bg[1], bg[2], bg[3], bg[4])
    DrawRoundedRectFilled(x0, y0, x1, y1, CORNER_BUTTON_RADIUS)

    glColor(t.border[1], t.border[2], t.border[3], t.border[4])
    DrawRoundedRectBorder(x0, y0, x1, y1, CORNER_BUTTON_RADIUS, 1)

    local fs = theme.fontSize.normal + 2
    local textW = glGetTextWidth(label) * fs
    local tx = x0 + (x1 - x0 - textW) * 0.5
    local ty = y0 + (y1 - y0 - fs) * 0.5 + 1

    glColor(t.text[1], t.text[2], t.text[3], t.text[4])
    glText(label, Snap(tx), Snap(ty), fs, "o")
end

--------------------------------------------------------------------------------
-- Fire mode
local fireArmed = false
local groundArmed = false

-- Aux panels (mutually exclusive): nil | "info" | "sound"
local activeAuxPanel = nil

--------------------------------------------------------------------------------

-----------------------------------------------------------------
-- UI-ONLY SOUND ENUMERATION (LuaUI; VFS)
-----------------------------------------------------------------
local function GetAllSoundsUI()
    local sounds = {}
    local seen = {}

    local dirs = {
        "sounds/weapons/",
        "sounds/weapons-mult/",
        "sounds/bombs/",
    }

    local exts = { [".ogg"]=true, [".wav"]=true }

    -- Asset visibility can vary by environment; try multiple modes and union results.
    local modes = { VFS.RAW, VFS.GAME, VFS.MOD, VFS.ZIP, VFS.MAP }

    for _, base in ipairs(dirs) do
        for _, mode in ipairs(modes) do
            local files = VFS.DirList(base, "*", mode)
            for _, path in ipairs(files or {}) do
                local ext = path:match("%.[^%.]+$")
                if ext then ext = ext:lower() end
                if ext and exts[ext] then
                    local name = path
                        :gsub("^sounds/", "")
                        :gsub("%.[^%.]+$", "")
                    if not seen[name] then
                        seen[name] = true
                        sounds[#sounds + 1] = name
                    end
                end
            end
        end
    end

    table.sort(sounds)
    return sounds
end

-- SOUND PANEL (Preview-only selector; isolated state)
--------------------------------------------------------------------------------
local SoundPanelState = {
    -- window rect (set each DrawScreen when panel is drawn)
    win = {x0=0,y0=0,x1=0,y1=0},
    -- sound data (from ceg_lookup.lua)
    sourceList = GetAllSoundsUI(),

    filteredList = {},
    searchText = "",
    searchFocused = false,
    letterFilter = nil, -- nil | 'a'..'z' (browser-style)
    pageIndex = 0, -- 0-based like browser
    itemsPerPage = 20,
    selectedFireSound = nil,
    selectedImpactSound = nil,
    hitBoxes = {
        rows = {},
        search = nil,
        pagerPrev = nil,
        pagerNext = nil,
        reset = nil,
    },
}

local function SoundPanel_RebuildFiltered()
    local q  = (SoundPanelState.searchText or ""):lower()
    local lf = SoundPanelState.letterFilter -- nil or 'a'..'z'
    local t  = {}

    local function basename(s)
        -- ignore everything before the last '/'
        local b = s:match("([^/]+)$")
        return b or s
    end

    for _, name in ipairs(SoundPanelState.sourceList or {}) do
        if type(name) == "string" then
            local ok = true
            local base = basename(name):lower()

            -- A–Z filter applies to basename, not path
            if lf and lf ~= "" then
                if string.sub(base, 1, 1) ~= lf then
                    ok = false
                end
            end

            -- search still matches full string (path-aware)
            if ok and q ~= "" and not name:lower():find(q, 1, true) then
                ok = false
            end

            if ok then
                t[#t+1] = name
            end
        end
    end

    -- sort by basename first, full name second (stable, path-safe)
    table.sort(t, function(a, b)
        local ba = (a:match("([^/]+)$") or a):lower()
        local bb = (b:match("([^/]+)$") or b):lower()
        if ba == bb then
            return a < b
        end
        return ba < bb
    end)

    SoundPanelState.filteredList = t
end


SoundPanel_RebuildFiltered()
--------------------------------------------------------------------------------

local CFG_WIN_X = "ceg_proj_preview_lua_win_x"
local CFG_WIN_Y = "ceg_proj_preview_lua_win_y"

-- Expose browser rect to companion widgets (e.g. CEG Forge)
WG.CEGBrowser = WG.CEGBrowser or {}

function WG.CEGBrowser.GetPanelRect()
    local r = WG.CEGBrowser._lastRect
    if not r then return end
    return r[1], r[2], r[3], r[4]
end

local vsx, vsy
local winX, winY, winW, winH
local prevWinH
local collapsed = false

local GRID_COLS   = 2
local currentRows = 23
local function ItemsPerPage() return currentRows * GRID_COLS end

local ALPHA_ROWS = {
    {"All","A","B","C","D","E","F","G"},
    {"H","I","J","K","L","M","N"},
    {"O","P","Q","R","S","T","U"},
    {"V","W","X","Y","Z"},
}

local allCEGs      = {}
local filteredCEGs = {}
local pageIndex    = 0

local selectedCEGs = {}   -- map: name -> true
local lastSelected = nil

-- Right-click (impact) selection
local selectedImpactCEGs = {}
local lastImpactSelected = nil

-- Middle-click (muzzle) selection
local selectedMuzzleCEGs = {}
local lastMuzzleSelected = nil


local altHoverCEG = nil  -- ALT-hover tooltip state (from baseline)
local letterFilter  = nil
local searchText    = ""
local searchFocused = false

-- Projectile tuning
local yawDeg   = 0     -- -180..180
local projectileForwardOffset = 0
local projectileUpOffset      = 0
local pitchDeg = 20    -- -45..80
local speedVal = 17    -- 0..600

local ttlSeconds = 6    -- 1..30 seconds (default 6)
local airburstOnTTL = false  -- impact CEG on TTL expiry (airburst)

local gravityVal = 0.16 -- -1.00..+1.00 (default = baseline)
local tuningVisible = true -- deprecated
local settingsMode = "projectile"
    groundArmed = false

-- -----------------------------------------------------------------
-- CEG Browser settings (merged)
-- -----------------------------------------------------------------
local cegPattern    = "line"  -- "line" | "ring" | "scatter"
local cegSpawnCountF = 1       -- float accumulator for silky CTRL drag
local cegSpawnCount  = 1       -- 1..100       -- 1..100
local cegSpacing    = 20      -- 0..128

local cegSpacingF   = 20      -- float accumulator for silky CTRL drag
local cegHeightOffset = 0      -- 0..800
local cheatOn       = false
local globallosOn   = false

local draggingWin    = false
local dragOffX       = 0
local dragOffY       = 0
local draggingSlider = nil

local hitBoxes = {
    titleButtons = {},
    alphaButtons = {},
    topButtons   = {},
    reloadBtn    = nil,
    tuningBtn    = nil,
    fireBtn      = nil,
    searchBox    = nil,
    searchClear  = nil,
    sliderYaw    = nil,
    sliderPitch  = nil,
    sliderSpeed  = nil,
    sliderGravity = nil,
    sliderTTL     = nil,
    btnAirburst = nil,
    -- CEG Browser panel hitboxes
    patternBtns  = {},
    sliderCount  = nil,
    sliderSpace  = nil,
    sliderHeight = nil,
    listCells    = {},
    pagerPrev    = nil,
    pagerNext    = nil,
}

--------------------------------------------------------------------------------
-- Data loading & filtering 
--------------------------------------------------------------------------------

local function LoadAllCEGs()
    local ok, lookup = pcall(VFS.Include, "LuaRules/ceg_lookup.lua")
    if not ok or type(lookup) ~= "table" or type(lookup.GetAllNames) ~= "function" then
        spEcho("[CEG Proj Preview] Failed to load LuaRules/ceg_lookup.lua: " .. tostring(lookup))
        return
    end
    allCEGs = lookup.GetAllNames() or {}
    table.sort(allCEGs)
    spEcho("[CEG Proj Preview] Loaded " .. #allCEGs .. " CEG names.")
end

local function MatchesFilter(name)
    if letterFilter and letterFilter ~= "" then
        if string.lower(string.sub(name, 1, 1)) ~= letterFilter then
            return false
        end
    end
    if searchText ~= "" then
        local n = string.lower(name)
        local f = string.lower(searchText)
        if not string.find(n, f, 1, true) then
            return false
        end
    end
    return true
end

local function RebuildFiltered()
    filteredCEGs = {}
    for i = 1, #allCEGs do
        local n = allCEGs[i]
        if MatchesFilter(n) then
            filteredCEGs[#filteredCEGs+1] = n
        end
    end
    -- NOTE: Do NOT prune selection tables when filters change.
    -- Filtering/paging is a view concern only; it must not destroy user intent.
    -- Selected Trail / Impact / Muzzle CEGs may be off-screen/off-filter and should persist.
    local maxPage = math.max(0, math.floor((#filteredCEGs - 1) / ItemsPerPage()))
    pageIndex = Clamp(pageIndex, 0, maxPage)
end

local function ResolveCEGSourceFile(name)
    if not name then return nil end
    local ok, lookup = pcall(VFS.Include, "LuaRules/ceg_lookup.lua")
    if not ok or not lookup or not lookup.Resolve then
        return nil
    end
    local info = lookup.Resolve(name)
    return info and info.file
end


--------------------------------------------------------------------------------
-- Messaging
--------------------------------------------------------------------------------

local PREFIX = "cegproj:"

-- forward declaration (used by SpawnGroundCEGs)
local GetSelectedList

-- Ground CEG spawn helper (browser-faithful dispatch ONLY)
local function SpawnGroundCEGs()
    local mx, my = spGetMouseState()
    local typ, pos = spTraceScreenRay(mx, my, true)
    if typ ~= "ground" or not pos then return end

    -- NOTE: game_ceg_tester.lua expects X,Z (not Y), and an optional height offset.
    local x = math.floor(pos[1])
    local z = math.floor(pos[3])

    -- Spawn uses trail selection set (same as browser list selection)
    local names = GetSelectedList()
    if #names == 0 and lastSelected then
        names[1] = lastSelected
    end
    if #names == 0 then return end

    local height = math.floor(cegHeightOffset or 0)

    if #names == 1 then
    -- SINGLE (new): cegtest:name:x:z:count:spacing:pattern:height
    local msg =
        "cegtest:"
        .. names[1]
        .. ":" .. x
        .. ":" .. z
        .. ":" .. (cegSpawnCount or 1)
        .. ":" .. (cegSpacing or 0)
        .. ":" .. (cegPattern or "line")
        .. ":" .. height

    if SoundPanelState.selectedImpactSound then
        msg = msg .. "|impactSound=" .. SoundPanelState.selectedImpactSound
    end

    Spring.Echo("[CEG PREVIEW MSG][PROJECTILE]", msg)
    Spring.Echo("[CEG PREVIEW MSG][GROUND]", msg)
        spSendLuaRulesMsg(msg)

else
    -- MULTI (new): cegtest_multi:name1,name2,...:x:z:count:spacing:pattern:height
    local msg =
        "cegtest_multi:"
        .. table.concat(names, ",")
        .. ":" .. x
        .. ":" .. z
        .. ":" .. (cegSpawnCount or 1)
        .. ":" .. (cegSpacing or 0)
        .. ":" .. (cegPattern or "line")
        .. ":" .. height

    if SoundPanelState.selectedImpactSound then
        msg = msg .. "|impactSound=" .. SoundPanelState.selectedImpactSound
    end

    spSendLuaRulesMsg(msg)
end

end
-- synced gadget listens for this


GetSelectedList = function()
    -- IMPORTANT: selection state must be independent of filtering/paging.
    -- Iterate selection table directly so selected CEGs spawn even when off-screen/off-filter.
    local list = {}
    for n in pairs(selectedCEGs or {}) do
        list[#list+1] = n
    end
    table.sort(list)

    -- If none selected but we have a lastSelected, use that
    if #list == 0 and lastSelected then
        list[1] = lastSelected
    end
    return list
end

local function GetImpactSelectedList()
    -- IMPORTANT: selection state must be independent of filtering/paging.
    local list = {}
    for n in pairs(selectedImpactCEGs or {}) do
        list[#list+1] = n
    end
    table.sort(list)
    return list
end

local function GetMuzzleSelectedList()
    -- IMPORTANT: selection state must be independent of filtering/paging.
    local list = {}
    for n in pairs(selectedMuzzleCEGs or {}) do
        list[#list+1] = n
    end
    table.sort(list)
    return list
end

local function FireSelectedProjectiles()
    local mx, my = spGetMouseState()
    local typ, pos = spTraceScreenRay(mx, my, true)
    if typ ~= "ground" or not pos then
        spEcho("[CEG Proj Preview] Mouse is not over ground.")
        return
    end
    local wx = math.floor(pos[1])
    local wz = math.floor(pos[3])

    local list = GetSelectedList()
    if #list == 0 then
        spEcho("[CEG Proj Preview] No CEG selected.")
        return
    end

    local impactList = GetImpactSelectedList()
    local impactStr = table.concat(impactList, ",")

    -- Fire one message per CEG (simple + safe)
    local yd = math.floor(yawDeg)
    local pd = math.floor(pitchDeg)
    local sp = math.floor(speedVal)

    for i = 1, #list do
        local cegName = list[i]
            -- Baseline-correct projectile message (NO impactStr; preserves yaw/pitch order)
    
    -- Baseline-correct projectile message (fixed field order, inline impact CEGs)
    local impactList = GetImpactSelectedList()
    local impactStr  = table.concat(impactList or {}, ",")

    
    local muzzleList = GetMuzzleSelectedList()
    local muzzleStr  = table.concat(muzzleList or {}, ",")

    local msg = string.format(
        "%s%s:%s:%d:%d:%d:%d:%d:%.2f",
        PREFIX,
        cegName,
        impactStr or "",
        wx, wz, yd, pd, sp, gravityVal
    )    msg = msg .. string.format("|ttl=%.2f|airburst=%d", (ttlSeconds or 6), (airburstOnTTL and 1 or 0))

    if muzzleStr ~= "" then
        msg = msg .. "|muzzle=" .. muzzleStr
    end

        -- append selected sounds (baseline-safe)
    if SoundPanelState.selectedFireSound then
        msg = msg .. "|fireSound=" .. SoundPanelState.selectedFireSound
    end
    if SoundPanelState.selectedImpactSound then
        msg = msg .. "|impactSound=" .. SoundPanelState.selectedImpactSound
    end

    msg = msg .. string.format("|ofs=%d,%d", math.floor(projectileForwardOffset or 0), math.floor(projectileUpOffset or 0))
    spSendLuaRulesMsg(msg)


    end

    spEcho(string.format("[CEG Proj Preview] Fired %d projectile(s) yaw=%d pitch=%d speed=%d gravity=%.2f", #list, yd, pd, sp, gravityVal))
end

--------------------------------------------------------------------------------
-- Init / shutdown
--------------------------------------------------------------------------------

local function ClampWindowPosition()
    vsx, vsy = spGetViewGeometry()
    if not winX or not winY or not winW or not winH then return end
    local maxX = math.max(0, vsx - winW)
    local maxY = math.max(0, vsy - winH - 60)
    winX = Clamp(Snap(winX), 0, maxX)
    winY = Clamp(Snap(winY), 0, maxY)
end

function widget:Initialize()
    vsx, vsy = spGetViewGeometry()
    winW = 420
    winH = 970

    local cfgX = spGetConfigInt(CFG_WIN_X, 1)
    local cfgY = spGetConfigInt(CFG_WIN_Y, 1)
    if cfgX and cfgY and cfgX > 0 and cfgY > 0 then
        winX, winY = cfgX, cfgY
    else
        winX = math.floor((vsx - winW)/2)
        winY = math.floor((vsy - winH)/2)
    end
    ClampWindowPosition()

    LoadAllCEGs()
    RebuildFiltered()
    widgetHandler:RaiseWidget(self)
end

function widget:Shutdown()
    spSetConfigInt(CFG_WIN_X, winX or 0)
    spSetConfigInt(CFG_WIN_Y, winY or 0)
    -- Ensure SDL text input mode doesn't leak if widget is closed while a search is focused
    if searchFocused or (SoundPanelState and SoundPanelState.searchFocused) then
        Spring.SDLStopTextInput()
    end
end

--------------------------------------------------------------------------------
-- DrawScreen
--------------------------------------------------------------------------------

local function MouseInWindow(mx, my)
    return mx >= winX and mx <= winX+winW and my >= winY and my <= winY+winH
end


-- -----------------------------------------------------------------
-- CEG Browser settings panel (merged)
-- -----------------------------------------------------------------
local function DrawCEGBrowserSettingsPanel(tpX0, tpY0, tpX1, tpY1, theme)
    Spring.Echo("[CEG Proj Preview] Drawing CEG settings panel")

    hitBoxes.patternBtns = {}
    hitBoxes.sliderCount = nil
    hitBoxes.sliderSpace = nil

    -- panel bg/border/text already set by caller
    glText("CEG Tuning", Snap(tpX0 + 10), Snap(tpY1 - 22), theme.fontSize.normal, "o")

    local pattY0 = tpY1 - 44
    local pattH  = 22
    local pattW  = 70
    local pattPad= 4
    local pattX  = tpX0 + 90

    glText("Pattern", Snap(tpX0 + 10), Snap(pattY0 + 4), theme.fontSize.normal, "o")

    local patterns = {"line","ring","scatter"}
    for i,name in ipairs(patterns) do
        local xA = pattX + (i-1)*(pattW+pattPad)
        local xB = xA + pattW
        local label = name:gsub("^%l", string.upper)
        DrawButton(xA, pattY0, xB, pattY0+pattH, label, cegPattern == name, false, theme.fontSize.button)
        hitBoxes.patternBtns[#hitBoxes.patternBtns+1] = {
            id="pattern_"..name, name=name, x0=xA, y0=pattY0, x1=xB, y1=pattY0+pattH
        }
    end

    local labelX       = tpX0 + 10

    local countLabelY  = pattY0 - 22
    local countSliderY = countLabelY - 8
    glText("Spawn Count: "..tostring(cegSpawnCount),
        Snap(labelX), Snap(countLabelY+3), theme.fontSize.normal, "o")
    hitBoxes.sliderCount = drawSlider(labelX, countSliderY, cegSpawnCount, 1, 100)

    local spaceLabelY  = countSliderY - 22
    local spaceSliderY = spaceLabelY - 8
    glText("Spacing: "..tostring(cegSpacing),
        Snap(labelX), Snap(spaceLabelY+3), theme.fontSize.normal, "o")
    hitBoxes.sliderSpace = drawSlider(labelX, spaceSliderY, cegSpacing, 0, 128)
end

function widget:DrawScreen()
    if Spring.IsGUIHidden() then return end
    -- ALT hover: clear when ALT released (baseline behavior)
    local altDown = select(1, spGetModKeyState())
    if altHoverCEG and not altDown then altHoverCEG = nil end
    if not winX or not winY then return end

    vsx, vsy = spGetViewGeometry()

    local x0 = Snap(winX)
    local y0 = Snap(winY)
    local x1 = Snap(winX + winW)
    local y1 = Snap(winY + winH)

    -- Expose browser panel rect for companion widgets (e.g. CEG Forge)
    WG.CEGBrowser = WG.CEGBrowser or {}
    WG.CEGBrowser._lastRect = { x0, y0, x1, y1 }


    -- window background
    glColor(theme.window.bg[1], theme.window.bg[2], theme.window.bg[3], theme.window.bg[4])
    DrawRoundedRectFilled(x0, y0, x1, y1, CORNER_WINDOW_RADIUS)
    glColor(theme.window.border[1], theme.window.border[2], theme.window.border[3], theme.window.border[4])
    DrawRoundedRectBorder(x0, y0, x1, y1, CORNER_WINDOW_RADIUS, 1)

    -- title bar
    local titleH = 30
    glColor(theme.window.titleBg[1], theme.window.titleBg[2], theme.window.titleBg[3], theme.window.titleBg[4])
    DrawRoundedRectFilled(x0+1, y1-titleH, x1-1, y1-1, CORNER_WINDOW_RADIUS-1)

    glColor(theme.window.titleText[1], theme.window.titleText[2], theme.window.titleText[3], theme.window.titleText[4])
    glText("CEG Browser", x0 + PADDING_OUTER, y1 - titleH + 8, theme.fontSize.title, "o")

    ----------------------------------------------------------------
    -- Title buttons
    ----------------------------------------------------------------
    local topBtnW, topBtnH = 24, 18
    local topPad = 6
    hitBoxes.titleButtons = {}

    local closeX1 = x1 - topPad
    local closeX0 = closeX1 - topBtnW
    local closeY0 = y1 - titleH + 6
    local closeY1 = closeY0 + topBtnH

    DrawButton(closeX0, closeY0, closeX1, closeY1, "x", false, true, theme.fontSize.normal)
    hitBoxes.titleButtons.close = {id="close", x0=closeX0, y0=closeY0, x1=closeX1, y1=closeY1}

    local iconX1 = closeX0 - 4
    local iconX0 = iconX1 - topBtnW
    local iconY0 = closeY0
    local iconY1 = closeY1

    local iconLabel = collapsed and "+" or "–"
    DrawButton(iconX0, iconY0, iconX1, iconY1, iconLabel, collapsed, false, theme.fontSize.normal)
    hitBoxes.titleButtons.icon = {id="collapse", x0=iconX0, y0=iconY0, x1=iconX1, y1=iconY1}

    ----------------------------------------------------------------
    -- Alphabet (left) + command buttons (right)
    ----------------------------------------------------------------
    local alphaBtnH = 20
    local alphaPadY = 4
    local alphaPadX = 3
    local alphaPanelW = 210

    hitBoxes.alphaButtons = {}
    hitBoxes.topButtons   = {}

    local yAlphaTop = y1 - titleH - 8
    local yCursor   = yAlphaTop

    local alphaX0 = x0 + PADDING_OUTER
    local alphaX1 = alphaX0 + alphaPanelW

    for _, row in ipairs(ALPHA_ROWS) do
        local rowY1 = yCursor
        local rowY0 = rowY1 - alphaBtnH
        local colX  = alphaX0
        for _, label in ipairs(row) do
            local bw = (label == "All") and 30 or 20
            local x2 = colX + bw
            local active
            if label == "All" then
                active = (not letterFilter)
            else
                active = (letterFilter == string.lower(label))
            end
            DrawAlphaButton(colX, rowY0, x2, rowY1, label, active)
            hitBoxes.alphaButtons[#hitBoxes.alphaButtons+1] = {
                id="alpha_"..label, label=label,
                x0=colX, y0=rowY0, x1=x2, y1=rowY1
            }
            colX = x2 + alphaPadX
        end
        yCursor = rowY0 - alphaPadY
    end
    local alphaBottom = yCursor

    ----------------------------------------------------------------
    -- Right-side 2x3 button panel
    ----------------------------------------------------------------
    local cmdGapX = 8
    local cmdX0   = alphaX1 + cmdGapX
    local cmdX1   = x1 - PADDING_OUTER
    local cmdWidthTotal = cmdX1 - cmdX0
    local cmdColGap     = 6
    local cmdBtnW       = (cmdWidthTotal - cmdColGap) / 2
    local cmdBtnH       = 26

    local row1Y1 = yAlphaTop
    local row1Y0 = row1Y1 - cmdBtnH
    local row2Y1 = row1Y0 - 4
    local row2Y0 = row2Y1 - cmdBtnH
    local row3Y1 = row2Y0 - 4
    local row3Y0 = row3Y1 - cmdBtnH
    
    local row4Y1 = row3Y0 - 4
    local row4Y0 = row4Y1 - cmdBtnH

    local c1x0 = cmdX0
    local c1x1 = cmdX0 + cmdBtnW
    local c2x0 = cmdX0 + cmdBtnW + cmdColGap
    local c2x1 = cmdX1

    -- Row 1
    DrawButton(c1x0, row1Y0, c1x1, row1Y1, "cheat", cheatOn, false, theme.fontSize.button)
    DrawButton(c2x0, row1Y0, c2x1, row1Y1, "globallos", globallosOn, false, theme.fontSize.button)
    hitBoxes.topButtons.cheat = {id="cheat", x0=c1x0,y0=row1Y0,x1=c1x1,y1=row1Y1}
    hitBoxes.topButtons.glob  = {id="globallos", x0=c2x0,y0=row1Y0,x1=c2x1,y1=row1Y1}

    -- Row 2
    DrawButton(c1x0, row2Y0, c1x1, row2Y1, "Reload CEGs", false, false, theme.fontSize.button)
    DrawButton(c2x0, row2Y0, c2x1, row2Y1, groundArmed and "ARMED" or "GROUND", groundArmed, false, theme.fontSize.button)

    hitBoxes.reloadBtn = {id="reload", x0=c1x0,y0=row2Y0,x1=c1x1,y1=row2Y1}
    hitBoxes.tuningBtn = {id="tuning", x0=c2x0,y0=row2Y0,x1=c2x1,y1=row2Y1}

    -- Row 3
    DrawButton(c1x0, row3Y0, c1x1, row3Y1, "Reset", false, false, theme.fontSize.button)
    DrawButton(
        c2x0, row3Y0, c2x1, row3Y1,
        fireArmed and "ARMED" or "PROJECTILE",
        fireArmed,
        false,
        theme.fontSize.button
    )
    hitBoxes.topButtons.resetSel = {id="resetSel", x0=c1x0,y0=row3Y0,x1=c1x1,y1=row3Y1}
    hitBoxes.fireBtn             = {id="fire",     x0=c2x0,y0=row3Y0,x1=c2x1,y1=row3Y1}

    -- Row 4 (CEG Forge)
    DrawButton(
        c1x0, row4Y0, c1x1, row4Y1,
        "CEG INFO",
        activeAuxPanel == "info",
        false,
        theme.fontSize.button
    )

    -- Row 4 (Sounds)
    DrawButton(
        c2x0, row4Y0, c2x1, row4Y1,
        "SOUNDS",
        activeAuxPanel == "sound",
        false,
        theme.fontSize.button
    )
    hitBoxes.topButtons.sounds = {
        id = "sounds",
        x0 = c2x0, y0 = row4Y0,
        x1 = c2x1, y1 = row4Y1
    }

    hitBoxes.topButtons.forge = {
        id = "forge",
        x0 = c1x0, y0 = row4Y0,
        x1 = c1x1, y1 = row4Y1
    }

    local cmdBottom   = row4Y0
    local blockBottom = math.min(alphaBottom, cmdBottom)

    ----------------------------------------------------------------
    -- Search row
    ----------------------------------------------------------------
    local searchH  = 22
    local searchW  = 260
    local searchY1 = blockBottom - 8
    local searchY0 = searchY1 - searchH
    local searchX0 = x0 + PADDING_OUTER
    local searchX1 = searchX0 + searchW

    glColor(theme.search.bg[1], theme.search.bg[2], theme.search.bg[3], theme.search.bg[4])
    DrawRoundedRectFilled(searchX0, searchY0, searchX1, searchY1, CORNER_BUTTON_RADIUS)
    glColor(theme.search.border[1], theme.search.border[2], theme.search.border[3], theme.search.border[4])
    DrawRoundedRectBorder(searchX0, searchY0, searchX1, searchY1, CORNER_BUTTON_RADIUS, 1)

    local drawText = searchText
    local col = theme.search.text
    if drawText == "" and not searchFocused then
        drawText = "search CEG name..."
        col = theme.search.hintText
    end
    glColor(col[1], col[2], col[3], col[4])
    glText(drawText, Snap(searchX0 + 8), Snap(searchY0 + 4), theme.fontSize.normal, "o")

    local clrW = 20
    local clrX1 = searchX1 + clrW
    local clrX0 = clrX1 - clrW
    DrawButton(clrX0, searchY0, clrX1, searchY1, "x", false, false, theme.fontSize.normal)
    hitBoxes.searchBox   = {x0=searchX0,y0=searchY0,x1=searchX1,y1=searchY1}
    hitBoxes.searchClear = {id="search_clear",x0=clrX0,y0=searchY0,x1=clrX1,y1=searchY1}

    glColor(theme.text.dim[1], theme.text.dim[2], theme.text.dim[3], theme.text.dim[4])
    glText(string.format("%d CEGs (filtered)", #filteredCEGs),
           Snap(clrX1 + 8), Snap(searchY0 + 4), theme.fontSize.normal, "o")

    if collapsed then
        return
    end

    ----------------------------------------------------------------
    -- Settings panel (Projectile / CEG Browser)
    ----------------------------------------------------------------
    -- Settings panel (mode-based)
    ----------------------------------------------------------------
        -- Reset hitboxes
        hitBoxes.sliderYaw     = nil
        hitBoxes.sliderPitch   = nil
        hitBoxes.sliderSpeed   = nil
        hitBoxes.sliderGravity = nil
        hitBoxes.patternBtns   = {}
        hitBoxes.sliderCount   = nil
        hitBoxes.sliderSpace   = nil
        hitBoxes.sliderHeight  = nil

        local tpX0 = x0 + PADDING_OUTER
        local tpX1 = x1 - PADDING_OUTER
        local tpY1 = searchY0 - 10

        -- Panel heights preserved from baselines:
        --  projectile tuning panel: 180
        --  CEG browser tuning panel: 180
        local panelH = (settingsMode == "projectile") and 210 or 210
        local tpY0 = tpY1 - panelH
        local listTop

        
        if settingsMode == "projectile" then

            glColor(theme.tuningPanel.bg[1], theme.tuningPanel.bg[2], theme.tuningPanel.bg[3], theme.tuningPanel.bg[4])
            DrawRoundedRectFilled(tpX0, tpY0, tpX1, tpY1, CORNER_WINDOW_RADIUS)
            glColor(theme.tuningPanel.border[1], theme.tuningPanel.border[2], theme.tuningPanel.border[3], theme.tuningPanel.border[4])
            DrawRoundedRectBorder(tpX0, tpY0, tpX1, tpY1, CORNER_WINDOW_RADIUS, 1)

            glColor(theme.tuningPanel.text[1], theme.tuningPanel.text[2], theme.tuningPanel.text[3], theme.tuningPanel.text[4])
            glText("Projectile Tuning", Snap(tpX0 + 10), Snap(tpY1 - 22), theme.fontSize.normal, "o")

            local labelX   = tpX0 + 10
            local sliderW  = 170
            local colGap   = 40
            local col2X    = labelX + sliderW + colGap

            local function drawPSlider(x0s, yMid, val, minVal, maxVal)
                local tY0 = yMid-3
                local tY1 = yMid+3
                local x1s = x0s+sliderW

                glColor(theme.slider.track[1], theme.slider.track[2], theme.slider.track[3], theme.slider.track[4])
                glRect(Snap(x0s), Snap(tY0), Snap(x1s), Snap(tY1))

                local t = Clamp((val-minVal)/(maxVal-minVal),0,1)
                local pos = x0s + t*(sliderW)
                glColor(theme.slider.fill[1], theme.slider.fill[2], theme.slider.fill[3], theme.slider.fill[4])
                glRect(Snap(x0s), Snap(tY0), Snap(pos), Snap(tY1))

                local r = 5
                glColor(theme.slider.knob[1], theme.slider.knob[2], theme.slider.knob[3], theme.slider.knob[4])
                glBeginEnd(GL_TRIANGLE_FAN, function()
                    for i=0,12 do
                        local a = (i/12)*2*math.pi
                        glVertex(Snap(pos+math.cos(a)*r), Snap((tY0+tY1)/2+math.sin(a)*r))
                    end
                end)
                return {x0=x0s,y0=tY0-4,x1=x1s,y1=tY1+4}
            end

            local row1LabelY = tpY1 - 40
            glText(string.format("Direction: %d°", math.floor(yawDeg)), Snap(labelX), Snap(row1LabelY), theme.fontSize.normal, "o")
            hitBoxes.sliderYaw = drawPSlider(labelX, row1LabelY-10, yawDeg, -180, 180)

            glText(string.format("Pitch: %d°", math.floor(pitchDeg)), Snap(col2X), Snap(row1LabelY), theme.fontSize.normal, "o")
            hitBoxes.sliderPitch = drawPSlider(col2X, row1LabelY-10, pitchDeg, -45, 80)

            local row2LabelY = row1LabelY - 30
            glText(string.format("Speed: %d", math.floor(speedVal)), Snap(labelX), Snap(row2LabelY), theme.fontSize.normal, "o")
            hitBoxes.sliderSpeed = drawPSlider(labelX, row2LabelY-10, speedVal, 0, 600)

            glText(string.format("Gravity: %.2f", gravityVal), Snap(col2X), Snap(row2LabelY), theme.fontSize.normal, "o")
            hitBoxes.sliderGravity = drawPSlider(col2X, row2LabelY-10, gravityVal, -1.0, 1.0)

            -- Third row: Origin offsets (elmos)
            local row3LabelY = row2LabelY - 30

            glText(
                string.format("Origin Forward Offset: %d", math.floor(projectileForwardOffset)),
                Snap(labelX),
                Snap(row3LabelY),
                theme.fontSize.normal,
                "o"
            )
            hitBoxes.sliderProjForward = drawPSlider(
                labelX,
                row3LabelY - 10,
                projectileForwardOffset,
                0, 100
            )

            glText(
                string.format("Origin Height Offset: %d", math.floor(projectileUpOffset)),
                Snap(col2X),
                Snap(row3LabelY),
                theme.fontSize.normal,
                "o"
            )
            hitBoxes.sliderProjUp = drawPSlider(
                col2X,
                row3LabelY - 10,
                projectileUpOffset,
                0, 100
            )

            -- Fourth row: Time To Live (seconds)
            local row4LabelY = row3LabelY - 30
            glText(
                string.format("Time To Live: %.1fs", ttlSeconds),
                Snap(labelX),
                Snap(row4LabelY),
                theme.fontSize.normal,
                "o"
            )
            hitBoxes.sliderTTL = drawPSlider(
                labelX,
                row4LabelY - 10,
                ttlSeconds,
                1, 30
            )


            -- Airburst toggle (Impact CEG at TTL expiry)
            local abW, abH = 170, 18
            local abX0 = col2X
            local abY0 = (row4LabelY - 12)
            local abX1 = abX0 + abW
            local abY1 = abY0 + abH
            DrawButton(abX0, abY0, abX1, abY1, airburstOnTTL and "Airburst: ON" or "Airburst: OFF", airburstOnTTL, false, theme.fontSize.normal)
            hitBoxes.btnAirburst = {id="airburst", x0=abX0, y0=abY0, x1=abX1, y1=abY1}
            ----------------------------------------------------------------
            -- Selection legend (PROJECTILE panel)
            --   Line 1: Muzzle / Trail / Impact
            --   Line 2: + CTRL = Multi-Select
            -- Anchored to absolute bottom of the tuning panel (tpY0)
            ----------------------------------------------------------------
            local fs = theme.fontSize.normal + 2
            local legendBaseY = tpY0 + 10  -- absolute bottom
            local lx = tpX0 + 12
            local ly = legendBaseY + 20

            -- Muzzle (MMB)
            glColor(1.0, 0.55, 0.15, 1)
            glRect(lx, ly, lx + 10, ly + 10)
            glColor(1,1,1,1)
            glText("Muzzle (MMB)", Snap(lx + 14), Snap(ly), fs-1, "o")

            -- Trail (LMB)
            lx = lx + 110
            glColor(theme.list.rowBgSel[1], theme.list.rowBgSel[2], theme.list.rowBgSel[3], 1)
            glRect(lx, ly, lx + 10, ly + 10)
            glColor(1,1,1,1)
            glText("Trail (LMB)", Snap(lx + 14), Snap(ly), fs-1, "o")

            -- Impact (RMB)
            lx = lx + 100
            glColor(theme.list.rowBgSelImpact[1], theme.list.rowBgSelImpact[2], theme.list.rowBgSelImpact[3], 1)
            glRect(lx, ly, lx + 10, ly + 10)
            glColor(1,1,1,1)
            glText("Impact (RMB)", Snap(lx + 14), Snap(ly), fs-1, "o")

            -- Second line: CTRL hint
            glColor(theme.text.dim[1], theme.text.dim[2], theme.text.dim[3], 1)
            glText("+ CTRL = Multi-Select", Snap(tpX0 + 12), Snap(legendBaseY), fs-1, "o")

            -- Preserve listTop calculation (required by list renderer)
            local PANEL_GAP = 4
	    listTop = tpY0 - PANEL_GAP



else

            glColor(theme.tuningPanel.bg[1], theme.tuningPanel.bg[2], theme.tuningPanel.bg[3], theme.tuningPanel.bg[4])
            DrawRoundedRectFilled(tpX0, tpY0, tpX1, tpY1, CORNER_WINDOW_RADIUS)
            glColor(theme.tuningPanel.border[1], theme.tuningPanel.border[2], theme.tuningPanel.border[3], theme.tuningPanel.border[4])
            DrawRoundedRectBorder(tpX0, tpY0, tpX1, tpY1, CORNER_WINDOW_RADIUS, 1)

            glColor(theme.tuningPanel.text[1], theme.tuningPanel.text[2], theme.tuningPanel.text[3], theme.tuningPanel.text[4])
            glText("CEG Tuning", Snap(tpX0 + 10), Snap(tpY1 - 22), theme.fontSize.normal, "o")

            local pattY0 = tpY1 - 44
            local pattH  = 22
            local pattW  = 70
            local pattPad= 4
            local pattX  = tpX0 + 90

            glText("Pattern", Snap(tpX0 + 10), Snap(pattY0 + 4), theme.fontSize.normal, "o")

            local patterns = {"line","ring","scatter"}
            for i,name in ipairs(patterns) do
                local xA = pattX + (i-1)*(pattW+pattPad)
                local xB = xA + pattW
                local label = name:gsub("^%l", string.upper)
                DrawButton(xA, pattY0, xB, pattY0+pattH, label, cegPattern == name, false, theme.fontSize.button)
                hitBoxes.patternBtns[#hitBoxes.patternBtns+1] = {
                    id="pattern_"..name,name=name,x0=xA,y0=pattY0,x1=xB,y1=pattY0+pattH
                }
            end

            local labelX       = tpX0 + 10
            local sliderW      = 140

            local function drawSlider(x0s, yMid, val, minVal, maxVal)
                local tY0 = yMid-3
                local tY1 = yMid+3
                local x1s = x0s+sliderW

                glColor(theme.slider.track[1], theme.slider.track[2], theme.slider.track[3], theme.slider.track[4])
                glRect(Snap(x0s), Snap(tY0), Snap(x1s), Snap(tY1))

                local t = Clamp((val-minVal)/(maxVal-minVal),0,1)
                local pos = x0s + t*(sliderW)
                glColor(theme.slider.fill[1], theme.slider.fill[2], theme.slider.fill[3], theme.slider.fill[4])
                glRect(Snap(x0s), Snap(tY0), Snap(pos), Snap(tY1))

                local r = 5
                glColor(theme.slider.knob[1], theme.slider.knob[2], theme.slider.knob[3], theme.slider.knob[4])
                glBeginEnd(GL_TRIANGLE_FAN, function()
                    for i=0,12 do
                        local a = (i/12)*2*math.pi
                        glVertex(Snap(pos+math.cos(a)*r), Snap((tY0+tY1)/2+math.sin(a)*r))
                    end
                end)
                return {x0=x0s,y0=tY0-4,x1=x1s,y1=tY1+4}
            end

            -- Spawn Count (left column)
            local countLabelY  = pattY0 - 22
            local countSliderY = countLabelY - 8
            glText("Spawn Count: "..tostring(cegSpawnCount),
                Snap(labelX), Snap(countLabelY+3), theme.fontSize.normal, "o")
            hitBoxes.sliderCount = drawSlider(labelX, countSliderY, cegSpawnCount,   1, 100)

            -- Height Offset (right column, same row as Spawn Count)
            local heightLabelX  = labelX + sliderW + 60
            glText("Height Offset: "..tostring(cegHeightOffset),
                Snap(heightLabelX), Snap(countLabelY+3), theme.fontSize.normal, "o")
            hitBoxes.sliderHeight = drawSlider(heightLabelX, countSliderY, cegHeightOffset, 0, 800)

            -- Spacing (left column, below)
            local spaceLabelY  = countSliderY - 22
            local spaceSliderY = spaceLabelY - 8
            glText("Spacing: "..tostring(cegSpacing),
                Snap(labelX), Snap(spaceLabelY+3), theme.fontSize.normal, "o")
            hitBoxes.sliderSpace = drawSlider(labelX, spaceSliderY, cegSpacing, 0, 128)


            ----------------------------------------------------------------
            -- Multi-select legend (GROUND panel, bottom-aligned like projectile)
            ----------------------------------------------------------------
            local legendY = tpY0 + 6
            local legendX = tpX0 + 12
            local fs = theme.fontSize.normal + 2
            glColor(theme.text.dim[1], theme.text.dim[2], theme.text.dim[3], 1)
            glColor(theme.text.dim[1], theme.text.dim[2], theme.text.dim[3], 1)
            
            -- Ground panel legend (Baseline #5.5)
            local lgx = Snap(tpX0 + 12)

            -- Line 1: Selected CEG (LMB) + CTRL multi-select
            glColor(0.15, 0.85, 0.25, 0.90)
            glRect(lgx,
                   Snap(tpY0 + 22),
                   lgx + 10,
                   Snap(tpY0 + 32))
            glColor(1,1,1,1)
            glText("Selected CEG (LMB)   + CTRL = Multi-Select",
                   lgx + 14,
                   Snap(tpY0 + 24),
                   theme.fontSize.normal+1,
                   "o")

            -- Line 2: Mouse buttons note
            glText("MMB / RMB: have no effect on this panel",
                   lgx,
                   Snap(tpY0 + 6),
                   theme.fontSize.normal,
                   "o")


            listTop = tpY0 - 10
        end

    ----------------------------------------------------------------
    -- CEG list (copied behavior)
    ----------------------------------------------------------------
    local listX0 = x0 + PADDING_OUTER
    local listX1 = x1 - PADDING_OUTER
    local rowH   = 22
    local colPad = 6
    local footerH= 26

    local rows = 23
    currentRows = rows

    glColor(theme.list.bg[1], theme.list.bg[2], theme.list.bg[3], theme.list.bg[4])
    glRect(Snap(listX0), Snap(listTop - rows*rowH - 8), Snap(listX1), Snap(listTop))

    hitBoxes.listCells = {}
    local colW = (listX1 - listX0 - colPad)/2

    local startIdx = pageIndex * ItemsPerPage() + 1
    local endIdx   = math.min(#filteredCEGs, startIdx + ItemsPerPage() - 1)

    local idx = startIdx
    local baseY = listTop - 4

    for row=1,rows do
        local y1r = baseY - (row-1)*rowH
        local y0r = y1r - rowH + 2
        for col=1,GRID_COLS do
            if idx > endIdx then break end
            local xCell0 = listX0 + (col-1)*(colW+colPad)
            local xCell1 = xCell0 + colW
            local name   = filteredCEGs[idx]
            local isTrail  = selectedCEGs[name]
            local isImpact = selectedImpactCEGs[name]
            local isMuzzle = selectedMuzzleCEGs and selectedMuzzleCEGs[name]

            local bg
            if isTrail then
                bg = theme.list.rowBgSel
            elseif isImpact then
                bg = theme.list.rowBgSelImpact
            elseif isMuzzle then
                bg = {1.0, 0.55, 0.15, 1.0} -- ORANGE (muzzle)
            else
                bg = theme.list.rowBg
            end
            glColor(bg[1],bg[2],bg[3],bg[4])
            glRect(Snap(xCell0), Snap(y0r), Snap(xCell1), Snap(y1r))

            glColor(theme.list.border[1], theme.list.border[2], theme.list.border[3], theme.list.border[4])
            glRect(Snap(xCell0), Snap(y0r), Snap(xCell1), Snap(y0r+1))

            local txtCol = (isTrail or isImpact or isMuzzle) and theme.list.rowTextSel or theme.list.rowText
            glColor(txtCol[1],txtCol[2],txtCol[3],txtCol[4])
            local show = name
            if #show > 28 then show = show:sub(1,26).."..."
            end
            glText(show, Snap(xCell0+6), Snap(y0r+4), theme.fontSize.list, "o")


            -- ALT hover detection (CEG list)
            if altDown then
                local mx2, my2 = spGetMouseState()
                if mx2 >= xCell0 and mx2 <= xCell1 and my2 >= y0r and my2 <= y1r then
                    altHoverCEG = {
                        name      = name,
                        isTrail   = isTrail,
                        isImpact  = isImpact,
                        isMuzzle  = isMuzzle,
                    }
                end
            end

            hitBoxes.listCells[idx] = {xCell0, y0r, xCell1, y1r, name = name}
            idx = idx+1
            if idx> endIdx then break end
        end
        if idx> endIdx then break end
    end

    ----------------------------------------------------------------
    -- Pager
    ----------------------------------------------------------------
    local pagerH    = 18
    local pagerY0   = y0 + (footerH - pagerH) * 0.5
    local midX      = (listX0 + listX1) * 0.5
    local pPrevX0   = midX - 60
    local pPrevX1   = pPrevX0 + 30
    local pNextX1   = midX + 60
    local pNextX0   = pNextX1 - 30

    DrawButton(pPrevX0, pagerY0, pPrevX1, pagerY0+pagerH, "<", false, false, theme.fontSize.normal)
    DrawButton(pNextX0, pagerY0, pNextX1, pagerY0+pagerH, ">", false, false, theme.fontSize.normal)
    hitBoxes.pagerPrev = {id="page_prev",x0=pPrevX0,y0=pagerY0,x1=pPrevX1,y1=pagerY0+pagerH}
    hitBoxes.pagerNext = {id="page_next",x0=pNextX0,y0=pagerY0,x1=pNextX1,y1=pagerY0+pagerH}

    local totalPages = math.max(1, math.floor((#filteredCEGs - 1)/ItemsPerPage()) + 1)
    local curPage = math.min(totalPages, pageIndex+1)
    glColor(theme.text.normal[1],theme.text.normal[2],theme.text.normal[3],theme.text.normal[4])
    
    -- ALT tooltip hint (baseline-style, non-intrusive)
    glColor(1, 1, 1, 0.75)
    glText(
        "Hold ALT to view full CEG name",
        Snap(midX - glGetTextWidth("Hold ALT to view full CEG name") * theme.fontSize.normal * 0.5),
        Snap(pagerY0 + theme.fontSize.normal + 16),
        theme.fontSize.normal,
        "o"
    )
glText(string.format("Page %d / %d", curPage, totalPages),
           Snap(midX - 35), Snap(pagerY0+3), theme.fontSize.normal, "o")

    ----------------------------------------------------------------
    -- ALT-hover tooltip (full CEG name, suffix colorized)
    ----------------------------------------------------------------
    if altHoverCEG and altDown then
        local mx, my = spGetMouseState()

        local fs  = theme.fontSize.list + 3  -- baseline readability bump
        local pad = 12

        local fullName = altHoverCEG.name or ""
        local pre, suf = fullName:match("^([^%-%_]+)([%-%_].+)$")
        if not pre then
            pre = fullName
            suf = nil
        end

        local w = glGetTextWidth(pre) * fs
        if suf then
            w = w + glGetTextWidth(suf) * fs
        end
        w = w + pad*2

        local h = fs + pad*2

        local tx = Clamp(mx + 16, 0, vsx - w)
        local ty = Clamp(my - h - 12, 0, vsy - h)

        glColor(0, 0, 0, 0.95)
        glRect(tx, ty, tx + w, ty + h)

        glColor(1, 1, 1, 1)
        glText(pre, tx + pad, ty + h - pad - fs, fs, "o")

        if suf then
            local pw = glGetTextWidth(pre) * fs
            glColor(0.6, 0.85, 1.0, 1)
            glText(suf, tx + pad + pw, ty + h - pad - fs, fs, "o")
        end
    end

    ----------------------------------------------------------------
    -- Forge panel overlay draw (mode-agnostic; always draw when open)
    ----------------------------------------------------------------
    if activeAuxPanel == "info" and WG.CEGForge and WG.CEGForge.Draw then
        WG.CEGForge.Draw()
    end

    ----------------------------------------------------------------
    ----------------------------------------------------------------
    -- Sound panel UI (stub list + isolated search/paging)
    ----------------------------------------------------------------
    local function DrawSoundPanelUI(sx0, sy0, sx1, sy1)
        -- persist window rect for input routing
        SoundPanelState.win.x0, SoundPanelState.win.y0 = sx0, sy0
        SoundPanelState.win.x1, SoundPanelState.win.y1 = sx1, sy1

        -- Window frame
        glColor(theme.window.bg[1], theme.window.bg[2], theme.window.bg[3], theme.window.bg[4])
        DrawRoundedRectFilled(sx0, sy0, sx1, sy1, CORNER_WINDOW_RADIUS)
        glColor(theme.window.border[1], theme.window.border[2], theme.window.border[3], theme.window.border[4])
        DrawRoundedRectFilled(sx0, sy0, sx1, sy1, CORNER_WINDOW_RADIUS)

        local titleH = 28
        glColor(theme.window.titleBg[1], theme.window.titleBg[2], theme.window.titleBg[3], theme.window.titleBg[4])
        glRect(sx0 + CORNER_WINDOW_RADIUS, sy1 - titleH, sx1 - CORNER_WINDOW_RADIUS, sy1)
        glColor(theme.window.titleText[1], theme.window.titleText[2], theme.window.titleText[3], theme.window.titleText[4])
        glText("Sounds", sx0 + PADDING_OUTER, sy1 - titleH + 7, theme.fontSize.title, "o")


        -- Close button (X) for Sounds panel (browser-identical)
        local closeBtnW, closeBtnH = 20, 20
        local closeX1 = sx1 - PADDING_OUTER
        local closeX0 = closeX1 - closeBtnW
        local closeY1 = sy1 - (titleH - closeBtnH) / 2
        local closeY0 = closeY1 - closeBtnH

        DrawButton(closeX0, closeY0, closeX1, closeY1, "X", false, false, theme.fontSize.small)
        SoundPanelState.hitBoxes.close = {id="sound_close", x0=closeX0,y0=closeY0,x1=closeX1,y1=closeY1}

        ----------------------------------------------------------------
        -- Alphabet selector (browser-identical layout; SoundPanel-scoped)
        ----------------------------------------------------------------
        local alphaBtnH   = 20
        local alphaPadY   = 4
        local alphaPadX   = 3
        local alphaPanelW = 210

        SoundPanelState.hitBoxes.alphaButtons = {}

        local yAlphaTop = sy1 - titleH - 8
        local yCursor   = yAlphaTop

        local alphaX0 = sx0 + PADDING_OUTER
        local alphaX1 = alphaX0 + alphaPanelW


        -- RESET button (Sound Panel): placed next to alphabet row (like browser Cheat button row)
        -- Larger: spans the width of two standard browser buttons (cheat + globallos)
        local resetBtnW = (80 * 2) + alphaPadX  -- 2 buttons + gap
        local resetBtnH = alphaBtnH
        local resetX0   = alphaX1 + 8
        local resetY1   = yAlphaTop
        local resetY0   = resetY1 - resetBtnH
        local resetX1   = resetX0 + resetBtnW

        DrawButton(resetX0, resetY0, resetX1, resetY1, "RESET", false, false, theme.fontSize.small)
        SoundPanelState.hitBoxes.reset = {id="sound_reset", x0=resetX0,y0=resetY0,x1=resetX1,y1=resetY1}

        -- Play sound buttons (Sounds panel) - disabled unless a sound is selected
        local playGap = 4

        -- Play Firing Sound (uses selectedFireSound, plays at muzzle/origin)
        local fireSel = SoundPanelState.selectedFireSound
        local fireY1  = resetY0 - playGap
        local fireY0  = fireY1 - resetBtnH
        
        glColor(1.0, 0.9, 0.0, 1.0)
        
-- Play Firing Sound button (active when LMB sound selected)
local fireActive = (SoundPanelState.selectedFireSound ~= nil)
DrawButton(
    resetX0, fireY0, resetX1, fireY1,
    "Play Firing Sound",
    fireActive,
    not fireActive,
    theme.fontSize.small
)

        glColor(1,1,1,1)
    
        if fireSel and fireSel ~= "" then
            SoundPanelState.hitBoxes.playFire = {id="sound_play_fire", x0=resetX0,y0=fireY0,x1=resetX1,y1=fireY1}
        else
            SoundPanelState.hitBoxes.playFire = nil
            glColor(0, 0, 0, 0.35)
            glRect(Snap(resetX0), Snap(fireY0), Snap(resetX1), Snap(fireY1))
        end

        -- Play Impact Sound (uses selectedImpactSound, plays at last impact position)
        local impactSel = SoundPanelState.selectedImpactSound
        local impY1     = fireY0 - playGap
        local impY0     = impY1 - resetBtnH
        
        glColor(1.0, 0.15, 0.15, 1.0)
        
-- Play Impact Sound button (active when RMB sound selected)
local impactActive = (SoundPanelState.selectedImpactSound ~= nil)
DrawButton(
    resetX0, impY0, resetX1, impY1,
    "Play Impact Sound",
    impactActive,
    not impactActive,
    theme.fontSize.small
)

        glColor(1,1,1,1)
    
        if impactSel and impactSel ~= "" then
            SoundPanelState.hitBoxes.playImpact = {id="sound_play_impact", x0=resetX0,y0=impY0,x1=resetX1,y1=impY1}
        else
            SoundPanelState.hitBoxes.playImpact = nil
            glColor(0, 0, 0, 0.35)
            glRect(Snap(resetX0), Snap(impY0), Snap(resetX1), Snap(impY1))
        end


        local letterFilter = SoundPanelState.letterFilter -- nil or lower-case 'a'..'z'
        for _, row in ipairs(ALPHA_ROWS) do
            local rowY1 = yCursor
            local rowY0 = rowY1 - alphaBtnH
            local colX  = alphaX0
            for _, label in ipairs(row) do
                local bw = (label == "All") and 30 or 20
                local x2 = colX + bw
                local active
                if label == "All" then
                    active = (not letterFilter)
                else
                    active = (letterFilter == string.lower(label))
                end
                DrawAlphaButton(colX, rowY0, x2, rowY1, label, active)
                SoundPanelState.hitBoxes.alphaButtons[#SoundPanelState.hitBoxes.alphaButtons+1] = {
                    id="sound_alpha_"..label, label=label,
                    x0=colX, y0=rowY0, x1=x2, y1=rowY1
                }
                colX = x2 + alphaPadX
            end
            yCursor = rowY0 - alphaPadY
        end
        local alphaBottom = yCursor

        ----------------------------------------------------------------
        -- Search row (browser-identical layout; SoundPanel-scoped)
        ----------------------------------------------------------------
        local searchH  = 22
        local searchW  = 260
        local searchY1 = alphaBottom - 8
        local searchY0 = searchY1 - searchH
        local searchX0 = sx0 + PADDING_OUTER
        local searchX1 = searchX0 + searchW

        glColor(theme.search.bg[1], theme.search.bg[2], theme.search.bg[3], theme.search.bg[4])
        DrawRoundedRectFilled(searchX0, searchY0, searchX1, searchY1, CORNER_BUTTON_RADIUS)
        glColor(theme.search.border[1], theme.search.border[2], theme.search.border[3], theme.search.border[4])
        DrawRoundedRectBorder(searchX0, searchY0, searchX1, searchY1, CORNER_BUTTON_RADIUS, 1)

        local drawText = SoundPanelState.searchText or ""
        local col = theme.search.text
        if drawText == "" and not SoundPanelState.searchFocused then
            drawText = ""
            drawText = "search sound name..."
            col = theme.search.hintText
        end
        glColor(col[1], col[2], col[3], col[4])
        glText(drawText, Snap(searchX0 + 8), Snap(searchY0 + 4), theme.fontSize.normal, "o")

        local clrW = 20
        local clrX1 = searchX1 + clrW
        local clrX0 = clrX1 - clrW
        DrawButton(clrX0, searchY0, clrX1, searchY1, "x", false, false, theme.fontSize.normal)

        SoundPanelState.hitBoxes.search      = {id="sound_search", x0=searchX0,y0=searchY0,x1=searchX1,y1=searchY1}
        SoundPanelState.hitBoxes.searchClear = {id="sound_search_clear", x0=clrX0,y0=searchY0,x1=clrX1,y1=searchY1}

        glColor(theme.text.dim[1], theme.text.dim[2], theme.text.dim[3], theme.text.dim[4])
        glText(string.format("%d sounds (filtered)", #(SoundPanelState.filteredList or {})),
               Snap(clrX1 + 8), Snap(searchY0 + 4), theme.fontSize.normal, "o")


        ----------------------------------------------------------------
        -- List area (two-column; CEG-identical)
        ----------------------------------------------------------------
        local footerH = 26
        local pagerH  = 18
        local pagerY0 = sy0 + (footerH - pagerH) * 0.5
        local pagerY1 = pagerY0 + pagerH

        local listY0 = pagerY1 + 8
        local legendH = 22
        local legendPad = 6

        -- shrink list by one row so it does not intrude into legend padding
local listY1 = searchY0 - 10 - legendH - legendPad - rowH
        local rowH   = 22
        local colPad = 6
        local SOUND_GRID_COLS = 2

        local rowsVisible = math.floor((listY1 - listY0) / rowH)
        SoundPanelState.itemsPerPage = rowsVisible * SOUND_GRID_COLS

        local listW = (sx1 - sx0) - PADDING_OUTER * 2
        local colW  = (listW - colPad) / SOUND_GRID_COLS

        
        -- Sound selection legend (single-line, bottom-anchored like main browser)
        -- place sound legend directly below the search bar, above the list
local lgY = searchY0 - legendH - legendPad
        local lgX = sx0 + PADDING_OUTER + 8
        local fs  = theme.fontSize.normal + 1

        -- Fire Sound (LMB)
        glColor(1.0, 0.9, 0.0, 1.0)
        glRect(lgX, lgY, lgX + 10, lgY + 10)
        glColor(1,1,1,1)
        local fireLabel = "Fire Sound (LMB)"
        glText(fireLabel, Snap(lgX + 14), Snap(lgY - 1), fs, "o")

        -- advance X by swatch + text width + padding
        lgX = lgX + 14 + (glGetTextWidth(fireLabel) * fs) + 24

        -- Impact Sound (RMB)
        glColor(1.0, 0.15, 0.15, 1.0)
        glRect(lgX, lgY, lgX + 10, lgY + 10)
        glColor(1,1,1,1)
        glText("Impact Sound (RMB)", Snap(lgX + 14), Snap(lgY - 1), fs, "o")

local list  = SoundPanelState.filteredList or {}
        local start = SoundPanelState.pageIndex * SoundPanelState.itemsPerPage + 1
        local stop  = math.min(#list, start + SoundPanelState.itemsPerPage - 1)

        SoundPanelState.hitBoxes.rows = {}

        local idx = start
        local baseY = listY1 - rowH

        for row = 1, rowsVisible do
            local y0 = baseY - (row - 1) * rowH
            local y1 = y0 + rowH
            if y0 < listY0 then break end

            for col = 1, SOUND_GRID_COLS do
                if idx > stop then break end
                local name = list[idx]

                local x0 = sx0 + PADDING_OUTER + (col - 1) * (colW + colPad)
                local x1 = x0 + colW

                SoundPanelState.hitBoxes.rows[#SoundPanelState.hitBoxes.rows + 1] = {
                    id="sound_cell", name=name, x0=x0,y0=y0,x1=x1,y1=y1
                }

                -- base row background (CEG list style)
                glColor(
                    theme.list.rowBg[1],
                    theme.list.rowBg[2],
                    theme.list.rowBg[3],
                    theme.list.rowBg[4]
                )
                glRect(Snap(x0), Snap(y0), Snap(x1), Snap(y1))

                -- selection overlays
                if name == SoundPanelState.selectedFireSound then
                    -- Fire (LMB): bright unit-nameplate yellow
                    glColor(1.0, 0.9, 0.0, 0.85)
                    glRect(Snap(x0), Snap(y0), Snap(x1), Snap(y1))
                elseif name == SoundPanelState.selectedImpactSound then
                    -- Impact (RMB): bright unit-nameplate red
                    glColor(1.0, 0.15, 0.15, 0.85)
                    glRect(Snap(x0), Snap(y0), Snap(x1), Snap(y1))
                end

                glColor(theme.list.border[1], theme.list.border[2], theme.list.border[3], theme.list.border[4])
                glRect(Snap(x0), Snap(y0), Snap(x1), Snap(y0 + 1))

                local show = name
                if #show > 28 then show = show:sub(1,26) .. "..." end
                glColor(1,1,1,1)
                glText(show, Snap(x0 + 6), Snap(y0 + 4), theme.fontSize.list, "o")

                idx = idx + 1
            end
        end

        ----------------------------------------------------------------
        -- Pager (browser-style placement)
        ----------------------------------------------------------------
        local midX    = (sx0 + PADDING_OUTER + (sx1 - PADDING_OUTER)) * 0.5
        local pPrevX0 = midX - 60
        local pPrevX1 = pPrevX0 + 30
        local pNextX1 = midX + 60
        local pNextX0 = pNextX1 - 30

        DrawButton(pPrevX0, pagerY0, pPrevX1, pagerY1, "<", false, false, theme.fontSize.normal)
        DrawButton(pNextX0, pagerY0, pNextX1, pagerY1, ">", false, false, theme.fontSize.normal)
        SoundPanelState.hitBoxes.pagerPrev = {id="sound_prev", x0=pPrevX0,y0=pagerY0,x1=pPrevX1,y1=pagerY1}
        SoundPanelState.hitBoxes.pagerNext = {id="sound_next", x0=pNextX0,y0=pagerY0,x1=pNextX1,y1=pagerY1}

        local totalPages = math.max(1, math.floor(((#(SoundPanelState.filteredList or {})) - 1)/SoundPanelState.itemsPerPage) + 1)
        local curPage = math.min(totalPages, SoundPanelState.pageIndex + 1)
        glColor(1,1,1,0.75)
        glText(string.format("Page %d / %d", curPage, totalPages),
               Snap(midX - 35), Snap(pagerY0 + 3), theme.fontSize.normal, "o")
    end
    ----------------------------------------------------------------
    -- Sounds panel (stub UI; list/search isolated to SoundPanelState)
    ----------------------------------------------------------------
    if activeAuxPanel == "sound" then
        local bx0, by0, bx1, by1
        if WG.CEGBrowser and WG.CEGBrowser.GetPanelRect then
            bx0, by0, bx1, by1 = WG.CEGBrowser.GetPanelRect()
        end
        if not bx0 then
            bx0, by0, bx1, by1 = panelX, panelY, panelX + panelW, panelY + panelH
        end

        -- Sound panel size is self-contained (do NOT rely on forgeW/forgeH locals declared later)
        local sw = 420
        local sh = (by1 - by0)
        local sx1 = bx0 - PADDING_OUTER
        local sx0 = sx1 - sw
        local sy0 = by0
        local sy1 = by1
DrawSoundPanelUI(sx0, sy0, sx1, sy1)
    end

end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

function widget:MousePress(mx, my, button)

        -- Close Sounds panel (X button)
        if activeAuxPanel == "sound" then
            local hb = SoundPanelState.hitBoxes.close
            if hb and mx >= hb.x0 and mx <= hb.x1 and my >= hb.y0 and my <= hb.y1 then
                activeAuxPanel = nil
                SoundPanelState.searchFocused = false
                SoundPanelState.letterFilter = nil
                return true
            end
        end

    -- Forge module (CEG INFO panel) gets first right of refusal, even outside browser window
    if WG.CEGForge and WG.CEGForge.MousePress then
        if WG.CEGForge.MousePress(mx, my, button) then
            return true
        end
    end


    -- Sound panel gets first right of refusal when open (isolated input)
    if activeAuxPanel == "sound" then
        local w = SoundPanelState.win
        if w and mx >= w.x0 and mx <= w.x1 and my >= w.y0 and my <= w.y1 then
            -- reset button
            local hb = SoundPanelState.hitBoxes
            local reset = hb and hb.reset
            if reset and mx>=reset.x0 and mx<=reset.x1 and my>=reset.y0 and my<=reset.y1 then
                SoundPanelState.selectedFireSound   = nil
                SoundPanelState.selectedImpactSound = nil
                return true
            end


            -- play sound buttons (disabled unless a sound is selected)
            local playFire = hb and hb.playFire
            if playFire and mx>=playFire.x0 and mx<=playFire.x1 and my>=playFire.y0 and my<=playFire.y1 then
                local s = SoundPanelState.selectedFireSound
                if s and s ~= "" then
                    Spring.SendLuaRulesMsg("ceg_preview_sound:" .. s)
                end
                return true
            end
            local playImpact = hb and hb.playImpact
            if playImpact and mx>=playImpact.x0 and mx<=playImpact.x1 and my>=playImpact.y0 and my<=playImpact.y1 then
                local s = SoundPanelState.selectedImpactSound
                if s and s ~= "" then
                    Spring.SendLuaRulesMsg("ceg_preview_sound:" .. s)
                end
                return true
            end

            -- alpha buttons (browser-identical; SoundPanel-scoped)
            local abs = hb and hb.alphaButtons or {}
            for _, ab in ipairs(abs) do
                if mx>=ab.x0 and mx<=ab.x1 and my>=ab.y0 and my<=ab.y1 then
                    if ab.label == "All" then
                        SoundPanelState.letterFilter = nil
                    else
                        SoundPanelState.letterFilter = string.lower(ab.label)
                    end
                    SoundPanelState.pageIndex = 0
                    SoundPanel_RebuildFiltered()
                    return true
                end
            end

            -- search clear
            local sc = hb and hb.searchClear
            if sc and mx>=sc.x0 and mx<=sc.x1 and my>=sc.y0 and my<=sc.y1 then
                SoundPanelState.searchText = ""
                SoundPanelState.pageIndex = 0
                SoundPanel_RebuildFiltered()
                return true
            end

            -- search focus
            local s = hb and hb.search
            if s and mx>=s.x0 and mx<=s.x1 and my>=s.y0 and my<=s.y1 then
                SoundPanelState.searchFocused = true
                Spring.SDLStartTextInput()
                -- unfocus browser search if any
                if searchFocused then Spring.SDLStopTextInput() end
                searchFocused = false
                return true
            else
                if SoundPanelState.searchFocused then Spring.SDLStopTextInput() end
                SoundPanelState.searchFocused = false
            end

            -- pager
            local pprev = hb and hb.pagerPrev
            local pnext = hb and hb.pagerNext
            if pprev and mx>=pprev.x0 and mx<=pprev.x1 and my>=pprev.y0 and my<=pprev.y1 then
                SoundPanelState.pageIndex = math.max(0, SoundPanelState.pageIndex - 1)
                return true
            end
            if pnext and mx>=pnext.x0 and mx<=pnext.x1 and my>=pnext.y0 and my<=pnext.y1 then
                local totalPages = math.max(1, math.floor(((#(SoundPanelState.filteredList or {})) - 1)/SoundPanelState.itemsPerPage) + 1)
                SoundPanelState.pageIndex = math.min(totalPages-1, SoundPanelState.pageIndex + 1)
                return true
            end

            -- row selection: LMB=fire, RMB=impact
            local rows = hb and hb.rows or {}
            for _, r in pairs(rows) do
                if mx>=r.x0 and mx<=r.x1 and my>=r.y0 and my<=r.y1 then
                    if button == 1 then
                        SoundPanelState.selectedFireSound = r.name
                    elseif button == 3 then
                        SoundPanelState.selectedImpactSound = r.name
                    end
                    return true
                end
            end

            -- consume clicks inside panel even if not on a control
            return true
        end
    end

    if MouseInWindow(mx,my) then
        if button ~= 1 and button ~= 2 and button ~= 3 then
            return true
        end

        local tb = hitBoxes.titleButtons or {}
        local close = tb.close
        local icon  = tb.icon

        if close and mx>=close.x0 and mx<=close.x1 and my>=close.y0 and my<=close.y1 then
            widgetHandler:RemoveWidget(self)
            return true
        end
        if icon and mx>=icon.x0 and mx<=icon.x1 and my>=icon.y0 and my<=icon.y1 then
            local topY = winY + winH
            collapsed = not collapsed
            if collapsed then
                prevWinH = winH
                winH = 260
                winY = topY - winH
            else
                if prevWinH then
                    winH = prevWinH
                    winY = topY - winH
                    ClampWindowPosition()
                end
            end
            return true
        end

        local titleH = 30
        if my >= winY+winH-titleH and my <= winY+winH then
            draggingWin = true
            dragOffX = mx-winX
            dragOffY = my-winY
            return true
        end

        local topButtons = hitBoxes.topButtons or {}
        local cheat    = topButtons.cheat
        local glob     = topButtons.glob
        local resetSel = topButtons.resetSel
        -- Aux panel toggles (mutually exclusive)
        local forge  = topButtons.forge
        local sounds = topButtons.sounds

        local function InBox(b)
            return b and mx >= b.x0 and mx <= b.x1 and my >= b.y0 and my <= b.y1
        end

        -- CEG INFO (Forge) toggle
        if InBox(forge) then
            if activeAuxPanel == "info" then
                activeAuxPanel = nil
                if WG.CEGForge and WG.CEGForge.Close then
                    WG.CEGForge.Close()
                end
            else
                -- opening INFO closes SOUNDS
                activeAuxPanel = "info"
                if WG.CEGForge and WG.CEGForge.Open then
                    local srcFile = ResolveCEGSourceFile(lastSelected)
                    WG.CEGForge.Open(lastSelected, srcFile)
                end
            end
            return true
        end

        -- SOUNDS toggle (placeholder)
        if InBox(sounds) then
            if activeAuxPanel == "sound" then
                activeAuxPanel = nil
            else
                -- opening SOUNDS closes INFO
                activeAuxPanel = "sound"
                if WG.CEGForge and WG.CEGForge.Close then
                    WG.CEGForge.Close()
                end
            end
            return true
        end

        if cheat and mx>=cheat.x0 and mx<=cheat.x1 and my>=cheat.y0 and my<=cheat.y1 then
            cheatOn = not cheatOn
            spSendCommands("cheat")
            return true
        end
        if glob and mx>=glob.x0 and mx<=glob.x1 and my>=glob.y0 and my<=glob.y1 then
            globallosOn = not globallosOn
            spSendCommands("globallos")
            return true
        end
        
	if resetSel and mx>=resetSel.x0 and mx<=resetSel.x1 and my>=resetSel.y0 and my<=resetSel.y1 then
    	   -- Clear trail (left-click) selections
    	   selectedCEGs = {}
    	   lastSelected = nil

	    -- Clear impact (right-click) selections
	    selectedImpactCEGs = {}
	    lastImpactSelected = nil

	    -- Clear muzzle (middle-click) selections
	    selectedMuzzleCEGs = {}
	    lastMuzzleSelected = nil

	    spEcho("[CEG Proj Preview] Selection reset.")
	    return true
	end


        local rb = hitBoxes.reloadBtn
	if rb and mx>=rb.x0 and mx<=rb.x1 and my>=rb.y0 and my<=rb.y1 then
    	    -- 1) Force engine to reparse CEG definitions
    	    spSendCommands("reloadcegs")

    	    -- 2) Reload lookup + browser list
    	    LoadAllCEGs()
    	    RebuildFiltered()

    	    spEcho("[CEG Browser] Reloaded CEGs (engine + browser)")
    	    return true
	end

        local tbx = hitBoxes.tuningBtn
        if tbx and mx>=tbx.x0 and mx<=tbx.x1 and my>=tbx.y0 and my<=tbx.y1 then
            settingsMode = "ceg"
            groundArmed = not groundArmed
            fireArmed   = false
            Spring.Echo("[CEG Browser] Ground mode: " .. (groundArmed and "ARMED" or "OFF"))
            return true
        end

        local fb = hitBoxes.fireBtn
	if fb and mx>=fb.x0 and mx<=fb.x1 and my>=fb.y0 and my<=fb.y1 then
    	    settingsMode = "projectile"
    groundArmed = false
    	    fireArmed = not fireArmed
    	    Spring.Echo("[CEG Proj Preview] Fire mode: " .. (fireArmed and "ON" or "OFF"))
    	    return true
	end


        for _,ab in ipairs(hitBoxes.alphaButtons or {}) do
            if mx>=ab.x0 and mx<=ab.x1 and my>=ab.y0 and my<=ab.y1 then
                if ab.label=="All" then
                    letterFilter = nil
                else
                    letterFilter = string.lower(ab.label)
                end
                pageIndex = 0
                RebuildFiltered()
                return true
            end
        end

        local sb = hitBoxes.searchBox
        local sc = hitBoxes.searchClear
        if sc and mx>=sc.x0 and mx<=sc.x1 and my>=sc.y0 and my<=sc.y1 then
            searchText = ""
            RebuildFiltered()
            return true
        end
        if sb and mx>=sb.x0 and mx<=sb.x1 and my>=sb.y0 and my<=sb.y1 then
            searchFocused = true
            Spring.SDLStartTextInput()
            return true
        else
            if searchFocused then Spring.SDLStopTextInput() end
            searchFocused = false
        end

        if collapsed then
            return true
        end

        -- settings panel (mode-based)
if settingsMode == "projectile" then
            local yb = hitBoxes.sliderYaw
            local pb = hitBoxes.sliderPitch
            local sbx= hitBoxes.sliderSpeed

            local gb = hitBoxes.sliderGravity
        local pf = hitBoxes.sliderProjForward
        local pu = hitBoxes.sliderProjUp
        local tt = hitBoxes.sliderTTL
        local ab = hitBoxes.btnAirburst
            if ab and mx>=ab.x0 and mx<=ab.x1 and my>=ab.y0 and my<=ab.y1 then
            airburstOnTTL = not airburstOnTTL
            return true
        end

            if yb and mx>=yb.x0 and mx<=yb.x1 and my>=yb.y0 and my<=yb.y1 then
                draggingSlider = "yaw"
                local t = Clamp((mx - yb.x0)/(yb.x1-yb.x0),0,1)
                                local v = -180 + t*360
                local alt, ctrl = spGetModKeyState()
                if ctrl then v = RoundToStep(v, 1) end
                yawDeg = v
                return true
            end
            if pb and mx>=pb.x0 and mx<=pb.x1 and my>=pb.y0 and my<=pb.y1 then
                draggingSlider = "pitch"
                local t = Clamp((mx - pb.x0)/(pb.x1-pb.x0),0,1)
                                local v = -45 + t*(80+45)
                local alt, ctrl = spGetModKeyState()
                if ctrl then v = RoundToStep(v, 1) end
                pitchDeg = v
                return true
            end
            if sbx and mx>=sbx.x0 and mx<=sbx.x1 and my>=sbx.y0 and my<=sbx.y1 then
                draggingSlider = "speed"
                local t = Clamp((mx - sbx.x0)/(sbx.x1-sbx.x0),0,1)
                                local v = t*600
                local alt, ctrl = spGetModKeyState()
                if ctrl then v = RoundToStep(v, 1) end
                speedVal = v
                return true
            end

    
        if pf and mx>=pf.x0 and mx<=pf.x1 and my>=pf.y0 and my<=pf.y1 then
            draggingSlider = "proj_forward"
            lastMouseX = mx
            lastMouseY = my
            local t = Clamp((mx - pf.x0)/(pf.x1 - pf.x0), 0, 1)
            local v = 0 + t * 100
            local alt, ctrl = spGetModKeyState()
            if ctrl then v = RoundToStep(v, 1) end
            projectileForwardOffset = Clamp(v, 0, 100)
            return true
        end

        if tt and mx>=tt.x0 and mx<=tt.x1 and my>=tt.y0 and my<=tt.y1 then
            draggingSlider = "ttl"
            local t = Clamp((mx - tt.x0)/(tt.x1 - tt.x0), 0, 1)
            local v = 1 + t * (30 - 1)
            local alt, ctrl = spGetModKeyState()
            if ctrl then v = RoundToStep(v, 0.5) end
            ttlSeconds = Clamp(v, 1, 30)
            return true
        end

        if pu and mx>=pu.x0 and mx<=pu.x1 and my>=pu.y0 and my<=pu.y1 then
            draggingSlider = "proj_up"
            lastMouseX = mx
            lastMouseY = my
            local t = Clamp((mx - pu.x0)/(pu.x1 - pu.x0), 0, 1)
            local v = 0 + t * 100
            local alt, ctrl = spGetModKeyState()
            if ctrl then v = RoundToStep(v, 1) end
            projectileUpOffset = Clamp(v, 0, 100)
            return true
        end

        if gb and mx>=gb.x0 and mx<=gb.x1 and my>=gb.y0 and my<=gb.y1 then
                draggingSlider = "gravity"
                local t = Clamp((mx - gb.x0)/(gb.x1-gb.x0),0,1)
                local v = -1.0 + t*2.0
                local alt, ctrl = spGetModKeyState()
                if ctrl then
                    v = RoundToStep(v, 0.01)
                end
                gravityVal = Clamp(v, -1.0, 1.0)
                return true
            end
        end

        for idx,box in pairs(hitBoxes.listCells or {}) do
            local xA, y0r, xB, y1r = box[1], box[2], box[3], box[4]
            if mx>=xA and mx<=xB and my>=y0r and my<=y1r then
                local name = box.name or filteredCEGs[idx]
                if not name then
                    return true
                end
                local alt, ctrl, meta, shift = spGetModKeyState()

                -- MIDDLE CLICK = muzzle (CTRL = multi-select)
                if button == 2 then
                    if ctrl then
                        if selectedMuzzleCEGs[name] then
                            selectedMuzzleCEGs[name] = nil
                            if lastMuzzleSelected == name then lastMuzzleSelected = nil end
                        else
                            selectedMuzzleCEGs[name] = true
                            lastMuzzleSelected = name
                        end
                    else
                        selectedMuzzleCEGs = {}
                        selectedMuzzleCEGs[name] = true
                        lastMuzzleSelected = name
                    end
                    return true
                end

                -- LEFT CLICK = trail
		if button == 1 then
    		    if ctrl then
        	        if selectedCEGs[name] then
            		    selectedCEGs[name] = nil
            		    if lastSelected == name then
                		lastSelected = nil

                -- 🔔 Notify Forge: selection cleared
                if WG.CEGForge and WG.CEGForge.SetSource then
                    WG.CEGForge.SetSource(nil, nil)
                end
            end
        else
            selectedCEGs[name] = true
            lastSelected = name

            -- 🔔 Notify Forge: new primary selection
            if WG.CEGForge and WG.CEGForge.SetSource then
                local srcFile = ResolveCEGSourceFile(lastSelected)
		WG.CEGForge.SetSource(lastSelected, srcFile)
            end
        end
    else
        selectedCEGs = {}
        selectedCEGs[name] = true
        lastSelected = name

        -- 🔔 Notify Forge: new primary selection
        if WG.CEGForge and WG.CEGForge.SetSource then
            local srcFile = ResolveCEGSourceFile(lastSelected)
	    WG.CEGForge.SetSource(lastSelected, srcFile)
        end
    end
    return true
end

                -- RIGHT CLICK = impact
                if button == 3 then
                    if ctrl then
                        if selectedImpactCEGs[name] then
                            selectedImpactCEGs[name] = nil
                            if lastImpactSelected == name then lastImpactSelected = nil end
                        else
                            selectedImpactCEGs[name] = true
                            lastImpactSelected = name
                        end
                    else
                        selectedImpactCEGs = {}
                        selectedImpactCEGs[name] = true
                        lastImpactSelected = name
                    end
                    return true
                end
            end
        end

        local pr = hitBoxes.pagerPrev
        local ne = hitBoxes.pagerNext
        if pr and mx>=pr.x0 and mx<=pr.x1 and my>=pr.y0 and my<=pr.y1 then
            pageIndex = math.max(0,pageIndex-1)
            return true
        end
        if ne and mx>=ne.x0 and mx<=ne.x1 and my>=ne.y0 and my<=ne.y1 then
            local maxPage = math.max(0, math.floor((#filteredCEGs - 1) / ItemsPerPage()))
            if pageIndex < maxPage then pageIndex = pageIndex + 1 end
            return true
        end


        -- CEG Browser panel interaction (merged)
            if settingsMode == "ceg" then
                for _,pb in ipairs(hitBoxes.patternBtns or {}) do
                    if mx>=pb.x0 and mx<=pb.x1 and my>=pb.y0 and my<=pb.y1 then
                        cegPattern = pb.name
                        return true
                    end
                end
                local scb = hitBoxes.sliderCount
                if scb and mx>=scb.x0 and mx<=scb.x1 and my>=scb.y0 and my<=scb.y1 then
                    draggingSlider = "ceg_count"
                    lastMouseX = mx
                    lastMouseY = my
                    local t = Clamp((mx - scb.x0)/(scb.x1-scb.x0),0,1)
                    local v = 1 + t * (100 - 1)
                    cegSpawnCountF = Clamp(v, 1, 100)
                    cegSpawnCount  = Clamp(math.floor(cegSpawnCountF + 0.5), 1, 100)
                    return true
                end

                local shb = hitBoxes.sliderHeight
                if shb and mx>=shb.x0 and mx<=shb.x1 and my>=shb.y0 and my<=shb.y1 then
                    draggingSlider = "ceg_height"
                    lastMouseX = mx
                    lastMouseY = my
                    local t = Clamp((mx - shb.x0)/(shb.x1-shb.x0),0,1)
                    cegHeightOffset = Clamp(math.floor(t*800+0.5),0,800)
                    return true
                end
        local ssb = hitBoxes.sliderSpace
                if ssb and mx>=ssb.x0 and mx<=ssb.x1 and my>=ssb.y0 and my<=ssb.y1 then
                    draggingSlider = "ceg_spacing"
                    lastMouseX = mx
                    lastMouseY = my
                    local t = Clamp((mx - ssb.x0)/(ssb.x1-ssb.x0),0,1)
                    cegSpacingF = Clamp(t * 128, 0, 128)
                    cegSpacing  = Clamp(math.floor(cegSpacingF + 0.5), 0, 128)
                    return true
                end
            end
        return true
    end

    if button == 1 then
        searchFocused = false

        if settingsMode == "projectile" and fireArmed and not MouseInWindow(mx, my) then
            FireSelectedProjectiles()
            return false
        end

        if settingsMode == "ceg" and groundArmed and not MouseInWindow(mx, my) then
            SpawnGroundCEGs()
            return false
        end
    end

    return false
end


function widget:MouseMove(mx, my, dx, dy, button)
    if draggingWin then
        winX = mx - dragOffX
        winY = my - dragOffY
        ClampWindowPosition()
        return true
    end

    -- Projectile sliders
    if draggingSlider and settingsMode == "projectile" then
        local alt, ctrl = spGetModKeyState()

        if draggingSlider == "yaw" and hitBoxes.sliderYaw then
            if ctrl then
                yawDeg = Clamp(yawDeg + dx * 0.25, -180, 180)
            else
                local b = hitBoxes.sliderYaw
                local t = Clamp((mx - b.x0)/(b.x1-b.x0),0,1)
                yawDeg = -180 + t*360
            end
            return true

        elseif draggingSlider == "pitch" and hitBoxes.sliderPitch then
            if ctrl then
                pitchDeg = Clamp(pitchDeg + dx * 0.25, -45, 80)
            else
                local b = hitBoxes.sliderPitch
                local t = Clamp((mx - b.x0)/(b.x1-b.x0),0,1)
                pitchDeg = -45 + t*(80+45)
            end
            return true

        
            elseif draggingSlider == "speed" then
                if ctrl then
                    speedVal = Clamp(
                        speedVal + dx * 0.4,
                        0, 600
                    )
                else
                    local b = hitBoxes.sliderSpeed
                    if b then
                        local t = Clamp((mx - b.x0)/(b.x1 - b.x0), 0, 1)
                        speedVal = 0 + t * (600)
                    end
                end
                lastMouseX = mx
                lastMouseY = my
                return true



        
            
            elseif draggingSlider == "proj_forward" then
                if ctrl then
                    projectileForwardOffset = Clamp(
                        projectileForwardOffset + dx * 0.15,
                        0, 100
                    )
                else
                    local b = hitBoxes.sliderProjForward
                    if b then
                        local t = Clamp((mx - b.x0)/(b.x1 - b.x0), 0, 1)
                        projectileForwardOffset = 0 + t * (100)
                    end
                end
                lastMouseX = mx
                lastMouseY = my
                return true



        
            
            elseif draggingSlider == "ttl" then
                if ctrl then
                    ttlSeconds = Clamp(ttlSeconds + dx * 0.05, 1, 30)
                else
                    local b = hitBoxes.sliderTTL
                    if b then
                        local t = Clamp((mx - b.x0)/(b.x1 - b.x0), 0, 1)
                        ttlSeconds = 1 + t * (30 - 1)
                    end
                end
                lastMouseX = mx
                lastMouseY = my
                return true

            elseif draggingSlider == "proj_up" then
                if ctrl then
                    projectileUpOffset = Clamp(
                        projectileUpOffset + dx * 0.15,
                        0, 100
                    )
                else
                    local b = hitBoxes.sliderProjUp
                    if b then
                        local t = Clamp((mx - b.x0)/(b.x1 - b.x0), 0, 1)
                        projectileUpOffset = 0 + t * (100)
                    end
                end
                lastMouseX = mx
                lastMouseY = my
                return true


        
            
            elseif draggingSlider == "gravity" then
                if ctrl then
                    gravityVal = Clamp(
                        gravityVal + dx * 0.005,
                        -1.0, 1.0
                    )
                else
                    local b = hitBoxes.sliderGravity
                    if b then
                        local t = Clamp((mx - b.x0)/(b.x1 - b.x0), 0, 1)
                        gravityVal = -1.0 + t * (2.0)
                    end
                end
                lastMouseX = mx
                lastMouseY = my
                return true


        end
    end


    -- Ground (CEG) sliders
    if draggingSlider and settingsMode == "ceg" then
        local alt, ctrl = spGetModKeyState()

        -- Spawn Count (silky CTRL fine drag, consistent with other sliders)
        if draggingSlider == "ceg_count" then
            if ctrl then
                local ddx = mx - (lastMouseX or mx)
                cegSpawnCountF = Clamp((cegSpawnCountF or cegSpawnCount) + ddx * 0.10, 1, 100)
                cegSpawnCount  = Clamp(math.floor(cegSpawnCountF + 0.5), 1, 100)
                lastMouseX = mx
                lastMouseY = my
                return true
            else
                local b = hitBoxes.sliderCount
                if b then
                    local t = Clamp((mx - b.x0)/(b.x1-b.x0), 0, 1)
                    cegSpawnCountF = Clamp(1 + t * (100 - 1), 1, 100)
                    cegSpawnCount  = Clamp(math.floor(cegSpawnCountF + 0.5), 1, 100)
                    lastMouseX = mx
                    lastMouseY = my
                end
                return true
            end
        end

        -- Spacing (fixed hitbox name + unified float accumulator)
        if draggingSlider == "ceg_spacing" then
            if ctrl then
                local ddx = mx - (lastMouseX or mx)
                cegSpacingF = Clamp((cegSpacingF or cegSpacing) + ddx * 0.25, 0, 128)
                cegSpacing  = Clamp(math.floor(cegSpacingF + 0.5), 0, 128)
                lastMouseX = mx
                lastMouseY = my
                return true
            else
                local b = hitBoxes.sliderSpace
                if b then
                    local t = Clamp((mx - b.x0)/(b.x1-b.x0), 0, 1)
                    cegSpacingF = Clamp(t * 128, 0, 128)
                    cegSpacing  = Clamp(math.floor(cegSpacingF + 0.5), 0, 128)
                    lastMouseX = mx
                    lastMouseY = my
                end
                return true
            end
        end

        -- Height Offset (leave existing feel; CTRL fine relative adjustment)
        if draggingSlider == "ceg_height" then
            if ctrl then
                cegHeightOffset = Clamp(math.floor(cegHeightOffset + dx * 1.00 + 0.5), 0, 800)
                return true
            else
                local b = hitBoxes.sliderHeight
                if b then
                    local t = Clamp((mx - b.x0)/(b.x1-b.x0), 0, 1)
                    cegHeightOffset = Clamp(math.floor(t * 800 + 0.5), 0, 800)
                end
                return true
            end
        end
    end

    return MouseInWindow(mx,my)
end





--------------------------------------------------------------------------------
-- Mouse wheel (delegated to Forge panel when open/hovered)
--------------------------------------------------------------------------------
function widget:MouseWheel(up, value)
    if WG.CEGForge and WG.CEGForge.MouseWheel then
        if WG.CEGForge.MouseWheel(up, value) then
            return true
        end
    end
    return false
end

function widget:MouseRelease(mx, my, button)
    -- Always release drag state on mouse up (prevents stuck sliders)
    draggingWin    = false
    draggingSlider = nil
    return MouseInWindow(mx,my)
end


--------------------------------------------------------------------------------
-- Keyboard / search text input
--------------------------------------------------------------------------------

function widget:KeyPress(key, mods, isRepeat)
    if key == string.byte("x") and mods.alt and not mods.ctrl and not mods.shift then
        widgetHandler:RemoveWidget(self)
        return true
    end


    -- Sound panel search (isolated)
    if activeAuxPanel == "sound" and SoundPanelState.searchFocused then
        if key == 8 then -- backspace
            if #SoundPanelState.searchText > 0 then
                SoundPanelState.searchText = SoundPanelState.searchText:sub(1, #SoundPanelState.searchText - 1)
                SoundPanel_RebuildFiltered()
            end
            return true
        end
        if key == 13 then -- enter
            return true
        end
        if key == 27 then -- esc
            SoundPanelState.searchFocused = false
            Spring.SDLStopTextInput()
            return true
        end
    end

    if searchFocused then
        if key == 8 then -- backspace
            if #searchText > 0 then
                searchText = searchText:sub(1, #searchText - 1)
                RebuildFiltered()
            end
            return true
        end
        if key == 13 then -- enter
            searchFocused = false
            Spring.SDLStopTextInput()
            return true
        end
        if key == 27 then -- esc
            searchFocused = false
            Spring.SDLStopTextInput()
            return true
        end
        return true
    end
    return false
end

function widget:TextInput(ch)
    if activeAuxPanel == "sound" and SoundPanelState.searchFocused then
        if not ch or ch == "" then return true end
        if ch < " " then return true end
        SoundPanelState.searchText = (SoundPanelState.searchText or "") .. ch
        SoundPanel_RebuildFiltered()
        return true
    end

    if not searchFocused then
        return false
    end
    if not ch or ch == "" then
        return true
    end
    if ch < " " then
        return true
    end
    searchText = searchText .. ch
    RebuildFiltered()
    return true
end


--------------------------------------------------------------------------------
-- FORGE MODULE (Embedded CEG Info Panel)
--------------------------------------------------------------------------------
do
--------------------------------------------------------------------------------
-- CEG Forge
-- Companion panel for the CEG Browser
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Engine refs
--------------------------------------------------------------------------------

local spGetViewGeometry = Spring.GetViewGeometry
local glColor          = gl.Color
local glRect           = gl.Rect
local glText           = gl.Text

--------------------------------------------------------------------------------
-- Text wrapping helpers (Forge-only, UI-safe)
--------------------------------------------------------------------------------
local function WordWrap(text, maxWidth, fontSize)
    local lines = {}
    local spaceW = gl.GetTextWidth(" ") * fontSize

    for paragraph in tostring(text or ""):gmatch("[^\n]+") do
        local line = ""
        local lineW = 0

        for word in paragraph:gmatch("%S+") do
            local wordW = gl.GetTextWidth(word) * fontSize

            -- Clamp absurdly long tokens (e.g. colormap strings with no sensible breaks)
            if wordW > maxWidth then
                local ratio = maxWidth / math.max(1, wordW)
                local cut = math.max(1, math.floor(#word * ratio))
                word = word:sub(1, cut) .. "…"
                wordW = gl.GetTextWidth(word) * fontSize
            end

            if line == "" then
                line = word
                lineW = wordW
            elseif lineW + spaceW + wordW <= maxWidth then
                line = line .. " " .. word
                lineW = lineW + spaceW + wordW
            else
                lines[#lines + 1] = line
                line = word
                lineW = wordW
            end

        end

        if line ~= "" then
            lines[#lines + 1] = line
        end
    end

    return lines
end

local function DrawWrappedText(text, x, y, maxWidth, fontSize, lineH)
    lineH = lineH or (fontSize + 2)
    local lines = WordWrap(text, maxWidth, fontSize)
    local cy = y
    for i = 1, #lines do
        gl.Text(lines[i], x, cy, fontSize, "o")
        cy = cy - lineH
    end
    return y - math.max(0, (#lines - 1)) * lineH, #lines
end

local glLineWidth      = gl.LineWidth
local glBeginEnd       = gl.BeginEnd
local glVertex         = gl.Vertex

local GL = GL

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------

local theme = {
    window = {
        bg        = {0.03, 0.03, 0.03, 0.92},
        border    = {0.10, 0.10, 0.10, 1.00},
        titleBg   = {0.00, 0.00, 0.00, 0.55},
        titleText = {1.00, 1.00, 1.00, 1.00},
    },
    tree = {
        key     = {0.85, 0.85, 0.85, 1.00},
        value   = {0.70, 0.80, 1.00, 1.00},
        table   = {0.60, 0.60, 0.60, 1.00},
        indent  = 14,
    },
    fontSize = {
        title  = 18,
        normal = 14,
        small  = 14,
    },
}

local PADDING = 10
local CORNER_WINDOW_RADIUS = 6
local LINE_H = 14

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local forgeOpen  = false
local scrollY    = 0
local maxScrollY = 0
local forgeCloseBtn = nil

local sourceName = nil
local sourceDef  = nil
local sourceFile = nil

local forgeX, forgeY, forgeW, forgeH
forgeW = 420

--------------------------------------------------------------------------------
-- WG API
--------------------------------------------------------------------------------

WG.CEGForge = WG.CEGForge or {}
--------------------------------------------------------------------------------
-- Deep copy helper
--------------------------------------------------------------------------------

local function DeepCopy(src)
    if type(src) ~= "table" then
        return src
    end
    local dst = {}
    for k, v in pairs(src) do
        dst[k] = DeepCopy(v)
    end
    return dst
end

--------------------------------------------------------------------------------
-- Definition finder (handles wrapper / nested effect files)
--------------------------------------------------------------------------------

local function FindDefRecursive(root, targetName, maxDepth)
    if type(root) ~= "table" then
        return nil
    end
    maxDepth = maxDepth or 5
    local seen = {}

    local function walk(t, depth)
        if type(t) ~= "table" then return nil end
        if seen[t] then return nil end
        seen[t] = true
        if depth > maxDepth then return nil end

        local v = rawget(t, targetName)
        if type(v) == "table" then
            return v
        end

        for _, vv in pairs(t) do
            if type(vv) == "table" then
                local found = walk(vv, depth + 1)
                if found then return found end
            end
        end
        return nil
    end

    return walk(root, 0)
end

--------------------------------------------------------------------------------
-- Internal clone logic (file-driven, no lookup)
--------------------------------------------------------------------------------

local function CloneCEG(name, file)
    sourceName = name
    sourceDef  = nil
    sourceFile = file

    if not name or not file then return end

    local ok, defs = pcall(VFS.Include, file)
    if not ok or type(defs) ~= "table" then return end

    local def = defs[name]
    if type(def) ~= "table" then
        def = FindDefRecursive(defs, name, 6)
    end
    if type(def) ~= "table" then return end

    sourceDef = DeepCopy(def)
end

--------------------------------------------------------------------------------
-- Open / Close / Update
--------------------------------------------------------------------------------

function WG.CEGForge.Open(name, file)
    forgeOpen = true
    CloneCEG(name, file)
end

function WG.CEGForge.SetSource(name, file)
    if not forgeOpen then return end
    CloneCEG(name, file)
end

function WG.CEGForge.Close()
    forgeOpen  = false
    sourceName = nil
    sourceDef  = nil
    sourceFile = nil
end

function WG.CEGForge.IsOpen()
    return forgeOpen
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Snap(v)
    return math.floor(v + 0.5)
end

--------------------------------------------------------------------------------
-- Rounded rect helpers
--------------------------------------------------------------------------------

local function DrawRoundedRectFilled(x0, y0, x1, y1, r)
    x0, y0, x1, y1 = Snap(x0), Snap(y0), Snap(x1), Snap(y1)
    r = math.max(0, math.min(r, math.min((x1-x0)/2, (y1-y0)/2)))

    glRect(x0 + r, y0,     x1 - r, y1)
    glRect(x0,     y0 + r, x1,     y1 - r)

    local steps = 8
    local function corner(cx, cy, a0, a1)
        glBeginEnd(GL.TRIANGLE_FAN, function()
            glVertex(cx, cy)
            for i = 0, steps do
                local a = a0 + (a1 - a0) * (i / steps)
                glVertex(cx + math.cos(a)*r, cy + math.sin(a)*r)
            end
        end)
    end

    corner(x0+r, y0+r, math.pi, 1.5*math.pi)
    corner(x1-r, y0+r, 1.5*math.pi, 2*math.pi)
    corner(x1-r, y1-r, 0, 0.5*math.pi)
    corner(x0+r, y1-r, 0.5*math.pi, math.pi)
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function UpdateLayout()
    local vsx, vsy = spGetViewGeometry()

    if WG.CEGBrowser and WG.CEGBrowser.GetPanelRect then
        local bx0, by0, bx1, by1 = WG.CEGBrowser.GetPanelRect()
        if bx0 then
            forgeX = bx0 - forgeW - 8
            forgeY = by0
            forgeH = by1 - by0
            return
        end
    end

    forgeX = 10
    forgeY = 100
    forgeH = vsy - 200
end

--------------------------------------------------------------------------------
-- Tree rendering (read-only)
--------------------------------------------------------------------------------

local function DrawValue(val, x, y, maxWidth)
    if type(val) == "table" then
        glColor(theme.tree.table)
        glText("{ }", x, y, theme.fontSize.small, "o")
        return y, 1
    end

    glColor(theme.tree.value)
    local s = tostring(val)

    -- Wrap only when we have a sane width budget
    if maxWidth and maxWidth > 20 then
        local newY, nLines = DrawWrappedText(s, x, y, maxWidth, theme.fontSize.small, LINE_H)
        return newY, nLines
    else
        glText(s, x, y, theme.fontSize.small, "o")
        return y, 1
    end
end

local function DrawTable(tbl, x, y, depth)
    local startY = y
    for k, v in pairs(tbl) do
        local indent = depth * theme.tree.indent
        glColor(theme.tree.key)
        glText(tostring(k) .. ":", x + indent, y, theme.fontSize.small, "o")

        local keyText = tostring(k) .. ":"
	local keyW = gl.GetTextWidth(keyText) * theme.fontSize.small
	local valueX = x + indent + keyW + 8
        local maxW = (forgeX + forgeW - PADDING) - valueX

        if type(v) == "table" then
            DrawValue(v, valueX, y, maxW)
            y = DrawTable(v, x, y - LINE_H, depth + 1)
        else
            local newY = select(1, DrawValue(v, valueX, y, maxW))
            y = newY - LINE_H
        end
    end
    return y, (startY - y)
end

--------------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------------

function WG.CEGForge.Draw()
if not forgeOpen then return end

    UpdateLayout()

    local x0, y0 = forgeX, forgeY
    local x1, y1 = forgeX + forgeW, forgeY + forgeH

    glColor(theme.window.bg)
    DrawRoundedRectFilled(x0, y0, x1, y1, CORNER_WINDOW_RADIUS)

    glColor(theme.window.border)
    DrawRoundedRectFilled(x0, y0, x1, y1, CORNER_WINDOW_RADIUS)

    local titleH = 28
    glColor(theme.window.titleBg)
    glRect(x0 + CORNER_WINDOW_RADIUS, y1 - titleH, x1 - CORNER_WINDOW_RADIUS, y1)

    glColor(theme.window.titleText)
    glText("CEG Information", x0 + PADDING, y1 - titleH + 7, theme.fontSize.title, "o")

    -- Close button (browser-style red X)
    local btnW, btnH = 22, 18
    local btnPad = 6

    forgeCloseBtn = {
        x0 = x1 - btnPad - btnW,
        y0 = y1 - titleH + (titleH - btnH) / 2,
        x1 = x1 - btnPad,
        y1 = y1 - titleH + (titleH - btnH) / 2 + btnH,
    }

    glColor(0.40, 0.10, 0.10, 1.00)
    DrawRoundedRectFilled(
        forgeCloseBtn.x0,
        forgeCloseBtn.y0,
        forgeCloseBtn.x1,
        forgeCloseBtn.y1,
        4
    )

    glColor(0.20, 0.02, 0.02, 1.00)
    glRect(
        forgeCloseBtn.x0,
        forgeCloseBtn.y0,
        forgeCloseBtn.x1,
        forgeCloseBtn.y1
    )

    glColor(1, 1, 1, 1)
    glText(
        "x",
        forgeCloseBtn.x0 + 7,
        forgeCloseBtn.y0 + 2,
        theme.fontSize.normal,
        "o"
    )

    local cy = y1 - titleH - 20
    glColor(0.9, 0.9, 0.9, 1)
    glText("CEG Definition is located in this file:", x0 + PADDING, cy, theme.fontSize.normal, "o")

    cy = cy - 18
    if sourceFile then
        glColor(0.7, 0.8, 1.0, 1)
        glText(sourceFile, x0 + PADDING, cy, theme.fontSize.small, "o")
    else
        glColor(0.6, 0.6, 0.6, 1)
        glText("(no source)", x0 + PADDING, cy, theme.fontSize.small, "o")
    end

    cy = cy - 24
    
    if sourceDef then
        -- Top of scrollable content (just under header text)
        local contentTop = cy + 5
	local textTopPadding = 10

        -- Bottom of scrollable content (inside window padding)
        local contentBottom = forgeY + PADDING

        -- Visible height of scroll area
        local viewHeight = contentTop - contentBottom

        -- Draw clipped, scrolled content
        gl.Scissor(
            math.floor(forgeX),
            math.floor(contentBottom),
            math.floor(forgeW),
            math.floor(viewHeight)
        )

        gl.PushMatrix()
	gl.Translate(0, scrollY, 0)

	local endY, contentHeight =
    	   DrawTable(sourceDef, x0 + PADDING, contentTop - textTopPadding, 0)

	gl.PopMatrix()

	-- Restore full viewport scissor
	local vsx, vsy = spGetViewGeometry()
	gl.Scissor(0, 0, vsx, vsy)

	-- Clamp scroll (positive space, canonical)
	contentHeight = contentHeight or 0
	local maxScroll = math.max(0, contentHeight - viewHeight)
	maxScrollY = maxScroll

	scrollY = math.max(0, math.min(maxScroll, scrollY))

    else

        glColor(0.6, 0.6, 0.6, 1)
        glText("Select a CEG in the browser to load definition.", x0 + PADDING, cy, theme.fontSize.small, "o")
    end
end

--------------------------------------------------------------------------------
-- Mouse wheel scrolling (Forge definition panel only)
--------------------------------------------------------------------------------

function WG.CEGForge.MouseWheel(up, value)
if not forgeOpen then
        return false
    end

    local mx, my = Spring.GetMouseState()
    if mx < forgeX or mx > forgeX + forgeW
    or my < forgeY or my > forgeY + forgeH then
        return false
    end

    local _, ctrl = Spring.GetModKeyState()
    local step = LINE_H * (ctrl and 3 or 1)

    if up then
        scrollY = scrollY - step
    else
        scrollY = scrollY + step
    end

    scrollY = math.max(0, math.min(maxScrollY, scrollY))
    return true
end


--------------------------------------------------------------------------------
-- Mouse input (Forge close button)
--------------------------------------------------------------------------------

function WG.CEGForge.MousePress(mx, my, button)
if forgeOpen and button == 1 and forgeCloseBtn then
        if mx >= forgeCloseBtn.x0 and mx <= forgeCloseBtn.x1
        and my >= forgeCloseBtn.y0 and my <= forgeCloseBtn.y1 then
            WG.CEGForge.Close()
            return true
        end
    end
    return false
end
end