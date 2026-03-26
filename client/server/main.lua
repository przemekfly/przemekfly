local ESX = exports['es_extended']:getSharedObject()
local storeSettings = {}
local pendingDeliveries = {}
local weeklySales = {}

local SalesPrices = {
    ['water'] = 10,
    ['bread'] = 15,
    ['phone'] = 1200
}

MySQL.ready(function()
    MySQL.query('SELECT * FROM custom_shops', {}, function(results)
        if results then
            for _, row in ipairs(results) do
                if row.settings then
                    storeSettings[row.store_id] = json.decode(row.settings)
                end
                if row.sales then
                    weeklySales[row.store_id] = json.decode(row.sales)
                end
            end
            print('^2[Shop]^7 Successfully loaded settings and charts from the database.')
        end
    end)
end)

local function SaveStoreDataToDB(storeId)
    local settingsJson = json.encode(storeSettings[storeId] or {})
    local salesJson = json.encode(weeklySales[storeId] or {0,0,0,0,0,0,0})

    MySQL.insert('INSERT INTO custom_shops (store_id, settings, sales) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE settings = ?, sales = ?', {
        storeId, settingsJson, salesJson, settingsJson, salesJson
    })
end

function SendLog(webhook, title, message)
    if not webhook or webhook == "" then return end
    local embed = {{ ["color"] = 0, ["title"] = title, ["description"] = message, ["footer"] = {["text"] = os.date("%Y-%m-%d %H:%M:%S")} }}
    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({username = "Shop Logs", embeds = embed}), { ['Content-Type'] = 'application/json' })
end

ESX.RegisterServerCallback('customShop:server:getFullData', function(source, cb, storeId)
    local jobName = Config.Stores[storeId].JobName
    local societyName = 'society_' .. jobName
    local data = {
        balance = 0,
        employees = {},
        stock = {},
        status = storeSettings[storeId] or { name = Config.Stores[storeId].Blip.Label, closed = false, webhook = "" },
        salesData = weeklySales[storeId] or {0,0,0,0,0,0,0}
    }

    TriggerEvent('esx_addonaccount:getSharedAccount', societyName, function(account)
        if account then data.balance = account.money end
    end)

    MySQL.query('SELECT identifier, firstname, lastname, job_grade FROM users WHERE job = ?', {jobName}, function(results)
        if results then
            for _, v in pairs(results) do
                table.insert(data.employees, { id = v.identifier, name = v.firstname .. " " .. v.lastname, grade = v.job_grade })
            end
        end
        
        TriggerEvent('esx_addoninventory:getSharedInventory', societyName, function(inventory)
            if inventory then
                for i=1, #inventory.items, 1 do
                    local item = inventory.items[i]
                    if item.count > 0 then
                        table.insert(data.stock, { name = item.name, label = item.label, count = item.count })
                    end
                end
            end
            cb(data)
        end)
    end)
end)

ESX.RegisterServerCallback('customShop:server:getShopItems', function(source, cb, storeId)
    local jobName = Config.Stores[storeId].JobName
    local societyName = 'society_' .. jobName
    local items = {}
    TriggerEvent('esx_addoninventory:getSharedInventory', societyName, function(inventory)
        if inventory then
            for i=1, #inventory.items, 1 do
                local item = inventory.items[i]
                if item.count > 0 then
                    table.insert(items, { 
                        name = item.name, 
                        label = item.label, 
                        count = item.count,
                        price = SalesPrices[item.name] or 50 
                    })
                end
            end
        end
        cb(items)
    end)
end)

RegisterServerEvent('customShop:server:checkoutCart')
AddEventHandler('customShop:server:checkoutCart', function(storeId, cart, method)
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    local jobName = Config.Stores[storeId].JobName
    local societyName = 'society_' .. jobName

    local totalCost = 0
    local totalItemsSold = 0

    for _, item in pairs(cart) do
        totalCost = totalCost + (item.price * item.quantity)
        totalItemsSold = totalItemsSold + item.quantity
    end

    if totalCost <= 0 then return end

    local hasMoney = false
    if method == 'cash' then
        if xPlayer.getMoney() >= totalCost then hasMoney = true end
    elseif method == 'bank' then
        if xPlayer.getAccount('bank').money >= totalCost then hasMoney = true end
    end

    if not hasMoney then
        local methodLabel = method == 'cash' and "cash" or "card funds"
        TriggerClientEvent('esx:showNotification', _source, "~r~You don't have enough " .. methodLabel .. "!")
        return
    end

    TriggerEvent('esx_addoninventory:getSharedInventory', societyName, function(inventory)
        if not inventory then return end
        
        local allInStock = true
        for _, item in pairs(cart) do
            local invItem = inventory.getItem(item.name)
            if not invItem or invItem.count < item.quantity then
                allInStock = false
                break
            end
        end

        if not allInStock then
            TriggerClientEvent('esx:showNotification', _source, "~r~Some items in your cart are sold out!")
            return
        end

        if method == 'cash' then
            xPlayer.removeMoney(totalCost)
        elseif method == 'bank' then
            xPlayer.removeAccountMoney('bank', totalCost)
        end

        for _, item in pairs(cart) do
            inventory.removeItem(item.name, item.quantity)
            xPlayer.addInventoryItem(item.name, item.quantity)
        end

        TriggerEvent('esx_addonaccount:getSharedAccount', societyName, function(account)
            if account then account.addMoney(totalCost) end
        end)

        local dayOfWeek = os.date('*t').wday
        local realDay = dayOfWeek == 1 and 7 or dayOfWeek - 1
        
        if not weeklySales[storeId] then weeklySales[storeId] = {0,0,0,0,0,0,0} end
        weeklySales[storeId][realDay] = weeklySales[storeId][realDay] + totalItemsSold
        
        SaveStoreDataToDB(storeId)

        TriggerClientEvent('esx:showNotification', _source, "Paid successfully: ~g~$" .. totalCost)
    end)
end)

RegisterServerEvent('customShop:server:bossInteract')
AddEventHandler('customShop:server:bossInteract', function(data)
    local xPlayer = ESX.GetPlayerFromId(source)
    local jobName = Config.Stores[data.store].JobName
    local societyName = 'society_' .. jobName
    local currentSettings = storeSettings[data.store] or {}

    if data.action == 'settings' then
        storeSettings[data.store] = { name = data.name, closed = data.closed, webhook = data.webhook }
        
        SaveStoreDataToDB(data.store)
        TriggerClientEvent('customShop:client:updateStatus', -1, storeSettings)
        
    elseif data.action == 'deposit' then
        local amount = tonumber(data.amount)
        if xPlayer.getMoney() >= amount then
            TriggerEvent('esx_addonaccount:getSharedAccount', societyName, function(account)
                if account then
                    xPlayer.removeMoney(amount)
                    account.addMoney(amount)
                    SendLog(currentSettings.webhook, "Finance", xPlayer.name .. " deposited $" .. amount)
                end
            end)
        end
    elseif data.action == 'withdraw' then
        local amount = tonumber(data.amount)
        TriggerEvent('esx_addonaccount:getSharedAccount', societyName, function(account)
            if account and account.money >= amount then
                account.removeMoney(amount)
                xPlayer.addMoney(amount)
                SendLog(currentSettings.webhook, "Finance", xPlayer.name .. " withdrew $" .. amount)
            end
        end)
    elseif data.action == 'fire' then
        MySQL.update('UPDATE users SET job = "unemployed", job_grade = 0 WHERE identifier = ?', {data.targetId})
    elseif data.action == 'promote' then
        MySQL.update('UPDATE users SET job_grade = job_grade + 1 WHERE identifier = ?', {data.targetId})
    elseif data.action == 'pay_bonus' then
        local amount = tonumber(data.amount)
        TriggerEvent('esx_addonaccount:getSharedAccount', societyName, function(account)
            if account and account.money >= amount then
                account.removeMoney(amount)
                local target = ESX.GetPlayerFromIdentifier(data.targetId)
                if target then target.addAccountMoney('bank', amount) end
            end
        end)
    end
end)

ESX.RegisterServerCallback('customShop:server:BuyWholesale', function(source, cb, items, storeId)
    local societyName = 'society_' .. Config.Stores[storeId].JobName
    local price = 0
    for _, v in pairs(items) do price = price + (v.price * v.amount) end

    TriggerEvent('esx_addonaccount:getSharedAccount', societyName, function(account)
        if account and account.money >= price then
            account.removeMoney(price)
            pendingDeliveries[source] = items
            cb(true)
        else cb(false) end
    end)
end)

RegisterNetEvent('customShop:server:FinishDelivery')
AddEventHandler('customShop:server:FinishDelivery', function(storeId)
    local _source = source
    local items = pendingDeliveries[_source]
    local societyName = 'society_' .. Config.Stores[storeId].JobName

    if items then
        TriggerEvent('esx_addoninventory:getSharedInventory', societyName, function(inventory)
            if inventory then
                for _, v in pairs(items) do
                    inventory.addItem(v.name, v.amount)
                end
            end
        end)
        pendingDeliveries[_source] = nil
    end
end)

RegisterServerEvent('customShop:server:syncStatus')
AddEventHandler('customShop:server:syncStatus', function()
    TriggerClientEvent('customShop:client:updateStatus', source, storeSettings)
end)
