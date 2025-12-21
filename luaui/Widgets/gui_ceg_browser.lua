--------------------------------------------------------------------------------
-- CEG Browser
-- LuaUI Widget for Beyond All Reason made by Steel
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
--       - Optional impact CEGs can be assigned per projectile
--       - Direction, pitch, speed, and gravity are adjustable in real time
--
--     GROUND mode:
--       - Spawns selected CEGs directly on the ground under the mouse cursor
--       - Supports line, ring, and scatter spawn patterns
--       - Spawn count, spacing, and height offset are adjustable
--
-- Usage highlights:
--   - Left-click on a CEG: select as Trail
--   - Right-click on a CEG: select as Impact (PROJECTILE mode only)
--     * Right-click has no effect in GROUND mode
--   - CTRL + click: multi-select
--   - CTRL + drag on sliders: fine adjustment (reduced slider sensitivity)
--   - ALT + hover on CEG list: show full CEG name tooltip
--   - Search and alphabet filters allow fast navigation of large CEG sets
--
-- File dependencies:
--   This widget is UI-only and relies on the following runtime components:
--
--   LuaRules/ceg_lookup.lua
--     - Provides the authoritative list of available CEG names
--     - Must expose GetAllNames()
--
--   LuaRules/Gadgets/game_ceg_preview.lua
--     - Synced gadget that receives messages from this widget
--     - Responsible for spawning test projectiles and ground CEGs
--     - Handles projectile physics, impact dispatch, and cleanup
--
--   units/other/ceg_test_projectile.lua
--     - Helper unit used for projectile-based CEG previews
--     - Defines a lightweight weapon used to emit test projectiles
--     - Never selectable, controllable, or persistent
--     - Exists only to carry projectile and impact CEGs during preview
--
-- Notes:
--   - This widget does NOT modify units, weapons, or CEG definitions
--   - All effects are preview-only and safe to use in live games
--   - Designed to remain layout- and behavior-stable as a tooling baseline
--
--------------------------------------------------------------------------------



function widget:GetInfo()
    return {
        name    = "CEG Browser",
        desc    = "In-game browser and preview tool for Core Effect Generators (CEGs)",
        author  = "Steel",
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

    local fs = theme.fontSize.normal
    local textW = glGetTextWidth(label) * fs
    local tx = x0 + (x1 - x0 - textW) * 0.5
    local ty = y0 + (y1 - y0 - fs) * 0.5 + 1

    glColor(t.text[1], t.text[2], t.text[3], t.text[4])
    glText(label, Snap(tx), Snap(ty), fs, "o")
end

--------------------------------------------------------------------------------
-- Fire mode
local fireArmed = false
--------------------------------------------------------------------------------

local CFG_WIN_X = "ceg_proj_preview_lua_win_x"
local CFG_WIN_Y = "ceg_proj_preview_lua_win_y"

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


local altHoverCEG = nil  -- ALT-hover tooltip state (from baseline)
local letterFilter  = nil
local searchText    = ""
local searchFocused = false

-- Projectile tuning
local yawDeg   = 0     -- -180..180
local pitchDeg = 20    -- -45..80
local speedVal = 220   -- 0..600

local gravityVal = 0.16 -- -1.00..+1.00 (default = baseline)
local tuningVisible = true -- deprecated
local settingsMode = "projectile"

-- -----------------------------------------------------------------
-- CEG Browser settings (merged)
-- -----------------------------------------------------------------
local cegPattern    = "line"  -- "line" | "ring" | "scatter"
local cegSpawnCount = 1       -- 1..100
local cegSpacing    = 20      -- 0..128
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

    -- Keep only selections still visible (trail + impact)
local newSel = {}
local newImp = {}
for _, n in ipairs(filteredCEGs) do
    if selectedCEGs[n] then
        newSel[n] = true
    end
    if selectedImpactCEGs[n] then
        newImp[n] = true
    end
end
selectedCEGs = newSel
selectedImpactCEGs = newImp


    local maxPage = math.max(0, math.floor((#filteredCEGs - 1) / ItemsPerPage()))
    pageIndex = Clamp(pageIndex, 0, maxPage)
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
        spSendLuaRulesMsg(
            "cegtest:"
            .. names[1]
            .. ":" .. x
            .. ":" .. z
            .. ":" .. (cegSpawnCount or 1)
            .. ":" .. (cegSpacing or 0)
            .. ":" .. (cegPattern or "line")
            .. ":" .. height
        )
    else
        -- MULTI (new): cegtest_multi:name1,name2,...:x:z:count:spacing:pattern:height
        spSendLuaRulesMsg(
            "cegtest_multi:"
            .. table.concat(names, ",")
            .. ":" .. x
            .. ":" .. z
            .. ":" .. (cegSpawnCount or 1)
            .. ":" .. (cegSpacing or 0)
            .. ":" .. (cegPattern or "line")
            .. ":" .. height
        )
    end
end
-- synced gadget listens for this


GetSelectedList = function()
    local list = {}
    for i = 1, #filteredCEGs do
        local n = filteredCEGs[i]
        if selectedCEGs[n] then
            list[#list+1] = n
        end
    end
    -- If none selected but we have a lastSelected, use that
    if #list == 0 and lastSelected then
        list[1] = lastSelected
    end
    return list
end

local function GetImpactSelectedList()
    local list = {}
    for i = 1, #filteredCEGs do
        local n = filteredCEGs[i]
        if selectedImpactCEGs[n] then
            list[#list+1] = n
        end
    end
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

    local msg = string.format(
        "%s%s|%s:%d:%d:%d:%d:%d:%.2f",
        PREFIX,
        cegName,
        impactStr or "",
        wx, wz, yd, pd, sp, gravityVal
    )
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
    winH = 900

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
    glText("CEG Projectile Preview", x0 + PADDING_OUTER, y1 - titleH + 8, theme.fontSize.title, "o")

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
    DrawButton(c2x0, row2Y0, c2x1, row2Y1, "GROUND", settingsMode == "ceg", false, theme.fontSize.button)

    hitBoxes.reloadBtn = {id="reload", x0=c1x0,y0=row2Y0,x1=c1x1,y1=row2Y1}
    hitBoxes.tuningBtn = {id="tuning", x0=c2x0,y0=row2Y0,x1=c2x1,y1=row2Y1}

    -- Row 3
    DrawButton(c1x0, row3Y0, c1x1, row3Y1, "Reset", false, false, theme.fontSize.button)
    DrawButton(
        c2x0, row3Y0, c2x1, row3Y1,
        fireArmed and "ARMED" or "PROJECTILE",
        settingsMode == "projectile",
        false,
        theme.fontSize.button
    )
    hitBoxes.topButtons.resetSel = {id="resetSel", x0=c1x0,y0=row3Y0,x1=c1x1,y1=row3Y1}
    hitBoxes.fireBtn             = {id="fire",     x0=c2x0,y0=row3Y0,x1=c2x1,y1=row3Y1}

    local cmdBottom   = row3Y0
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
        --  projectile tuning panel: 164
        --  CEG browser tuning panel: 110
        local panelH = (settingsMode == "projectile") and 164 or 130
        local tpY0 = tpY1 - panelH
        local listTop

        if settingsMode == "projectile" then

            glColor(theme.tuningPanel.bg[1], theme.tuningPanel.bg[2], theme.tuningPanel.bg[3], theme.tuningPanel.bg[4])
            DrawRoundedRectFilled(tpX0, tpY0, tpX1, tpY1, CORNER_WINDOW_RADIUS)
            glColor(theme.tuningPanel.border[1], theme.tuningPanel.border[2], theme.tuningPanel.border[3], theme.tuningPanel.border[4])
            DrawRoundedRectBorder(tpX0, tpY0, tpX1, tpY1, CORNER_WINDOW_RADIUS, 1)

            glColor(theme.tuningPanel.text[1], theme.tuningPanel.text[2], theme.tuningPanel.text[3], theme.tuningPanel.text[4])
            glText("Projectile Tuning", Snap(tpX0 + 10), Snap(tpY1 - 22), theme.fontSize.normal, "o")

            local labelX  = tpX0 + 10
            local LABEL_COL_W = 150
            local sliderW = 220

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

            local row1Y = tpY1 - 48
            glText(string.format("Direction: %d°", math.floor(yawDeg)), Snap(labelX), Snap(row1Y+10), theme.fontSize.normal, "o")
            hitBoxes.sliderYaw = drawSlider(labelX + LABEL_COL_W, row1Y + 12, yawDeg, -180, 180)

            local row2Y = row1Y - 34
            glText(string.format("Pitch: %d°", math.floor(pitchDeg)), Snap(labelX), Snap(row2Y+10), theme.fontSize.normal, "o")
            hitBoxes.sliderPitch = drawSlider(labelX + LABEL_COL_W, row2Y + 12, pitchDeg, -45, 80)

            local row3Y = row2Y - 34
            glText(string.format("Speed: %d", math.floor(speedVal)), Snap(labelX), Snap(row3Y+10), theme.fontSize.normal, "o")
            hitBoxes.sliderSpeed = drawSlider(labelX + LABEL_COL_W, row3Y + 12, speedVal, 0, 600)


            local row4Y = row3Y - 34
            glText(string.format("Gravity: %.2f", gravityVal), Snap(labelX), Snap(row4Y+10), theme.fontSize.normal, "o")
            hitBoxes.sliderGravity = drawSlider(labelX + LABEL_COL_W, row4Y + 12, gravityVal, -1.0, 1.0)

            glColor(theme.text.dim[1], theme.text.dim[2], theme.text.dim[3], theme.text.dim[4])
            -- Selection legend

    	----------------------------------------------------------------
    	-- Selection legend
    	----------------------------------------------------------------
    	local legendY = row4Y - 18
    	local legendX = tpX0 + 12
    	local fs = theme.fontSize.normal

    	-- Trail (left click)
    	glColor(theme.list.rowBgSel[1], theme.list.rowBgSel[2], theme.list.rowBgSel[3], 1)
    	glRect(Snap(legendX), Snap(legendY), Snap(legendX+10), Snap(legendY+10))
    	glColor(1,1,1,1)
    	glText("Trail (LMB)", Snap(legendX+16), Snap(legendY-1), fs, "o")

    	-- Impact (right click)
    	local ix = legendX + 110
    	glColor(theme.list.rowBgSelImpact[1], theme.list.rowBgSelImpact[2], theme.list.rowBgSelImpact[3], 1)
    	glRect(Snap(ix), Snap(legendY), Snap(ix+10), Snap(legendY+10))
    	glColor(1,1,1,1)
    	glText("Impact (RMB)", Snap(ix+16), Snap(legendY-1), fs, "o")

    	-- Multi-select hint (to the right)
    	local impactLabel = "Impact (RMB)"
    	local ctrlFs = fs - 1
    	local ctrlX = ix + 16 + (glGetTextWidth(impactLabel) * fs) + 14

    	glColor(theme.text.dim[1], theme.text.dim[2], theme.text.dim[3], 1)
    	glText("+ CTRL = Multi-Select", Snap(ctrlX), Snap(legendY-1), ctrlFs, "o")

            listTop = tpY0 - 10
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
            local fs = theme.fontSize.normal
            glColor(theme.text.dim[1], theme.text.dim[2], theme.text.dim[3], 1)
            glText("+ CTRL = multi-select", Snap(legendX), Snap(legendY), fs-1, "o")
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

            local bg
            if isTrail then
                bg = theme.list.rowBgSel
            elseif isImpact then
                bg = theme.list.rowBgSelImpact
            else
                bg = theme.list.rowBg
            end
            glColor(bg[1],bg[2],bg[3],bg[4])
            glRect(Snap(xCell0), Snap(y0r), Snap(xCell1), Snap(y1r))

            glColor(theme.list.border[1], theme.list.border[2], theme.list.border[3], theme.list.border[4])
            glRect(Snap(xCell0), Snap(y0r), Snap(xCell1), Snap(y0r+1))

            local txtCol = (isTrail or isImpact) and theme.list.rowTextSel or theme.list.rowText
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
                        name     = name,
                        isTrail  = isTrail,
                        isImpact = isImpact,
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
end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

function widget:MousePress(mx, my, button)
    if MouseInWindow(mx,my) then
        if button ~= 1 and button ~= 3 then
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
            fireArmed = false
    	    return true
	end

        local fb = hitBoxes.fireBtn
	if fb and mx>=fb.x0 and mx<=fb.x1 and my>=fb.y0 and my<=fb.y1 then
    	    settingsMode = "projectile"
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
            return true
        else
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
                -- LEFT CLICK = trail
                if button == 1 then
                    if ctrl then
                        if selectedCEGs[name] then
                            selectedCEGs[name] = nil
                            if lastSelected == name then lastSelected = nil end
                        else
                            selectedCEGs[name] = true
                            lastSelected = name
                        end
                    else
                        selectedCEGs = {}
                        selectedCEGs[name] = true
                        lastSelected = name
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
                    local t = Clamp((mx - scb.x0)/(scb.x1-scb.x0),0,1)
                    cegSpawnCount = Clamp(math.floor(t*100+0.5),1,100)
                    return true
                end

                local shb = hitBoxes.sliderHeight
                if shb and mx>=shb.x0 and mx<=shb.x1 and my>=shb.y0 and my<=shb.y1 then
                    draggingSlider = "ceg_height"
                    local t = Clamp((mx - shb.x0)/(shb.x1-shb.x0),0,1)
                    cegHeightOffset = Clamp(math.floor(t*800+0.5),0,800)
                    return true
                end
        local ssb = hitBoxes.sliderSpace
                if ssb and mx>=ssb.x0 and mx<=ssb.x1 and my>=ssb.y0 and my<=ssb.y1 then
                    draggingSlider = "ceg_spacing"
                    local t = Clamp((mx - ssb.x0)/(ssb.x1-ssb.x0),0,1)
                    cegSpacing = Clamp(math.floor(t*128+0.5),0,128)
                    return true
                end
            end
        return true
    end

    if button == 1 then
        searchFocused = false

        if settingsMode == "projectile" and fireArmed and not MouseInWindow(mx, my) then
            FireSelectedProjectiles()
            return true
        end

        if settingsMode == "ceg" and not MouseInWindow(mx, my) then
            SpawnGroundCEGs()
            return true
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

        elseif draggingSlider == "speed" and hitBoxes.sliderSpeed then
            if ctrl then
                speedVal = Clamp(speedVal + dx * 0.6, 0, 600)
            else
                local b = hitBoxes.sliderSpeed
                local t = Clamp((mx - b.x0)/(b.x1-b.x0),0,1)
                speedVal = t*600
            end
            return true

        elseif draggingSlider == "gravity" and hitBoxes.sliderGravity then
            if ctrl then
                gravityVal = Clamp(
                    RoundToStep(gravityVal + dx * 0.002, 0.01),
                    -1.0, 1.0
                )
            else
                local b = hitBoxes.sliderGravity
                local t = Clamp((mx - b.x0)/(b.x1-b.x0),0,1)
                gravityVal = -1.0 + t*2.0
            end
            return true
        end
    end

    -- Ground (CEG) sliders
    if draggingSlider and settingsMode == "ceg" then
        local alt, ctrl = spGetModKeyState()

        -- CTRL = fine relative adjustment
        if ctrl then
            if draggingSlider == "ceg_count" then
                cegSpawnCount = Clamp(math.floor(cegSpawnCount + dx * 0.20 + 0.5), 1, 100)
                return true
            elseif draggingSlider == "ceg_spacing" then
                cegSpacing = Clamp(math.floor(cegSpacing + dx * 0.20 + 0.5), 0, 128)
                return true
            elseif draggingSlider == "ceg_height" then
                cegHeightOffset = Clamp(math.floor(cegHeightOffset + dx * 1.00 + 0.5), 0, 800)
                return true
            end
        end

        -- Normal drag = absolute follow
        if draggingSlider == "ceg_count" and hitBoxes.sliderCount then
            local b = hitBoxes.sliderCount
            local t = Clamp((mx - b.x0)/(b.x1-b.x0),0,1)
            local v = 1 + t*(100-1)
            cegSpawnCount = Clamp(math.floor(v + 0.5), 1, 100)
            return true

        elseif draggingSlider == "ceg_spacing" and hitBoxes.sliderSpace then
            local b = hitBoxes.sliderSpace
            local t = Clamp((mx - b.x0)/(b.x1-b.x0),0,1)
            local v = t*128
            cegSpacing = Clamp(math.floor(v + 0.5), 0, 128)
            return true

        elseif draggingSlider == "ceg_height" and hitBoxes.sliderHeight then
            local b = hitBoxes.sliderHeight
            local t = Clamp((mx - b.x0)/(b.x1-b.x0),0,1)
            local v = t*800
            cegHeightOffset = Clamp(math.floor(v + 0.5), 0, 800)
            return true
        end
    end

    return MouseInWindow(mx,my)
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

    if searchFocused then
        if key == 8 then -- backspace
            if #searchText > 0 then
                searchText = searchText:sub(1, #searchText - 1)
                RebuildFiltered()
            end
            return true
        end
        if key == 13 then -- enter
            return true
        end
        return true
    end
    return false
end

function widget:TextInput(ch)
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