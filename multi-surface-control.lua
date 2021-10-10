
-- WARNING: messy, dirty code below
local module = {}


local DELAY_OF_SURFACE_CHECK = 60 * 60
local MAX_SURFACES_COUNT = 30
local CHECK_CHUNKS_COUNT = 15


-- Global data
-- ###########
local surfaces_queue
local mod_surfaces
-- ###########


local function copy_table(obj)
	if type(obj) ~= 'table' then return obj end
	local res = {}
	for k, v in pairs(obj) do res[copy_table(k)] = copy_table(v) end
	return res
end

local function get_is_someone_on_new_surface(target)
	local surface = target.surface
	for _, player in pairs(game.connected_players) do
		if player.valid and player ~= target and player.surface == surface then
			return true
		end
	end
	return false
end

local function get_target_surface()
	local target_surface_data = global.target_surface_data
	if target_surface_data then
		local surface = game.get_surface(target_surface_data.id)
		if not (surface and surface.valid) then
			target_surface_data = nil
		else
			return surface, target_surface_data
		end
	end

	for surface_index, surface_data in pairs(surfaces_queue) do
		if surface_data.tick + DELAY_OF_SURFACE_CHECK > game.tick then break end
		local surface = game.get_surface(surface_index)
		surfaces_queue[surface_index] = nil
		if not (surface and surface.valid) then
			break
		else
			global.target_surface_data = {
				id = surface_index,
				active_state = surface_data.active_state
			}
			return surface, global.target_surface_data
		end
	end
end

local function destroy_GUIs(player)
	local surfaces_menu = player.gui.center.surfaces_menu
	if surfaces_menu then
		surfaces_menu.destroy()
	end
end

local function create_surfaces_menu_UI(player)
	local gui = player.gui.center
	if gui.surfaces_menu then
		gui.surfaces_menu.destroy()
		return
	end

	local frame = player.gui.center.add{type = "frame", name = "surfaces_menu"}
	local main_table = frame.add{type = "table", column_count = 2}
	local items = {}
	local size = 0
	for surface_index in pairs(mod_surfaces) do
		size = size + 1
		items[size] = game.get_surface(surface_index).name
	end
	main_table.add{type = "button", name = "ms_pick_surface", caption = "Pick surface"}
	main_table.add{type = "drop-down", name = "ms_surfaces_list", items = items}
end

local function check_surfaces()
	local surface, surface_data = get_target_surface()
	if surface_data == nil then return end
	local state = surface_data.active_states
	local checked_chunks_count = global.checked_chunks_count
	if surface_data.is_reverse then
		state = not state
		if checked_chunks_count > 0 then
			local chunk_iterator = surface.get_chunks()
			for _=1, checked_chunks_count do
				chunk_iterator() -- weird, but it works
			end
			local filter = {force = "neutral", invert = true}
			local find_entities_filtered = surface.find_entities_filtered
			local i = 0
			for chunk in chunk_iterator do
				filter.area = chunk.area
				local entites = find_entities_filtered(filter)
				if #entites > 0 then
					i = i + 1
					for j=1, #entites do
						local entity = entites[j]
						if entity.valid then
							entity.active = state
						end
					end
					if i > CHECK_CHUNKS_COUNT then
						global.checked_chunks_count = checked_chunks_count - i
						return
					end
				else
					checked_chunks_count = checked_chunks_count - 1
				end
			end
		end
	else
		local chunk_iterator = surface.get_chunks()
		if checked_chunks_count == 0 then
			surface.clear_pollution()
		end
		for _=1, checked_chunks_count do
			chunk_iterator() -- weird, but it works
		end
		local filter = {force = "neutral", invert = true}
		local find_entities_filtered = surface.find_entities_filtered
		local i = 0
		for chunk in chunk_iterator do
			filter.area = chunk.area
			local entites = find_entities_filtered(filter)
			if #entites > 0 then
				i = i + 1
				for j=1, #entites do
					local entity = entites[j]
					if entity.valid then
						entity.active = state
					end
				end
				if i > CHECK_CHUNKS_COUNT then
					global.checked_chunks_count = checked_chunks_count + i
					return
				end
			else
				checked_chunks_count = checked_chunks_count + 1
			end
		end
	end
	mod_surfaces[surface.index] = state
	surfaces_queue[surface.index] = nil -- this seems not necessary
	global.target_surface_data = nil
	global.checked_chunks_count = 0
end


local function delete_UI_command(cmd)
	if cmd.player_index == 0 then
		print("Deleted UIs")
	else
		local player = game.get_player(cmd.player_index)
		if not (player and player.valid) then return end
		if not player.admin then
			player.print({"command-output.parameters-require-admin"})
			return
		end
		player.print("Deleted UIs")
	end

	for _, player in pairs(game.players) do
		if player.valid then
			destroy_GUIs(player)
		end
	end
end

local function surfaces_command(cmd)
	local player = game.get_player(cmd.player_index)
	if not (player and player.valid) then return end
	create_surfaces_menu_UI(player)
end

local function add_surface_command(cmd)
	local player = game.get_player(cmd.player_index)
	if not (player and player.valid) then return end
	if not player.admin then
		player.print({"command-output.parameters-require-admin"})
		return
	end

	if #mod_surfaces > MAX_SURFACES_COUNT then
		player.print("Max surfaces: 30")
		return
	end

	local main_surface = game.get_surface(global.main_surface_index)
	local new_surface_name = main_surface.name .. "_c" .. global.created_surfaces_count
	local map_gen_settings = copy_table(main_surface.map_gen_settings)
	map_gen_settings.seed = math.random(1, 4294967290)
	local surface = game.create_surface(new_surface_name, map_gen_settings) -- TODO: improve
	global.created_surfaces_count = global.created_surfaces_count + 1
	mod_surfaces[surface.index] = true
	game.print("Created new surface")
end


local function on_gui_click(event)
	local element = event.element
	if not (element and element.valid) then return end
	if element.name ~= "ms_pick_surface" then return end
	local ms_surfaces_list = element.parent.ms_surfaces_list
	if ms_surfaces_list.selected_index == 0 then return end

	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end

	local surface_name = ms_surfaces_list.items[ms_surfaces_list.selected_index]
	local surface = game.get_surface(surface_name)
	if not (surface and surface.valid) then
		create_surfaces_menu_UI(player)
		player.print("Selected surface wasn't available")
		return
	elseif surface == player.surface then
		player.print("You're already on the surface")
		return
	end

	if mod_surfaces[surface.index] == nil then
		create_surfaces_menu_UI(player)
		player.print("Selected surface wasn't available")
		return
	end


	if not surface.is_chunk_generated(player.position) then
		surface.request_to_generate_chunks(player.position, 1)
	end
	local new_position = surface.find_non_colliding_position("character", player.position, 15, 1)
	if new_position then
		player.teleport(new_position, surface)
	else
		player.print("Please, repeat your action find another place in order to teleport you on another surface")
	end
end

local function on_player_joined_game(event)
	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end
	local surface_index = player.surface.index
	local is_active_surface = mod_surfaces[surface_index]
	if is_active_surface ~= false then return end
	if get_is_someone_on_new_surface(player) then
		surfaces_queue[surface_index] = nil
		return
	end

	surfaces_queue[surface_index] = {
		tick = game.tick,
		active_state = not is_active_surface
	}
end

local function on_player_left_game(event)
	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end
	local surface_index = player.surface.index
	local is_active_surface = mod_surfaces[surface_index]
	if is_active_surface ~= true then return end
	if not get_is_someone_on_new_surface(player) then
		surfaces_queue[surface_index] = nil
		return
	end

	surfaces_queue[surface_index] = {
		tick = game.tick,
		active_state = not is_active_surface
	}
end

local function on_player_changed_surface(event)
	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end
	destroy_GUIs(player)
	local target_data = global.target_surface_data

	local player_surface_index = player.surface.index
	local is_active_surface = mod_surfaces[player_surface_index]
	if is_active_surface == false then -- Make active the surface
		if target_data and target_data.id == player_surface_index then
			target_data.is_reverse = not target_data.active_state
			surfaces_queue[player_surface_index] = nil
		else
			surfaces_queue[player_surface_index] = {
				tick = game.tick,
				active_state = not is_active_surface
			}
		end
	else
		if target_data and target_data.id == player_surface_index then
			target_data.is_reverse = not target_data.active_state
		end
	end

	local prev_surface = game.get_surface(event.surface_index)
	if not (prev_surface and prev_surface.valid) then return end -- TODO: Recheck this
	local prev_surface_index = prev_surface.index
	local is_active_surface = mod_surfaces[prev_surface_index]
	if is_active_surface == true then -- Make not active the surface
		if get_is_someone_on_new_surface(player) then
			-- Someone on surface
			if target_data and target_data.id == prev_surface_index then
				target_data.is_reverse = not target_data.active_state
				surfaces_queue[prev_surface_index] = nil
			end
		else
			-- Nobody on surface
			if target_data and target_data.id == prev_surface_index then
				target_data.is_reverse = target_data.active_state
				surfaces_queue[prev_surface_index] = nil
			else
				surfaces_queue[prev_surface_index] = {
					tick = game.tick,
					active_state = not is_active_surface
				}
			end
		end
	else
		if target_data and target_data.id == prev_surface_index then
			target_data.is_reverse = target_data.active_state
		end
	end
end

local function on_surface_deleted(event)
	mod_surfaces[event.surface_index] = nil
end


local function link_data()
	surfaces_queue = global.surfaces_queue
	mod_surfaces = global.surfaces
end

local function update_global_data()
	global.created_surfaces_count = global.created_surfaces_count or 0
	global.surfaces_queue = global.surfaces_queue or {}
	global.main_surface_index = global.main_surface_index or 1
	global.checked_chunks_count = global.checked_chunks_count or 0
	global.surfaces = global.surfaces or {
		[1] = true
	}

	for _, player in pairs(game.players) do
		destroy_GUIs(player)
	end
end

module.on_init = (function()
	update_global_data()
	link_data()
end)

module.on_load = (function()
	link_data()
end)

module.on_configuration_changed = (function()
	update_global_data()
	link_data()
end)


module.events = {
	[defines.events.on_gui_click] = on_gui_click,
	[defines.events.on_player_joined_game] = on_player_joined_game,
	[defines.events.on_player_left_game] = on_player_left_game,
	[defines.events.on_player_changed_surface] = on_player_changed_surface,
	[defines.events.on_surface_deleted] = on_surface_deleted
}

module.on_nth_tick = {
	[30] = check_surfaces -- TODO: Change tick
}

commands.add_command("add-surface", {"multi-surface-commands.add-surface"}, add_surface_command)
commands.add_command("surfaces", {"multi-surface-commands.surfaces"}, surfaces_command)
commands.add_command("delete-UI", {"multi-surface-commands.delete-UI"}, delete_UI_command)

return module
