if script.active_mods["zk-lib"] then
	require("__zk-lib__/static-libs/lualibs/event_handler_vZO.lua").add_lib(require("multi-surface-control"))
else
	require("event_handler").add_lib(require("multi-surface-control"))
end
