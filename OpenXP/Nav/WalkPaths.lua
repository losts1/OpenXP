-- Baked walking paths from the optional OpenXP_Nav add-on.
--
-- SoupEngine walks every leg of the guide route on SoupNav's walking map
-- ahead of time and writes the corners of each walk into OpenXP_Nav
-- (a separate, load-on-demand add-on folder next to OpenXP). When it is
-- installed, the arrow points at the next corner of the baked walk to the
-- guide's spot instead of straight at the spot, the same way it follows
-- path hints (Nav/PathHints.lua). Without it nothing changes.
--
-- OpenXP_Nav's data (see docs/2.0/SOUPENGINE.md):
--   paths["map:x,y>map:x,y"] = { x1, y1, z1, indoor1, x2, ... }  one walk, map %
--   spots["map:x,y"]         = { z, indoor }                     a guide spot's floor
--   packed[map]              = SoupNav's packed zone graph (not used yet)
-- Keys have two decimals, like the guide's own goto x and y.
local _, OXP = ...

local WP = {}
OXP.WalkPaths = WP

local Places = OXP.Places
local fmt, sqrt, huge = string.format, math.sqrt, math.huge

local NEAR = 40       -- yards: further than this from every baked walk, the arrow doesn't use them
local REACH = 8       -- yards: a corner this close is passed
local THROTTLE = 0.2  -- seconds between corner updates

local nav             -- OpenXP_Nav's table, once loaded
local byEnd = {}      -- ["map:x,y"] = { leg, ... }; leg = { map = n, key = s, flat = {...} }
local tried = false

local function SpotKey(map, x, y)
    return fmt("%d:%.2f,%.2f", map, x, y)
end
WP.SpotKey = SpotKey

local function Index(data)
    byEnd = {}
    local legs = 0
    for key, flat in pairs(data.paths) do
        local to = key:match(">(.+)$")
        local map = to and tonumber(to:match("^(%d+):"))
        if map and type(flat) == "table" and #flat >= 8 then
            local list = byEnd[to]
            if not list then
                list = {}
                byEnd[to] = list
            end
            list[#list + 1] = { map = map, key = key, flat = flat }
            legs = legs + 1
        end
    end
    WP.legs = legs
end

--- Use this OpenXP_Nav table (tests hand one in; nil turns paths off).
function WP.Use(data)
    if type(data) == "table" and type(data.paths) == "table" then
        nav = data
        Index(data)
    else
        nav, byEnd, WP.legs = nil, {}, 0
    end
    WP.Reset()
end

--- Load OpenXP_Nav if it is installed and enabled. Returns its table or nil.
function WP.Load()
    if nav or tried then return nav end
    tried = true
    local data = rawget(_G, "OpenXP_Nav")
    if not data then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or rawget(_G, "LoadAddOn")
        if load then pcall(load, "OpenXP_Nav") end
        data = rawget(_G, "OpenXP_Nav")
    end
    WP.Use(data)
    return nav
end

function WP.IsLoaded() return nav ~= nil end

--- A guide spot's floor from OpenXP_Nav: z (yards), indoor (true/false); nil if unknown.
function WP.Floor(map, x, y)
    local s = nav and nav.spots and nav.spots[SpotKey(map, x, y)]
    if s then return s[1], s[2] == 1 end
end

-- The leg's corners in world coordinates (worked out once per leg).
local function Corners(leg)
    if leg.wx then return leg end
    local wx, wy, inst = {}, {}, nil
    local flat = leg.flat
    for i = 1, #flat - 3, 4 do
        local x, y, ins = Places.ToWorld(leg.map, flat[i], flat[i + 1])
        if not x then return nil end
        wx[#wx + 1], wy[#wy + 1], inst = x, y, ins
    end
    leg.wx, leg.wy, leg.instance = wx, wy, inst
    return leg
end

-- Distance from (px, py) to the segment a-b, and how far along it (0-1).
local function SegDist(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local f = 0
    if len2 > 0 then
        f = ((px - ax) * dx + (py - ay) * dy) / len2
        if f < 0 then f = 0 elseif f > 1 then f = 1 end
    end
    local cx, cy = ax + f * dx, ay + f * dy
    return sqrt((px - cx) ^ 2 + (py - cy) ^ 2), f
end

--- The next corner on the baked walk to `target` for a player at px, py:
--- wx, wy (or nil when there is no baked walk near the player, or the spot
--- itself is next).
function WP.NextCorner(target, px, py, inst)
    if not (target and target.map and target.x and target.y and px) then return nil end
    local legs = byEnd[SpotKey(target.map, target.x, target.y)]
    if not legs then return nil end
    local best, bestSeg, bestD = nil, nil, huge
    for _, leg in ipairs(legs) do
        local c = Corners(leg)
        if c and c.instance == inst then
            for i = 1, #c.wx - 1 do
                local d = SegDist(px, py, c.wx[i], c.wy[i], c.wx[i + 1], c.wy[i + 1])
                if d < bestD then best, bestSeg, bestD = c, i, d end
            end
        end
    end
    if not best or bestD > NEAR then return nil end
    local n = #best.wx
    local j = bestSeg + 1
    while j < n and Places.Distance(px, py, best.wx[j], best.wy[j]) <= REACH do j = j + 1 end
    if j >= n then return nil end   -- the last corner is the spot: the arrow's own target
    return best.wx[j], best.wy[j]
end

local proxy = {}
local lastTarget, lastCheck, lastX, lastY, lastTX, lastTY = nil, -huge, nil, nil, nil, nil

function WP.Reset()
    lastTarget, lastCheck, lastX, lastY, lastTX, lastTY = nil, -huge, nil, nil, nil, nil
end

--- A stepping stone for the arrow toward `target` ({wx, wy, instance, map,
--- x, y, title}), or nil.
function WP.ForArrow(target)
    if not nav or not target or target == proxy then return nil end
    local now = GetTime and GetTime() or 0
    if target ~= lastTarget or target.x ~= lastTX or target.y ~= lastTY or now - lastCheck >= THROTTLE then
        lastTarget, lastCheck, lastTX, lastTY = target, now, target.x, target.y
        local px, py, inst = Places.Player()
        lastX, lastY = WP.NextCorner(target, px, py, inst)
    end
    if not lastX then return nil end
    proxy.wx, proxy.wy, proxy.instance, proxy.map = lastX, lastY, target.instance, target.map
    proxy.title, proxy.real, proxy.walkPath = target.title, target, true
    return proxy
end

OXP.OnReady(function() WP.Load() end)
