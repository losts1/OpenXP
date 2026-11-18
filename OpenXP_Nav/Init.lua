-- OpenXP_Nav: walking data for OpenXP, made by SoupEngine (paths, floors) and SoupNav
-- (packed zone graphs). Generated: do not edit.
local _, NAV = ...
NAV.packed = NAV.packed or {}                 -- [uiMap] = packed zone graph (Graphs/*.lua)
NAV.packedInstance = NAV.packedInstance or {} -- [instance map id] = packed dungeon graph
NAV.paths = NAV.paths or {}                   -- ["map:x,y>map:x,y"] = {x, y, z, indoor, ...}
NAV.spots = NAV.spots or {}                   -- ["map:x,y"] = {z, indoor}
OpenXP_Nav = NAV                                  -- OpenXP finds it here after LoadAddOn("OpenXP_Nav")
