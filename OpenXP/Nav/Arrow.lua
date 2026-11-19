-- The arrow: a pointer in a round dial with the distance in large text and
-- what to do there under it, turning into a green check on arrival.
local ADDON, OXP = ...

local Arrow = {}
OXP.Arrow = Arrow

local Places = OXP.Places
local HBD = Places.HBD
local L = OXP.L

local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Card\\"
local ARRIVED = 8      -- yards: "Here"
local TICK = 0.05      -- seconds between redraws while shown
local GREEN = { 61 / 255, 187 / 255, 122 / 255 }
local BLUE = { 90 / 255, 184 / 255, 1 }

local f = CreateFrame("Button", "OpenXPArrow", UIParent)
Arrow.frame = f
f:SetSize(80, 80)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:Hide()

f.dial = f:CreateTexture(nil, "BACKGROUND")
f.dial:SetTexture(TEX .. "dialdisc")
f.dial:SetPoint("CENTER")
f.dial:SetVertexColor(16 / 255, 17 / 255, 21 / 255, 0.85)
f.ring = f:CreateTexture(nil, "BORDER")
f.ring:SetTexture(TEX .. "dialring")
f.ring:SetPoint("CENTER")
f.pointer = f:CreateTexture(nil, "ARTWORK")
f.pointer:SetTexture(TEX .. "pointer")
f.pointer:SetPoint("CENTER")
f.check = f:CreateTexture(nil, "OVERLAY")
f.check:SetTexture(TEX .. "check")
f.check:SetPoint("CENTER")
f.check:SetVertexColor(GREEN[1], GREEN[2], GREEN[3])
f.check:Hide()
f.dist = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
f.dist:SetPoint("TOP", f.dial, "BOTTOM", 0, -6)
f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
f.label:SetPoint("TOP", f.dist, "BOTTOM", 0, -3)
f.label:SetTextColor(0.72, 0.74, 0.8)

local sized
local function ApplySizes()
    local s = OXP.settings
    local scale, text = s.arrowScale or 1, s.arrowText or 12
    local font, flags = OXP.Fonts.Path(), OXP.Fonts.Flags("OUTLINE")
    local key = scale .. ":" .. text .. ":" .. font .. ":" .. flags
    if sized == key then return end
    sized = key
    f.dial:SetSize(76 * scale, 76 * scale)
    f.ring:SetSize(76 * scale, 76 * scale)
    f.check:SetSize(36 * scale, 36 * scale)
    f.pointer:SetSize(44 * scale, 44 * scale)
    f:SetSize(80 * scale, 80 * scale)
    OXP.Fonts.Apply(f.dist, font, text + 5, flags)
    OXP.Fonts.Apply(f.label, font, text, flags)
end
Arrow.ApplySizes = function() sized = nil; ApplySizes() end

f:SetScript("OnDragStart", function(self)
    if OXP.settings.lockFrames then return end
    self:StartMoving()
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    OXP.settings.arrowPos = { point, rel, x, y }
end)
f:SetScript("OnEnter", function(self)
    local t = OXP.Target.Current()
    if not t then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(t.title or L("Next stop"), 1, 1, 1, 1, true)
    if t.real and t.real ~= t and t.real.title then
        GameTooltip:AddLine(L("On the way to: ") .. t.real.title, 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine(L("Drag to move. /oxp arrow hides or shows it."), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
f:SetScript("OnLeave", function() GameTooltip:Hide() end)

--- Angle (radians, like GetPlayerFacing) and yards from the player to t.
function Arrow.Vector(t)
    local px, py, inst = Places.Player()
    if not px or inst ~= t.instance then return nil end
    local angle, dist = HBD:GetWorldVector(inst, px, py, t.wx, t.wy)
    return angle, dist
end

local elapsed = 0
local LEAVE = ARRIVED + 5 -- yards: "Here" stays until you're this far off again
local TURN = 12           -- how fast the pointer swings to a new heading (per second)
local shownAngle, wasHere, lastReal
local pi2 = math.pi * 2

-- Swing the pointer toward `want` instead of snapping (the look-ahead point
-- on a walk moves on as you go, and a snap reads as a flicker).
local function Turn(want, dt)
    if not shownAngle then shownAngle = want return want end
    local diff = (want - shownAngle + math.pi) % pi2 - math.pi
    local k = math.min(1, (dt or TICK) * TURN)
    shownAngle = (shownAngle + diff * k) % pi2
    return shownAngle
end

local function Draw(dt)
    local t = OXP.Target.Update()
    if not t then
        f.pointer:Hide()
        f.check:Hide()
        f.dist:SetText("")
        f.label:SetText("")
        f:SetAlpha(0)
        shownAngle, wasHere, lastReal = nil, false, nil
        return
    end
    f:SetAlpha(1)
    ApplySizes()
    local angle, dist = Arrow.Vector(t)
    -- "Here" is about the real spot only, never a corner of the walk on the
    -- way, so the arrow doesn't flash "Here" and turn away again
    local real = t.focus or t.real or t
    if real ~= lastReal then wasHere, lastReal = false, real end
    local realDist = dist
    if real ~= t then
        local _, d = Arrow.Vector(real)
        realDist = d
    end
    local here = realDist and realDist <= (wasHere and LEAVE or ARRIVED) or false
    wasHere = here
    if t.inside then
        f.pointer:Hide()
        f.check:Show()
        f.ring:SetVertexColor(GREEN[1], GREEN[2], GREEN[3], 1)
        f.dist:SetText(L("In the area"))
        f.dist:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        shownAngle = nil
    elseif here then
        f.pointer:Hide()
        f.check:Show()
        f.ring:SetVertexColor(GREEN[1], GREEN[2], GREEN[3], 1)
        f.dist:SetText(L("Here"))
        f.dist:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        shownAngle = nil
    elseif angle then
        local facing = GetPlayerFacing and GetPlayerFacing()
        f.check:Hide()
        f.pointer:Show()
        if facing then f.pointer:SetRotation(Turn(angle - facing, dt)) end
        f.ring:SetVertexColor(BLUE[1], BLUE[2], BLUE[3], 0.6)
        -- along a walk: what's left of it, not the straight line to its next bend
        f.dist:SetText(("%d yd"):format(t.left or realDist or dist))
        f.dist:SetTextColor(0.96, 0.97, 0.98)
    else
        -- another continent and no plan to get there
        f.check:Hide()
        f.pointer:Hide()
        f.ring:SetVertexColor(BLUE[1], BLUE[2], BLUE[3], 0.3)
        f.dist:SetText("...")
    end
    f.label:SetText(t.title and OXP.Text.Strip(t.title) or "")
    Arrow.lastDistance, Arrow.lastHere = realDist or dist, here or t.inside or false
end
Arrow.Draw = OXP.Perf.Wrap("arrow", Draw)

f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < TICK then return end
    local spent = elapsed
    elapsed = 0
    Arrow.Draw(spent)
end)

function Arrow.Refresh()
    local s = OXP.settings
    local show = (s.arrowShown and OXP.Engine.GetGuide() ~= nil) or OXP.PathHints.go ~= nil
    if show then
        f:Show()
        Arrow.Draw()
    else
        f:Hide()
    end
end

function Arrow.Toggle()
    OXP.settings.arrowShown = not OXP.settings.arrowShown
    Arrow.Refresh()
end

function Arrow.ResetPosition()
    OXP.settings.arrowPos = nil
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
end

OXP.OnReady(function()
    local pos = OXP.settings.arrowPos
    if pos then
        f:ClearAllPoints()
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    Arrow.Refresh()
end)
for _, m in ipairs({ "GUIDE_LOADED", "ARROW_CHANGED", "SETTINGS_CHANGED" }) do
    OXP.Listen(m, function() Arrow.Refresh() end)
end

OXP.AddCommand("arrow", "hide or show the arrow", function() Arrow.Toggle() end)
