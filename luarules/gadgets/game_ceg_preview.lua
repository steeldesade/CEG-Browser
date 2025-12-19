--------------------------------------------------------------------------------
-- CEG Preview (Synced Gadget) written by Steel
--
-- Overview:
--   This gadget provides the synced execution layer for the CEG Browser UI.
--   It receives preview commands from LuaUI widgets and safely spawns Core
--   Effect Generator (CEG) effects in-game for visual inspection.
--
--   Two preview systems are implemented:
--
--     Ground CEG Tester:
--       - Spawns one or more CEGs directly on the ground
--       - Supports line, ring, and scatter patterns
--       - Handles multi-selection, spacing, count, and height offset
--
--     Projectile CEG Preview:
--       - Spawns an invisible helper unit to emit test projectiles
--       - Attaches selected CEGs as projectile trails
--       - Supports optional impact CEGs on ground collision
--       - Handles yaw, pitch, speed, gravity, and cleanup timing
--
-- Message protocol:
--   This gadget listens for the following LuaRules messages (protocol-stable):
--
--     cegtest:        Single ground CEG spawn
--     cegtest_multi:  Multiple ground CEG spawn
--     cegproj:        Projectile-based CEG preview
--
-- Dependencies:
--   - units/other/ceg_test_projectile.lua
--       Invisible helper unit used for projectile previews.
--       Carries a lightweight weapon definition for ballistic testing.
--
-- Notes:
--   - This gadget does NOT modify CEG definitions or gameplay units.
--   - All spawned units and effects are temporary and cleaned up automatically.
--   - Intended for developer and artist tooling only.
--
--------------------------------------------------------------------------------


function gadget:GetInfo()
    return {
        name    = "CEG Preview",
        desc    = "Synced execution for ground and projectile CEG preview",
        author  = "Steel",
        enabled = true,
        layer   = 0,
    }
end

--------------------------------------------------------------------------------
-- SYNCED ONLY
--------------------------------------------------------------------------------
if not gadgetHandler:IsSyncedCode() then
    return
end

--------------------------------------------------------------------------------
-- Engine refs
--------------------------------------------------------------------------------
local spSpawnCEG        = Spring.SpawnCEG
local spGetGroundHeight = Spring.GetGroundHeight
local spEcho            = Spring.Echo

local spCreateUnit         = Spring.CreateUnit
local spDestroyUnit        = Spring.DestroyUnit
local spGiveOrderToUnit    = Spring.GiveOrderToUnit
local spValidUnitID        = Spring.ValidUnitID
local spSetUnitWeaponState = Spring.SetUnitWeaponState
local spGetGameFrame       = Spring.GetGameFrame
local spSetUnitRulesParam  = Spring.SetUnitRulesParam

--------------------------------------------------------------------------------
-- Math
--------------------------------------------------------------------------------
local math   = math
local cos    = math.cos
local sin    = math.sin
local sqrt   = math.sqrt
local pi     = math.pi
local random = math.random

--------------------------------------------------------------------------------
-- Message prefixes (UNCHANGED)
--------------------------------------------------------------------------------
local PREFIX_SINGLE = "cegtest:"
local PREFIX_MULTI  = "cegtest_multi:"
local PREFIX_PROJ   = "cegproj:"

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 1: GROUND CEG TESTER (from game_ceg_tester.lua)
-- ============================================================================
--------------------------------------------------------------------------------

local function SpawnCEG(name, x, z, height)
    if not name or name == "" then return end
    x = tonumber(x)
    z = tonumber(z)
    if not x or not z then
        spEcho("[CEG Tester] ERROR: bad coordinates")
        return
    end

    height = tonumber(height) or 0
    local y = (spGetGroundHeight(x, z) or 0) + height
    spSpawnCEG(name, x, y, z, 0, 1, 0, 0, 0)
end

local function SpawnCEGSet(names, x, z, height)
    if type(names) ~= "table" then return end
    for i = 1, #names do
        SpawnCEG(names[i], x, z, height)
    end
end

local function SpawnPattern(names, x, z, count, spacing, pat, height)
    count   = math.max(1, math.min(100, count or 1))
    spacing = math.max(0, spacing or 0)
    pat     = (pat == "ring" or pat == "scatter") and pat or "line"

    if pat == "line" then
        for i = 0, count - 1 do
            SpawnCEGSet(names, x + i * spacing, z, height)
        end

    elseif pat == "ring" then
        local radius = spacing * 5
        for i = 0, count - 1 do
            local a = (2 * pi * i) / count
            SpawnCEGSet(names,
                x + radius * cos(a),
                z + radius * sin(a),
                height
            )
        end

    elseif pat == "scatter" then
        local radius = spacing * 3
        for i = 1, count do
            local r = radius * sqrt(random())
            local a = 2 * pi * random()
            SpawnCEGSet(names,
                x + r * cos(a),
                z + r * sin(a),
                height
            )
        end
    end
end

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 2: PROJECTILE CEG PREVIEW (from game_ceg_projectile_preview.lua)
-- ============================================================================
--------------------------------------------------------------------------------

local TEST_UNIT_NAME    = "ceg_test_projectile_unit"
local TEST_WEAPON_INDEX = 1

local SPAWN_LIFT        = 12
local CLEANUP_FRAMES    = 30 * 10

local TRAIL_EVERY_FRAMES = 1
local MAX_TRAIL_FRAMES   = 30 * 6

local DEFAULT_GRAVITY = 0.16

local cleanupQueue = {}
local trails = {}
local trailSeq = 0

local function DegToRad(d) return d * pi / 180 end
local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function FireCEGTestProjectile(ceg, impactBlock, x, z, yawDeg, pitchDeg, speed, gravity)
    x = tonumber(x)
    z = tonumber(z)
    if not x or not z then return end

    local impactCEGs = {}
    if impactBlock and impactBlock ~= "" then
        for n in impactBlock:gmatch("([^,]+)") do
            impactCEGs[#impactCEGs+1] = n
        end
    end

    yawDeg   = Clamp(tonumber(yawDeg)   or 0, -180, 180)
    pitchDeg = Clamp(tonumber(pitchDeg) or 0,  -89,  89)
    speed    = Clamp(tonumber(speed)    or 0,    0, 5000)
    gravity  = tonumber(gravity) or DEFAULT_GRAVITY

    local y = (spGetGroundHeight(x, z) or 0) + SPAWN_LIFT

    local yaw   = DegToRad(yawDeg)
    local pitch = DegToRad(pitchDeg)

    local dx = cos(pitch) * cos(yaw)
    local dy = sin(pitch)
    local dz = cos(pitch) * sin(yaw)

    local unitID = spCreateUnit(
        TEST_UNIT_NAME,
        x, y, z,
        0,
        Spring.GetGaiaTeamID()
    )
    if not unitID then return end

    spSetUnitRulesParam(unitID, "no_autofire", 1)
    spGiveOrderToUnit(unitID, CMD.STOP, {}, {})

    -- VISUAL AIM (baseline-correct: applied AFTER STOP)
    Spring.SetUnitDirection(unitID, dx, 0, dz)

    spSetUnitWeaponState(unitID, TEST_WEAPON_INDEX, {
        weaponVelocity = speed,
    })

    local dist = math.max(256, speed * 2)
    spGiveOrderToUnit(unitID, CMD.ATTACK, {
        x + dx * dist,
        y + dy * dist,
        z + dz * dist
    }, {})

    cleanupQueue[unitID] = spGetGameFrame() + CLEANUP_FRAMES

    trailSeq = trailSeq + 1
    trails[trailSeq] = {
        ceg   = ceg,
        impactCEGs = impactCEGs,
        gravity = gravity,
        x     = x,
        y     = y,
        z     = z,
        vx    = dx * speed,
        vy    = dy * speed,
        vz    = dz * speed,
        nextF = spGetGameFrame(),
        endF  = spGetGameFrame() + MAX_TRAIL_FRAMES,
    }
end

function gadget:GameFrame(f)
    for unitID, deathFrame in pairs(cleanupQueue) do
        if f >= deathFrame then
            if spValidUnitID(unitID) then
                spDestroyUnit(unitID, false, true)
            end
            cleanupQueue[unitID] = nil
        end
    end

    for id, t in pairs(trails) do
        if f >= t.endF then
            trails[id] = nil
        else
            if f >= t.nextF then
                spSpawnCEG(t.ceg, t.x, t.y, t.z, t.vx, t.vy, t.vz)
                t.nextF = f + TRAIL_EVERY_FRAMES
            end

            t.x = t.x + t.vx
            t.y = t.y + t.vy
            t.z = t.z + t.vz
            t.vy = t.vy - t.gravity

            local gy = spGetGroundHeight(t.x, t.z) or 0
            if t.y <= gy then
                if t.impactCEGs then
                    for i = 1, #t.impactCEGs do
                        spSpawnCEG(t.impactCEGs[i], t.x, gy, t.z, 0, 1, 0)
                    end
                end
                trails[id] = nil
            end
        end
    end
end

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 3: MESSAGE ROUTER (unchanged protocol)
-- ============================================================================
--------------------------------------------------------------------------------

function gadget:RecvLuaMsg(msg, playerID)

    -- PROJECTILE
    if msg:sub(1, #PREFIX_PROJ) == PREFIX_PROJ then
        local body = msg:sub(#PREFIX_PROJ + 1)
        local cegBlock, xs, zs, yaw, pitch, speed, gravity =
            body:match("^([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)$")
        if not cegBlock then return end

        local trailCEG, impactBlock = cegBlock:match("^([^|]+)|?(.*)$")
        if not trailCEG then return end

        FireCEGTestProjectile(trailCEG, impactBlock, xs, zs, yaw, pitch, speed, gravity)
        return
    end

    -- GROUND
    local isMulti = false
    local body

    if msg:sub(1, #PREFIX_MULTI) == PREFIX_MULTI then
        isMulti = true
        body    = msg:sub(#PREFIX_MULTI + 1)
    elseif msg:sub(1, #PREFIX_SINGLE) == PREFIX_SINGLE then
        body = msg:sub(#PREFIX_SINGLE + 1)
    else
        return
    end

    local nameField, xs, zs, cs, ss, pat, hs =
        body:match("^([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):?(.*)$")
    if not nameField then
        spEcho("[CEG Tester] ERROR: bad message: " .. tostring(msg))
        return
    end

    local names = {}
    if isMulti then
        for n in nameField:gmatch("([^,]+)") do
            names[#names+1] = n
        end
    else
        names[1] = nameField
    end

    SpawnPattern(
        names,
        tonumber(xs),
        tonumber(zs),
        tonumber(cs) or 1,
        tonumber(ss) or 0,
        pat,
        tonumber(hs) or 0
    )
end
