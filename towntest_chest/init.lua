--[[

Towntest for Minetest

Copyright (c) 2012 cornernote, Brett O'Donnell <cornernote@gmail.com>
Source Code: https://github.com/cornernote/minetest-towntest
License: BSD-3-Clause https://raw.github.com/cornernote/minetest-towntest/master/LICENSE

CHEST

]]--


--if the value is to big, it can happen the builder stucks and just stay (beter hardware required in RL)
--if to low, it can happen the searching next near node is poor and the builder acts overwhelmed, fail to see some nearly gaps. The order seems to be randomized
--the right value is depend on building size. If the building (or the not builded rest) can full imaginated (less blocks in building then c_npc_imagination) there is the full search potencial active
local c_npc_imagination = 600


-- expose api
towntest_chest = {}

-- table of non playing characters
towntest_chest.npc = {}


-- debug. Used for debug messages. In production the function should be empty
local function dprint(...)
-- debug print. Comment out the next line if you don't need debug out
--	print(unpack(arg))
end

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- get worldedit parser load_schematic from worldedit mod
dofile(modpath.."/".."worldedit-serialization.lua")

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
	table.sort(t,function(a,b) return a<b end)
	return t
end

-- load
-- filename - the building file to load
-- return - WE-Shema, containing the pos and nodes to build
towntest_chest.load = function(filename)
	local filepath = modpath.."/buildings/"..filename
	local file, err = io.open(filepath, "rb")
	if err ~= nil then
		minetest.chat_send_player(placer:get_player_name(), "[towntest_chest] error: could not open file \"" .. filepath .. "\"")
		return
	end
	-- load the building starting from the lowest y
	local building_plan = towntest_chest.we_load_schematic(file:read("*a"))
	return building_plan
end


-- mapname Take filters and actions on nodes before building. Currently the payment item determination and check for registred node only
-- name - Node name to check and map
-- return - item name used as payment
local function mapname(name)
	-- no name given - something wrong
	if not name then
		return nil
	end

	-- item table (can be happen in drops). Search for the first valid one
	if type(name) == "table" then -- drop table. Search for "any payment"
		for _, namex in pairs(name) do
			local validname = mapname(namex)
			if validname then
				return validname
			else
				--nothing valid found
				return nil
			end
		end
	end

	local node = minetest.registered_items[name]

	if not node then
		dprint("unknown node in building: "..name)
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


-- is_equal_meta - compare meta information of 2 nodes
-- name - Node name to check and map
-- return - item name used as payment
local function is_equal_meta(a,b)
	local typa = type(a)
	local typb = type(b)
	if typa ~= typb then
		return false
	end

	if typa == "table" then
		if #a ~= #b then
			return false
		else
			for i,v in ipairs(a) do
				if not is_equal_meta(a[i],b[i]) then
					return false
				end
			end
			return true
		end
	else
		if a == b then
			return true
		end
	end
end


-- skip_already_placed - check if the nodes are already placed
-- building_plan - filtered/enriched WE-Chema to process
-- chestpos      - building chest position for alignment
-- return        - filtered/enriched WE-Chema to process, without already placed nodes
local function skip_already_placed(building_plan, chestpos)
	-- skip already right placed nodes. remove themfrom build plan. Usefull to resume the build
	local building_out = {}
	for idx, def in ipairs(building_plan) do
		local pos = {x=def.x+chestpos.x,y=def.y+chestpos.y,z=def.z+chestpos.z}
		local node_placed = minetest.get_node(pos)
		if node_placed.name == def.name then -- right node is at the place. there are no costs to touch them
			if not def.meta then
--				--same item without metadata. nothing to do
			elseif is_equal_meta(minetest.get_meta(pos):to_table(), def.meta) then
--				--same metadata. Nothing to do
			else
				def.matname = "free"       --metadata correction for free
				table.insert(building_out, def)
			end
		elseif mapname(node_placed.name) == mapname(def.name) then
				def.matname = "free"        --same price. Check/set for free
				table.insert(building_out, def)
		else
			table.insert(building_out, def) --rebuild for payment as usual
		end
	end

	return building_out
end

-- do_prepare_building preprocessing of WE shema to be usable as building_plan
-- building_in: WE shema
-- return - filtered/enriched WE-Chema to process
towntest_chest.do_prepare_building = function(building_in)
	local building_out = {}
	for idx,def in pairs(building_in) do
		if (def.x and def.y and def.z) and -- more robust. Values should be existing
		   (tonumber(def.x)~=0 or tonumber(def.y)~=0 or tonumber(def.z)~=0) then
			if not def.matname then
				def.matname = mapname(def.name)
			end
			if def.matname then -- found
				-- the node will be built
				table.insert(building_out, {x=def.x,y=def.y,z=def.z,name=def.name,param1=def.param1,param2=def.param2,meta=def.meta,matname=def.matname})
			end
		end
	end
	return building_out
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
	local building_plan = minetest.deserialize((meta:get_string("building_plan")))
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
		if building_plan then
			towntest_chest.update_needed(meta:get_inventory(),building_plan)
		end
	end

	local npc = towntest_chest.npc[k]
	local npclua = npc:get_luaentity()

	-- no building plan
	if not building_plan then
		-- move the npc to the chest
		dprint("no building plan")
		npclua:moveto({x=chestpos.x,y=chestpos.y+1.5,z=chestpos.z},2,2)
		towntest_chest.set_status(meta,0)
		return
	end

	-- search for next buildable node from builder inventory
	local npcpos = npc:getpos()
	if not npcpos then --fallback
		npcpos = chestpos
	end
	local nextnode = {}
	local laterprocnode = {}
	local buildable_counter = 0
	dprint("building plan size", #building_plan)
	for i,v in ipairs(building_plan) do
		-- is payed or for free and the item is at the end of building plan (all next items already built, to avoid all free items are placed at the first)
		if inv:contains_item("builder", v.matname) or v.matname == "free" then
			local pos = {x=v.x+chestpos.x,y=v.y+chestpos.y,z=v.z+chestpos.z}
			local distance = math.abs(pos.x - npcpos.x) + math.abs(pos.y-(npcpos.y-10))*2 + math.abs(pos.z - npcpos.z)

			if 	v.matname ~= "free" or	(distance < 20 or i > (#building_plan-2)) then
				--buildable and payale / or build the free items if it is really nearly, or if it is at the end of the building plan

				buildable_counter = buildable_counter + 1
				if not nextnode.v or (distance < nextnode.distance) then
					nextnode.v = v
					nextnode.i = i
					nextnode.pos = pos
					nextnode.distance = distance
				elseif not laterprocnode.v or (distance > laterprocnode.distance) then -- the widest node in plan
					laterprocnode.v = v
					laterprocnode.i = i
					laterprocnode.pos = pos
					laterprocnode.distance = distance
				end
			end
		else
			-- not buildable at the time. Move to the end of plan till next grabbing from chest
			-- for better chance to find buildable in the next run (c_npc_imagination pack)
			table.remove(building_plan,i)
			table.insert(building_plan,v)
		end
			--respect "c_npc_imagination"
			if i > c_npc_imagination and nextnode.v then
				dprint("stuck at:", buildable_counter)
				if laterprocnode.v then
					--move the widest node to the end of building plan to get a new slot free it next build tick
					--maybe an other node can be found nearly
					if buildable_counter >= c_npc_imagination-1 then
						table.remove(building_plan,laterprocnode.i)
						table.insert(building_plan,laterprocnode.v)
						dprint("move to end of plan:", laterprocnode.v.name, "distance", laterprocnode.distance)
					end
					laterprocnode.v = nil
				end
				break
			end

	end

	-- next buildable node found
	if nextnode.v then
		dprint("next node:", nextnode.v.name, nextnode.v.matname, "distance", nextnode.distance)
		-- check if npc is on the way or waiting. We can change the route in this case
		if npclua and npclua.target ~= "reached" then
			meta:set_string("building_plan", minetest.serialize(building_plan))

			if not npclua.target or npclua.target.x ~= nextnode.pos.x or npclua.target.y ~= nextnode.pos.y+1.5 or npclua.target.z ~= nextnode.pos.z then
				if npclua.target then
					dprint("route changed!! old route was:", npclua.target.x, npclua.target.y, npclua.target.z)
				end

				-- move the npc to the build area
				npclua:moveto({x=nextnode.pos.x, y=nextnode.pos.y+1.5, z=nextnode.pos.z}, 2, 2, 0, function(self,after_param)
					-- take from the inv
					after_param.inv:remove_item("builder", after_param.v.matname.." 1")
					-- add the node to the world
					minetest.env:add_node(after_param.pos, {name=after_param.v.name,param1=after_param.v.param1,param2=after_param.v.param2})
					if after_param.v.meta then
						minetest.env:get_meta(after_param.pos):from_table(after_param.v.meta)
					end
					dprint("placed:", after_param.v.name, after_param.v.matname, "at", after_param.v.x, after_param.v.y, after_param.v.z)
					-- update the chest building_plan
					local building_plan = minetest.deserialize(meta:get_string("building_plan"))
					for i,v in ipairs(building_plan) do
						if v.x == after_param.v.x and v.y == after_param.v.y and v.z == after_param.v.z then
							table.remove(building_plan,i)
							break
						end
					end
					meta:set_string("building_plan", minetest.serialize(building_plan))
				end, {pos=nextnode.pos, v=nextnode.v, inv=inv, meta=nextnode.meta})
			else
				if npclua.target then
					dprint("same route recalculated:", npclua.target.x, npclua.target.y, npclua.target.z)
				end
			end
		end
		nextnode.v = nil

	else
		dprint("<<--- get new items and re-sort building plan --->>>")

		-- sort by y to prefer lower nodes in building order. At the same level prefer nodes nearly the chest
		table.sort(building_plan,function(a,b)
			if a and b then
				return ((a.y<b.y) or (a.y==b.y and a.x+a.z<b.x+b.z)) end
			end
		)

		-- try to get items from chest into builder inventory
		meta:set_string("building_plan", minetest.serialize(building_plan)) --save the used order
		local items_needed = true
		for i,v in ipairs(building_plan) do
			-- check if the chest has the node
			if inv:contains_item("main", v.matname) then
				items_needed = false
				-- check if npc is already moving
				if npclua and not npclua.target then
					-- move the npc to the chest
					npclua:moveto({x=chestpos.x, y=chestpos.y+1.5, z=chestpos.z}, 2, 2, 0, function(self, params)
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
										npclua.food = npclua.food + (stack:get_count() * quality * 4)
										inv:set_stack("main", i, nil)
									elseif node and node.groups.food ~= nil then
										local quality = 4 - node.groups.food
										npclua.food = npc.foodlua + (stack:get_count() * quality * 4)
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
		if npclua and items_needed then
			npclua:moveto({x=chestpos.x,y=chestpos.y+1.5,z=chestpos.z},2)
			towntest_chest.set_status(meta,0)
			towntest_chest.update_needed(meta:get_inventory(),building_plan)
		end
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
	local firstpage = 1
	if string.sub(page,0,5) == "page_" then
		firstpage = tonumber(string.sub(page,6))
		firstpage = (firstpage - 1) * 30 + 1  -- 1, 31, 61, ...
	end
	local lastpage = #pages
	if lastpage >= firstpage + 30 then
		lastpage = firstpage + 30 -1
	end

	for i = firstpage,lastpage,1 do
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
	local nav = {}
	nav.back = 0 --initialized for nav.next calculation
	if firstpage > 1 then
		if firstpage - 30 < 1 then
			nav.back = 1
		else
			nav.back = (firstpage - 1) / 30
		end
		formspec = formspec .."button[1,10;2,0.5;nav;page_"..nav.back.."]"
	end
	if #pages >= firstpage + 30 then
		nav.next = nav.back + 2
		formspec = formspec .."button[9,10;2,0.5;nav;page_"..nav.next.."]"
	end
	return formspec
end

-- on_receive_fields - called when a chest button is submitted
towntest_chest.on_receive_fields = function(pos, formname, fields, sender)
	local meta = minetest.env:get_meta(pos)
	if fields.building then
		local we = towntest_chest.load(fields.building)
		if we then
			dprint("nodes loaded from file:", #we)
		end
		local filtered = towntest_chest.do_prepare_building(we)
		local building_plan = skip_already_placed(filtered,pos)
		if building_plan then
			dprint("nodes in building plan:", #building_plan)
		end

		meta:set_string("building_plan", minetest.serialize(building_plan))
		meta:set_string("formspec", towntest_chest.formspec(pos,"chest"))
		towntest_chest.set_status(meta,1)
		towntest_chest.update_needed(meta:get_inventory(),building_plan)
	elseif fields.nav then
		meta:set_string("formspec", towntest_chest.formspec(pos, fields.nav))
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
	meta:set_string("building_plan", "") -- delete previous building plan on this node
	towntest_chest.set_status(meta, 0) --inactive till a building was selected
	dprint("chest initialization done")
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


minetest.register_craft({
	output = 'towntest_chest:chest',
	recipe = {
		{'default:mese_crystal', 'default:chest_locked', 'default:mese_crystal'},
		{'default:book', 'default:diamond', 'default:book'},
		{'default:mese_crystal', 'default:chest_locked', 'default:mese_crystal'},
	}
})

-- log that we started
minetest.log("action", "[MOD]"..minetest.get_current_modname().." -- loaded from "..modpath)
