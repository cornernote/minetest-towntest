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
local c_npc_imagination = 400
local c_npc_max_build_chunk = 2000

-- expose api
towntest_chest = {}

-- debug. Used for debug messages. In production the function should be empty
local dprint = function(...)
-- debug print. Comment out the next line if you don't need debug out
--	print(unpack(arg))
end
towntest_chest.dprint = dprint

-- We need a free item that always available to get visible working on them
towntest_chest.c_free_item = "default:cloud"

-- table of non playing characters
towntest_chest.npc = {}

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- nodes mapping functions
towntest_chest.mapping = {}
dofile(modpath.."/".."mapping.lua")

-- get worldedit parser load_schematic from worldedit mod
dofile(modpath.."/".."worldedit-serialization.lua")

-----------------------------------------------
-- get_files
-- no input parameters
-- returns a table containing buildings
-----------------------------------------------
function towntest_chest.get_files()
	local out = {}
	local files = minetest.get_dir_list(modpath .. "/buildings", false)

	for i=1, #files do
		table.insert(out, files[i])
	end
	table.sort(out,function(a,b) return a<b end)
	return out
end

-----------------------------------------------
-- load
-- filename - the building file to load
-- return - WE-Shema, containing the pos and nodes to build
-----------------------------------------------
function towntest_chest.load(filename)
	local filepath = modpath.."/buildings/"..filename
	local file, err = io.open(filepath, "rb")
	if err ~= nil then
		dprint("[towntest_chest] error: could not open file \"" .. filepath .. "\"")
		return
	end
	-- load the building starting from the lowest y
	local building_plan = towntest_chest.we_load_schematic(file:read("*a"))
	return building_plan
end

-----------------------------------------------
-- towntest_chest.mapnodes Take filters and actions on nodes before building. Currently the payment item determination and check for registred node only
-- node - Node (from file) to check if buildable and payable
-- return - node with enhanced informations
-----------------------------------------------
function towntest_chest.mapnodes(node)
	-- no name given - something wrong
	if not node or node.name == "" then
		return nil
	end

	local node_chk = minetest.registered_items[node.name]

	if not node_chk then
		local fallbacknode = towntest_chest.mapping.unknown_nodes(node)
		if fallbacknode then
			return towntest_chest.mapnodes(fallbacknode)
		end
	else
		-- known node Map them?
		local customizednode = towntest_chest.mapping.customize(node)

		if customizednode.name == "" then --disabled by mapping
			return nil
		end

		if not customizednode.matname then --no matname override customizied.

			--Check for price or if it is free
			local recipe = minetest.get_craft_recipe(node_chk.name)
			if (node_chk.groups.not_in_creative_inventory and --not in creative
					not (node_chk.groups.not_in_creative_inventory == 0) and
					(not recipe or not recipe.items)) --and not craftable
					or (not node_chk.description or node_chk.description == "") then -- no description
				if node_chk.drop and node_chk.drop ~= "" then
				-- use possible drop as payment
					if type(node_chk.drop) == "table" then -- drop table
						customizednode.matname = node_chk.drop[1] -- use the first one
					else
						customizednode.matname = node_chk.drop
					end
				else --something not supported, but known
					customizednode.matname = towntest_chest.c_free_item -- will be build for free. they are something like doors:hidden or second part of coffee lrfurn:coffeetable_back
				end
			else -- build for payment the 1:1
				customizednode.matname = customizednode.name
			end
		end
		return customizednode
	end
end

-----------------------------------------------
-- is_equal_meta - compare meta information of 2 nodes
-- name - Node name to check and map
-- return - item name used as payment
-----------------------------------------------
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


-----------------------------------------------
-- skip_already_placed - check if the nodes are already placed
-- building_plan - filtered/enriched WE-Chema to process
-- chestpos      - building chest position for alignment
-- return        - filtered/enriched WE-Chema to process, without already placed nodes
-----------------------------------------------
local function skip_already_placed(building_plan, chestpos)
	-- skip already right placed nodes. remove themfrom build plan. Usefull to resume the build
	local building_out = {}
	for idx, def in ipairs(building_plan) do
		local pos = {x=def.x+chestpos.x,y=def.y+chestpos.y,z=def.z+chestpos.z}
		if minetest.forceload_block(pos) then
			local node_placed = minetest.get_node(pos)
			if not (node_placed.drawtype == "airlike" and def.name == "air") then --skip all airlike
				if node_placed.name == def.name or node_placed.name == minetest.registered_nodes[def.name].name then -- right node is at the place. there are no costs to touch them
					if -- [(def.param1 ~= node_placed.param1 and not (def.param1 == nil and node_placed.param1 == 0)) or ]-- -- param1 (light) is can be changed
					(def.param2 ~= node_placed.param2 and not (def.param2 == nil and node_placed.param2 == 0)) then
						def.matname = towntest_chest.c_free_item -- adjust params for free
						table.insert(building_out, def)
						dprint("adjust params for free",def.name, def.param1, node_placed.param1, def.param2, node_placed.param2 )
					else
						if not def.meta then
	--						--same item without metadata. nothing to do
						elseif is_equal_meta(minetest.get_meta(pos):to_table(), def.meta) then
	--						--same metadata. Nothing to do
						else
							def.matname = towntest_chest.c_free_item --metadata correction for free
							table.insert(building_out, def)
							dprint("rebuild to correct metadata",def.name)
						end
					end
				else
					local mappeddef = towntest_chest.mapnodes(def)
					if not mappeddef or mappeddef.name == "" then -- excluded by mapping
						--skip
					else
						local mappednode = towntest_chest.mapnodes(node_placed)
						if mappednode and mappednode.matname == mappeddef.matname then
							def.matname = towntest_chest.c_free_item --same price. Check/set for free
							table.insert(building_out, def)
							dprint("rebuild for free because of the same matname",def.name)
						else
							table.insert(building_out, def) --rebuild for payment as usual
						end
					end
				end
			end
			minetest.forceload_free_block(pos)
		else
			dprint("cannot allocate node. Asume the rebuild is needed",def.name)
			table.insert(building_out, def) --rebuild for payment as usual
		end
	end
	return building_out
end

-----------------------------------------------
-- do_prepare_building preprocessing of WE shema to be usable as building_plan
-- building_in: WE shema
-- return - filtered/enriched WE-Chema to process
-----------------------------------------------
function towntest_chest.do_prepare_building(building_in)
	local building_out = {}
	local building_indexed = {}
	local sizing = {}
	for idx,def in pairs(building_in) do
		if (def.x and def.y and def.z) and -- more robust. Values should be existing
				(tonumber(def.x)~=0 or tonumber(def.y)~=0 or tonumber(def.z)~=0) then
			-- create sizing information
			if not sizing.min_x or sizing.min_x > def.x then
				sizing.min_x = def.x
			end
			if not sizing.max_x or sizing.max_x < def.x then
				sizing.max_x = def.x
			end
			if not sizing.min_y or sizing.min_y > def.y then
				sizing.min_y = def.y
			end
			if not sizing.max_y or sizing.max_y < def.y then
				sizing.max_y = def.y
			end
			if not sizing.min_z or sizing.min_z > def.z then
				sizing.min_z = def.z
			end
			if not sizing.max_z or sizing.max_z < def.z then
				sizing.max_z = def.z
			end

			-- map node
			local mapped_def = towntest_chest.mapnodes(def)
			if mapped_def and mapped_def.matname then -- found
				-- the node will be built
				table.insert(building_out, mapped_def)
				building_indexed[minetest.pos_to_string(def)] = true -- mark as build
			end
		end
	end
-- fill building with air
	for x = sizing.min_x -2, sizing.max_x + 2 do
		for y = sizing.min_y, sizing.max_y + 3 do
			for z = sizing.min_z - 2, sizing.max_z + 2 do
				if not building_indexed[minetest.pos_to_string({x=x, y=y, z=z})] and -- not in plan - flat them
					(x ~=0 or y ~=0 or z ~=0) then --not the chest
					local node = { x=x, y=y, z=z, name="air", matname = towntest_chest.c_free_item }
					table.insert(building_out, node)
				end
			end
		end
	end

	return building_out
end


-----------------------------------------------
-- update_needed - updates the needed inventory in the chest
-- inv - inventory object of the chest
-- building - table containing pos and nodes to build
-----------------------------------------------
function towntest_chest.update_needed(inv, building)
	dprint("update_needed - started")
	for i=1,inv:get_size("needed") do
		inv:set_stack("needed", i, nil)
	end

	if building == nil then
		return
	end

	local materials = {}

	-- sort by y to prefer lower nodes in building order. At the same level prefer nodes nearly the chest
	table.sort(building,function(a,b)
		if a and b then
			return ((a.y<b.y) or (a.y==b.y and a.x+a.z<b.x+b.z)) end
		end
	)
	dprint("update_needed - Building count:", #building)
	for i,v in ipairs(building) do
		if not materials[v.matname] then
			materials[v.matname] = {matname = v.matname, count = 1, order = i}
		else
			materials[v.matname].count = materials[v.matname].count+1
		end
		if i > (c_npc_imagination * 20) then --don't calculate all needs if it is really big value
			break
		end
	end

	dprint("update_needed - Materials:", #materials )
-- order the needed by building plan order
	local keys = {}
	for key in pairs(materials) do
		table.insert(keys, key)
	end

	table.sort(keys, function(a, b) return materials[a].order < materials[b].order end)

	for _, key in ipairs(keys) do
		inv:add_item("needed",materials[key].matname.." "..materials[key].count)
	end
	dprint("update_needed - finished")
end

-----------------------------------------------
-- set_status - activate or deactivate building
-- meta - meta object of the chest
-- status - integer (will toggle if status not given)
-----------------------------------------------
function towntest_chest.set_status(meta, status)
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
	dprint("status changed", meta:get_int("building_status"))
end


-----------------------------------------------
-- build - build a node of the structure
-- chestpos - the position of the chest containing the instructions
-----------------------------------------------
function towntest_chest.build(chestpos)

	-- load the building_plan
	local meta = minetest.env:get_meta(chestpos)
	if meta:get_int("building_status")~=1 then
		minetest.forceload_free_block(chestpos)
		return
	end

	dprint("build step started")
	local building_plan = minetest.deserialize((meta:get_string("building_plan")))

	-- create the npc if needed
	local inv = meta:get_inventory()
	local k = minetest.pos_to_string(chestpos)
	if not towntest_chest.npc[k] then
		towntest_chest.npc[k] = minetest.env:add_entity(chestpos, "towntest_npc:builder")
		towntest_chest.npc[k]:get_luaentity().chestpos = chestpos
		towntest_chest.npc[k]:get_luaentity():moveto({x=chestpos.x,y=chestpos.y+1.5,z=chestpos.z},1)
		if not inv:is_empty("builder") then
			for i=1,inv:get_size("builder") do
				inv:set_stack("builder", i, nil)
			end
		end
	end

	local npc = towntest_chest.npc[k]
	local npclua = npc:get_luaentity()

	if npclua and npclua.target == "reached" then
		dprint("build step cancelled because the npc is working")
		return --no thinking during working
	end

	local npcpos = npc:getpos()
	if not npcpos then --npc not reachable/unloaded
		dprint("npc away, disable forceload on the chest and skip processing")
		minetest.forceload_free_block(chestpos)
		return
	else
		-- something todo. keep the chest active
		minetest.forceload_block(chestpos) -- force the chest node is loade
	end

	dprint("NPC at", npcpos.x, npcpos.y, npcpos.z)
	local nextnode = {}

	-- building plan
	if building_plan then
		dprint("current building plan chunksize:", #building_plan)

		local laterprocnode = {}
		local buildable_counter = 0
		local really_stuck = false
		-- search for next buildable node from builder inventory
		dprint("start searching for the next node", #building_plan)
		for i,v in ipairs(building_plan) do
			-- is payed or for free and the item is at the end of building plan (all next items already built, to avoid all free items are placed at the first)
			if inv:contains_item("builder", v.matname) then
				local pos = {x=v.x+chestpos.x,y=v.y+chestpos.y,z=v.z+chestpos.z}
				local distance = math.abs(pos.x - npcpos.x) + math.abs(pos.y-(npcpos.y-10))*2 + math.abs(pos.z - npcpos.z)

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
			else
				-- not buildable anymore (material used up). remove from current building chunk
				table.remove(building_plan,i)
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
			elseif i > (c_npc_imagination * 5 ) then
				dprint("really stuck! try again at the next building step")
				really_stuck = true
				break
			end
		end
		if really_stuck == true then
			-- save current state and search again at the next step
			meta:set_string("building_plan", minetest.serialize(building_plan))
			return
		end
	end

	-- next buildable node found
	if nextnode.v then
		dprint("next node:", nextnode.v.name, nextnode.v.matname, "distance", nextnode.distance, "at", nextnode.pos.x, nextnode.pos.y, nextnode.pos.z)
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
					if after_param.v.matname then
						after_param.inv:remove_item("builder", after_param.v.matname.." 1")
					end
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

					-- update the chest building plan
					building_plan = minetest.deserialize(meta:get_string("full_plan"))
					for i,v in ipairs(building_plan) do
						if v.x == after_param.v.x and v.y == after_param.v.y and v.z == after_param.v.z then
							table.remove(building_plan,i)
							break
						end
					end
					meta:set_string("full_plan", minetest.serialize(building_plan))

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

		-- update the needed and sort
		local full_plan = minetest.deserialize(meta:get_string("full_plan"))
		if not full_plan then
			dprint("no plan")
			minetest.forceload_free_block(chestpos)
			return
		end
		
		towntest_chest.update_needed(meta:get_inventory(),full_plan)
		dprint("full plan is", #full_plan)
		if not full_plan then	 -- no plan. Finished work?
			npclua:moveto({x=chestpos.x,y=chestpos.y+1.5,z=chestpos.z},2)
			towntest_chest.set_status(meta,0)
			towntest_chest.update_needed(meta:get_inventory(),minetest.deserialize(meta:get_string("full_plan")))
			return
		end

		local items_needed = true
		for i,v in ipairs(full_plan) do
			-- check if the chest has the node
			if inv:contains_item("main", v.matname) or v.matname == towntest_chest.c_free_item then
				items_needed = false
				-- check if npc is already moving
				if npclua and not npclua.target then
					-- move the npc to the chest
					npclua:moveto({x=chestpos.x, y=chestpos.y+1.5, z=chestpos.z}, 2, 2, 0, function(self, params)
						-- check for food
						local inv = params.inv
						local full_plan = params.full_plan

						dprint("full plan is", #full_plan)
						local next_plan = {}
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

						--some free_items handling preparation
						local free_needed = 0
						local all_needed = #full_plan
						--get free needed count
						if not inv:is_empty("needed") then
							for i=1,inv:get_size("needed") do
								local stack = inv:get_stack("needed", i)
								if not stack:is_empty() and stack:get_name() == towntest_chest.c_free_item then
									free_needed = free_needed + stack:get_count()
								end
							end
						end
						local rarity_needed = 0
						if all_needed == free_needed then --free items only remeans
							rarity_needed = 1
						else
							rarity_needed = free_needed / (all_needed - free_needed) -- current rarity
						end
						dprint("rarity needed =", rarity_needed, "=", free_needed, all_needed)

						local free_selected = 0
						local all_selected = 0
						local rarity_selected = 0
						local free_nodes_pipe = {}
						for i,v in ipairs(full_plan) do
							-- take from the inv
							if inv:contains_item("main",v.matname.." 1") and inv:room_for_item("builder",v.matname.." 1") then
								inv:add_item("builder",inv:remove_item("main",v.matname.." 1"))
								inv:remove_item("needed", v.matname.." 1")
								all_selected = all_selected + 1
							end

							-- handle free items. There can be added, but relativelly to the needed
							if v.matname == towntest_chest.c_free_item and -- is free item
								#free_nodes_pipe < 10 then --limit for beter performance
								table.insert(free_nodes_pipe, v)
								dprint("free items pipeline:", #free_nodes_pipe)
							end

							for fnpi,fnp in ipairs(free_nodes_pipe) do
								if inv:room_for_item("builder",towntest_chest.c_free_item.." 1") then -- can be aplied
									if all_selected == free_selected then -- free only selected
										rarity_selected = 1
									else
										rarity_selected = free_selected / (all_selected - free_selected) -- current rarity
									end
									if rarity_selected <= rarity_needed then -- current selection have less rarity
										inv:add_item("builder", towntest_chest.c_free_item.." 1")
										inv:remove_item("needed", towntest_chest.c_free_item.." 1")
										free_selected = free_selected + 1
										all_selected = all_selected + 1
										table.remove(free_nodes_pipe,fnpi)
										table.insert(next_plan,fnp)
										dprint("rarity selected =", rarity_selected, "=", free_selected, all_selected)
										dprint("free item selected. left:", #free_nodes_pipe)
										if #free_nodes_pipe == 0 then
											break --exit free nodes pipe loop
										end
									end
								else
									free_nodes_pipe = {}
									dprint("free items requested: reset, no place")
									break --exit free nodes pipe loop
								end
							end

							-- create next chunk to be processed. only buildable items
							if v.matname ~= towntest_chest.c_free_item and -- free item already handled
									inv:contains_item("builder",v.matname.." 1")	then -- is in builder inventory
								table.insert(next_plan,v)
							end

							if i > c_npc_max_build_chunk then --limit the building plan chunk size
								break
							end
						end

						meta:set_string("building_plan", minetest.serialize(next_plan)) --save the used order
						dprint("next building plan chunk", #next_plan)
					end, {inv=inv,full_plan=full_plan})

				break --there is a update loop in moveto-function
				end
			end
		end

		-- stop building and tell the player what we need
		if npclua and items_needed then
			npclua:moveto({x=chestpos.x,y=chestpos.y+1.5,z=chestpos.z},2)
			towntest_chest.set_status(meta,0)
			towntest_chest.update_needed(meta:get_inventory(),minetest.deserialize(meta:get_string("full_plan")))
		end
	end
end


-----------------------------------------------
-- formspec - get the chest formspec
-----------------------------------------------
function towntest_chest.formspec(pos, page)
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
		firstpage = (firstpage - 1) * 30 + 1 -- 1, 31, 61, ...
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

-----------------------------------------------
-- on_receive_fields - called when a chest button is submitted
-----------------------------------------------
function towntest_chest.on_receive_fields(pos, formname, fields, sender)
	local meta = minetest.env:get_meta(pos)
	if fields.building then
		local we = towntest_chest.load(fields.building)
		if we then
			dprint("nodes loaded from file:", #we)
		end
		local filtered = towntest_chest.do_prepare_building(we)
		if filtered then
			dprint("nodes filtered:", #filtered)
		end
		local building_plan = skip_already_placed(filtered,pos)
		if building_plan then
			dprint("nodes in building plan:", #building_plan)
		end

		meta:set_string("full_plan", minetest.serialize(building_plan))
		meta:set_string("formspec", towntest_chest.formspec(pos,"chest"))
		towntest_chest.update_needed(meta:get_inventory(),building_plan)
		towntest_chest.set_status(meta,1)
	elseif fields.nav then
		meta:set_string("formspec", towntest_chest.formspec(pos, fields.nav))
	end
end

-----------------------------------------------
-- on_construct
-----------------------------------------------
function towntest_chest.on_construct(pos)
	-- setup chest meta and inventory
	local meta = minetest.env:get_meta(pos)
	meta:get_inventory():set_size("main", 8)
	meta:get_inventory():set_size("needed", 8*2)
	meta:get_inventory():set_size("builder", 2*2)
	meta:get_inventory():set_size("lumberjack", 2*2)
	meta:set_string("formspec", towntest_chest.formspec(pos, ""))
	meta:set_string("building_plan", "") -- delete previous building plan on this node
	meta:set_string("full_plan", "") -- delete previous building plan on this node
	towntest_chest.set_status(meta, 0) --inactive till a building was selected
	minetest.forceload_block(pos) -- force the chest node is loaded
	dprint("chest initialization done")
end

-----------------------------------------------
-- register_node - the chest where you put the items
-----------------------------------------------
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
		local k = minetest.pos_to_string(pos)
		if towntest_chest.npc[k] then
			towntest_chest.npc[k]:remove()
		end
		towntest_chest.npc[k] = nil
		minetest.forceload_free_block(pos)
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

-----------------------------------------------
-- register_abm - builds the building
-----------------------------------------------
minetest.register_abm({
	nodenames = {"towntest_chest:chest"},
	interval = 0.5,
	chance = 1,
	action = towntest_chest.build,
})

-----------------------------------------------
-- register craft recipe for the chest
-----------------------------------------------
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
