local addonName = ...

local DEFAULT_SCALE = 0.64
local MIN_SCALE = 0.4
local MAX_SCALE = 1.5
local EPSILON = 0.0005

UIScaleDB = UIScaleDB or {}

local frame = CreateFrame("Frame")
local pendingScale

local hasModernCVar = C_CVar and C_CVar.GetCVar
local hasLegacyCVar = type(GetCVar) == "function"
local hasCVarAccess = hasModernCVar or hasLegacyCVar

local function getCVarValue(name)
    if hasModernCVar then
        return C_CVar.GetCVar(name)
    elseif hasLegacyCVar then
        return GetCVar(name)
    end
end

local function inCombat()
    if InCombatLockdown then
        return InCombatLockdown()
    end
    return false
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end
    return value
end

local function formatScale(scale)
    local numeric = tonumber(scale)
    if not numeric then
        return nil
    end

    return tonumber(string.format("%.3f", numeric))
end

local function readCVarScale()
    if not hasCVarAccess then
        return nil
    end

    if getCVarValue("useUiScale") ~= "1" then
        return nil
    end

    local rounded = formatScale(getCVarValue("uiScale"))
    if not rounded then
        return nil
    end

    return clamp(rounded, MIN_SCALE, MAX_SCALE)
end

local function ensureDefaults()
    if type(UIScaleDB.scale) ~= "number" then
        UIScaleDB.scale = readCVarScale() or DEFAULT_SCALE
    end

    local rounded = formatScale(UIScaleDB.scale)
    if not rounded then
        local defaultRounded = formatScale(DEFAULT_SCALE) or DEFAULT_SCALE
        UIScaleDB.scale = clamp(defaultRounded, MIN_SCALE, MAX_SCALE)
        return
    end

    UIScaleDB.scale = clamp(rounded, MIN_SCALE, MAX_SCALE)
end

ensureDefaults()

local function applyScale(scale)
    if type(scale) ~= "number" then
        return nil, false
    end

    local rounded = formatScale(scale)
    if not rounded then
        return nil, false
    end
    local clamped = clamp(rounded, MIN_SCALE, MAX_SCALE)
    UIScaleDB.scale = clamped

    if inCombat() then
        pendingScale = clamped
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return clamped, false
    end

    local currentScale = UIParent:GetScale()
    local needsUpdate = not currentScale or math.abs(currentScale - clamped) > EPSILON
    if needsUpdate then
        UIParent:SetScale(clamped)
    end

    pendingScale = nil
    return clamped, needsUpdate
end

local function describeScale(scale)
    return string.format("%.3f", scale)
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ensureDefaults()
        applyScale(UIScaleDB.scale)
        frame:RegisterEvent("PLAYER_LOGIN")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("UI_SCALE_CHANGED")
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        applyScale(UIScaleDB.scale)
    elseif event == "UI_SCALE_CHANGED" then
        applyScale(UIScaleDB.scale)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingScale then
            local clamped, applied = applyScale(pendingScale)
            if applied then
                print("UIScale: Applied pending scale " .. describeScale(clamped) .. ".")
            end
        end
        if not pendingScale then
            frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    end
end)

frame:RegisterEvent("ADDON_LOADED")

local function printUsage()
    print("UIScale: current scale " .. describeScale(UIScaleDB.scale))
    print("Usage: /uis <scale>  (Example: /uis 0.640)")
    print("Usage: /uis reset    (Reset to the default scale of " .. describeScale(DEFAULT_SCALE) .. ")")
end

SLASH_UISCALE1 = "/uis"

SlashCmdList["UISCALE"] = function(msg)
    ensureDefaults()

    if not msg or msg == "" then
        printUsage()
        return
    end

    local command = msg:match("^%s*(%S+)")
    if not command then
        printUsage()
        return
    end

    if command:lower() == "reset" then
        local clamped, applied = applyScale(DEFAULT_SCALE)
        if not clamped then
            printUsage()
            return
        end

        if applied then
            print("UIScale: Reset to default scale " .. describeScale(clamped) .. ".")
        else
            print("UIScale: Stored default scale " .. describeScale(clamped) .. " and will apply after combat.")
        end
        return
    end

    local value = tonumber(command)
    if not value then
        printUsage()
        return
    end

    local clamped, applied = applyScale(value)
    if not clamped then
        printUsage()
        return
    end

    if applied then
        print("UIScale: Applied scale " .. describeScale(clamped) .. ".")
    else
        print("UIScale: Stored scale " .. describeScale(clamped) .. " and will apply after combat.")
    end
end
