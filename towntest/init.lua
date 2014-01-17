--[[

Towntest for Minetest

Copyright (c) 2012 cornernote, Brett O'Donnell <cornernote@gmail.com>
Source Code: https://github.com/cornernote/minetest-towntest
License: BSD-3-Clause https://raw.github.com/cornernote/minetest-towntest/master/LICENSE

]]--

-- expose api
towntest = {}

-- log that we started
minetest.log("action", "[MOD]"..minetest.get_current_modname().." -- loaded from "..minetest.get_modpath(minetest.get_current_modname()))
