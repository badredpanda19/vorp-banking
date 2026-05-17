local VORPcore = exports.vorp_core:GetCore()
local T = Translation.Langs[Config.Lang]

-- Helper to resolve ID
local function resolveID(charOrSource)
    if not charOrSource then return nil, nil end
    
    -- If it's already a string identifier (contains a colon)
    if type(charOrSource) == "string" and string.find(charOrSource, ":") then
        return charOrSource, nil
    end

    local id = tonumber(charOrSource)
    if not id then return charOrSource, nil end

    -- If ID is small (likely a Server ID), try to find the player
    if id < 100000 then 
        local user = VORPcore.getUser(id)
        if user and user.getUsedCharacter then
            print("^2[vorp_banking] Resolved Server ID^0", id, "^2to Character ID^0", user.getUsedCharacter.charIdentifier)
            return user.getUsedCharacter.charIdentifier, user
        end
    end

    -- If not a server ID or player not found, treat as raw Character ID (e.g. 82717279)
    print("^2[vorp_banking] Using raw Character ID^0", id)
    return id, nil
end

-- Salary Exports
exports('GetUnpaidSalary', function(charOrSource)
    local charIdentifier, user = resolveID(charOrSource)
    local identifier = nil
    
    -- If charIdentifier is already a string identifier (e.g. steam:xxx)
    if type(charIdentifier) == "string" and string.find(charIdentifier, ":") then
        identifier = charIdentifier
    elseif user then
        identifier = user.getUsedCharacter.identifier
    else
        -- If player is offline, try to find their identifier from the bank_users table first
        identifier = MySQL.scalar.await("SELECT identifier FROM bank_users WHERE charidentifier = @charid LIMIT 1", { charid = charIdentifier })
        if not identifier then
            -- Fallback to characters table
            identifier = MySQL.scalar.await("SELECT identifier FROM characters WHERE charidentifier = @charid OR crimson_id = @charid LIMIT 1", { charid = charIdentifier })
        end
    end

    local result
    if identifier then
        -- Search by permanent identifier to catch everything
        result = MySQL.scalar.await("SELECT SUM(unpaid_salary) FROM bank_users WHERE identifier = @identifier", { identifier = identifier })
    else
        -- Fallback to just the ID if we can't find an identifier
        result = MySQL.scalar.await("SELECT SUM(unpaid_salary) FROM bank_users WHERE charidentifier = @charidentifier", { charidentifier = charIdentifier })
    end
    
    return result or 0.0
end)

exports('PaySalaryToMember', function(charOrSource, amount, societyName)
    local charIdentifier, user = resolveID(charOrSource)
    print("^2[vorp_banking] PaySalaryToMember called:^0", charIdentifier, amount, societyName)
    local updateName = societyName and ("Salary: " .. societyName) or nil
    local result

    if updateName then
        result = MySQL.update.await("UPDATE bank_users SET unpaid_salary = unpaid_salary + @amount WHERE charidentifier = @charidentifier AND name = @name", { 
            amount = amount, 
            charidentifier = charIdentifier,
            name = updateName
        })
    else
        result = MySQL.update.await("UPDATE bank_users SET unpaid_salary = unpaid_salary + @amount WHERE charidentifier = @charidentifier AND name NOT LIKE 'Salary: %' LIMIT 1", { 
            amount = amount, 
            charidentifier = charIdentifier 
        })
    end
    
    if result == 0 then
        print("^3[vorp_banking] No row found for salary update, attempting to create one...^0")
        local identifier = nil
        
        if user then
            identifier = user.getUsedCharacter.identifier
            print("^2[vorp_banking] Found online player identifier:^0", identifier)
        end

        if not identifier then
            -- Safely find which column exists to avoid SQL errors
            local charTable = MySQL.query.await("SHOW COLUMNS FROM characters")
            local columnToUse = nil
            
            if charTable then
                for _, col in ipairs(charTable) do
                    if col.Field == "crimson_id" then
                        columnToUse = "crimson_id"
                        break
                    elseif col.Field == "charidentifier" then
                        columnToUse = "charidentifier"
                    end
                end
            end

            if columnToUse then
                print("^2[vorp_banking] Using database column:^0", columnToUse)
                identifier = MySQL.scalar.await("SELECT identifier FROM characters WHERE " .. columnToUse .. " = @id", { id = charIdentifier })
            else
                print("^1[vorp_banking] ERROR: Could not find a valid ID column (charidentifier or crimson_id) in characters table!^0")
            end
            
            print("^2[vorp_banking] DB Lookup for identifier:^0", identifier)
        end

        if identifier then
            local insertName = updateName or ""
            print("^2[vorp_banking] Inserting new salary row:^0", insertName, "for", charIdentifier)
            MySQL.insert.await("INSERT INTO bank_users (name, identifier, charidentifier, money, gold, invspace, unpaid_salary) VALUES (@name, @identifier, @charidentifier, 0, 0, 10, @amount)", {
                name = insertName,
                identifier = identifier,
                charidentifier = charIdentifier,
                amount = amount
            })
            return true
        else
            print("^1[vorp_banking] ERROR: Could not find identifier for character ID:^0", charIdentifier)
        end
        return false
    end
    print("^2[vorp_banking] Successfully updated existing salary row.^0")
    return true
end)

local function registerStorage(bankName, bankId, invspace)
    local isRegistered = exports.vorp_inventory:isCustomInventoryRegistered(bankId)
    if not isRegistered then
        local data = {
            id = bankId,
            name = bankName,
            limit = invspace,
            acceptWeapons = Config.banks[bankName].canStoreWeapons,
            shared = true,
            ignoreItemStackLimit = true,
            webhook = Config.CustomInventoryWebhook, -- add here your webhook url for discord logging
        }
        exports.vorp_inventory:registerInventory(data)
        Wait(200)
    end
end

local function IsNearBank(source, bankName)
    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)
    local bankLocation = Config.banks[bankName].BankLocation
    local distance = #(playerCoords - vector3(bankLocation.x, bankLocation.y, bankLocation.z))

    if distance <= Config.banks[bankName].distOpen + 10.0 then -- Adjusted Distance check to make sure it's within range (if any bank is facing issue then you can increase this value)
        return true
    else
        return false
    end
end

RegisterCommand("testsalary", function(source, args, rawCommand)
    if source ~= 0 then
        local user = VORPcore.getUser(source)
        if user and user.getGroup == "admin" then
            local targetId = tonumber(args[1])
            local amount = tonumber(args[2])
            local society = args[3] or "TestSociety"

            if targetId and amount then
                print("^2[vorp_banking] Running testsalary for ID:^0", targetId, "Amount:", amount, "Society:", society)
                
                local balance = exports['crimsonrp-society']:GetSocietyBalance(society)
                print("^2[vorp_banking] Test Society Balance for^0", society, "^2is:^0", balance)

                -- Call PaySalaryToMember directly to bypass society balance check
                local success = exports['vorp_banking']:PaySalaryToMember(targetId, amount, society)
                if success then
                    -- Resolve the ID to ensure we refresh the correct player
                    local charID, _ = resolveID(targetId)
                    
                    local players = GetPlayers()
                    for _, playerId in ipairs(players) do
                        local playerUser = VORPcore.getUser(tonumber(playerId))
                        if playerUser and playerUser.getUsedCharacter and playerUser.getUsedCharacter.charIdentifier == charID then
                            TriggerClientEvent('vorp_banking:client:refresh', tonumber(playerId))
                            break
                        end
                    end
                    VORPcore.NotifyRightTip(source, "Test salary processed for Char ID " .. charID, 4000)
                else
                    VORPcore.NotifyRightTip(source, "Test salary failed (Check logs)", 4000)
                end
            else
                VORPcore.NotifyRightTip(source, "Usage: /testsalary [id] [amount] [society]", 4000)
            end
        end
    end
end, false)

VORPcore.Callback.Register('vorp_bank:getinfo', function(source, cb, bankName)
    local _source = source
    local Character = VORPcore.getUser(_source).getUsedCharacter
    local charidentifier = Character.charIdentifier
    local identifier = Character.identifier
    local allBanks = {}

    -- Search by permanent identifier to find all linked rows (legacy IDs and Crimson IDs)
    MySQL.query("SELECT * FROM bank_users WHERE identifier = @identifier",
        { identifier = identifier }, function(allRows)
            local salaries = {}
            local totalSalary = 0
            local filteredBanks = {}
            local currentBankInfo = nil

            if allRows then
                for _, row in ipairs(allRows) do
                    -- Count all unpaid salaries across all rows linked to this steam/license
                    if row.unpaid_salary > 0 then
                        totalSalary = totalSalary + row.unpaid_salary
                        
                        if string.sub(row.name, 1, 8) == "Salary: " then
                            table.insert(salaries, { name = string.sub(row.name, 9), amount = row.unpaid_salary })
                        else
                            -- If it's a normal bank row with salary, add it to general
                            table.insert(salaries, { name = "society paycheck ("..row.name..")", amount = row.unpaid_salary })
                        end
                    end

                    -- Separate bank accounts from salary storage rows
                    if string.sub(row.name, 1, 8) ~= "Salary: " then
                        row.salary = row.unpaid_salary
                        table.insert(filteredBanks, row)
                        
                        -- Keep track of the specific bank the player is currently visiting
                        if row.name == bankName then
                            currentBankInfo = row
                        end
                    end
                end
            end

            -- If they are at a bank they don't have an account at yet, create it
            if not currentBankInfo then
                local defaultInvspace = 10
                local parameters = {
                    name = bankName,
                    identifier = identifier,
                    charidentifier = charidentifier,
                    money = 0,
                    gold = 0,
                    invspace = defaultInvspace
                }
                MySQL.insert.await("INSERT INTO bank_users (name, identifier, charidentifier, money, gold, invspace) VALUES (@name, @identifier, @charidentifier, @money, @gold, @invspace)", parameters)
                
                currentBankInfo = { 
                    name = bankName, 
                    money = 0, 
                    gold = 0, 
                    invspace = defaultInvspace, 
                    charidentifier = charidentifier,
                    identifier = identifier
                }
                table.insert(filteredBanks, currentBankInfo)
            end

            -- Finalize data for UI
            local charName = Character.firstname .. " " .. Character.lastname
            local bankinfo = { 
                money = currentBankInfo.money, 
                gold = currentBankInfo.gold, 
                invspace = currentBankInfo.invspace, 
                name = bankName, 
                salary = totalSalary, -- TOTAL across all linked IDs
                salaries = salaries,  -- BREAKDOWN by source
                charName = charName,
                accountID = "ACC: " .. (1000 + charidentifier)
            }

            print("^2[vorp_banking] Sending aggregated info to UI for^0", charName, "^2Total Salary:^0", totalSalary)
            return cb({ bankinfo, filteredBanks })
        end)
end)

RegisterServerEvent('vorp_bank:UpgradeSafeBox', function(slotsToBuy, currentspace, bankName)
    local _source        = source
    local Character      = VORPcore.getUser(_source).getUsedCharacter
    local charidentifier = Character.charIdentifier
    local money          = Character.money

    local maxslots       = Config.banks[bankName].maxslots
    local costslot       = Config.banks[bankName].costslot
    local name           = Config.banks[bankName].city

    local amountToPay    = costslot * slotsToBuy
    local FinalSlots     = currentspace + slotsToBuy

    if not IsNearBank(_source, bankName) then
        return VORPcore.NotifyRightTip(_source, T.notnear, 4000)
    end

    if money < amountToPay then
        return VORPcore.NotifyRightTip(_source, T.nomoney, 4000)
    end

    if FinalSlots > maxslots then
        return VORPcore.NotifyRightTip(_source, T.maxslots .. " | " .. slotsToBuy .. " / " .. maxslots, 4000)
    end

    Character.removeCurrency(0, amountToPay)
    local Parameters = { ['charidentifier'] = charidentifier, ['invspace'] = FinalSlots, ['name'] = name }
    MySQL.update("UPDATE bank_users SET invspace=@invspace WHERE charidentifier=@charidentifier AND name = @name", Parameters)
    local bankId = "vorp_banking_" .. bankName .. "_" .. charidentifier
    registerStorage(bankName, bankId, currentspace)
    exports.vorp_inventory:updateCustomInventorySlots(bankId, FinalSlots)
    VORPcore.NotifyRightTip(_source, T.success .. (costslot * slotsToBuy) .. " | " .. FinalSlots .. " / " .. maxslots, 4000)
end)

DiscordLogs = function(transactionAmount, bankName, playerName, transactionType, targetBankName, currencyType, itemName)
    local logTitle = T.Webhooks.LogTitle
    local webhookURL, logMessage = "", ""
    local currencySymbol = currencyType == "gold" and "G" or "$"

    if transactionType == "withdraw" then
        webhookURL = Config.WithdrawLogWebhook
        logMessage = string.format(T.Webhooks.WithdrawLogDescription, playerName, transactionAmount .. currencySymbol, bankName)
    elseif transactionType == "deposit" then
        webhookURL = Config.DepositLogWebhook
        logMessage = string.format(T.Webhooks.DepositLogDescription, playerName, transactionAmount .. currencySymbol, bankName)
    elseif transactionType == "transfer" then
        webhookURL = Config.TransferLogWebhook
        logMessage = string.format(T.Webhooks.TransferLogDescription, playerName, transactionAmount .. currencySymbol, bankName, targetBankName)
    elseif transactionType == "take" then
        webhookURL = Config.TakeLogWebhook
        logMessage = string.format(T.Webhooks.TakeLogDescription, playerName, transactionAmount, itemName, bankName)
    elseif transactionType == "move" then
        webhookURL = Config.MoveLogWebhook
        logMessage = string.format(T.Webhooks.MoveLogDescription, playerName, transactionAmount, itemName, bankName)
    end

    VORPcore.AddWebhook(logTitle, webhookURL, logMessage)
end

local function IsNearAnyBank(source)
    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)
    for _, bank in pairs(Config.banks) do
        local bankLocation = bank.BankLocation
        local distance = #(playerCoords - vector3(bankLocation.x, bankLocation.y, bankLocation.z))
        if distance <= (bank.distOpen or 3.5) + 10.0 then
            return true
        end
    end
    return false
end

RegisterServerEvent('vorp_bank:transfer', function(amount, fromBank, toBank)
    local _source = source
    local Character = VORPcore.getUser(_source).getUsedCharacter
    local playerFullName = Character.firstname .. ' ' .. Character.lastname
    local characterId = Character.charIdentifier

    if not IsNearAnyBank(_source) then
        return VORPcore.NotifyRightTip(_source, T.notnear, 4000)
    end

    local queryResult = MySQL.query.await("SELECT * FROM bank_users WHERE charidentifier = @characterId;", { characterId = characterId })
    local bankAccounts = {}
    if queryResult then
        for _, bank in pairs(queryResult) do
            bankAccounts[bank.name] = bank
        end

        if not bankAccounts[fromBank] or not bankAccounts[toBank] then
            return VORPcore.NotifyRightTip(_source, T.invalid, 4000)
        end

        if bankAccounts[fromBank].money >= amount then
            local newBalanceFrom = bankAccounts[fromBank].money - amount
            local newBalanceTo = bankAccounts[toBank].money + (amount * Config.feeamount)

            local updateFromResult = MySQL.update.await("UPDATE bank_users SET money = @newBalance WHERE charidentifier = @characterId AND name = @fromBank;", { newBalance = newBalanceFrom, characterId = characterId, fromBank = fromBank })

            if updateFromResult then
                local updateToResult = MySQL.update.await("UPDATE bank_users SET money = @newBalance WHERE charidentifier = @characterId AND name = @toBank;", { newBalance = newBalanceTo, characterId = characterId, toBank = toBank })

                if updateToResult then
                    local transferredAmount = amount * Config.feeamount
                    transferredAmount = string.format("%.2f", transferredAmount)
                    DiscordLogs(transferredAmount, fromBank, playerFullName, "transfer", toBank, "cash")
                    local msg = string.format(T.transfer .. " %s $" .. T.to .. " %s " .. T.transferred, transferredAmount, toBank)
                    VORPcore.NotifyRightTip(_source, msg, 4000)
                    TriggerClientEvent('vorp_banking:client:refresh', _source, fromBank)
                else
                    -- Second update failed
                end
            else
                -- First update failed
            end
        else
            VORPcore.NotifyRightTip(_source, T.noaccmoney, 4000)
        end
    end
end)

RegisterServerEvent('vorp_bank:depositcash', function(amount, bankName)
    local _source = source
    local playerCharacter = VORPcore.getUser(_source).getUsedCharacter
    local characterId = playerCharacter.charIdentifier
    local playerCash = playerCharacter.money

    if not IsNearBank(_source, bankName) then
        return VORPcore.NotifyRightTip(_source, T.notnear, 4000)
    end

    if playerCash >= amount then
        MySQL.query("SELECT money FROM bank_users WHERE charidentifier = @characterId AND name = @bankName", { characterId = characterId, bankName = bankName }, function(result)
            if result[1] then
                playerCharacter.removeCurrency(0, amount)
                DiscordLogs(amount, bankName, playerCharacter.firstname .. ' ' .. playerCharacter.lastname, "deposit", "cash")
                local newBalance = result[1].money + amount
                MySQL.update("UPDATE bank_users SET money=@newBalance WHERE charidentifier=@characterId AND name = @bankName", { characterId = characterId, newBalance = newBalance, bankName = bankName }, function()
                    TriggerClientEvent('vorp_banking:client:refresh', _source, bankName)
                end)
                VORPcore.NotifyRightTip(_source, T.youdepo .. amount, 4000)
            end
        end)
    else
        VORPcore.NotifyRightTip(_source, T.invalid, 4000)
    end
end)

RegisterServerEvent('vorp_bank:depositgold', function(amount, bankName)
    local _source = source
    local playerCharacter = VORPcore.getUser(_source).getUsedCharacter
    local characterId = playerCharacter.charIdentifier
    local playerGold = playerCharacter.gold

    if not IsNearBank(_source, bankName) then
        return VORPcore.NotifyRightTip(_source, T.notnear, 4000)
    end

    if playerGold >= amount then
        playerCharacter.removeCurrency(1, amount)
        MySQL.update("UPDATE bank_users SET gold = gold + @amount WHERE charidentifier = @characterId AND name = @bankName", { charidentifier = characterId, amount = amount, bankName = bankName }, function()
            TriggerClientEvent('vorp_banking:client:refresh', _source, bankName)
        end)
        VORPcore.NotifyRightTip(_source, T.youdepog .. amount, 4000)
    else
        VORPcore.NotifyRightTip(_source, T.invalid, 4000)
    end
end)


local lastMoney = {}

RegisterServerEvent('vorp_bank:withcash', function(amount, bankName)
    local _source = source
    local Character = VORPcore.getUser(_source).getUsedCharacter
    local playerFullName = Character.firstname .. ' ' .. Character.lastname
    local characterId = Character.charIdentifier

    if not IsNearBank(_source, bankName) then
        return VORPcore.NotifyRightTip(_source, T.notnear, 4000)
    end

    MySQL.query("SELECT money FROM bank_users WHERE charidentifier = @characterId AND name = @bankName", { characterId = characterId, bankName = bankName }, function(result)
        if result[1] then
            local bankBalance = result[1].money
            if bankBalance >= amount then
                if not lastMoney[_source] or lastMoney[_source] ~= bankBalance then
                    local newBalance = bankBalance - amount
                    MySQL.update("UPDATE bank_users SET money=@newBalance WHERE charidentifier=@characterId AND name = @bankName", { characterId = characterId, newBalance = newBalance, bankName = bankName }, function()
                        TriggerClientEvent('vorp_banking:client:refresh', _source, bankName)
                    end)
                    lastMoney[_source] = bankBalance
                    Character.addCurrency(0, amount)
                    DiscordLogs(amount, bankName, playerFullName, "withdraw", "cash")
                    VORPcore.NotifyRightTip(_source, T.withdrew .. amount, 4000)
                end
            else
                VORPcore.NotifyRightTip(_source, T.invalid .. amount, 4000)
            end
        end
    end)
end)

RegisterServerEvent('vorp_bank:withgold', function(amount, bankName)
    local _source = source
    local playerCharacter = VORPcore.getUser(_source).getUsedCharacter
    local playerFullName = playerCharacter.firstname .. ' ' .. playerCharacter.lastname
    local characterId = playerCharacter.charIdentifier

    if not IsNearBank(_source, bankName) then
        return VORPcore.NotifyRightTip(_source, T.notnear, 4000)
    end

    MySQL.query("SELECT gold FROM bank_users WHERE charidentifier = @characterId AND name = @bankName", { characterId = characterId, bankName = bankName }, function(result)
        if result[1] then
            local bankGold = result[1].gold
            if bankGold >= amount then
                local newGoldBalance = bankGold - amount
                MySQL.update("UPDATE bank_users SET gold = @newGoldBalance WHERE charidentifier = @characterId AND name = @bankName", { characterId = characterId, newGoldBalance = newGoldBalance, bankName = bankName }, function()
                    TriggerClientEvent('vorp_banking:client:refresh', _source, bankName)
                end)
                playerCharacter.addCurrency(1, amount)
                DiscordLogs(amount, bankName, playerFullName, "withdraw", "gold")
                VORPcore.NotifyRightTip(_source, T.withdrewg .. amount, 4000)
            else
                VORPcore.NotifyRightTip(_source, T.invalid, 4000)
            end
        end
    end)
end)


RegisterServerEvent("vorp_banking:server:OpenBankInventory", function(bankName)
    local _source = source
    local user = VORPcore.getUser(_source)
    if not user then return end

    local Character = user.getUsedCharacter
    local characterId = Character.charIdentifier
    local bankId = "vorp_banking_" .. bankName .. "_" .. characterId

    if not IsNearBank(_source, bankName) then
        return VORPcore.NotifyRightTip(_source, T.notnear, 4000)
    end

    -- Check database for invSpace server side.
    MySQL.scalar('SELECT `invspace` FROM `bank_users` WHERE `charidentifier` = @characterId AND `name` = @bankName LIMIT 1', {
        characterId = characterId, bankName = bankName
    }, function(invSpace)
        if invSpace then
            registerStorage(bankName, bankId, invSpace)
            exports.vorp_inventory:openInventory(_source, bankId)
        else
            VORPcore.NotifyRightTip(_source, T.invOpenFail, 4000)
        end
    end)
end)

RegisterServerEvent('vorp_banking:server:collectSalary', function(bankName)
    local src = source
    local VORPcore = exports.vorp_core:GetCore() -- Get the core right here
    local Character = VORPcore.getUser(src).getUsedCharacter
    if not Character then return end
    local charIdentifier = Character.charIdentifier

    -- 1. SUM ALL SALARY FIRST
    local totalSalary = MySQL.scalar.await("SELECT SUM(unpaid_salary) FROM bank_users WHERE charidentifier = ?", {charIdentifier})

    if totalSalary and totalSalary > 0 then
        -- 2. PAY THE PLAYER ONCE
        Character.addCurrency(0, totalSalary)

        -- 3. ZERO OUT EVERY SINGLE RECORD FOR THIS PLAYER SO THEY CAN'T COLLECT AGAIN
        MySQL.update.await("UPDATE bank_users SET unpaid_salary = 0 WHERE charidentifier = ?", {charIdentifier})

        VORPcore.NotifyRightTip(src, "You collected a total of $" .. totalSalary, 5000)
    else
        VORPcore.NotifyRightTip(src, "No salary to collect.", 5000)
    end
end)

exports('PaySocietySalaryToMember', function(socName, charOrSource, amount)
    local societyName = socName
    local charIdentifier, user = resolveID(charOrSource)
    
    -- Try to find the society resource name (handle both hyphen and underscore)
    local societyResource = "crimsonrp-society"
    if GetResourceState("crimsonrp_society") == "started" then
        societyResource = "crimsonrp_society"
    end

    print("^2[vorp_banking] Attempting ledger withdrawal:^0", societyName, "Amount:", amount, "Resource:", societyResource)

    local success_balance, societyBalance = pcall(function()
        return exports[societyResource]:GetSocietyBalance(societyName)
    end)
    
    print("^2[vorp_banking] Balance check:^0", success_balance, "Balance:", societyBalance)

    if success_balance and societyBalance and societyBalance >= amount then
        local success_remove = pcall(function()
            exports[societyResource]:RemoveMoney(societyName, amount)
        end)
        
        print("^2[vorp_banking] Removal attempt:^0", success_remove)

        local success_bank = exports['vorp_banking']:PaySalaryToMember(charIdentifier, amount, societyName)
        print("^2[vorp_banking] Bank update success:^0", success_bank)

        if success_bank then
            local players = GetPlayers()
            for _, playerId in ipairs(players) do
                local playerUser = VORPcore.getUser(tonumber(playerId))
                if playerUser and playerUser.getUsedCharacter and playerUser.getUsedCharacter.charIdentifier == charIdentifier then
                    TriggerClientEvent('vorp_banking:client:refresh', tonumber(playerId))
                    break
                end
            end
            return true
        end
    else
        print("^1[vorp_banking] ERROR: Insufficient balance or balance check failed.^0")
    end
    return false
end)
