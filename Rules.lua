local _, ns = ...
local Rules = {}
ns.Rules = Rules
local ammoClasses = { HUNTER = true, WARRIOR = true, ROGUE = true }
local knownClasses = { HUNTER = true, WARRIOR = true, ROGUE = true, DRUID = true,
    MAGE = true, PRIEST = true, WARLOCK = true, PALADIN = true, SHAMAN = true }

-- This module has no WoW API calls, so the decision rules can be tested outside WoW.
function Rules.CleanText(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("%s+", " ")
        :gsub("^%s+", ""):gsub("%s+$", ""))
end

local function FormatPattern(template, levelOnly)
    template = Rules.CleanText(template)
    if template == "" then return nil end
    -- Positional format tokens occur in some localized global strings.
    template = template:gsub("%%%d+%$([ds])", "%%%1")
    template = template:gsub("%%d", "\001"):gsub("%%s", "\002")
    template = template:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    template = template:gsub("\001", levelOnly and "(%%d+)" or "%%d+")
    template = template:gsub("\002", levelOnly and "(%%d+)" or ".+")
    return "^" .. template .. "$"
end

function Rules.LevelPattern(template)
    return FormatPattern(template, true)
end

function Rules.SkillPattern(template)
    return FormatPattern(template, false)
end

local function IsRed(color)
    return color and type(color.r) == "number" and type(color.g) == "number"
        and type(color.b) == "number" and color.r >= 0.75
        and color.g <= 0.3 and color.b <= 0.3
end

function Rules.Evaluate(item, player, options)
    local redReasons, orangeReasons, seen = {}, {}, {}
    local requiredLevel = item.requiredLevel or 0
    local function AddReason(status, text)
        if text ~= "" and not seen[text] then
            seen[text] = true
            local list = status == "orange" and orangeReasons or redReasons
            list[#list + 1] = text
        end
    end

    for _, line in ipairs(item.lines or {}) do
        for _, side in ipairs({ "left", "right" }) do
            local text = Rules.CleanText(line[side .. "Text"])
            local lineLevel = player.levelPattern and tonumber(text:match(player.levelPattern))
            if lineLevel then
                requiredLevel = math.max(requiredLevel, lineLevel)
            elseif IsRed(line[side .. "Color"]) then
                -- Restrict red-text detection to requirements and equipment types.
                -- Red item names, flavor text, and unrelated descriptions are ignored.
                local isEquipmentType = item.subType and text == item.subType
                local isRequirement = line.type == item.usageLineType
                    or (line.type == item.equipLineType)
                    or (player.requiresPrefix and text:sub(1, #player.requiresPrefix) == player.requiresPrefix)
                if isEquipmentType or isRequirement then
                    local professionRequirement = not isEquipmentType and player.skillPattern
                        and text:match(player.skillPattern)
                    AddReason(professionRequirement and "orange" or "red", text)
                end
            end
        end
    end

    -- Ammo-bag usefulness is separate from whether the bag can be equipped.
    -- Forever also gives Warriors and Rogues bow/crossbow/gun proficiencies.
    local ammoBag = item.classID == 11 or item.equipLoc == "INVTYPE_QUIVER"
    local ammunition = item.classID == 6 and (item.subclassID == 2 or item.subclassID == 3)
    if (ammoBag or ammunition) and knownClasses[player.classToken] and not ammoClasses[player.classToken] then
        AddReason("red", ammoBag and "Your class does not use the ammunition stored in this bag."
            or "Your class does not use arrows or bullets.")
    end

    if options.professionBags and item.bagProfession then
        if player.professionsKnown and not player.professions[item.bagProfession.id]
                and not (item.bagProfession.alternateID and player.professions[item.bagProfession.alternateID]) then
            AddReason("orange", "No " .. item.bagProfession.name .. " profession (specialty bag)")
        end
    end

    if options.professionBags and item.toolProfession then
        local profession = item.toolProfession
        if player.professionsKnown and not player.professions[profession.id]
                and not (profession.alternateID and player.professions[profession.alternateID]) then
            AddReason("orange", "No " .. profession.name .. " profession (profession tool; may still be equippable)")
        end
    end

    local levelBlocked = player.level and player.level > 0 and requiredLevel > player.level
    -- A false merchant usability flag alone cannot explain whether level is the ONLY
    -- obstacle. With incomplete tooltip data, wait rather than paint a false yellow.
    if item.ready and item.merchantUsable == false and #redReasons == 0 and #orangeReasons == 0 and not levelBlocked then
        AddReason("red", "You do not meet this item's requirements.")
    end

    if #redReasons > 0 or #orangeReasons > 0 then
        local reasons = {}
        for _, reason in ipairs(redReasons) do reasons[#reasons + 1] = reason end
        for _, reason in ipairs(orangeReasons) do reasons[#reasons + 1] = reason end
        if levelBlocked then reasons[#reasons + 1] = "Requires level " .. requiredLevel end
        return { status = #redReasons > 0 and "red" or "orange", reasons = reasons, requiredLevel = requiredLevel }
    end
    if not item.ready then return nil end
    if levelBlocked then
        return { status = "yellow", reasons = { "Requires level " .. requiredLevel }, requiredLevel = requiredLevel }
    end
    local gearOrBag = item.classID == 1 or item.classID == 2 or item.classID == 4
        or (ammoBag and ammoClasses[player.classToken])
    local bagUnknown = options.professionBags and (item.bagProfession or item.toolProfession) and not player.professionsKnown
    if options.green and gearOrBag and item.merchantUsable == true and not bagUnknown then
        return { status = "green", reasons = { "Usable now. This does not indicate an upgrade." }, requiredLevel = requiredLevel }
    end
    return nil
end
