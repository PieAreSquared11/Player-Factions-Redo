local storage = minetest.get_mod_storage()

factions = {}

function factions.get_factions()
    local factions_string = storage:get_string("factions")
    return factions_string ~= "" and minetest.parse_json(factions_string) or {}
end

function factions.save_factions(factions_data)
    storage:set_string("factions", minetest.write_json(factions_data))
end

function factions.get_player_invites(player_name)
    local invites_string = storage:get_string("invites_" .. player_name)
    return invites_string ~= "" and minetest.parse_json(invites_string) or {}
end

function factions.save_player_invites(player_name, invites)
    storage:set_string("invites_" .. player_name, minetest.write_json(invites))
end

function factions.get_player_faction(player_name)
    local factions_data = factions.get_factions()
    for faction_name, faction in pairs(factions_data) do
        if faction.members[player_name] then
            return faction_name
        end
    end
    return nil
end

function factions.get_faction_players(faction_name)
    local factions_data = factions.get_factions()
    local faction = factions_data[faction_name]
    if not faction then return {} end
    
    local players = {}
    for player_name in pairs(faction.members) do
        table.insert(players, player_name)
    end
    return players
end

function factions.player_is_owner(player_name, faction_name)
    local factions_data = factions.get_factions()
    local faction = factions_data[faction_name]
    return faction and faction.owner == player_name
end

function factions.player_is_member(player_name, faction_name)
    local factions_data = factions.get_factions()
    local faction = factions_data[faction_name]
    return faction and faction.members[player_name] == true
end

function factions.get_owned_faction(player_name)
    local factions_data = factions.get_factions()
    for faction_name, faction in pairs(factions_data) do
        if faction.owner == player_name then
            return faction_name
        end
    end
    return nil
end

function factions.create_faction(faction_name, owner)
    if not faction_name:match("^[a-zA-Z]+$") then
        return false, "Faction name must contain only letters (a-z, A-Z)"
    end
    
    local factions_data = factions.get_factions()
    
    for existing_name, _ in pairs(factions_data) do
        if existing_name:lower() == faction_name:lower() then
            return false, "A faction with this name already exists"
        end
    end
    
    factions_data[faction_name] = {
        owner = owner,
        members = {[owner] = true}
    }
    factions.save_factions(factions_data)
    
    local player = minetest.get_player_by_name(owner)
    if player then
        factions.update_nametag(player)
    end
    
    return true, "Faction created successfully"
end

function factions.players_in_same_faction(player1_name, player2_name)
    local faction1 = factions.get_player_faction(player1_name)
    local faction2 = factions.get_player_faction(player2_name)
    
    return faction1 and faction2 and faction1 == faction2
end

function on_damage(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
    return factions.players_in_same_faction(player:get_player_name(), hitter:get_player_name())
end

minetest.register_on_punchplayer(on_damage)

function factions.get_faction_owner(faction_name)
    local factions_data = factions.get_factions()
    local faction = factions_data[faction_name]
    return faction and faction.owner or nil
end

function factions.change_faction_owner(faction_name, new_owner)
    local factions_data = factions.get_factions()
    local faction = factions_data[faction_name]
    
    if not faction then
        return false, "Faction does not exist"
    end
    
    if not faction.members[new_owner] then
        return false, "New owner must be a faction member"
    end
    
    faction.owner = new_owner
    factions.save_factions(factions_data)
    return true, "Faction owner changed successfully"
end

function factions.update_nametag(player)
    local name = player:get_player_name()
    local prefix = factions.get_colored_faction_prefix(name)
    player:set_nametag_attributes({
        text = prefix .. name
    })
end

minetest.register_on_joinplayer(function(player)
    factions.update_nametag(player)
end)

function factions.update_all_member_nametags(faction_name)
    local members = factions.get_faction_players(faction_name)
    for _, member_name in ipairs(members) do
        local player = minetest.get_player_by_name(member_name)
        if player then
            factions.update_nametag(player)
        end
    end
end

function factions.rename_faction(old_name, new_name)
    if not new_name:match("^[a-zA-Z]+$") then
        return false, "Faction name must contain only letters (a-z, A-Z)"
    end
    
    local factions_data = factions.get_factions()
    
    for existing_name, _ in pairs(factions_data) do
        if existing_name:lower() == new_name:lower() then
            return false, "A faction with this name already exists"
        end
    end
    
    local faction = factions_data[old_name]
    factions_data[old_name] = nil
    factions_data[new_name] = faction
    factions.save_factions(factions_data)
    
    for member_name in pairs(faction.members) do
        local player = minetest.get_player_by_name(member_name)
        if player then
            factions.update_nametag(player)
        end
    end
    
    return true, "Faction renamed successfully"
end

function factions.send_faction_order(faction_name, order_message)
    local members = factions.get_faction_players(faction_name)
    for _, member_name in ipairs(members) do
        notifications_manager.handle_notification(member_name, minetest.colorize("#FF9900", "[Faction Order] ") .. order_message)
    end
end

function factions.send_faction_message(sender_name, faction_name, target_name, message)
    -- If no specific target, send to all faction members
    if not target_name then
        local members = factions.get_faction_players(faction_name)
        for _, member_name in ipairs(members) do
            if member_name ~= sender_name then  -- Don't send to the sender
                notifications_manager.handle_notification(member_name, 
                    minetest.colorize("#99FF99", "[Faction Chat] ") .. 
                    sender_name .. ": " .. message)
            end
        end
        return true, "Message sent to all faction members"
    end
    
    -- Check if target is in the same faction
    if not factions.player_is_member(target_name, faction_name) then
        return false, "Player is not in your faction"
    end
    
    -- Send direct message
    notifications_manager.handle_notification(target_name, 
        minetest.colorize("#99FF99", "[Faction PM] ") .. 
        sender_name .. ": " .. message)
    return true, "Message sent to " .. target_name
end

minetest.register_chatcommand("faction", {
    params = "<action> <parameters>",
    privs = {},
    description = [[Faction management commands:
- create <name>: Create a new faction (name can only contain letters and numbers)
- invite <player>: Invite a player to your faction (owner only)
- accept <faction>: Accept an invitation to join a faction
- invites: View your pending faction invites
- kick <player>: Remove a player from your faction (owner only)
- leave: Leave your current faction (not available for owners)
- disband: Delete your faction (owner only)
- owner <faction>: Check who owns a specific faction
- transfer <player>: Transfer faction ownership to another member (owner only)
- rename <newname>: Rename your faction (owner only)
- order <message>: Send an order message to all faction members (owner only)
- msg <message>: Send a message to all online faction members
- msg <player> <message>: Send a private message to a specific faction member]],
    func = function(name, param)
        local args = param:split(" ")
        local action = args[1]

        if action == "create" and args[2] then
            local faction_name = args[2]
            if factions.get_player_faction(name) then
                return false, "You are already in a faction"
            end
            return factions.create_faction(faction_name, name)
        
        elseif action == "leave" then
            local faction_name = factions.get_player_faction(name)
            local factions_data = factions.get_factions()
            
            if not faction_name then
                return false, "You are not in a faction"
            end
            
            if factions_data[faction_name].owner == name then
                return false, "Faction owner cannot leave. Use /faction disband instead"
            end

            factions_data[faction_name].members[name] = nil
            factions.save_factions(factions_data)
            
            notifications_manager.handle_notification(factions_data[faction_name].owner, name .. " has left your faction")
            
            local player = minetest.get_player_by_name(name)
            if player then
                factions.update_nametag(player)
            end
            
            return true, "You have left the faction " .. faction_name

        elseif action == "invite" and args[2] then
            local player = args[2]
            local faction_name = factions.get_player_faction(name)
            if not faction_name then
                return false, "You are not in a faction"
            end
            
            local factions_data = factions.get_factions()
            if factions_data[faction_name].owner ~= name then
                return false, "Only the faction owner can invite players"
            end

            local invites = factions.get_player_invites(player)
            table.insert(invites, faction_name)
            factions.save_player_invites(player, invites)
            notifications_manager.handle_notification(player, "You have been invited to join faction " .. faction_name .. ". Use /faction accept " .. faction_name .. " to join.")
            
            local invited_player = minetest.get_player_by_name(player)
            if invited_player then
                factions.update_nametag(invited_player)
            end
            
            return true, "Invited " .. player .. " to faction"
        
        elseif action == "accept" and args[2] then
            local faction_name = args[2]
            local invites = factions.get_player_invites(name)
            local found = false
            for i, invite in ipairs(invites) do
                if invite == faction_name then
                    found = true
                    table.remove(invites, i)
                    break
                end
            end

            if not found then
                return false, "No invite found for this faction"
            end

            local factions_data = factions.get_factions()
            if not factions_data[faction_name] then
                return false, "Faction no longer exists"
            end

            factions_data[faction_name].members[name] = true
            factions.save_factions(factions_data)
            factions.save_player_invites(name, invites)
            
            local player = minetest.get_player_by_name(name)
            if player then
                factions.update_nametag(player)
            end
            
            return true, "You have joined " .. faction_name
        
        elseif action == "kick" and args[2] then
            local player = args[2]
            local faction_name = factions.get_player_faction(name)
            local factions_data = factions.get_factions()
            
            if not faction_name or factions_data[faction_name].owner ~= name then
                return false, "You are not the faction owner"
            end

            if not factions_data[faction_name].members[player] then
                return false, "Player is not in your faction"
            end

            factions_data[faction_name].members[player] = nil
            factions.save_factions(factions_data)
            notifications_manager.handle_notification(player, "You have been kicked from faction " .. faction_name)
            
            local kicked_player = minetest.get_player_by_name(player)
            if kicked_player then
                factions.update_nametag(kicked_player)
            end
            
            return true, "Kicked " .. player .. " from faction"
        
        elseif action == "disband" then
            local faction_name = factions.get_player_faction(name)
            local factions_data = factions.get_factions()
            
            if not faction_name or factions_data[faction_name].owner ~= name then
                return false, "You are not the faction owner"
            end

            -- Get list of members before disbanding
            local members = factions.get_faction_players(faction_name)

            for member_name in pairs(factions_data[faction_name].members) do
                if member_name ~= name then
                    notifications_manager.handle_notification(member_name, "The faction " .. faction_name .. " has been disbanded by the owner")
                end
            end

            factions_data[faction_name] = nil
            factions.save_factions(factions_data)
            
            -- Update nametags for all former members
            for _, member_name in ipairs(members) do
                local player = minetest.get_player_by_name(member_name)
                if player then
                    factions.update_nametag(player)
                end
            end
            
            return true, "Faction disbanded"
        
        elseif action == "owner" and args[2] then
            local faction_name = args[2]
            local owner = factions.get_faction_owner(faction_name)
            
            if not owner then
                return false, "Faction does not exist"
            end
            
            return true, "The owner of faction " .. faction_name .. " is " .. owner

        elseif action == "transfer" and args[2] then
            local new_owner = args[2]
            local faction_name = factions.get_player_faction(name)
            
            if not faction_name then
                return false, "You are not in a faction"
            end
            
            if not factions.player_is_owner(name, faction_name) then
                return false, "Only the faction owner can transfer ownership"
            end
            
            local success, msg = factions.change_faction_owner(faction_name, new_owner)
            if success then
                notifications_manager.handle_notification(new_owner, "You are now the owner of faction " .. faction_name)
                local members = factions.get_faction_players(faction_name)
                for _, member in ipairs(members) do
                    if member ~= new_owner and member ~= name then
                        notifications_manager.handle_notification(member, new_owner .. " is now the owner of your faction")
                    end
                end
            end
            return success, msg

        elseif action == "rename" and args[2] then
            local new_name = args[2]
            local faction_name = factions.get_player_faction(name)
            local factions_data = factions.get_factions()
            
            if not faction_name then
                return false, "You are not in a faction"
            end
            
            if factions_data[faction_name].owner ~= name then
                return false, "Only the faction owner can rename the faction"
            end
            
            local success, msg = factions.rename_faction(faction_name, new_name)
            if success then
                for member_name in pairs(factions_data[faction_name].members) do
                    notifications_manager.handle_notification(member_name, "Your faction has been renamed to " .. new_name)
                end
            end
            return success, msg

        elseif action == "order" then
            local faction_name = factions.get_player_faction(name)
            if not faction_name then
                return false, "You are not in a faction"
            end
            
            if not factions.player_is_owner(name, faction_name) then
                return false, "Only the faction owner can send orders"
            end
            
            -- Get the order message (everything after "order")
            local order_message = param:sub(7) -- Remove "order "
            if order_message == "" then
                return false, "Please provide an order message"
            end
            
            factions.send_faction_order(faction_name, order_message)
            return true, "Order sent to all faction members"

        elseif action == "msg" then
            local faction_name = factions.get_player_faction(name)
            if not faction_name then
                return false, "You are not in a faction"
            end
            
            if not args[2] then
                return false, "Please provide a message or target player and message"
            end
            
            local target_name = nil
            local message
            
            -- Get the message (everything after "msg")
            if args[3] then
                -- If there's a third argument, treat the second as target name
                target_name = args[2]
                message = param:sub(#args[1] + #args[2] + 3) -- Remove "msg playername "
            else
                message = param:sub(5) -- Remove "msg "
            end
            
            if message == "" then
                return false, "Please provide a message"
            end
            
            return factions.send_faction_message(name, faction_name, target_name, message)

        elseif action == "invites" then
            local invites = factions.get_player_invites(name)
            
            if #invites == 0 then
                return true, "You have no pending faction invites."
            end
            
            local response = "Your pending faction invites:\n"
            for _, faction_name in ipairs(invites) do
                local owner = factions.get_faction_owner(faction_name)
                response = response .. "- " .. faction_name .. " (Owner: " .. owner .. ")\n"
            end
            response = response .. "Use '/faction accept <faction>' to join a faction."
            
            return true, response

        else
            return false, "Invalid command. Available commands: create, invite, accept, kick, disband, leave, owner, transfer, rename, order, msg"
        end
    end
})

minetest.register_chatcommand("factions", {
    description = "List all factions and their members",
    func = function(name, param)
        local factions_data = factions.get_factions()
        if not next(factions_data) then
            return true, "No factions exist yet."
        end

        local response = "Factions list:\n"
        for faction_name, faction in pairs(factions_data) do
            local member_count = 0
            for _ in pairs(faction.members) do
                member_count = member_count + 1
            end
            response = response .. "- " .. faction_name .. " (Owner: " .. faction.owner .. ", Members: " .. member_count .. ")\n"
        end
        return true, response
    end
})

function factions.get_colored_faction_prefix(player_name)
    local faction_name = factions.get_player_faction(player_name)
    if faction_name then
        return "[" .. minetest.colorize("#6699FF", faction_name) .. "] "
    end
    return ""
end

minetest.register_on_chat_message(function(name, message)
    local prefix = factions.get_colored_faction_prefix(name)
    minetest.chat_send_all(prefix .. name .. ": " .. message)
    return true
end)