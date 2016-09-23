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

-- door compatibility
u["doors:door_wood_b_c"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "0"}}}} --closed
u["doors:door_wood_b_o"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "1"}}}} --open
u["doors:door_wood_b_1"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "0"}}}} --closed
u["doors:door_wood_a_c"] = {name = "doors:door_wood_a", {["meta"] = {["fields"] = {["state"] = "0"}}}} --closed
u["doors:door_wood_b_o"] = {name = "doors:door_wood_a", {["meta"] = {["fields"] = {["state"] = "1"}}}} --open
u["doors:door_wood_a_c"] = {name = "doors:hidden" }
u["doors:door_wood_a_o"] = {name = "doors:hidden" }
u["doors:door_wood_t_1"] = {name = "doors:hidden" }

towntest_chest.mapping.unknown_nodes_data = u



local c = {}
-- "name" and "matname" are optional.
-- if name is missed it will not be changed
-- if matname is missed it will be determinated as usual (from changed name)
-- a crazy sample is: instead of cobble place goldblock, use wood as payment
-- c["default:cobble"] = { name = "default:goldblock", matname = "default:wood" }

c["beds:bed_top"] = { matname = "free" }  -- the bottom of the bed is payed, so buld the top for free

-- it is hard to get a source in survival, so we use buckets. Note, the bucket is lost after usage by NPC
c["default:lava_source"]        = { matname = "bucket:bucket_lava" }
c["default:river_water_source"] = { matname = "bucket:bucket_river_water" }
c["default:water_source"]       = { matname = "bucket:bucket_water" }

-- pay different dirt types by the sane dirt
c["default:dirt_with_dry_grass"] = { matname = "default:dirt" }
c["default:dirt_with_grass"]     = { matname = "default:dirt" }
c["default:dirt_with_snow"]      = { matname = "default:dirt" }

towntest_chest.mapping.customize_data = c



-- Fallback nodes replacement of  unknown nodes
-- Maybe it is beter to use aliases for unknown notes. But anyway
-- TODO: should be editable in game trough a nice gui, to customize the building before build
towntest_chest.mapping.unknown_nodes = function(node)

	local map = towntest_chest.mapping.unknown_nodes_data[node.name]
	if not map or map.name == node.name then -- no fallback mapping. don't use the node
		towntest_chest.dprint("mapping failed:", node.name, dump(map))
		print("unknown node in building", node.name)
		return nil
	end

	towntest_chest.dprint("mapped", node.name, "to", map.name)
	local mappednode = node
	mappednode.name = map.name

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
	return mappednode
end


-- Nodes replacement to customizie buildings
-- TODO: should be editable in game trough a nice gui, to customize the building before build
towntest_chest.mapping.customize = function(node)
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
