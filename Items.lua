local _, ns = ...
local Rules = ns.Rules

-- Container subclasses and base profession skill-line IDs, not class weapon tables.
-- Forever can change class proficiencies; its own tooltip is the authority for those.
local professionBags = {
    [2] = { id = 182, name = "Herbalism" },
    [3] = { id = 333, name = "Enchanting" },
    [4] = { id = 202, name = "Engineering" },
    [5] = { id = 755, name = "Jewelcrafting" },
    [6] = { id = 186, name = "Mining" },
    [7] = { id = 165, alternateID = 393, name = "Skinning or Leatherworking" },
    [8] = { id = 773, name = "Inscription" },
    [9] = { id = 356, name = "Fishing" },
    [10] = { id = 185, name = "Cooking" },
}

-- Verified basic tools only. Names such as "Cracked Blacksmith Hammer" can
-- describe ordinary weapons, so never classify tools by a name substring.
local professionTools = {
    [2901] = { id = 186, name = "Mining" }, -- Mining Pick
    [5956] = { id = 164, alternateID = 202, name = "Blacksmithing or Engineering" },
    [7005] = { id = 393, name = "Skinning" }, -- Skinning Knife
}

local function Public(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end
ns.Public = Public

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m = pcall(fn, ...)
    if not ok then return nil end
    return Public(a), Public(b), Public(c), Public(d), Public(e), Public(f), Public(g),
        Public(h), Public(i), Public(j), Public(k), Public(l), Public(m)
end
ns.SafeCall = Call

function ns.GetPlayer()
    local player = {
        level = Call(UnitLevel, "player"),
        classToken = select(2, Call(UnitClass, "player")),
        professions = {},
        professionsKnown = false,
        levelPattern = Rules.LevelPattern(ITEM_MIN_LEVEL or "Requires Level %d"),
        skillPattern = Rules.SkillPattern(ITEM_REQ_SKILL),
    }
    -- ITEM_REQ_SKILL is localized; extract only its prefix before the first token.
    local template = Rules.CleanText(ITEM_REQ_SKILL)
    player.requiresPrefix = template:match("^(.-)%%")
    if player.requiresPrefix == "" then player.requiresPrefix = nil end

    if GetProfessions and GetProfessionInfo then
        local ok, p1, p2, archaeology, fishing, cooking, firstAid = pcall(GetProfessions)
        if ok then
            player.professionsKnown = true
            for _, index in ipairs({ p1 or false, p2 or false, archaeology or false,
                    fishing or false, cooking or false, firstAid or false }) do
                index = Public(index)
                if index then
                    local name, _, _, _, _, _, skillLineID = Call(GetProfessionInfo, index)
                    if skillLineID then player.professions[skillLineID] = true end
                    if not name or not skillLineID then player.professionsKnown = false end
                end
            end
        end
    end
    return player
end

local function CopyColor(color)
    color = Public(color)
    if not color then return nil end
    local r, g, b = Public(color.r), Public(color.g), Public(color.b)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return { r = r, g = g, b = b }
    end
end

local function CopyLines(data)
    local lines, ready = {}, false
    if not data then return lines, ready end
    local sourceLines = Public(data.lines)
    if type(sourceLines) ~= "table" then return lines, ready end
    ready = #sourceLines > 0
    for _, source in ipairs(sourceLines) do
        source = Public(source)
        if source then
            local left, right = Public(source.leftText), Public(source.rightText)
            local lineType = Public(source.type)
            if (RETRIEVING_ITEM_INFO and left == RETRIEVING_ITEM_INFO)
                    or (SEARCH_LOADING_TEXT and left == SEARCH_LOADING_TEXT) then ready = false end
            -- If any relevant text/color is secret, do not certify level-only usability.
            if issecretvalue and (issecretvalue(source.leftText) or issecretvalue(source.rightText)
                    or issecretvalue(source.leftColor) or issecretvalue(source.rightColor)
                    or issecretvalue(source.type)) then ready = false end
            local leftColor, rightColor = CopyColor(source.leftColor), CopyColor(source.rightColor)
            if Public(source.leftColor) and not leftColor then ready = false end
            if Public(source.rightColor) and not rightColor then ready = false end
            lines[#lines + 1] = {
                type = lineType, leftText = left, rightText = right,
                leftColor = leftColor, rightColor = rightColor,
            }
        else
            ready = false
        end
    end
    return lines, ready
end

function ns.ReadItem(index)
    local link = Call(GetMerchantItemLink, index)
    if not link then return nil end
    local api = C_Item or {}
    local name, _, _, _, minLevel, _, subType, _, equipLoc, _, _, classID, subclassID =
        Call(api.GetItemInfo or GetItemInfo, link)
    local itemID = Call(api.GetItemInfoInstant or GetItemInfoInstant, link)
    local data = Call(C_TooltipInfo and C_TooltipInfo.GetMerchantItem, index)
    local lines, ready = CopyLines(data)
    local merchantInfo = Call(C_MerchantFrame and C_MerchantFrame.GetItemInfo, index)
    local usable = merchantInfo and Public(merchantInfo.isUsable)
    if not merchantInfo and GetMerchantItemInfo then
        usable = select(7, Call(GetMerchantItemInfo, index))
    end
    local lineTypes = Enum and Enum.TooltipDataLineType or {}
    return {
        link = link, id = itemID, name = name, requiredLevel = minLevel,
        subType = subType, equipLoc = equipLoc, classID = classID, subclassID = subclassID,
        bagProfession = classID == 1 and professionBags[subclassID] or nil,
        toolProfession = professionTools[itemID],
        lines = lines, ready = name ~= nil and ready,
        merchantUsable = usable,
        usageLineType = lineTypes.UsageRequirement or 43,
        equipLineType = lineTypes.EquipSlot or 21,
    }
end
