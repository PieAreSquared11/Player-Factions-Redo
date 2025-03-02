notifications_manager = {}
notifications_manager.storage = minetest.get_mod_storage()

function notifications_manager.handle_notification(target_player, message)
    -- Check if it's a message for all players
    if target_player == "all" then
        for _, player in ipairs(minetest.get_connected_players()) do
            minetest.chat_send_player(player:get_player_name(), message)
        end
        
        -- Store message for offline players
        local players_list = minetest.deserialize(notifications_manager.storage:get_string("registered_players") or "{}") or {}
        for player_name, _ in pairs(players_list) do
            if not minetest.get_player_by_name(player_name) then
                local notifications = minetest.deserialize(notifications_manager.storage:get_string("notifications_" .. player_name) or "{}") or {}
                table.insert(notifications, message)
                notifications_manager.storage:set_string("notifications_" .. player_name, minetest.serialize(notifications))
            end
        end
    else
        -- Single player notification
        local player = minetest.get_player_by_name(target_player)
        if player then
            -- Player is online, send directly
            minetest.chat_send_player(target_player, message)
        else
            -- Player is offline, store notification
            local notifications = minetest.deserialize(notifications_manager.storage:get_string("notifications_" .. target_player) or "{}") or {}
            table.insert(notifications, message)
            notifications_manager.storage:set_string("notifications_" .. target_player, minetest.serialize(notifications))
        end
    end
end

minetest.register_on_joinplayer(function(player)
    local player_name = player:get_player_name()
    
    -- Add player to registered players list
    local players_list = minetest.deserialize(notifications_manager.storage:get_string("registered_players") or "{}") or {}
    players_list[player_name] = true
    notifications_manager.storage:set_string("registered_players", minetest.serialize(players_list))
    
    -- Check for stored notifications
    local notifications = minetest.deserialize(notifications_manager.storage:get_string("notifications_" .. player_name) or "{}") or {}
    if #notifications > 0 then
        -- Send stored notifications
        for _, msg in ipairs(notifications) do
            minetest.chat_send_player(player_name, msg)
        end
        -- Clear notifications
        notifications_manager.storage:set_string("notifications_" .. player_name, minetest.serialize({}))
    end
end)
