--[[

Towntest for Minetest

Copyright (c) 2012 cornernote, Brett O'Donnell <cornernote@gmail.com>
Source Code: https://github.com/cornernote/minetest-towntest
License: BSD-3-Clause https://raw.github.com/cornernote/minetest-towntest/master/LICENSE

CHEST

]]--

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- expose api
towntest_chest = {}

-- table of non playing characters
towntest_chest.npc = {}

-- get_files 
-- returns a table containing buildings
towntest_chest.get_files = function()
	local lfs = require("lfs")
	local i, t = 0, {}
	for filename in lfs.dir(modpath .. "/buildings") do
		if filename ~= "." and filename ~= ".." then
			i = i + 1
			t[i] = filename
		end
	end
	return t
end

-- load
-- filename - the building file to load
-- return - string containing the pos and nodes to build
towntest_chest.load = function(filename)
	local filepath = modpath.."/buildings/"..filename
	local file, err = io.open(filepath, "rb")
	if err ~= nil then
		minetest.chat_send_player(placer:get_player_name(), "[towntest_chest] error: could not open file \"" .. filepath .. "\"")
		return
	end
	-- load the building starting from the lowest y
	local building = towntest_chest.get_table(file:read("*a"))
	local building_ordered = {}
	for i,v in ipairs(building) do
		if not building_ordered[v.y] then building_ordered[v.y] = {} end
		table.insert(building_ordered[v.y],v)
	end
	building = {}
	local a = {}
	for k in pairs(building_ordered) do table.insert(a, k) end
	table.sort(a)
	for i,k in ipairs(a) do
		for ii,vv in ipairs(building_ordered[k]) do
			table.insert(building,vv)
		end
	end
	return towntest_chest.get_string(building)
end


local function mapname(name)
	local node = minetest.registered_items[name]

	if not node then
		minetest.log("info", "unknown node in building: "..name)
		return nil
	else

-- known node. Check for price or if it is free
		if (node.groups.not_in_creative_inventory and not (node.groups.not_in_creative_inventory == 0)) or
		   (not node.description or node.description == "") then
			if node.drop then
				return mapname(node.drop) --use the drop as payment
			else --something not supported, but known
				return "free" -- will be build for free. they are something like doors:hidden or second part of coffee lrfurn:coffeetable_back
			end
		else
			return node.name
		end
	end
end

-- get_table - convert building table to string
-- building_string - string containing pos and nodes to build
-- return - table containing pos and nodes to build
towntest_chest.get_table = function(building_string)
	local building = {}
        local wefile = {}
	local idx, def
	local retpos = string.find(string.sub(building_string,0,10), "return")
	if retpos then
		local exe, err, ok
		exe,err = loadstring(string.sub(building_string,retpos))
		if exe then
			ok, wefile = pcall(exe)
		end
		
		for idx,def in pairs(wefile) do
			if tonumber(def.x)~=0 or tonumber(def.y)~=0 or tonumber(def.z)~=0 then
				if not def.matname then
					def.matname = mapname(def.name)
				end
				if def.matname then -- found
					table.insert(building, {x=def.x,y=def.y,z=def.z,name=def.name,param1=def.param1,param2=def.param2,meta=def.meta,matname=def.matname})
				end
			end
		end
	else
		for x, y, z, name, param1, param2 in building_string:gmatch("([+-]?%d+)%s+([+-]?%d+)%s+([+-]?%d+)%s+([^%s]+)%s+(%d+)%s+(%d+)[^\r\n]*[\r\n]*") do
			if tonumber(x)~=0 or tonumber(y)~=0 or tonumber(z)~=0 then
				local matname = mapname(name)
				if def.matname then 
					table.insert(building, {x=x,y=y,z=z,name=name,param1=param1,param2=param2,matname=matname})
				end
			end
		end
	end
	return building
end

-- get_string - convert building string to table
-- building - table containing pos and nodes to build
-- return - string containing pos and nodes to build
towntest_chest.get_string = function(building)
	local building_string = ""
	if building_string then
		building_string = "return "..dump(building)
	end
	return building_string
end

-- update_needed - updates the needed inventory in the chest
-- inv - inventory object of the chest
-- building - table containing pos and nodes to build 
towntest_chest.update_needed = function(inv,building)
	for i=1,inv:get_size("needed") do
		inv:set_stack("needed", i, nil)
	end
	local materials = {}
	for i,v in ipairs(building) do
		if v.matname ~= "free" then --free materials will be built for free
			if not materials[v.matname] then
				materials[v.matname] = 1
			else 
				materials[v.matname] = materials[v.matname]+1
			end
		end
	end
	for k,v in pairs(materials) do
		inv:add_item("needed",k.." "..v)
	end
end

-- set_status - activate or deactivate building
-- meta - meta object of the chest
-- status - integer (will toggle if status not given)
towntest_chest.set_status = function(meta,status)
	if status==nil then
		status=meta:get_int("building_status")
		if status==1 then status=0 else status=1 end
	end
	if status==0 then
		meta:set_string("infotext", "Building Chest (inactive)")
		meta:set_int("building_status",0)
	else
		meta:set_string("infotext", "Building Chest (active)")
		meta:set_int("building_status",1)
	end
end

-- build - build a node of the structure
-- chestpos - the position of the chest containing the instructions
towntest_chest.build = function(chestpos)
	-- load the building_plan
	local meta = minetest.env:get_meta(chestpos)
	if meta:get_int("building_status")~=1 then return end
	local building_plan = towntest_chest.get_table(meta:get_string("building_plan"))

	-- create the npc if needed
	local inv = meta:get_inventory()
	local k = chestpos.x..","..chestpos.y..","..chestpos.z
	if not towntest_chest.npc[k] then
		towntest_chest.npc[k] = minetest.env:add_entity(chestpos, "towntest_npc:builder")
		towntest_chest.npc[k]:get_luaentity().chestpos = chestpos
		towntest_chest.npc[k]:get_luaentity():moveto({x=chestpos.x,y=chestpos.y+1.5,z=chestpos.z},1)
		if not inv:is_empty("builder") then
			for i=1,inv:get_size("builder") do
				inv:set_stack("builder", i, nil)
			end
		end
		towntest_chest.update_needed(meta:get_inventory(),building_plan)
	end
	local npc = towntest_chest.npc[k]:get_luaentity()

	-- no building plan
	if building_plan=="" then
		-- move the npc to the chest
		npc:moveto({x=chestpos.x,y=chestpos.y+1.5,z=chestpos.z},2,2)
		towntest_chest.set_status(meta,0)
		return
	end
	
	-- try to build from builder inventory
	for i,v in ipairs(building_plan) do
		local pos = {x=v.x+chestpos.x,y=v.y+chestpos.y,z=v.z+chestpos.z}
		-- check if the builder has the node
		if inv:contains_item("builder", v.matname) or -- is payed or
-- for free and the item is at the end of building plan (all next items already built, to avoid all free items are placed at the first)
		   ( v.matname == "free" and i == #building_plan )
		then
			-- check if npc is already moving
			if npc and not npc.target then
				table.remove(building_plan,i)
				-- move the npc to the build area
				npc:moveto({x=pos.x, y=pos.y+1.5, z=pos.z}, 2, 2, 0, function(self,after_param)
					-- take from the inv
					after_param.inv:remove_item("builder", after_param.v.matname.." 1")
					-- add the node to the world
					minetest.env:add_node(after_param.pos, {name=after_param.v.name,param1=after_param.v.param1,param2=after_param.v.param2})
			                if v.meta then
						minetest.env:get_meta(after_param.pos):from_table(after_param.v.meta)
			                end

					-- update the chest building_plan
					meta:set_string("building_plan", towntest_chest.get_string(building_plan))
				end, {pos=pos, v=v, inv=inv, meta=meta})
			end
			return
		end
	end

	-- try to get items from chest into builder inventory
	local items_needed = true
	for i,v in ipairs(building_plan) do
		-- check if the chest has the node
		if inv:contains_item("main", v.matname) then
			items_needed = false
			-- check if npc is already moving
			if npc and not npc.target then
				-- move the npc to the chest
				npc:moveto({x=chestpos.x, y=chestpos.y+1.5, z=chestpos.z}, 2, 0, 0, function(self, params)
					-- check for food
					local inv = params.inv
					local building_plan = params.building_plan
					if not inv:is_empty("main") then
						for i=1,inv:get_size("main") do
							-- check if this is a food, if so take it
							local stack = inv:get_stack("main", i)
							if not stack:is_empty() then
								local node = minetest.registered_nodes[stack:get_name()]
								if node and node.name == "default:apple" then
									local quality = 1
									npc.food = npc.food + (stack:get_count() * quality * 4)
									inv:set_stack("main", i, nil)
								elseif node and node.groups.food ~= nil then
									local quality = 4 - node.groups.food
									npc.food = npc.food + (stack:get_count() * quality * 4)
									inv:set_stack("main", i, nil)
								end
							end
						end
					end
					-- take from the inv
					for i,v in ipairs(building_plan) do
						if inv:contains_item("main",v.matname.." 1") and inv:room_for_item("builder",v.matname.." 1") then
							inv:add_item("builder",inv:remove_item("main",v.matname.." 1"))
							inv:remove_item("needed", v.matname.." 1")
						end
					end
				end, {inv=inv,building_plan=building_plan})
			end
		end
	end

	-- stop building and tell the player what we need
	if npc and items_needed then
		npc:moveto({x=chestpos.x,y=chestpos.y+1.5,z=chestpos.z},2)
		towntest_chest.set_status(meta,0)
		towntest_chest.update_needed(meta:get_inventory(),building_plan)
	end
	
end

-- formspec - get the chest formspec
towntest_chest.formspec = function(pos,page)
	local formspec = ""
	-- chest page
	if page=="chest" then
		formspec = formspec 
			.."size[10.5,9]"
			.."list[current_player;main;0,5;8,4;]"

			.."label[0,0; items needed:]"
			.."list[current_name;needed;0,0.5;8,2;]"

			.."label[0,2.5; put items here to build:]"
			.."list[current_name;main;0,3;8,1;]"
			
			.."label[8.5,0; builder:]"
			.."list[current_name;builder;8.5,0.5;2,2;]"

			.."label[8.5,2.5; lumberjack:]"
			.."list[current_name;lumberjack;8.5,3;2,2;]"
			
		return formspec
	end
	-- main page
	formspec = formspec.."size[12,10]"
	local pages = towntest_chest.get_files()
	local x,y = 0,0
	local p
	for i = #pages,1,-1 do
		p = pages[i]
		if x == 12 then
			y = y+1
			x = 0
		end
		formspec = formspec .."button["..(x)..","..(y)..";4,0.5;building;"..p.."]"
		x = x+4
	end
	if #pages == 0 then
		formspec = formspec
			.."label[4,4.5; no files found in buildings folder:]"
			.."label[4,5.0; "..minetest.get_modpath("towntest_chest").."/buildings".."]"
	end
	return formspec
end

-- on_receive_fields - called when a chest button is submitted
towntest_chest.on_receive_fields = function(pos, formname, fields, sender)
	local meta = minetest.env:get_meta(pos)
	if fields.building then
		meta:set_string("building_plan", towntest_chest.load(fields.building))
		meta:set_string("formspec", towntest_chest.formspec(pos,"chest"))
		towntest_chest.set_status(meta,1)
	end
end

-- on_construct
towntest_chest.on_construct = function(pos)
	-- setup chest meta and inventory
	local meta = minetest.env:get_meta(pos)
	meta:get_inventory():set_size("main", 8)
	meta:get_inventory():set_size("needed", 8*2)
	meta:get_inventory():set_size("builder", 2*2)
	meta:get_inventory():set_size("lumberjack", 2*2)
	meta:set_string("formspec", towntest_chest.formspec(pos, ""))
	towntest_chest.set_status(meta, 1)
end

-- register_node - the chest where you put the items
minetest.register_node("towntest_chest:chest", {
    description = "Building Chest",
	tiles = {"default_chest_top.png", "default_chest_top.png", "default_chest_side.png",
		"default_chest_side.png", "default_chest_side.png", "default_chest_front.png"},
	paramtype2 = "facedir",
	groups = {snappy=2,choppy=2,oddly_breakable_by_hand=2},
	legacy_facedir_simple = true,
	sounds = default.node_sound_wood_defaults(),
	on_construct = towntest_chest.on_construct,
	on_receive_fields = towntest_chest.on_receive_fields,
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		local k = pos.x..","..pos.y..","..pos.z
		if towntest_chest.npc[k] then
			towntest_chest.npc[k]:remove()
		end
		towntest_chest.npc[k] = nil
	end,
	on_punch = function(pos)
		towntest_chest.set_status(minetest.env:get_meta(pos))
	end,
	on_metadata_inventory_put = function(pos)
		towntest_chest.set_status(minetest.env:get_meta(pos),1)
	end,
	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		if from_list=="needed" or to_list=="needed" then return 0 end
		if from_list=="builder" or to_list=="builder" then return 0 end
		if from_list=="lumberjack" or to_list=="lumberjack" then return 0 end
		return count
	end,
	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		if listname=="needed" then return 0 end
		if listname=="builder" then return 0 end
		if listname=="lumberjack" then return 0 end
		return stack:get_count()
	end,
	allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		if listname=="needed" then return 0 end
		if listname=="builder" then return 0 end
		if listname=="lumberjack" then return 0 end
		return stack:get_count()
	end,
})

-- register_abm - builds the building
minetest.register_abm({
	nodenames = {"towntest_chest:chest"},
	interval = 0.5,
	chance = 1,
	action = towntest_chest.build,
})

-- log that we started
minetest.log("action", "[MOD]"..minetest.get_current_modname().." -- loaded from "..modpath)

