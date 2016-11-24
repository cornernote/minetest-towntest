--[[

Towntest for Minetest

Copyright (c) 2012 cornernote, Brett O'Donnell <cornernote@gmail.com>
Source Code: https://github.com/cornernote/minetest-towntest
License: BSD-3-Clause https://raw.github.com/cornernote/minetest-towntest/master/LICENSE

NPCs

]]--

local visual, visual_size, textures

function x(val) return ((val -80) / 160) end
function z(val) return ((val -80) / 160) end
function y(val) return ((val + 80) / 160) end

minetest.register_node("towntest_npc:builder_box", {
	tiles = {
		"towntest_npc_builder_top.png",
		"towntest_npc_builder_bottom.png",
		"towntest_npc_builder_front.png",
		"towntest_npc_builder_back.png",
		"towntest_npc_builder_left.png",
		"towntest_npc_builder_right.png",
	},
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			--head
			{x(95),y(-10), z(65), x(65), y(-40), z(95)},
			--neck
			{x(90),y(-40),z(70) , x(70), y(-50),z(90) },
			--body
			{x(90),y(-50), z(60), x(70), y(-100), z(100)},
			--legs
			{x(90),y(-100), z(60),x(70), y(-160),z(79) },
			{x(90),y(-100), z(81),x(70), y(-160), z(100)},
			--shoulders
			{x(89),y(-50), z(58), x(71),y(-68),z(60)},
			{x(89),y(-50), z(100),x(71) ,y(-68),z(102)},
			--left arm
			{x(139),y(-50),z(45),x(71),y(-63),z(58)},
			--right arm
			{x(89),y(-50),z(102),x(71),y(-100),z(115)},
			{x(115),y(-87),z(102),x(71),y(-100),z(115)},
		}
	},
})

minetest.register_entity("towntest_npc:builder", {
	hp_max = 1,
	physical = false,
	makes_footstep_sound = true,
	collisionbox = {-0.4, -1, -0.4, 0.4, 1, 0.4},

	visual_size = nil,
	visual = "wielditem",
	textures = {"towntest_npc:builder_box"},

	target = nil,
	speed = nil,
	range = nil,
	range_y = nil,
	after = nil,
	after_param = nil,

	food = 0,

	get_staticdata = function(self)
		return minetest.serialize({
			chestpos = self.chestpos,
			food = self.food,
		})
	end,

	on_activate = function(self, staticdata)
		local data = minetest.deserialize(staticdata)
		-- load chestpos
		if data and data.chestpos then
			local k = minetest.pos_to_string(data.chestpos)
			if towntest_chest.npc[k] then
				towntest_chest.npc[k]:remove()
			end
			towntest_chest.npc[k] = self.object
			self.chestpos = data.chestpos
		end
		-- load food
		if data and data.food then
			self.food = data.food
		end
	end,

	on_punch = function(self)
		-- remove npc from the list of npcs when they die
		if self.object:get_hp() <= 0 and self.chestpos then
			towntest_chest.npc[minetest.pos_to_string(self.chestpos)] = nil
		end
	end,

	on_step = function(self, dtime)
		-- remove
		if not self.chestpos then
			self.object:remove()
		end

		-- moveto
		if self.target and self.speed then
			local s = self.object:getpos()
			local t = self.target
			local diff = {x=t.x-s.x, y=t.y-s.y, z=t.z-s.z}

			local yaw = math.atan(diff.z / diff.x) + math.pi / 2
			if diff.x == 0 then
				if diff.z > 0 then
					yaw = math.pi / 2 -- face north
				else
					yaw = - math.pi / 2 -- face south
				end
			elseif diff.x > 0 then
				yaw = yaw - math.pi / 2
			end
			self.object:setyaw(yaw) -- turn and look in given direction

			if math.abs(diff.x) < self.range and math.abs(diff.y) < self.range_y and math.abs(diff.z) < self.range then
				self.object:setvelocity({x=0, y=0, z=0})
				self.target = "reached" --status the after_param is in process
				self.speed = nil
				if self.after then
					self.after(self, self.after_param) -- after they arrive
				end
				self.target = nil --self.after is done
				return
			end

			local v = self.speed
			if self.food > 0 then
				self.food = self.food - dtime
				v = v*4
			end
			local amount = (diff.x^2+diff.y^2+diff.z^2)^0.5
			local vec = {x=0, y=0, z=0}
			vec.x = diff.x*v/amount
			vec.y = diff.y*v/amount
			vec.z = diff.z*v/amount
			self.object:setvelocity(vec) -- walk in given direction
		-- idle
		else
			-- look around
			if math.random(50) == 1 then
				self.object:setyaw(self.object:getyaw()+((math.random(0,360)-180)/180*math.pi))
			end
		end

	end,

	-- API
	-- self: the lua entity
	-- pos: the position to move to
	-- range: the distance within pos the npc will go to
	-- range_y: the height within pos the npc will go to
	-- speed: the speed at which the npc will move
	-- after: callback function(self) which is triggered when the npc gets within range of pos
	moveto = function(self, pos, speed, range, range_y, after, after_param)
		self.target = pos
		self.speed = tonumber(speed) or 1
		self.range = tonumber(range) or 0.1
		self.range_y = tonumber(range_y) or 0.1
		if self.speed < 0.1 then self.speed = 0.1 end
		if self.range < 0.1 then self.range = 0.1 end
		if self.range_y < 0.1 then self.range_y = 0.1 end
		self.after = after
		self.after_param = after_param
	end
})

