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
towntest_chest.get_files = function(size)
	local directory = minetest.get_modpath("towntest_chest").."/buildings"
	local output
	if os.getenv('home')~=nil then 
		output = io.execute('ls -a "'..directory..'/*.we"') -- linux/mac
	else
		output = io.popen('dir "'..directory..'\\*.we" /b') -- windows
	end
    local i, t = 0, {}
    for filename in output:lines() do
        i = i + 1
        t[i] = filename
    end
    return t
end

-- load
towntest_chest.load = function(filename)
	local filepath = minetest.get_modpath("towntest_chest").."/buildings/"..filename
	local file, err = io.open(filepath, "rb")
	if err ~= nil then
		minetest.chat_send_player(placer:get_player_name(), "[towntest_chest] error: could not open file \"" .. filepath .. "\"")
		return
	end
	local contents = file:read("*a")
	file:close()
	return contents
end

-- get_table
towntest_chest.get_table = function(building_string)
	local building = {}
	for x, y, z, name, param1, param2 in building_string:gmatch("([+-]?%d+)%s+([+-]?%d+)%s+([+-]?%d+)%s+([^%s]+)%s+(%d+)%s+(%d+)[^\r\n]*[\r\n]*") do
		if tonumber(x)~=0 or tonumber(y)~=0 or tonumber(z)~=0 then
			table.insert(building, {x=x,y=y,z=z,name=name,param1=param1,param2=param2})
		end
	end
	return building
end

-- get_string
towntest_chest.get_string = function(building)
	local building_string = ""
	for i,v in ipairs(building) do
		building_string = building_string..v.x.." "..v.y.." "..v.z.." "..v.name.." "..v.param1.." "..v.param2.."\n"
	end
	return building_string
end

-- build
towntest_chest.build = function(chestpos)
	local meta = minetest.env:get_meta(chestpos)
	if meta:get_int("building_status")~=1 then return end
	local inv = meta:get_inventory()
	local building = towntest_chest.get_table(meta:get_string("building_plan"))
	local materials = {}
	for i,v in ipairs(building) do
		-- check if the chest contains the node
		if inv:contains_item("main", v.name) then
			-- create the npc
			local pos = {x=v.x+chestpos.x,y=v.y+chestpos.y,z=v.z+chestpos.z}
			local k = chestpos.x..","..chestpos.y..","..chestpos.z
			if not towntest_chest.npc[k] then
				towntest_chest.npc[k] = minetest.env:add_entity({x=chestpos.x,y=chestpos.y,z=chestpos.z}, "towntest_npc:builder")
				towntest_chest.npc[k]:get_luaentity():moveto({x=pos.x,y=pos.y+1.5,z=pos.z},0,1)
			end
			-- check if npc is already moving
			if not towntest_chest.npc[k]:get_luaentity().target then
				table.remove(building,i)
				-- move the npc
				towntest_chest.npc[k]:get_luaentity():moveto({x=pos.x,y=pos.y+1.5,z=pos.z},2,2,function(self,after_param)
					-- take from the inv
					after_param.inv:remove_item("main", after_param.v.name.." 1")
					after_param.inv:remove_item("needed", after_param.v.name.." 1")
					-- add the node to the world
					minetest.env:add_node(after_param.pos, {name=after_param.v.name,param1=after_param.v.param1,param2=after_param.v.param2})
					-- update the chest building plan
					meta:set_string("building_plan", towntest_chest.get_string(building))
				end, {pos=pos,v=v,inv=inv,meta=meta})
			end
			return true
		end
		-- make a list of materials needed
		if not materials[v.name] then
			materials[v.name] = 1
		else 
			materials[v.name] = materials[v.name]+1
		end
	end
	-- stop building and tell the player what we need
	towntest_chest.set_status(meta,0)
	if #building>0 then
		minetest.chat_send_player(meta:get_string("owner"), "[towntest_chest] materials not found in chest")
		towntest_chest.update_needed(meta:get_inventory(),building)
	end
end

-- formspec
towntest_chest.formspec = function(pos,page)
	local formspec = ""
	-- chest page
	if page=="chest" then
		formspec = formspec 
			.."size[8,9]"
			.."label[0,0; items needed:]"
			.."list[current_name;needed;0,0.5;8,2;]"
			.."label[0,2.5; put items here to build:]"
			.."list[current_name;main;0,3;8,1;]"
			.."list[current_player;main;0,5;8,4;]"
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

-- on_receive_fields
towntest_chest.on_receive_fields = function(pos, formname, fields, sender)
	local meta = minetest.env:get_meta(pos)
	if fields.building then
		meta:set_string("building_plan", towntest_chest.load(fields.building))
		meta:set_string("formspec", towntest_chest.formspec(pos,"chest"))
		towntest_chest.set_status(meta,1)
	end
end

-- update_needed
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

-- after_place_node
towntest_chest.after_place_node = function(pos,placer)
	-- setup chest meta and inventory
	local meta = minetest.env:get_meta(pos)
	meta:get_inventory():set_size("needed", 8*2)
	meta:get_inventory():set_size("main", 8)
	meta:set_string("formspec", towntest_chest.formspec(pos))
	meta:set_string("infotext", "Building Chest (inactive)")
	meta:set_string("owner", placer:get_player_name())
	-- add npc
	towntest_chest.npc[pos.x..","..pos.y..","..pos.z] = minetest.env:add_entity({x=pos.x,y=pos.y,z=pos.z}, "towntest_npc:builder")
	towntest_chest.npc[pos.x..","..pos.y..","..pos.z]:get_luaentity():moveto({x=pos.x,y=pos.y+1.5,z=pos.z},0,1)
end

-- can_dig
towntest_chest.can_dig = function(pos,player)
	if not minetest.env:get_meta(pos):get_inventory():is_empty("main") then
		return false
	end
	return true
end

-- set_status (or toggle if status not given)
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

-- register_node - the chest where you put the items
minetest.register_node("towntest_chest:chest", {
    description = "Building Chest",
	tiles = {"default_chest_top.png", "default_chest_top.png", "default_chest_side.png",
		"default_chest_side.png", "default_chest_side.png", "default_chest_front.png"},
	paramtype2 = "facedir",
	groups = {snappy=2,choppy=2,oddly_breakable_by_hand=2},
	legacy_facedir_simple = true,
	sounds = default.node_sound_wood_defaults(),
	after_place_node = towntest_chest.after_place_node,
	on_receive_fields = towntest_chest.on_receive_fields,
	can_dig = towntest_chest.can_dig,
	on_punch = function(pos)
		towntest_chest.set_status(minetest.env:get_meta(pos))
	end,
	on_metadata_inventory_put = function(pos)
		towntest_chest.set_status(minetest.env:get_meta(pos),1)
	end,
	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		if from_list=="needed" or to_list=="needed" then return 0 end
		return count
	end,
	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		if listname=="needed" then return 0 end
		return stack:get_count()
	end,
	allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		if listname=="needed" then return 0 end
		return stack:get_count()
	end,
})

-- register_abm
minetest.register_abm({
	nodenames = {"towntest_chest:chest"},
	interval = 0.5,
	chance = 1,
	action = towntest_chest.build,
})

-- log that we started
minetest.log("action", "[MOD]"..minetest.get_current_modname().." -- loaded from "..minetest.get_modpath(minetest.get_current_modname()))
