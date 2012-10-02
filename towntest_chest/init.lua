--[[

Towntest for Minetest

Copyright (c) 2012 cornernote, Brett O'Donnell <cornernote@gmail.com>
Source Code: https://github.com/cornernote/minetest-towntest
License: GPLv3

CHEST

]]--


-- expose api
towntest_chest = {}

-- table of non playing characters
towntest_chest.npc = {}

-- get_files 
-- returns a table containing buildings
towntest_chest.get_files = function()
	local modpath = minetest.get_modpath("towntest_chest")
	local output
	if os.getenv('HOME')~=nil then 
		os.execute('\ls -a "'..modpath..'/buildings/" | grep .we > "'..modpath..'/buildings/_buildings"') -- linux/mac
		local file, err = io.open(modpath..'/buildings/_buildings', "rb")
		if err ~= nil then
			return
		end
		output = file:lines()
	else
		output = io.popen('dir "'..modpath..'\\buildings\\*.we" /b'):lines()  -- windows
	end
    local i, t = 0, {}
    for filename in output do
        i = i + 1
        t[i] = filename
    end
    return t
end

-- load
-- filename - the building file to load
-- return - string containing the pos and nodes to build
towntest_chest.load = function(filename)
	local filepath = minetest.get_modpath("towntest_chest").."/buildings/"..filename
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

-- get_table - convert building table to string
-- building_string - string containing pos and nodes to build
-- return - table containing pos and nodes to build
towntest_chest.get_table = function(building_string)
	local building = {}
	for x, y, z, name, param1, param2 in building_string:gmatch("([+-]?%d+)%s+([+-]?%d+)%s+([+-]?%d+)%s+([^%s]+)%s+(%d+)%s+(%d+)[^\r\n]*[\r\n]*") do
		if tonumber(x)~=0 or tonumber(y)~=0 or tonumber(z)~=0 then
			table.insert(building, {x=x,y=y,z=z,name=name,param1=param1,param2=param2})
		end
	end
	return building
end

-- get_string - convert building string to table
-- building - table containing pos and nodes to build
-- return - string containing pos and nodes to build
towntest_chest.get_string = function(building)
	local building_string = ""
	for i,v in ipairs(building) do
		building_string = building_string..v.x.." "..v.y.." "..v.z.." "..v.name.." "..v.param1.." "..v.param2.."\n"
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
		if not materials[v.name] then
			materials[v.name] = 1
		else 
			materials[v.name] = materials[v.name]+1
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
		if inv:contains_item("builder", v.name) then
			-- check if npc is already moving
			if npc and not npc.target then
				table.remove(building_plan,i)
				-- move the npc to the build area
				npc:moveto({x=pos.x,y=pos.y+1.5,z=pos.z},2,2,0,function(self,after_param)
					-- take from the inv
					after_param.inv:remove_item("builder", after_param.v.name.." 1")
					-- add the node to the world
					minetest.env:add_node(after_param.pos, {name=after_param.v.name,param1=after_param.v.param1,param2=after_param.v.param2})
					-- update the chest building_plan
					meta:set_string("building_plan", towntest_chest.get_string(building_plan))
				end, {pos=pos,v=v,inv=inv,meta=meta})
			end
			return
		end
	end

	-- try to get items from chest into builder inventory
	local items_needed = true
	for i,v in ipairs(building_plan) do
		-- check if the chest has the node
		if inv:contains_item("main", v.name) then
			items_needed = false
			-- check if npc is already moving
			if npc and not npc.target then
				-- move the npc to the chest
				npc:moveto({x=chestpos.x,y=chestpos.y+1.5,z=chestpos.z},2,0,0,function(self,params)
					-- check for food
					local inv = params.inv
					local building_plan = params.building_plan
					if not inv:is_empty("main") then
						for i=1,inv:get_size("main") do
							-- check if this is a food, if so take it
							local stack = inv:get_stack("main", i)
							if not stack:is_empty() then
								local node = minetest.registered_nodes[stack:get_name()]
								if node.name == "default:apple" then
									local quality = 1
									npc.food = npc.food + (stack:get_count() * quality * 4)
									inv:set_stack("main", i, nil)
								elseif node.groups.food ~= nil then
									local quality = 4 - node.groups.food
									npc.food = npc.food + (stack:get_count() * quality * 4)
									inv:set_stack("main", i, nil)
								end
							end
						end
					end
					-- take from the inv
					for i,v in ipairs(building_plan) do
						if inv:contains_item("main",v.name.." 1") and inv:room_for_item("builder",v.name.." 1") then
							inv:add_item("builder",inv:remove_item("main",v.name.." 1"))
							inv:remove_item("needed", v.name.." 1")
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
	formspec = formspec 
		.."size[12,10]"
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
	meta:set_string("formspec", towntest_chest.formspec(pos))
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
		towntest_chest.npc[k]:remove()
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

-- register_on_generated - spawns the chest
minetest.register_on_generated(function(minp, maxp, blockseed)
	if math.random(1, 10) ~= 1 then
		return
	end
	local tmp = {x=(maxp.x-minp.x)/2+minp.x, y=(maxp.y-minp.y)/2+minp.y, z=(maxp.z-minp.z)/2+minp.z}
	local pos = minetest.env:find_node_near(tmp, maxp.x-minp.x, {"default:dirt_with_grass"})
	if pos ~= nil then
		minetest.env:set_node({x=pos.x, y=pos.y+1, z=pos.z}, {name="towntest_chest:chest"})
		print("chest added at "..dump(pos))
	end
end)

-- log that we started
minetest.log("action", "[MOD]"..minetest.get_current_modname().." -- loaded from "..minetest.get_modpath(minetest.get_current_modname()))
