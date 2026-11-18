-- Two things live here:
--   the menu      a small list from the card's menu button (also right-click
--                 on the card, minimap right-click): pick a guide, find your
--                 place, skipped chains, settings, feedback, what's new
--   Pick a guide  a window with every guide your character can use,
--                 grouped and sorted by level, a search box, the guide
--                 you're on highlighted, a details pane and one Start button
local _, OXP = ...

local Picker = {}
OXP.GuidePicker = Picker

local Style, L, Text = OXP.Style, OXP.L, OXP.Text
local C, S = Style.C, Style.S
local fmt = string.format

---------------------------------------------------------------------------
-- The menu
---------------------------------------------------------------------------

local MENU_W, ROW_H = 240, 30
local menu, rows = nil, {}

local function MenuRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, menu)
    row:SetHeight(ROW_H)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    Style.Fill(row.hl, { 1, 1, 1 }, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 12, 0)
    row.text = Style.Text(row, 13, C.text)
    row.text:SetPoint("LEFT", 34, 0)
    row.text:SetPoint("RIGHT", -12, 0)
    row.text:SetWordWrap(false)
    row.extra = Style.Text(row, 11, C.faint)
    row.extra:SetPoint("RIGHT", -12, 0)
    row.extra:SetJustifyH("RIGHT")
    row.line = Style.Divider(row)
    row.line:SetPoint("BOTTOMLEFT", 10, 0)
    row.line:SetPoint("BOTTOMRIGHT", -10, 0)
    row:SetScript("OnEnter", function(self)
        if self.fn then
            Style.Fill(self.hl, { 1, 1, 1 }, 0.07)
            self.text:SetTextColor(1, 1, 1)
            Style.Tint(self.icon, C.blue)
        end
    end)
    row:SetScript("OnLeave", function(self)
        Style.Fill(self.hl, { 1, 1, 1 }, 0)
        self.text:SetTextColor(unpack(self.header and C.faint or C.text))
        Style.Tint(self.icon, C.dim)
    end)
    row:SetScript("OnClick", function(self)
        if self.fn then
            menu:Hide()
            self.fn()
        end
    end)
    rows[i] = row
    return row
end

local function BuildMenu()
    menu = CreateFrame("Frame", "OpenXPMenu", UIParent, "BackdropTemplate")
    Style.Backdrop(menu, C.bgSolid, C.borderStrong)
    menu:SetFrameStrata("DIALOG")
    menu:SetWidth(MENU_W)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)
    tinsert(_G.UISpecialFrames, "OpenXPMenu")
    menu.logo = menu:CreateTexture(nil, "ARTWORK")
    menu.logo:SetTexture(Style.LOGO)
    menu.logo:SetSize(18, 18)
    menu.logo:SetPoint("TOPLEFT", 12, -10)
    menu.title = Style.Text(menu, 13, { 1, 1, 1 })
    menu.title:SetPoint("LEFT", menu.logo, "RIGHT", 8, 0)
    menu.title:SetText("OpenXP")
    menu.guide = Style.Text(menu, 11, C.dim)
    menu.guide:SetPoint("TOPLEFT", 12, -34)
    menu.guide:SetPoint("RIGHT", menu, "RIGHT", -12, 0)
    menu.guide:SetWordWrap(false)
    menu.line = Style.Divider(menu)
    menu.line:SetPoint("TOPLEFT", 1, -54)
    menu.line:SetPoint("TOPRIGHT", -1, -54)
    Style.Shadow(menu)
    menu:Hide()
end

-- entries: { text, icon, fn, extra }
local function FillMenu(entries)
    local g = OXP.Engine.GetGuide()
    menu.guide:SetText(g and (L("On: ") .. Text.Strip(g.name)) or L("No guide loaded"))
    for i = 1, math.max(#entries, #rows) do
        local e = entries[i]
        local row = e and MenuRow(i) or rows[i]
        if e then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 1, -56 - (i - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", -1, -56 - (i - 1) * ROW_H)
            row.text:SetText(e.text)
            row.text:SetTextColor(unpack(C.text))
            row.icon:SetTexture(Style.TEX .. (e.icon or "next"))
            Style.Tint(row.icon, C.dim)
            row.extra:SetText(e.extra or "")
            row.line:SetShown(i < #entries)
            row.fn = e.fn
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    menu:SetHeight(56 + #entries * ROW_H + 6)
end

function Picker.MenuEntries()
    return {
        { text = L("Pick a guide"), icon = "menu", extra = L("all guides"), fn = function() Picker.ShowGuides() end },
        { text = L("Find my place"), icon = "target", fn = function() OXP.SmartStart.Run(false) end },
        { text = L("Skipped quest chains"), icon = "travel", fn = function() OXP.SmartStart.ShowCatchUp() end },
        { text = L("Settings"), icon = "gear", fn = function() OXP.Settings.Show() end },
        { text = L("Feedback and bugs"), icon = "pointer", fn = function() OXP.Feedback.Show() end },
        { text = L("What's new"), icon = "check", fn = function() OXP.Welcome.Show("update") end },
    }
end

function Picker.Show(anchor)
    if not menu then BuildMenu() end
    if anchor then
        menu:ClearAllPoints()
        menu:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)
    elseif not menu:GetPoint() then
        menu:SetPoint("CENTER")
    end
    FillMenu(Picker.MenuEntries())
    Style.Fade(menu, true, 0.12)
end

function Picker.Toggle(anchor)
    if menu and menu:IsShown() then
        menu:Hide()
        return
    end
    Picker.Show(anchor)
end

Picker.menuFrame = function() return menu end

---------------------------------------------------------------------------
-- Pick a guide
---------------------------------------------------------------------------

local WIN_W, WIN_H, LIST_W = 820, 560, 340
local LIST_ROW, LIST_HEAD = 40, 30
local win
local selected        -- the guide shown in the details pane
local query = ""

local function Zone(g)
    local name = Text.Strip(g.name or "")
    return (name:gsub("^%d+%s*%-%s*%d+%s+", ""))
end

local function Range(g)
    if g.minLevel and g.maxLevel then return fmt("%d–%d", g.minLevel, g.maxLevel) end
    return ""
end

-- "OpenXP Leveling (Alliance)" -> "OpenXP Leveling"
local function GroupTitle(name)
    return (tostring(name or ""):gsub("%s*%((%a+)%)%s*$", ""))
end

local function Percent(g)
    local done, total = OXP.Engine.GetProgress(g)
    if total <= 0 then return 0, 0, 0 end
    return math.floor(done / total * 100 + 0.5), done, total
end

--- The list as rows: { header = text } and { guide = g }, filtered by
--- the search text (zone, group or a level inside the range).
function Picker.ListRows(search)
    search = (search or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local level = tonumber(search)
    local out = {}
    for _, group in ipairs(OXP.Registry.Groups()) do
        local hits = {}
        for _, g in ipairs(group.guides) do
            local ok = search == ""
                or (level and g.minLevel and level >= g.minLevel and level <= (g.maxLevel or g.minLevel))
                or Zone(g):lower():find(search, 1, true)
                or tostring(group.name):lower():find(search, 1, true)
            if ok then hits[#hits + 1] = g end
        end
        if #hits > 0 then
            out[#out + 1] = { header = GroupTitle(group.name), count = #hits }
            for _, g in ipairs(hits) do out[#out + 1] = { guide = g } end
        end
    end
    return out
end

local function ForYourLevel(g)
    local lvl = OXP.Player.level or (UnitLevel and UnitLevel("player")) or 1
    return g.minLevel and lvl >= g.minLevel and lvl <= (g.maxLevel or g.minLevel)
end

local listRows = {}

local function ListRow(i)
    local row = listRows[i]
    if row then return row end
    local content = win.list.content
    row = CreateFrame("Button", nil, content)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    Style.Fill(row.hl, { 1, 1, 1 }, 0)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("TOPLEFT", 0, -6)
    row.bar:SetPoint("BOTTOMLEFT", 0, 6)
    row.bar:SetWidth(3)
    Style.Fill(row.bar, C.blue)
    row.range = Style.Pill(row)
    row.range:SetPoint("LEFT", 14, 0)
    row.zone = Style.Text(row, 13, C.text)
    row.zone:SetPoint("LEFT", 74, 0)
    row.zone:SetPoint("RIGHT", -64, 0)
    row.zone:SetWordWrap(false)
    row.right = Style.Text(row, 11, C.faint)
    row.right:SetPoint("RIGHT", -14, 0)
    row.right:SetJustifyH("RIGHT")
    row.head = Style.Text(row, 11, C.faint)
    row.head:SetPoint("BOTTOMLEFT", 14, 7)
    row.headCount = Style.Text(row, 11, C.faint)
    row.headCount:SetPoint("BOTTOMRIGHT", -14, 7)
    row.headCount:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function(self)
        if self.guide and self.guide ~= selected then Style.Fill(self.hl, { 1, 1, 1 }, 0.05) end
    end)
    row:SetScript("OnLeave", function(self) Picker.PaintRow(self) end)
    row:SetScript("OnClick", function(self)
        if self.guide then Picker.Select(self.guide) end
    end)
    row:SetScript("OnDoubleClick", function(self)
        if self.guide then
            Picker.Select(self.guide)
            Picker.Start()
        end
    end)
    listRows[i] = row
    return row
end

function Picker.PaintRow(row)
    local g = row.guide
    if not g then Style.Fill(row.hl, { 1, 1, 1 }, 0) row.bar:Hide() return end
    local current = g == OXP.Engine.GetGuide()
    local sel = g == selected
    Style.Fill(row.hl, sel and C.raised or { 1, 1, 1, 0 })
    row.bar:SetShown(sel)
    row.zone:SetTextColor(unpack(current and C.blue or sel and { 1, 1, 1 } or C.text))
end

function Picker.FillList()
    local data = Picker.ListRows(query)
    local y = 0
    local current = OXP.Engine.GetGuide()
    for i = 1, math.max(#data, #listRows) do
        local e = data[i]
        local row = e and ListRow(i) or listRows[i]
        if e then
            local h = e.header and LIST_HEAD or LIST_ROW
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", win.list.content, "RIGHT", -8, 0)
            row:SetHeight(h)
            row.guide = e.guide
            row.head:SetShown(e.header ~= nil)
            row.headCount:SetShown(e.header ~= nil)
            row.zone:SetShown(e.guide ~= nil)
            row.right:SetShown(e.guide ~= nil)
            if e.header then
                row.head:SetText(e.header:upper())
                row.headCount:SetText(e.count)
                row.range:Hide()
                row:EnableMouse(false)
            else
                local g = e.guide
                row:EnableMouse(true)
                row.range:SetTag(Range(g), ForYourLevel(g) and C.green or C.dim, 11)
                row.range:SetWidth(50)
                row.zone:SetText(Zone(g))
                local pct = Percent(g)
                row.right:SetText(g == current and L("current") or pct >= 100 and L("done") or pct > 0 and (pct .. "%") or "")
                row.right:SetTextColor(unpack(g == current and C.blue or pct >= 100 and C.green or C.faint))
            end
            Picker.PaintRow(row)
            row:Show()
            y = y + h
        elseif row then
            row:Hide()
            row.guide = nil
        end
    end
    win.list:SetContentHeight(y + 8)
    win.empty:SetShown(#data == 0)
    return data
end

-- the details pane
function Picker.FillDetails()
    local d = win.details
    local g = selected
    d:SetShown(g ~= nil)
    win.none:SetShown(g == nil)
    if not g then return end
    local current = g == OXP.Engine.GetGuide()
    d.group:SetText(GroupTitle(g.group):upper())
    d.zone:SetText(Zone(g))
    d.levels:SetText(g.minLevel and fmt(L("Levels %d to %d"), g.minLevel, g.maxLevel or g.minLevel) or "")
    local pct, done, total = Percent(g)
    local steps = #(g.steps or {})
    d.steps:SetText(fmt(L("%d steps"), total > 0 and total or steps))
    d.progressFill:SetWidth(math.max(1, (d.progressBg:GetWidth() or 300) * pct / 100))
    d.progressText:SetText(total > 0 and done > 0 and fmt(L("%d%% done, step %d of %d"), pct, done + 1 > total and total or done + 1, total)
        or L("Not started"))
    local nextG = OXP.Registry.Next(g)
    d.nextGuide:SetText(nextG and (L("Then: ") .. Text.Strip(nextG.name)) or "")
    d.yours:SetShown(ForYourLevel(g) and true or false)
    -- what the guide starts with
    local lines, n = {}, 0
    for _, step in ipairs(g.steps or {}) do
        for _, goal in ipairs(step) do
            if goal.text and goal[1] ~= "xp" then
                local t = Text.Strip(Text.Format(goal.text))
                if t ~= "" and #t < 90 then
                    n = n + 1
                    lines[#lines + 1] = "|cFF5AB8FF" .. n .. ".|r  " .. t
                end
                break
            end
        end
        if n >= 5 then break end
    end
    d.first:SetText(table.concat(lines, "\n"))
    if current then
        d.start:SetLabel(L("You're on this guide"))
        d.start:SetEnabled(false)
    else
        d.start:SetEnabled(true)
        d.start:SetLabel(done > 0 and fmt(L("Continue at step %d"), math.min(done + 1, total)) or L("Start guide"))
    end
    d.restart:SetShown(done > 0 or current)
end

function Picker.Select(g)
    selected = g
    if not win then return end
    for _, row in ipairs(listRows) do if row:IsShown() then Picker.PaintRow(row) end end
    Picker.FillDetails()
end

function Picker.Start(fromTop)
    if not selected then return end
    if fromTop then OXP.Engine.Load(selected, 1) else OXP.Engine.Load(selected) end
    if OXP.Card then OXP.Card.Refresh(true) end
    win:Hide()
end

local function BuildDetails(parent)
    local d = CreateFrame("Frame", nil, parent)
    d:SetAllPoints()
    local pad = S.xl
    d.group = Style.Text(d, 11, C.faint)
    d.group:SetPoint("TOPLEFT", pad, -pad)
    d.zone = Style.Text(d, 22, { 1, 1, 1 })
    d.zone:SetPoint("TOPLEFT", d.group, "BOTTOMLEFT", 0, -6)
    d.zone:SetPoint("RIGHT", d, "RIGHT", -pad, 0)
    d.zone:SetWordWrap(false)
    d.levels = Style.Text(d, 13, C.dim)
    d.levels:SetPoint("TOPLEFT", d.zone, "BOTTOMLEFT", 0, -6)
    d.yours = Style.Pill(d)
    d.yours:SetPoint("LEFT", d.levels, "RIGHT", 10, 0)
    d.yours:SetTag(L("YOUR LEVEL"), C.green, 10)
    d.steps = Style.Text(d, 13, C.dim)
    d.steps:SetPoint("TOPRIGHT", -pad, -pad - 18)
    d.steps:SetJustifyH("RIGHT")

    d.progressBg = d:CreateTexture(nil, "ARTWORK")
    d.progressBg:SetPoint("TOPLEFT", d.levels, "BOTTOMLEFT", 0, -18)
    d.progressBg:SetPoint("RIGHT", d, "RIGHT", -pad, 0)
    d.progressBg:SetHeight(4)
    Style.Fill(d.progressBg, C.raised)
    d.progressFill = d:CreateTexture(nil, "OVERLAY")
    d.progressFill:SetPoint("LEFT", d.progressBg, "LEFT")
    d.progressFill:SetHeight(4)
    Style.Fill(d.progressFill, C.blue)
    d.progressText = Style.Text(d, 11, C.dim)
    d.progressText:SetPoint("TOPLEFT", d.progressBg, "BOTTOMLEFT", 0, -6)

    local firstHead = Style.Text(d, 11, C.faint)
    firstHead:SetPoint("TOPLEFT", d.progressText, "BOTTOMLEFT", 0, -22)
    firstHead:SetText(L("IT STARTS WITH"))
    d.first = Style.Text(d, 12, C.text)
    d.first:SetPoint("TOPLEFT", firstHead, "BOTTOMLEFT", 0, -8)
    d.first:SetPoint("RIGHT", d, "RIGHT", -pad, 0)
    d.first:SetWordWrap(true)
    d.first:SetSpacing(6)
    d.nextGuide = Style.Text(d, 12, C.dim)
    d.nextGuide:SetPoint("BOTTOMLEFT", pad, 64)
    d.nextGuide:SetPoint("RIGHT", d, "RIGHT", -pad, 0)
    d.nextGuide:SetWordWrap(false)

    d.start = Style.Button(d, L("Start guide"), "primary", 200, function() Picker.Start(false) end)
    d.start:SetHeight(34)
    d.start:SetPoint("BOTTOMRIGHT", -pad, pad - 4)
    d.restart = Style.Button(d, L("Start over"), "ghost", 110, function() Picker.Start(true) end,
        L("Go back to step 1 of this guide."))
    d.restart:SetHeight(34)
    d.restart:SetPoint("RIGHT", d.start, "LEFT", -8, 0)
    return d
end

local function BuildWindow()
    win = Style.Window("OpenXPGuides", WIN_W, WIN_H, L("Pick a guide"),
        L("Every guide for your character, by level. Double-click to start."))
    -- left: search and list
    local left = CreateFrame("Frame", nil, win.body)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LIST_W)
    left.bg = left:CreateTexture(nil, "BACKGROUND")
    left.bg:SetAllPoints()
    Style.Fill(left.bg, C.panel)
    local line = Style.Divider(win.body, true)
    line:SetPoint("TOPLEFT", LIST_W, 0)
    line:SetPoint("BOTTOMLEFT", LIST_W, 0)
    win.search = Style.SearchBox(left, LIST_W - S.lg * 2, L("Search a zone or a level"), function(text)
        query = text
        Picker.FillList()
    end)
    win.search:SetPoint("TOPLEFT", S.lg, -S.lg)
    win.list = Style.ScrollArea(left)
    win.list:SetPoint("TOPLEFT", 0, -S.lg - 28 - S.sm)
    win.list:SetPoint("BOTTOMRIGHT", 0, 0)
    win.list.content:SetWidth(LIST_W)
    win.empty = Style.Text(left, 12, C.faint)
    win.empty:SetPoint("TOP", 0, -90)
    win.empty:SetText(L("No guide matches that."))
    win.empty:Hide()
    -- right: details
    local right = CreateFrame("Frame", nil, win.body)
    right:SetPoint("TOPLEFT", LIST_W + 1, 0)
    right:SetPoint("BOTTOMRIGHT")
    win.details = BuildDetails(right)
    win.none = Style.Text(right, 13, C.faint)
    win.none:SetPoint("CENTER")
    win.none:SetText(L("Pick a guide on the left."))
    -- header: find my place
    win.find = Style.Button(win, L("Find my place"), "secondary", 130, function()
        win:Hide()
        OXP.SmartStart.Run(false)
    end, L("Jump to the right guide and step for your level, zone and quests."))
    win.find:SetHeight(28)
    win.find:SetPoint("RIGHT", win.close, "LEFT", -10, 0)
    Picker.window = win
end

--- Open "Pick a guide" on the guide you're on (or the first for your level).
function Picker.ShowGuides()
    if menu then menu:Hide() end
    if not win then BuildWindow() end
    selected = OXP.Engine.GetGuide()
    if not selected then
        for _, g in ipairs(OXP.Registry.ForPlayer()) do
            if ForYourLevel(g) then selected = g break end
        end
    end
    win.search:SetText("")
    query = ""
    local data = Picker.FillList()
    -- scroll the selected guide into view
    local y = 0
    for _, e in ipairs(data) do
        if e.guide and e.guide == selected then break end
        y = y + (e.header and LIST_HEAD or LIST_ROW)
    end
    win.list:ScrollTo(math.max(0, y - 120))
    Picker.FillDetails()
    win:Show()
end

function Picker.ToggleGuides()
    if win and win:IsShown() then win:Hide() else Picker.ShowGuides() end
end

OXP.AddCommand("menu", "open the OpenXP menu", function() Picker.Toggle() end)
OXP.AddCommand("guides", "pick a guide", function() Picker.ToggleGuides() end)
