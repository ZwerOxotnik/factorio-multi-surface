local module = {}


--#region Global data
local surfaces_queue
local mod_surfaces

---@type LuaSurface
local target_surface

---@type boolean
local target_state

---@type boolean
local is_reverse_target
--#endregion


--#region Settings
---@type number
local surface_check_delay = settings.global["MS_surface_check_delay"].value

---@type number
local max_surfaces_count = settings.global["MS_max_surfaces_count"].value

---@type number
local check_chunks_count = settings.global["MS_check_chunks_count"].value

---@type number
local update_tick = settings.global["MS_update_tick"].value

---@type number
local check_queue_tick = settings.global["MS_check_queue_tick"].value
if check_queue_tick == update_tick then
	settings.global["MS_check_queue_tick"] = {
		value = check_queue_tick + 1
	}
end

---@type boolean
local delete_unimportant_chunks = settings.global["MS_delete_unimportant_chunks"].value
--#endregion


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
	if target_state == nil then return end
	local checked_chunks_count = global.checked_chunks_count
	local state = target_state
	if is_reverse_target then
		state = not state
		if checked_chunks_count > 0 then
			local chunk_iterator = target_surface.get_chunks()
			for _=1, checked_chunks_count do
				chunk_iterator() -- weird, but it works
			end
			local filter = {force = "neutral", invert = true}
			local find_entities_filtered = target_surface.find_entities_filtered
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
					if i > check_chunks_count then
						global.checked_chunks_count = checked_chunks_count - i
						return
					end
				else
					checked_chunks_count = checked_chunks_count - 1
				end
			end
		end
	else
		local chunk_iterator = target_surface.get_chunks()
		for _=1, checked_chunks_count do
			chunk_iterator() -- weird, but it works
		end
		local filter = {force = "neutral", invert = true}
		local chunk_position = {x = 0, y = 0}
		local find_entities_filtered = target_surface.find_entities_filtered
		local delete_chunk = target_surface.delete_chunk
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
				if i > check_chunks_count then
					global.checked_chunks_count = checked_chunks_count + i
					return
				end
			else
				if delete_unimportant_chunks then
					chunk_position.x = chunk.x
					chunk_position.y = chunk.y
					delete_chunk(chunk_position)
				else
					checked_chunks_count = checked_chunks_count + 1
				end
			end
		end
		game.forces["enemy"].kill_all_units()
		target_surface.clear_pollution()
	end
	surfaces_queue[target_surface.index] = nil -- this seems not necessary
	global.checked_chunks_count = 0
	global.is_reverse_target = nil
	global.target_state = nil
	global.target_surface = nil
	is_reverse_target = nil
	target_state = nil
	target_surface = nil
end

local function check_queue()
	if target_surface ~= nil then return end

	for surface_index, surface_data in pairs(surfaces_queue) do
		if surface_data.tick + surface_check_delay > game.tick then break end
		local surface = game.get_surface(surface_index)
		surfaces_queue[surface_index] = nil
		if not (surface and surface.valid) then
			break
		else
			global.target_surface = surface
			global.target_state = surface_data.active_state
			target_surface = global.target_surface
			target_state = global.target_state
			if not is_reverse_target then
				game.forces["enemy"].kill_all_units()
				target_surface.clear_pollution()
			end
		end
	end
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

	if #mod_surfaces > max_surfaces_count then
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

local mod_settings = {
	["MS_check_chunks_count"] = function(value) check_chunks_count = value end,
	["MS_max_surfaces_count"] = function(value) max_surfaces_count = value end,
	["MS_surface_check_delay"] = function(value) surface_check_delay = value end,
	["MS_delete_unimportant_chunks"] = function(value) delete_unimportant_chunks = value end,
	["MS_update_tick"] = function(value)
		if check_queue_tick == value then
			settings.global["MS_check_queue_tick"] = {
				value = value + 1
			}
			return
		end
		script.on_nth_tick(update_tick, nil)
		update_tick = value
		script.on_nth_tick(value, check_surfaces)
	end,
	["MS_check_queue_tick"] = function(value)
		if update_tick == value then
			settings.global["MS_check_queue_tick"] = {
				value = value + 1
			}
			return
		end
		script.on_nth_tick(check_queue_tick, nil)
		check_queue_tick = value
		script.on_nth_tick(value, check_queue)
	end
}
local function on_runtime_mod_setting_changed(event)
	local f = mod_settings[event.setting]
	if f then f(settings.global[event.setting].value) end
end

local function on_pre_surface_deleted(event)
	if target_surface == nil then return end
	if event.surface_index ~= target_surface.index then return end

	surfaces_queue[target_surface.index] = nil
	global.checked_chunks_count = 0
	global.is_reverse_target = nil
	global.target_surface = nil
	global.target_state = nil
	is_reverse_target = nil
	target_surface = nil
	target_state = nil
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


	local position = player.position
	if not surface.is_chunk_generated(position) then
		surface.request_to_generate_chunks(position, 1)
	end
	local new_position = surface.find_non_colliding_position("character", position, 15, 1)
	if new_position then
		player.teleport(new_position, surface)
	else
		player.print("Please, repeat your action or find another place in order to teleport you on another surface")
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

	local surface = player.surface
	local player_surface_index = player.surface.index
	local is_active_surface = mod_surfaces[player_surface_index]
	if is_active_surface == false then -- Make active the surface
		if target_surface and target_surface == surface then
			global.is_reverse_target = not target_state
			is_reverse_target = not target_state
			surfaces_queue[player_surface_index] = nil
		else
			surfaces_queue[player_surface_index] = {
				tick = game.tick,
				active_state = not is_active_surface
			}
		end
	else
		if target_surface and target_surface == surface then
			global.is_reverse_target = not target_state
			is_reverse_target = not target_state
		end
	end

	local prev_surface = game.get_surface(event.surface_index)
	if not (prev_surface and prev_surface.valid) then return end -- TODO: Recheck this
	local prev_surface_index = prev_surface.index
	local is_active_surface = mod_surfaces[prev_surface_index]
	if is_active_surface == true then -- Make not active the surface
		if get_is_someone_on_new_surface(player) then
			-- Someone on surface
			if target_surface and target_surface == prev_surface then
				global.is_reverse_target = not target_state
				is_reverse_target = not target_state
				surfaces_queue[prev_surface_index] = nil
			end
		else
			-- Nobody on surface
			if target_surface and target_surface == prev_surface then
				global.is_reverse_target = target_state
				is_reverse_target = not target_state
				surfaces_queue[prev_surface_index] = nil
			else
				surfaces_queue[prev_surface_index] = {
					tick = game.tick,
					active_state = not is_active_surface
				}
			end
		end
	else
		if target_surface and target_surface == prev_surface then
			global.is_reverse_target = target_state
			is_reverse_target = not target_state
		end
	end
end

local function on_surface_deleted(event)
	mod_surfaces[event.surface_index] = nil
end


local function link_data()
	surfaces_queue = global.surfaces_queue
	mod_surfaces = global.surfaces
	target_surface = global.target_surface
	is_reverse_target = global.is_reverse_target
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
	[defines.events.on_runtime_mod_setting_changed] = on_runtime_mod_setting_changed,
	[defines.events.on_pre_surface_deleted] = on_pre_surface_deleted,
	[defines.events.on_gui_click] = on_gui_click,
	[defines.events.on_player_joined_game] = on_player_joined_game,
	[defines.events.on_player_left_game] = on_player_left_game,
	[defines.events.on_player_changed_surface] = on_player_changed_surface,
	[defines.events.on_surface_deleted] = on_surface_deleted
}

module.on_nth_tick = {
	[update_tick] = check_surfaces,
	[check_queue_tick] = check_queue
}

commands.add_command("add-surface", {"multi-surface-commands.add-surface"}, add_surface_command)
commands.add_command("surfaces", {"multi-surface-commands.surfaces"}, surfaces_command)
commands.add_command("delete-UI", {"multi-surface-commands.delete-UI"}, delete_UI_command)

return module
