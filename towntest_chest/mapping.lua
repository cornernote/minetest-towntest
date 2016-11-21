local u = {}
-- Fallback nodes replacement of unknown nodes
-- Maybe it is beter to use aliases for unknown notes. But anyway
u["xpanes:pane_glass_10"] = { name = "xpanes:pane_10" }
u["xpanes:pane_glass_5"]  = { name = "xpanes:pane_5" }
u["beds:bed_top_blue"]    = { name = "beds:bed_top" }
u["beds:bed_bottom_blue"] = { name = "beds:bed_bottom" }

u["homedecor:table_lamp_max"] = { name = "homedecor:table_lamp_white_max" }
u["homedecor:refrigerator"]   = { name = "homedecor:refrigerator_steel" }

u["ethereal:green_dirt"] = { name = "default:dirt_with_grass" }

-- door compatibility. Seems the old doors was facedir and now the wallmounted values should be used
local param2_wallmounted_to_facedir = function(node)
	if node.param2 == 0 then     -- +y?
		return 0
	elseif node.param2 == 1 then -- -y?
		return 1
	elseif node.param2 == 2 then --unsure
		return 3
	elseif node.param2 == 3 then --unsure
		return 1
	elseif node.param2 == 4 then --unsure
		return 2
	elseif node.param2 == 5 then --unsure
		return 0
	end
end

u["doors:door_wood_b_c"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "0"}}},param2 = param2_wallmounted_to_facedir} --closed
u["doors:door_wood_b_o"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "1"}}},param2 = param2_wallmounted_to_facedir} --open
u["doors:door_wood_b_1"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "0"}}}} --closed
u["doors:door_wood_b_2"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "3"}}}} --closed / reversed ??
u["doors:door_wood_a_c"] = {name = "doors:hidden" }
u["doors:door_wood_a_o"] = {name = "doors:hidden" }
u["doors:door_wood_t_1"] = {name = "doors:hidden" }
u["doors:door_wood_t_2"] = {name = "doors:hidden" }

u["doors:door_glass_b_c"] = {name = "doors:door_glass_b", {["meta"] = {["fields"] = {["state"] = "0"}}},param2 = param2_wallmounted_to_facedir} --closed
u["doors:door_glass_b_o"] = {name = "doors:door_glass_b", {["meta"] = {["fields"] = {["state"] = "1"}}},param2 = param2_wallmounted_to_facedir} --open
u["doors:door_glass_b_1"] = {name = "doors:door_glass_b", {["meta"] = {["fields"] = {["state"] = "0"}}}} --closed
u["doors:door_glass_b_2"] = {name = "doors:door_glass_b", {["meta"] = {["fields"] = {["state"] = "3"}}}} --closed / reversed ??
u["doors:door_glass_a_c"] = {name = "doors:hidden" }
u["doors:door_glass_a_o"] = {name = "doors:hidden" }
u["doors:door_glass_t_1"] = {name = "doors:hidden" }
u["doors:door_glass_t_2"] = {name = "doors:hidden" }

u["doors:door_steel_b_c"] = {name = "doors:door_steel_b", {["meta"] = {["fields"] = {["state"] = "0"}}},param2 = param2_wallmounted_to_facedir} --closed
u["doors:door_steel_b_o"] = {name = "doors:door_steel_b", {["meta"] = {["fields"] = {["state"] = "1"}}},param2 = param2_wallmounted_to_facedir} --open
u["doors:door_steel_b_1"] = {name = "doors:door_steel_b", {["meta"] = {["fields"] = {["state"] = "0"}}}} --closed
u["doors:door_steel_b_2"] = {name = "doors:door_steel_b", {["meta"] = {["fields"] = {["state"] = "3"}}}} --closed / reversed ??
u["doors:door_steel_a_c"] = {name = "doors:hidden" }
u["doors:door_steel_a_o"] = {name = "doors:hidden" }
u["doors:door_steel_t_1"] = {name = "doors:hidden" }
u["doors:door_steel_t_2"] = {name = "doors:hidden" }

towntest_chest.mapping.unknown_nodes_data = u



local c = {}
-- "name" and "matname" are optional.
-- if name is missed it will not be changed
-- if matname is missed it will be determinated as usual (from changed name)
-- a crazy sample is: instead of cobble place goldblock, use wood as payment
-- c["default:cobble"] = { name = "default:goldblock", matname = "default:wood" }

c["beds:bed_top"] = { matname = towntest_chest.c_free_item }  -- the bottom of the bed is payed, so buld the top for free

-- it is hard to get a source in survival, so we use buckets. Note, the bucket is lost after usage by NPC
c["default:lava_source"]        = { matname = "bucket:bucket_lava" }
c["default:river_water_source"] = { matname = "bucket:bucket_river_water" }
c["default:water_source"]       = { matname = "bucket:bucket_water" }

-- does not sense to set flowing water because it flow away without the source (and will be generated trough source)
c["default:water_flowing"]       = { name = "" }
c["default:lava_flowing"]        = { name = "" }
c["default:river_water_flowing"] = { name = "" }

-- pay different dirt types by the sane dirt
c["default:dirt_with_dry_grass"] = { matname = "default:dirt" }
c["default:dirt_with_grass"]     = { matname = "default:dirt" }
c["default:dirt_with_snow"]      = { matname = "default:dirt" }


towntest_chest.mapping.customize_data = c



-- Fallback nodes replacement of  unknown nodes
-- Maybe it is beter to use aliases for unknown notes. But anyway
-- TODO: should be editable in game trough a nice gui, to customize the building before build
function towntest_chest.mapping.unknown_nodes(node)

	local map = towntest_chest.mapping.unknown_nodes_data[node.name]
	if not map or map.name == node.name then -- no fallback mapping. don't use the node
		towntest_chest.dprint("mapping failed:", node.name, dump(map))
		print("unknown node in building", node.name)
		return nil
	end

	towntest_chest.dprint("mapped", node.name, "to", map.name)
	local mappednode = node
	mappednode.name = map.name -- must be there!

	if map.meta then
		towntest_chest.dprint("metadata mapping", dump(map.meta))
		if not mappednode.meta then
			mappednode.meta = {}
		end
		for k, v in pairs(map.meta) do
			mappednode.meta[k] = v
			towntest_chest.dprint("map", k, dump(v))
		end
	end

--	towntest_chest.dprint(dump(map))
	if map.param1 then
		if type(map.param1) == "function" then
			towntest_chest.dprint("map param1 by function")
			mappednode.param1 = map.param1(node)
		else
			mappednode.param1 = map.param1
			towntest_chest.dprint("map param1 by value")
		end
	end

	if map.param2 then
		if type(map.param2) == "function" then
			towntest_chest.dprint("map param2 by function")
			mappednode.param2 = map.param2(node)
		else
			towntest_chest.dprint("map param2 by value")
			mappednode.param2 = map.param2
		end
	end

	return mappednode
end


-- Nodes replacement to customizie buildings
-- TODO: should be editable in game trough a nice gui, to customize the building before build
function towntest_chest.mapping.customize(node)
	local map = towntest_chest.mapping.customize_data[node.name]
	if not map then -- no mapping. return unchanged
		return node
	end
	towntest_chest.dprint("map", node.name, "to", map.name, map.matname)
	local mappednode = node
	if map.name then
		mappednode.name = map.name
	end
	if map.matname then
		mappednode.matname = map.matname
	end

	if map.meta then
		if not mappednode.meta then
			mappednode.meta = {}
		end
		for k, v in pairs(map.meta) do
			mappednode.meta[k] = v
		end
	end
	return mappednode
end
