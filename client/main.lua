local ESX = exports['es_extended']:getSharedObject()
local PlayerData = {}
local isDelivering = false
local deliveryVehicle = nil
local currentDeliveryStore = nil
local storeStatus = {}
local storeBlips = {}

function DrawText3D(coords, text)
    local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z + 0.5)
    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextColour(255, 255, 255, 215)
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
    end
end

function RefreshBlips()
    for _, blip in pairs(storeBlips) do RemoveBlip(blip) end
    storeBlips = {}

    for k, v in pairs(Config.Stores) do
        local label = v.Blip.Label
        if storeStatus[k] and storeStatus[k].name then
            label = storeStatus[k].name
        end
        
        if storeStatus[k] and storeStatus[k].closed then
            label = label .. " (Closed)"
        else
            label = label .. " (Open)"
        end

        local blip = AddBlipForCoord(v.Locations.Shop)
        SetBlipSprite(blip, v.Blip.Id)
        SetBlipScale(blip, v.Blip.Scale)
        SetBlipColour(blip, v.Blip.Color)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(label)
        EndTextCommandSetBlipName(blip)
        storeBlips[k] = blip
    end
end

function OpenCustomerShop(storeId)
    ESX.TriggerServerCallback('customShop:server:getShopItems', function(items)
        if #items == 0 then 
            ESX.ShowNotification("The shop is empty!")
            return 
        end
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "openCustomerShop",
            store = storeId,
            storeName = storeStatus[storeId] and storeStatus[storeId].name or Config.Stores[storeId].Blip.Label,
            items = items
        })
    end, storeId)
end

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    Wait(1000)
    PlayerData = ESX.GetPlayerData()
    TriggerServerEvent('customShop:server:syncStatus')
end)

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(xPlayer)
    PlayerData = xPlayer
    TriggerServerEvent('customShop:server:syncStatus')
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job) PlayerData.job = job end)

RegisterNetEvent('customShop:client:updateStatus')
AddEventHandler('customShop:client:updateStatus', function(data) 
    storeStatus = data 
    RefreshBlips()
end)

CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        local hasJobForWholesale = false
        local myStoreId = nil
        for id, d in pairs(Config.Stores) do
            if PlayerData.job and PlayerData.job.name == d.JobName then 
                hasJobForWholesale = true 
                myStoreId = id
                break 
            end
        end

        if hasJobForWholesale and not isDelivering then
            local distWholesale = #(coords - Config.Wholesale.PedCoords)
            if distWholesale < 10.0 then
                sleep = 0
                DrawMarker(29, Config.Wholesale.PedCoords.x, Config.Wholesale.PedCoords.y, Config.Wholesale.PedCoords.z, 0,0,0,0,0,0, 0.5, 0.5, 0.5, 255, 255, 255, 100, false, true, 2, true)
                if distWholesale < 1.5 then
                    DrawText3D(Config.Wholesale.PedCoords, "[~w~E~w~] WHOLESALE")
                    if IsControlJustReleased(0, 38) then
                        SetNuiFocus(true, true)
                        SendNUIMessage({ action = "openWholesale", items = Config.WholesaleItems, store = myStoreId })
                    end
                end
            end
        end

        for storeId, data in pairs(Config.Stores) do
            local distShop = #(coords - data.Locations.Shop)
            if distShop < 5.0 then
                sleep = 0
                DrawMarker(2, data.Locations.Shop, 0,0,0,0,0,0, 0.2, 0.2, 0.2, 255, 255, 255, 150, 0, 1, 2, 0)
                if distShop < 1.3 and IsControlJustReleased(0, 38) then 
                    if storeStatus[storeId] and storeStatus[storeId].closed then
                        ESX.ShowNotification("The shop is currently closed.")
                    else
                        OpenCustomerShop(storeId)
                    end
                end
            end

            if PlayerData.job and PlayerData.job.name == data.JobName and PlayerData.job.grade_name == 'boss' then
                local distBoss = #(coords - data.Locations.BossMenu)
                if distBoss < 5.0 then
                    sleep = 0
                    DrawMarker(22, data.Locations.BossMenu, 0,0,0,0,0,0, 0.2, 0.2, 0.2, 255, 255, 255, 150, 0, 1, 2, 0)
                    if distBoss < 1.3 and IsControlJustReleased(0, 38) then OpenBossMenu(storeId) end
                end
            end

            if isDelivering and currentDeliveryStore == storeId then
                local unloadPos = data.Locations.DeliveryUnload
                if #(coords - unloadPos) < 10.0 then
                    sleep = 0
                    DrawMarker(1, unloadPos - vector3(0,0,1.0), 0,0,0,0,0,0, 3.0, 3.0, 1.0, 255, 255, 255, 50, 0, 0, 2, 0)
                    if #(coords - unloadPos) < 3.0 and IsPedInAnyVehicle(ped, false) then
                        DrawText3D(unloadPos, "[~w~E~w~] UNLOAD")
                        if IsControlJustReleased(0, 38) then FinishDelivery() end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

function OpenBossMenu(id)
    ESX.TriggerServerCallback('customShop:server:getFullData', function(data)
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "openBossMenu",
            store = id,
            balance = data.balance,
            storeName = storeStatus[id] and storeStatus[id].name or Config.Stores[id].Blip.Label,
            employees = data.employees,
            stock = data.stock,
            status = data.status,
            salesData = data.salesData
        })
    end, id)
end

function FinishDelivery()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= deliveryVehicle then return end
    FreezeEntityPosition(veh, true)
    
    local storeIdCache = currentDeliveryStore
    isDelivering = false
    currentDeliveryStore = nil

    CreateThread(function()
        local time = 10000
        local timer = GetGameTimer() + time
        
        while GetGameTimer() < timer do
            Wait(20)
            local coords = GetEntityCoords(veh)
            local timeLeft = math.ceil((timer - GetGameTimer()) / 1000)
            local progress = 1.0 - ((timer - GetGameTimer()) / time)
            
            local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z + 2.0)
            
            SendNUIMessage({
                action = "updateProgress",
                show = true,
                onScreen = onScreen,
                x = _x,
                y = _y,
                timeLeft = timeLeft,
                progress = progress
            })
        end
        
        SendNUIMessage({ action = "updateProgress", show = false })
        
        FreezeEntityPosition(veh, false)
        ESX.Game.DeleteVehicle(veh)
        TriggerServerEvent('customShop:server:FinishDelivery', storeIdCache)
        ESX.ShowNotification("~g~Delivery completed successfully!")
    end)
end

RegisterNUICallback('closeUI', function(data, cb) SetNuiFocus(false, false); cb('ok') end)

RegisterNUICallback('bossInteract', function(data, cb)
    TriggerServerEvent('customShop:server:bossInteract', data)
    Wait(500)
    if data.action ~= 'settings' then OpenBossMenu(data.store) end
    cb('ok')
end)

RegisterNUICallback('checkoutCart', function(data, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent('customShop:server:checkoutCart', data.store, data.cart, data.method)
    cb('ok')
end)

RegisterNUICallback('buyWholesale', function(data, cb)
    SetNuiFocus(false, false)
    ESX.TriggerServerCallback('customShop:server:BuyWholesale', function(success)
        if success then
            isDelivering = true
            currentDeliveryStore = data.store
            local spawn = Config.Wholesale.VehicleSpawn
            ESX.Game.SpawnVehicle(Config.Wholesale.VehicleModel, vector3(spawn.x, spawn.y, spawn.z), spawn.w, function(veh)
                deliveryVehicle = veh
                TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
                SetNewWaypoint(Config.Stores[data.store].Locations.DeliveryUnload.x, Config.Stores[data.store].Locations.DeliveryUnload.y)
            end)
        else
            ESX.ShowNotification("Not enough funds in the company account!")
        end
    end, data.items, data.store)
    cb('ok')
end)
