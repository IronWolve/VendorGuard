local _, ns = ...
local Compare = {}
ns.Comparison = Compare
local Call, Public = ns.SafeCall, ns.Public
local cache = {}
local requested = {}
local dpsKey = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"

-- Equipment slot numbers are client inventory slots, not class proficiency rules.
local slots = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local statOrder = { dpsKey, "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STRENGTH_SHORT",
    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_SPIRIT_SHORT",
    "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_MASTERY_RATING_SHORT",
    "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_EXPERTISE_RATING_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT",
    "ITEM_MOD_SPELL_POWER_SHORT", "RESISTANCE0_NAME" }
local shortNames = { [dpsKey] = "DPS", ITEM_MOD_AGILITY_SHORT = "Agi", ITEM_MOD_STRENGTH_SHORT = "Str",
    ITEM_MOD_INTELLECT_SHORT = "Int", ITEM_MOD_STAMINA_SHORT = "Sta", ITEM_MOD_SPIRIT_SHORT = "Spi",
    ITEM_MOD_CRIT_RATING_SHORT = "Crit", ITEM_MOD_HASTE_RATING_SHORT = "Haste",
    ITEM_MOD_MASTERY_RATING_SHORT = "Mastery", ITEM_MOD_HIT_RATING_SHORT = "Hit",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "Exp", ITEM_MOD_ATTACK_POWER_SHORT = "AP",
    ITEM_MOD_SPELL_POWER_SHORT = "SP", RESISTANCE0_NAME = "Armor" }
local fullNames = { [dpsKey] = "weapon DPS", ITEM_MOD_AGILITY_SHORT = "Agility",
    ITEM_MOD_STRENGTH_SHORT = "Strength", ITEM_MOD_INTELLECT_SHORT = "Intellect",
    ITEM_MOD_STAMINA_SHORT = "Stamina", ITEM_MOD_SPIRIT_SHORT = "Spirit",
    ITEM_MOD_CRIT_RATING_SHORT = "Critical Strike", ITEM_MOD_HASTE_RATING_SHORT = "Haste",
    ITEM_MOD_MASTERY_RATING_SHORT = "Mastery", ITEM_MOD_HIT_RATING_SHORT = "Hit",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "Expertise", ITEM_MOD_ATTACK_POWER_SHORT = "Attack Power",
    ITEM_MOD_SPELL_POWER_SHORT = "Spell Power", RESISTANCE0_NAME = "Armor" }

local function Number(value)
    value = Public(value)
    if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
        return value
    end
end

local function EquipLoc(link)
    return select(9, Call(C_Item and C_Item.GetItemInfo or GetItemInfo, link))
end

local function Request(link)
    local id = Call(C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant, link)
    if id and not requested[id] then
        requested[id] = true
        Call(C_Item and C_Item.RequestLoadItemDataByID, id)
    end
end

local function TooltipDPS(lines)
    local locale = Call(GetLocale)
    if locale ~= "enUS" and locale ~= "enGB" then return nil end
    if type(lines) ~= "table" then return nil end
    for _, line in ipairs(lines) do
        line = Public(line)
        local text = line and Public(line.leftText)
        if type(text) == "string" then
            local value = ns.Rules.CleanText(text):match("^%(([%d%.]+) damage per second%)$")
            local number = Number(tonumber(value))
            if number then return number end
        end
    end
end

local function ReadStats(link, tooltipLines)
    if cache[link] then return cache[link].stats, cache[link].complete end
    local info = Call(C_Item and C_Item.GetItemInfo or GetItemInfo, link)
    if type(info) ~= "string" then Request(link); return nil end
    local api = C_Item and C_Item.GetItemStats or GetItemStats
    local source = Call(api, link)
    local complete = type(source) == "table"
    local stats = {}
    for key, value in pairs(complete and source or {}) do
        key = Public(key)
        local number = Number(value)
        -- Withhold the entire comparison if any stat is unavailable/restricted.
        if type(key) ~= "string" or number == nil then return nil end
        stats[key] = number
    end
    -- Normalize clients that expose base armor under a different stat key.
    if stats.RESISTANCE0_NAME == nil then stats.RESISTANCE0_NAME = stats.ITEM_MOD_ARMOR_SHORT end
    stats.ITEM_MOD_ARMOR_SHORT = nil
    -- Some clients omit weapon DPS from GetItemStats. Read the explicit tooltip
    -- DPS line, never infer character damage or strip numbers from arbitrary text.
    if stats[dpsKey] == nil then
        stats[dpsKey] = TooltipDPS(tooltipLines)
        if stats[dpsKey] == nil then
            local data = Call(C_TooltipInfo and C_TooltipInfo.GetHyperlink, link)
            stats[dpsKey] = TooltipDPS(data and Public(data.lines))
        end
    end
    if not complete and stats[dpsKey] == nil then Request(link); return nil end
    cache[link] = { stats = stats, complete = complete }
    return stats, complete
end

function Compare.Clear(resetRequests)
    cache = {}
    if resetRequests then requested = {} end
end

local function Deltas(candidate, equipped, weapon, complete)
    local deltas, keys, seen = {}, {}, {}
    for _, key in ipairs(statOrder) do keys[#keys + 1] = key; seen[key] = true end
    local extra = {}
    for key in pairs(candidate) do if not seen[key] then extra[key] = true end end
    for key in pairs(equipped) do if not seen[key] then extra[key] = true end end
    local sorted = {}; for key in pairs(extra) do sorted[#sorted + 1] = key end; table.sort(sorted)
    for _, key in ipairs(sorted) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
        -- A missing DPS line means unknown, not zero. Other absent stats are zero.
        local known = (key ~= dpsKey and complete)
            or (key == dpsKey and weapon and candidate[key] ~= nil and equipped[key] ~= nil)
        local amount = known and ((candidate[key] or 0) - (equipped[key] or 0)) or 0
        if math.abs(amount) >= 0.05 then
            local name = key == dpsKey and "weapon DPS" or Public(_G[key]) or fullNames[key] or key
            deltas[#deltas + 1] = { key = key, amount = amount, name = name,
                short = shortNames[key] or name }
        end
    end
    return deltas
end

function Compare.FormatDelta(delta, short)
    return ("%+.1f"):format(delta.amount):gsub("%.0$", "") .. " " .. (short and delta.short or delta.name)
end

local function RawComparisons(item)
    local slotList = slots[item.equipLoc]
    if not slotList or type(GetInventoryItemLink) ~= "function" then return {}, nil end
    local main = Call(GetInventoryItemLink, "player", 16)
    local off = Call(GetInventoryItemLink, "player", 17)
    local mainLoc = main and EquipLoc(main)
    local handItem = item.equipLoc == "INVTYPE_WEAPON" or item.equipLoc == "INVTYPE_WEAPONMAINHAND"
        or item.equipLoc == "INVTYPE_WEAPONOFFHAND" or item.equipLoc == "INVTYPE_SHIELD"
        or item.equipLoc == "INVTYPE_HOLDABLE"
    if (handItem and main and (not mainLoc or mainLoc == "INVTYPE_2HWEAPON"))
            or (item.equipLoc == "INVTYPE_2HWEAPON" and (off or (main and mainLoc ~= "INVTYPE_2HWEAPON"))) then
        return {}, "Weapon setup changes: use the game's equipment comparison for both hands.", "Check setup"
    end
    -- Only offer an off-hand comparison if a weapon is already equipped there.
    -- Do not assume every class can dual wield an empty off-hand slot.
    if item.equipLoc == "INVTYPE_WEAPON" and off then
        local offLoc = EquipLoc(off)
        if offLoc == "INVTYPE_WEAPON" or offLoc == "INVTYPE_WEAPONOFFHAND" then slotList = { 16, 17 } end
    end
    local candidate, candidateComplete = ReadStats(item.link, item.lines)
    if not candidate then return {}, "Comparison data is still loading or unavailable.", "No data" end
    local comparisons = {}
    for _, slot in ipairs(slotList) do
        local link = Call(GetInventoryItemLink, "player", slot)
        if link then
            local data = Call(C_TooltipInfo and C_TooltipInfo.GetInventoryItem, "player", slot)
            local equipped, equippedComplete = ReadStats(link, data and Public(data.lines))
            if not equipped then return {}, "Comparison data is still loading or unavailable.", "No data" end
            comparisons[#comparisons + 1] = { slot = slot, link = link,
                deltas = Deltas(candidate, equipped, item.classID == 2, candidateComplete and equippedComplete) }
        else
            comparisons[#comparisons + 1] = { slot = slot, empty = true, deltas = {} }
        end
    end
    return comparisons
end

-- Usability warnings stay active even when comparison labels are hidden.
function Compare.WarnLowerDPS(item, result)
    if item.toolProfession or not item.ready or item.classID ~= 2 or item.merchantUsable ~= true
            or (result and result.status ~= "green") then return result end
    local comparisons = RawComparisons(item)
    local reasons = {}
    for _, entry in ipairs(comparisons) do
        for _, delta in ipairs(entry.deltas) do
            if delta.key == dpsKey and delta.amount < 0 then
                local slot = entry.slot == 16 and "main hand" or entry.slot == 17 and "off hand"
                    or "slot " .. entry.slot
                reasons[#reasons + 1] = Compare.FormatDelta(delta) .. " vs equipped " .. slot .. "."
            end
        end
    end
    if #reasons == 0 then return result end
    table.insert(reasons, 1, "Usable now, but lower weapon DPS in the comparison below.")
    reasons[#reasons + 1] = "Other stats and effects may still make it useful."
    return { status = "orange", kind = "dpsLoss", badge = "!", heading = "lower weapon DPS", reasons = reasons }
end

function Compare.Get(item, result, options)
    if item.toolProfession or not options.comparisons or not item.ready or not slots[item.equipLoc]
            or (item.classID ~= 2 and item.classID ~= 4) then return nil end
    if result and (result.status == "red" or (result.status == "orange" and result.kind ~= "dpsLoss")) then return nil end
    local later = result and result.status == "yellow"
    if not later and item.merchantUsable ~= true then return nil end
    local comparisons, note, fallbackLabel = RawComparisons(item)
    local label, tone = fallbackLabel, "neutral"
    if #comparisons > 1 then
        label = "Compare 2 slots"
    elseif #comparisons == 1 then
        local comparison = comparisons[1]
        if comparison.empty then label = "Empty slot"
        elseif #comparison.deltas == 0 then label = "Same stats"
        else
            -- One delta fits the native merchant entry.
            label = Compare.FormatDelta(comparison.deltas[1], true)
            tone = comparison.deltas[1].amount > 0 and "gain" or "loss"
        end
    end
    -- A setup change prevents an equipment verdict, not reading the weapon's
    -- own DPS. Prefer the already-loaded merchant tooltip for that fallback.
    if item.classID == 2 and (#comparisons ~= 1 or comparisons[1].empty or fallbackLabel) then
        local value = TooltipDPS(item.lines)
        if not value then
            local stats = ReadStats(item.link)
            value = stats and stats[dpsKey]
        end
        if value then label, tone = ("%.1f DPS"):format(value), "neutral" end
    end
    if label and later then label, tone = "L" .. result.requiredLevel .. ": " .. label, "later" end
    if not label and not note then return nil end
    return { label = label, tone = tone, comparisons = comparisons, note = note, later = later }
end
