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
local fmt, sqrt, huge, floor = string.format, math.sqrt, math.huge, math.floor

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
    if OXP.WalkGraph then OXP.WalkGraph.Reset() end
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

-- Distance from (px, py) to the segment a-b, and the nearest point on it.
local function SegDist(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local f = 0
    if len2 > 0 then
        f = ((px - ax) * dx + (py - ay) * dy) / len2
        if f < 0 then f = 0 elseif f > 1 then f = 1 end
    end
    local cx, cy = ax + f * dx, ay + f * dy
    return sqrt((px - cx) ^ 2 + (py - cy) ^ 2), cx, cy
end

-- Of `legs`, the one passing nearest (px, py): leg, segment, distance and
-- the nearest point on it (world).
local function Nearest(legs, px, py, inst)
    local best, bestSeg, bestD, bx, by = nil, nil, huge, nil, nil
    for _, leg in ipairs(legs or {}) do
        local c = Corners(leg)
        if c and c.instance == inst then
            for i = 1, #c.wx - 1 do
                local d, cx, cy = SegDist(px, py, c.wx[i], c.wy[i], c.wx[i + 1], c.wy[i + 1])
                if d < bestD then best, bestSeg, bestD, bx, by = c, i, d, cx, cy end
            end
        end
    end
    return best, bestSeg, bestD, bx, by
end

-- A walk worked out on SoupNav's zone graph (Nav/WalkGraph.lua) from the
-- player to `target`, as a leg like the baked ones; kept while you stay on
-- it, worked out again (at most once a second) when you leave it.
local GRAPH_AGAIN = 1
local graphLeg = { key = nil, leg = nil, at = -huge }

local function FlatLeg(map, pts, key)
    local flat = {}
    for _, p in ipairs(pts) do
        flat[#flat + 1], flat[#flat + 2], flat[#flat + 3], flat[#flat + 4] = p[1], p[2], 0, 0
    end
    if #flat < 8 then return nil end
    return { map = map, key = key, flat = flat, graph = true }
end

local function GraphLeg(target, key, px, py, inst)
    if not (nav and nav.packed and OXP.WalkGraph) then return nil end
    local cached = graphLeg.key == key and graphLeg.leg
    if cached then
        local _, _, d = Nearest({ cached }, px, py, inst)
        if d <= NEAR then return cached end
    end
    local now = GetTime and GetTime() or 0
    if graphLeg.key == key and now - graphLeg.at < GRAPH_AGAIN then return cached or nil end
    graphLeg.key, graphLeg.at, graphLeg.leg = key, now, nil
    local zx, zy = Places.ToZone(px, py, target.map)
    if not zx then return nil end
    local pts = OXP.WalkGraph.Route(nav, target.map, zx, zy, target.x, target.y)
    graphLeg.leg = pts and FlatLeg(target.map, pts, "graph>" .. key) or nil
    return graphLeg.leg
end

-- The walk to `target` passing nearest (px, py): SoupEngine's baked walks
-- first; when none is baked to the spot or you're more than NEAR yards off
-- them, one worked out on SoupNav's graph from where you stand. Returns the
-- leg, the index of the next corner ahead on it, the distance to the walk
-- and the nearest point on it (world); nil when there's no walk at all.
local function Ahead(target, px, py, inst)
    if not (target and target.map and target.x and target.y and px) then return nil end
    local key = SpotKey(target.map, target.x, target.y)
    local best, bestSeg, bestD, bx, by = Nearest(byEnd[key], px, py, inst)
    if not best or bestD > NEAR then
        local gl = GraphLeg(target, key, px, py, inst)
        if gl then
            local b2, s2, d2, x2, y2 = Nearest({ gl }, px, py, inst)
            if b2 and d2 < bestD then best, bestSeg, bestD, bx, by = b2, s2, d2, x2, y2 end
        end
    end
    if not best then return nil end
    local n = #best.wx
    local j = bestSeg + 1
    while j < n and Places.Distance(px, py, best.wx[j], best.wy[j]) <= REACH do j = j + 1 end
    return best, j, bestD, bx, by
end

--- Where the arrow should point on the baked walk to `target` for a player
--- at px, py: wx, wy. Off the walk (more than NEAR yards): the nearest point
--- on it, to lead you back. On it: the next corner ahead. nil when nothing is
--- baked to the spot, or the spot itself is next.
function WP.NextCorner(target, px, py, inst)
    local best, j, d, bx, by = Ahead(target, px, py, inst)
    if not best then return nil end
    local n = #best.wx
    if d > NEAR then
        if Places.Distance(bx, by, best.wx[n], best.wy[n]) <= REACH then return nil end
        return bx, by
    end
    if j >= n then return nil end -- the last corner is the spot: the arrow's own target
    return best.wx[j], best.wy[j]
end

--- For the map's route line: the points (map %, on target.map) from a
--- player at world px, py along the baked walk to `target`, ending on the
--- spot: first the nearest point on the walk when you're off it. nil when
--- nothing is baked to the spot.
function WP.RouteFrom(target, px, py, inst)
    local best, j, d, bx, by = Ahead(target, px, py, inst)
    if not best then return nil end
    local out, flat = {}, best.flat
    if d > REACH then
        local x, y = Places.ToZone(bx, by, target.map)
        if x then out[1] = { x, y } end
    end
    for k = j, #best.wx do out[#out + 1] = { flat[k * 4 - 3], flat[k * 4 - 2] } end
    return out
end

--- The corners (map %) of the baked walk from one guide spot to the next on
--- `map`, ending on b; nil when SoupEngine baked none.
local between = {}   -- graph walks between spots, worked out once: [key] = pts or false

function WP.Between(map, ax, ay, bx, by)
    if not nav then return nil end
    local key = SpotKey(map, ax, ay) .. ">" .. SpotKey(map, bx, by)
    local flat = nav.paths[key]
    local out = {}
    if flat then
        for i = 5, #flat - 3, 4 do out[#out + 1] = { flat[i], flat[i + 1] } end
        return out
    end
    -- not baked: SoupNav's graph (Nav/WalkGraph.lua)
    if between[key] == nil then
        local pts = OXP.WalkGraph and nav.packed and OXP.WalkGraph.Route(nav, map, ax, ay, bx, by)
        between[key] = pts or false
    end
    local pts = between[key]
    if not pts then return nil end
    for i = 2, #pts do out[#out + 1] = pts[i] end
    return out
end

local proxy = {}
local lastTarget, lastCheck, lastX, lastY, lastTX, lastTY = nil, -huge, nil, nil, nil, nil

function WP.Reset()
    graphLeg.key, graphLeg.leg, graphLeg.at = nil, nil, -huge
    between = {}
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

--- /oxp nav: is OpenXP_Nav loaded, and is there a baked walk to the arrow's spot?
function WP.Command()
    if not nav then
        OXP.Print("OpenXP_Nav isn't loaded: no SoupEngine walks. Check it's enabled in the AddOns list, then restart the game.")
        return
    end
    OXP.Print(("OpenXP_Nav loaded: %d SoupEngine walks."):format(WP.legs or 0))
    local real = OXP.Target.Real and OXP.Target.Real()
    if not (real and real.x) then OXP.Print("No guide spot to walk to right now.") return end
    local px, py, inst = Places.Player()
    local best, _, d = Ahead(real, px, py, inst)
    local key = SpotKey(real.map, real.x, real.y)
    if not best then
        OXP.Print(("No walk to this step's spot (%s): nothing baked and no graph way from here."):format(key))
    else
        OXP.Print(("Walk to this step's spot (%s): %s; you're %d yards from it%s."):format(key,
            best.graph and "worked out on SoupNav's zone graph" or "SoupEngine's baked walk", floor(d + 0.5),
            d > NEAR and " (the arrow leads you back onto it)" or ""))
    end
end
OXP.AddCommand("nav", "SoupEngine walks: loaded? one to this step?", function() WP.Command() end)

OXP.OnReady(function() WP.Load() end)
