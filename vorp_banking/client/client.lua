local VORPcore = exports.vorp_core:GetCore()
local prompts = GetRandomIntInRange(0, 0xffffff)
local PromptGroup2 = GetRandomIntInRange(0, 0xffffff)
local openmenu
local CloseBanks
local inmenu = false
local T = Translation.Langs[Config.Lang]

local currentBankName = nil

local function closeMenu()
    SetNuiFocus(false, false)
    inmenu = false
    currentBankName = nil
    ClearPedTasks(PlayerPedId())
    DisplayRadar(true)
end

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        for _, v in pairs(Config.banks) do
            if v.BlipHandle then
                RemoveBlip(v.BlipHandle)
            end
            if v.NPC then
                DeleteEntity(v.NPC)
                DeletePed(v.NPC)
                SetEntityAsNoLongerNeeded(v.NPC)
            end
        end
        DisplayRadar(true)
        -- MenuData.CloseAll()
        ClearPedTasks(PlayerPedId(), true, true)
        SetNuiFocus(false, false)
    end
end)

-- Refresh UI after transaction
RegisterNetEvent('vorp_banking:client:refresh')
AddEventHandler('vorp_banking:client:refresh', function(bankName)
    if not inmenu then return end
    local nameToRefresh = bankName or currentBankName
    if not nameToRefresh then return end

    local data = VORPcore.Callback.TriggerAwait('vorp_bank:getinfo', nameToRefresh)
    local bankinfo = data[1]
    local allbanks = data[2]
    Openbank(nameToRefresh, bankinfo, allbanks)
end)

-- Close menu on ESC
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if inmenu and IsControlJustReleased(0, 322) then -- 322 is ESC
            TriggerServerEvent('vorp_banking:server:closeMenu')
            closeMenu()
        end
    end
end)

-- NUI Callbacks
RegisterNUICallback('close', function(data, cb)
    closeMenu()
    SendNUIMessage({ type = "close" })
    cb('ok')
end)

RegisterNUICallback('depositCash', function(data, cb)
    TriggerServerEvent("vorp_bank:depositcash", tonumber(data.amount), data.city, data.bankinfo)
    cb('ok')
end)

RegisterNUICallback('withdrawCash', function(data, cb)
    TriggerServerEvent("vorp_bank:withcash", tonumber(data.amount), data.city, data.bankinfo)
    cb('ok')
end)

RegisterNUICallback('depositGold', function(data, cb)
    TriggerServerEvent("vorp_bank:depositgold", tonumber(data.amount), data.city, data.bankinfo)
    cb('ok')
end)

RegisterNUICallback('withdrawGold', function(data, cb)
    TriggerServerEvent("vorp_bank:withgold", tonumber(data.amount), data.city, data.bankinfo)
    cb('ok')
end)

RegisterNUICallback('transfer', function(data, cb)
    TriggerServerEvent("vorp_bank:transfer", tonumber(data.amount), data.fromCity, data.toCity)
    cb('ok')
end)

RegisterNUICallback('collectSalary', function(data, cb)
    TriggerServerEvent("vorp_banking:server:collectSalary", data.city)
    cb('ok')
end)

---------------- BLIPS ---------------------
local function addBlip(index)
    if Config.banks[index].blipAllowed then
        local blip = BlipAddForCoords(1664425300, Config.banks[index].BankLocation.x, Config.banks[index].BankLocation.y, Config.banks[index].BankLocation.z)
        SetBlipSprite(blip, Config.banks[index].blipsprite, true)
        SetBlipScale(blip, 0.2)
        SetBlipName(blip, Config.banks[index].name)
        Config.banks[index].BlipHandle = blip
    end
end

---------------- NPC ---------------------
local function loadModel(model)
    if not HasModelLoaded(model) then
        RequestModel(model, false)
        repeat Wait(0) until HasModelLoaded(model)
    end
end

local function spawnNPC(index)
    local v = Config.banks[index]
    loadModel(v.NpcModel)
    local npc = CreatePed(joaat(v.NpcModel), v.NpcPosition.x, v.NpcPosition.y, v.NpcPosition.z, v.NpcPosition.h, false, false, false, false)
    repeat Wait(0) until DoesEntityExist(npc)
    PlaceEntityOnGroundProperly(npc, true)
    Citizen.InvokeNative(0x283978A15512B2FE, npc, true)
    SetEntityCanBeDamaged(npc, false)
    SetEntityInvincible(npc, true)
    Wait(1000)
    TaskStandStill(npc, -1)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetModelAsNoLongerNeeded(v.NpcModel)
    Config.banks[index].NPC = npc
end

local function promptSetUp()
    local str = T.openmenu
    openmenu = UiPromptRegisterBegin()
    UiPromptSetControlAction(openmenu, Config.Key)
    str = VarString(10, 'LITERAL_STRING', str)
    UiPromptSetText(openmenu, str)
    UiPromptSetEnabled(openmenu, true)
    UiPromptSetVisible(openmenu, true)
    UiPromptSetStandardMode(openmenu, true)
    UiPromptSetGroup(openmenu, prompts, 0)
    UiPromptRegisterEnd(openmenu)
end

local function promptSetUp2()
    local str = T.closemenu
    CloseBanks = UiPromptRegisterBegin()
    UiPromptSetControlAction(CloseBanks, Config.Key)
    str = VarString(10, 'LITERAL_STRING', str)
    UiPromptSetText(CloseBanks, str)
    UiPromptSetEnabled(CloseBanks, true)
    UiPromptSetVisible(CloseBanks, true)
    UiPromptSetStandardMode(CloseBanks, true)
    UiPromptSetGroup(CloseBanks, PromptGroup2, 0)
    UiPromptRegisterEnd(CloseBanks)
end

local function getDistance(config)
    local coords = GetEntityCoords(PlayerPedId())
    local coords2 = vector3(config.x, config.y, config.z)
    return #(coords - coords2)
end

local function createNpcByDistance(distance, index)
    if Config.banks[index].NpcAllowed then
        if distance <= 40 then
            if not Config.banks[index].NPC then
                spawnNPC(index)
            end
        else
            if Config.banks[index].NPC then
                SetEntityAsNoLongerNeeded(Config.banks[index].NPC)
                DeleteEntity(Config.banks[index].NPC)
                Config.banks[index].NPC = nil
            end
        end
    end
end

local function getBankInfo(bankConfig)
    local result = VORPcore.Callback.TriggerAwait("vorp_bank:getinfo", bankConfig.city)
    Openbank(bankConfig.city, result[1], result[2])
    TaskStandStill(PlayerPedId(), -1)
    DisplayRadar(false)
end

CreateThread(function()
    repeat Wait(5000) until LocalPlayer.state.IsInSession
    promptSetUp()
    promptSetUp2()

    while true do
        local sleep = 1000
        local player = PlayerPedId()
        local dead = IsEntityDead(player)

        if not inmenu and not dead then
            for index, bankConfig in pairs(Config.banks) do
                if bankConfig.StoreHoursAllowed then
                    local hour = GetClockHours()
                    if hour >= bankConfig.StoreClose or hour < bankConfig.StoreOpen then
                        if not Config.banks[index].BlipHandle and bankConfig.blipAllowed then
                            addBlip(index)
                        end

                        if Config.banks[index].BlipHandle then
                            BlipAddModifier(Config.banks[index].BlipHandle, joaat('BLIP_MODIFIER_MP_COLOR_10'))
                        end

                        if Config.banks[index].NPC then
                            DeleteEntity(Config.banks[index].NPC)
                            DeletePed(Config.banks[index].NPC)
                            SetEntityAsNoLongerNeeded(Config.banks[index].NPC)
                            Config.banks[index].NPC = nil
                        end

                        local distance = getDistance(bankConfig.BankLocation)

                        if distance <= bankConfig.distOpen then
                            sleep = 0
                            local label2 = VarString(10, 'LITERAL_STRING', T.openHours .. " " .. bankConfig.StoreOpen .. T.amTimeZone .. " - " .. bankConfig.StoreClose .. T.pmTimeZone)
                            UiPromptSetActiveGroupThisFrame(PromptGroup2, label2, 0, 0, 0, 0)

                            if UiPromptHasStandardModeCompleted(CloseBanks, 0) then
                                Wait(1000)
                                VORPcore.NotifyRightTip(T.closed, 4000)
                            end
                        end
                    elseif hour >= bankConfig.StoreOpen then
                        if not Config.banks[index].BlipHandle and bankConfig.blipAllowed then
                            addBlip(index)
                        end

                        if Config.banks[index].BlipHandle then
                            BlipAddModifier(Config.banks[index].BlipHandle, joaat('BLIP_MODIFIER_MP_COLOR_32'))
                        end

                        local distance = getDistance(bankConfig.BankLocation)
                        createNpcByDistance(distance, index)
                        if distance <= bankConfig.distOpen then
                            sleep = 0

                            local label = VarString(10, 'LITERAL_STRING', T.bank .. " " .. bankConfig.name)
                            UiPromptSetActiveGroupThisFrame(prompts, label, 0, 0, 0, 0)

                            if UiPromptHasStandardModeCompleted(openmenu, 0) then
                                inmenu = true
                                getBankInfo(bankConfig)
                            end
                        end
                    end
                else
                    local distance = getDistance(bankConfig.BankLocation)
                    if not Config.banks[index].BlipHandle and bankConfig.blipAllowed then
                        addBlip(index)
                    end

                    createNpcByDistance(distance, index)

                    if distance <= bankConfig.distOpen then
                        sleep = 0
                        local label = VarString(10, 'LITERAL_STRING', T.bank .. " " .. bankConfig.name)
                        UiPromptSetActiveGroupThisFrame(prompts, label, 0, 0, 0, 0)

                        if UiPromptHasStandardModeCompleted(openmenu, 0) then
                            inmenu = true
                            getBankInfo(bankConfig)
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

function Openbank(bankName, bankinfo, allbanks)
    SetNuiFocus(true, true)
    inmenu = true
    currentBankName = bankName
    
    local data = {
        type = "open",
        bankName = bankName,
        bankinfo = bankinfo,
        allbanks = allbanks,
        config = Config.banks[bankName]
    }
    
    SendNUIMessage(data)
end

function Openallbanks(bankName, allbanks)
    -- This should now be handled within the NUI if needed.
    -- For now, just close or log it.
end
