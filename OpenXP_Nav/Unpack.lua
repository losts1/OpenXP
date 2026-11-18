-- Unpacks a zone's walking graph packed by SoupNav (soupnav/pack.py).
-- As an addon file (listed in OpenXP_Nav's TOC before the zone graph files) it sets
-- NAV.Unpack on the addon's namespace and creates NAV.packed (zone graphs by uiMap) and
-- NAV.packedInstance (dungeon graphs by instance map id), which the zone files fill.
-- Loaded any other way (dofile, a test) it just returns Unpack.
-- Returns { n = count, x = {}, y = {}, z = {}, indoor = {}, links = {[a] = {b, secs, b, secs, ...}},
--           starts = {[cell*2 + indoor] = {node, ...}}, grid = nil or {x0, y0, size, cols} }
-- with 1-based node indexes. Zone cells are row*100+col of the zone map (in %); dungeon
-- cells (grid set) are row*cols+col of a world grid starting at x0, y0.
-- world yards and seconds of running at 7 yd/s.
local RUN = 7.0
local ALPHA = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"
local VAL = {}
for i = 1, #ALPHA do VAL[ALPHA:byte(i)] = i - 1 end

local function Unpack(s)
    local pos = 1
    local byte = string.byte
    local function u()
        local n, mul = 0, 1
        while true do
            local v = VAL[byte(s, pos)]
            pos = pos + 1
            if v < 32 then return n + v * mul end
            n = n + (v - 32) * mul
            mul = mul * 32
        end
    end
    local function sv()
        local n = u()
        if n % 2 == 0 then return n / 2 end
        return -(n + 1) / 2
    end
    local g = { x = {}, y = {}, z = {}, indoor = {}, links = {}, starts = {} }
    local n = u()
    g.n = n
    local bx, by, bz = sv(), sv(), sv()
    if u() == 1 then        -- a dungeon: start cells on a world grid
        g.grid = { x0 = sv() / 2, y0 = sv() / 2, size = u(), cols = u() }
    end
    local px, py = bx, by
    for i = 1, n do
        px, py = px + sv(), py + sv()
        local zi = u()
        g.x[i], g.y[i] = px / 2, py / 2
        g.z[i] = (math.floor(zi / 2) + bz) / 2
        g.indoor[i] = zi % 2 == 1
        g.links[i] = {}
    end
    local sqrt = math.sqrt
    for a = 1, n do
        local prev = a
        for _ = 1, u() do
            local b = prev + 1 + u()
            local extra = u() / 2
            local dx, dy = g.x[a] - g.x[b], g.y[a] - g.y[b]
            local secs = sqrt(dx * dx + dy * dy) / RUN + extra
            local la, lb = g.links[a], g.links[b]
            la[#la + 1], la[#la + 2] = b, secs
            lb[#lb + 1], lb[#lb + 2] = a, secs
            prev = b
        end
    end
    local cell = 0
    for _ = 1, u() do
        cell = cell + u()
        local ind = u()
        local list = {}
        for k = 1, u() do list[k] = u() + 1 end
        g.starts[cell * 2 + ind] = list
    end
    return g
end

local _, NAV = ...
if type(NAV) == "table" then
    NAV.packed = NAV.packed or {}
    NAV.packedInstance = NAV.packedInstance or {}
    NAV.Unpack = Unpack
end

return Unpack   -- for dofile and tests; ignored when the game loads the file
