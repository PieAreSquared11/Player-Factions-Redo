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

function on_damage(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
  if not minetest.settings:get_bool("player_factions.mode_unique_faction") then
    if factions.get_player_faction(hitter:get_player_name()) == factions.get_player_faction(player:get_player_name()) then
      return true
    end
  end

  return false
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

minetest.register_chatcommand("faction", {
    params = "<action> <parameters>",
    privs = {},
    description = [[Faction management commands:
- create <name>: Create a new faction (name can only contain letters and numbers)
- invite <player>: Invite a player to your faction (owner only)
- accept <faction>: Accept an invitation to join a faction
- kick <player>: Remove a player from your faction (owner only)
- leave: Leave your current faction (not available for owners)
- disband: Delete your faction (owner only)
- owner <faction>: Check who owns a specific faction
- transfer <player>: Transfer faction ownership to another member (owner only)]],
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
            
            factions.notify_player(factions_data[faction_name].owner, name .. " has left your faction")
            
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
            factions.notify_player(player, "You have been invited to join faction " .. faction_name .. ". Use /faction accept " .. faction_name .. " to join.")
            
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
            factions.notify_player(player, "You have been kicked from faction " .. faction_name)
            
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

            for member_name in pairs(factions_data[faction_name].members) do
                if member_name ~= name then
                    factions.notify_player(member_name, "The faction " .. faction_name .. " has been disbanded by the owner")
                end
            end

            factions_data[faction_name] = nil
            factions.save_factions(factions_data)
            
            local members = factions.get_faction_players(faction_name)
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
                factions.notify_player(new_owner, "You are now the owner of faction " .. faction_name)
                local members = factions.get_faction_players(faction_name)
                for _, member in ipairs(members) do
                    if member ~= new_owner and member ~= name then
                        factions.notify_player(member, new_owner .. " is now the owner of your faction")
                    end
                end
            end
            return success, msg

        else
            return false, "Invalid command. Available commands: create, invite, accept, kick, disband, leave, owner, transfer"
        end
    end
})

function factions.notify_player(player_name, message)
    local player = minetest.get_player_by_name(player_name)
    if player then
        minetest.chat_send_player(player_name, message)
    end
end

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