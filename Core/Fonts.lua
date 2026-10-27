-- VoidcoreAdvisor Reborn: Fonts
-- Every text of the addon uses one of the VCAFont* font objects below. Changing the font of
-- those objects changes the font of the addon and all its windows at once.
-- The choices are the fonts of the game, Source Sans 3 (shipped in the Fonts folder) and every
-- font other addons register with LibSharedMedia-3.0.
local addonName, VCA = ...

local Fonts = {}
VCA.Fonts = Fonts

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Fonts\\"

-- The font objects the addon uses, the game font object each one copies, and whether it is a
-- "heading" (gold labels and titles take the semibold weight when the font has one).
-- The fourth value is the size of the addon text.  It is fixed here instead of being copied from the
-- game font, so an addon that makes all the game fonts bigger cannot stretch the text of this one
-- (the windows are laid out for these sizes).
local OBJECTS = {
    {"VCAFontNormal", "GameFontNormal", true, 12},
    {"VCAFontNormalLarge", "GameFontNormalLarge", true, 16},
    {"VCAFontNormalSmall", "GameFontNormalSmall", true, 10},
    {"VCAFontNormalHuge", "GameFontNormalHuge", true, 20},
    {"VCAFontHighlight", "GameFontHighlight", false, 12},
    {"VCAFontHighlightSmall", "GameFontHighlightSmall", false, 10},
    {"VCAFontHighlightLarge", "GameFontHighlightLarge", false, 16},
    {"VCAFontDisableSmall", "GameFontDisableSmall", false, 10}
}

local DEFAULT = "default"

-- Fonts that come with the game or the addon. regular/bold: bold is used for headings.
local BUILTIN = {
    {name = "Source Sans 3", regular = MEDIA .. "SourceSans3-Regular.ttf", bold = MEDIA .. "SourceSans3-Semibold.ttf"},
    {name = "Friz Quadrata", regular = "Fonts\\FRIZQT__.TTF"},
    {name = "Arial Narrow", regular = "Fonts\\ARIALN.TTF"},
    {name = "Morpheus", regular = "Fonts\\MORPHEUS.TTF"},
    {name = "Skurri", regular = "Fonts\\skurri.TTF"}
}

local objects = {}
local enforcing = false

-- Text size chosen in the settings: 1 = the sizes above.
local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.8, 1.6, 0.1
local scale = 1

local function TargetSize(o)
    return math.floor(o.size * scale + 0.5)
end

-- Puts the fixed size back on one object if something else changed it.
local function EnforceSize(o)
    if enforcing or not (o.obj and o.obj.GetFont) then
        return
    end
    local path, size, flags = o.obj:GetFont()
    local target = TargetSize(o)
    if path and size and math.abs(size - target) > 0.01 then
        enforcing = true
        pcall(o.obj.SetFont, o.obj, path, target, flags or "")
        enforcing = false
    end
end

for _, def in ipairs(OBJECTS) do
    local obj = CreateFont(def[1])
    if _G[def[2]] then
        obj:CopyFontObject(_G[def[2]])
    end
    local o = {obj = obj, base = def[2], heading = def[3], size = def[4]}
    objects[#objects + 1] = o
    EnforceSize(o)
    -- If another addon later sets the font of this object, the size goes back to ours.
    if hooksecurefunc then
        pcall(hooksecurefunc, obj, "SetFont", function()
            EnforceSize(o)
        end)
        pcall(hooksecurefunc, obj, "CopyFontObject", function()
            EnforceSize(o)
        end)
    end
end

-- Sets the size of every addon font again (used when the world loads and a little later, in
-- case a font addon rewrites all the fonts after the addon loaded).
function Fonts.EnforceSizes()
    for _, o in ipairs(objects) do
        EnforceSize(o)
    end
end

local function LSM()
    if LibStub then
        return LibStub("LibSharedMedia-3.0", true)
    end
    return nil
end

local function GDB()
    return _G[VCA.GLOBAL_DB_NAME]
end

-- The file(s) of a font name: regular and bold paths, or nil when it is not available.
function Fonts.Resolve(name)
    if not name or name == DEFAULT then
        return nil
    end
    for _, f in ipairs(BUILTIN) do
        if f.name == name then
            return f.regular, f.bold or f.regular
        end
    end
    local lsm = LSM()
    if lsm and lsm.Fetch then
        local path = lsm:Fetch("font", name, true)
        if type(path) == "string" then
            return path, path
        end
    end
    return nil
end

-- All the names to choose from: the game and addon fonts first, then everything LibSharedMedia
-- has (other addons), without repeats, each group in alphabetical order.
function Fonts.List()
    local list, seen = {}, {}
    for _, f in ipairs(BUILTIN) do
        list[#list + 1] = f.name
        seen[f.name] = true
    end
    local lsm = LSM()
    if lsm and lsm.List then
        local names = {}
        local all = lsm:List("font")
        for i = 1, type(all) == "table" and #all or 0 do
            local n = all[i]
            if type(n) == "string" and not seen[n] then
                seen[n] = true
                names[#names + 1] = n
            end
        end
        table.sort(names, function(a, b)
            return a:lower() < b:lower()
        end)
        for _, n in ipairs(names) do
            list[#list + 1] = n
        end
    end
    return list
end

-- Puts the named font on every addon font object (nil or "default" restores the game's).
-- Returns true when the font was applied.
function Fonts.Apply(name)
    local regular, bold = Fonts.Resolve(name)
    local applied = false
    for _, o in ipairs(objects) do
        local base = _G[o.base]
        if not regular then
            if base then
                o.obj:CopyFontObject(base)
                EnforceSize(o)
            end
        else
            local _, _, flags
            if base and base.GetFont then
                _, _, flags = base:GetFont()
            end
            local path = (o.heading and bold) or regular
            local ok = pcall(o.obj.SetFont, o.obj, path, TargetSize(o), flags or "")
            if ok then
                applied = true
            elseif base then
                o.obj:CopyFontObject(base)
                EnforceSize(o)
            end
        end
    end
    return applied
end

-- Saves the choice and applies it.
function Fonts.Choose(name)
    local gdb = GDB()
    if gdb then
        gdb.fontName = (name and name ~= DEFAULT) and name or nil
    end
    return Fonts.Apply(name)
end

function Fonts.Current()
    local gdb = GDB()
    return gdb and gdb.fontName or nil
end

-- Text size: a multiplier of the addon font sizes (saved with the settings).
function Fonts.GetScale()
    return scale
end

-- Sets the multiplier (kept between 0.8 and 1.6, in steps of 0.1) and applies it.
function Fonts.SetScale(value)
    value = tonumber(value) or 1
    value = math.min(MAX_SCALE, math.max(MIN_SCALE, math.floor(value / SCALE_STEP + 0.5) * SCALE_STEP))
    scale = value
    local gdb = GDB()
    if gdb then
        gdb.fontScale = (math.abs(value - 1) > 0.001) and value or nil
    end
    Fonts.Apply(Fonts.Current())
    Fonts.EnforceSizes()
    return value
end

function Fonts.CanScale(direction)
    if direction > 0 then
        return scale < MAX_SCALE - 0.001
    end
    return scale > MIN_SCALE + 0.001
end

function Fonts.LoadScale()
    local gdb = GDB()
    local saved = gdb and tonumber(gdb.fontScale)
    scale = saved and math.min(MAX_SCALE, math.max(MIN_SCALE, saved)) or 1
end

-- Apply the saved choice once every addon has loaded (others register their fonts on the way),
-- and again when the chosen font gets registered late.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        Fonts.EnforceSizes()
        C_Timer.After(2, Fonts.EnforceSizes)
        return
    end
    Fonts.LoadScale()
    Fonts.Apply(Fonts.Current())
    Fonts.EnforceSizes()
    C_Timer.After(2, Fonts.EnforceSizes)
    local lsm = LSM()
    if lsm and lsm.RegisterCallback then
        local owner = {}
        lsm.RegisterCallback(owner, "LibSharedMedia_Registered", function(_, mediaType, key)
            if mediaType == "font" and key == Fonts.Current() then
                Fonts.Apply(key)
            end
        end)
    end
end)
