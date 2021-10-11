data:extend({
	{type = "int-setting", name = "MS_check_chunks_count", setting_type = "runtime-global", default_value = 15, minimal_value = 1, maximal_value = 300},
	{type = "int-setting", name = "MS_max_surfaces_count", setting_type = "runtime-global", default_value = 30, minimal_value = 1, maximal_value = 100},
	{type = "int-setting", name = "MS_surface_check_delay", setting_type = "runtime-global", default_value = 60 * 60, minimal_value = 0, maximal_value = 1e7},
	{type = "int-setting", name = "MS_update_tick", setting_type = "runtime-global", default_value = 30, minimal_value = 1, maximal_value = 8e4},
})
