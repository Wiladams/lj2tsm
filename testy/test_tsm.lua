package.path = "../?.lua;"..package.path

local ffi = require ("ffi")

local tsm = require("lj2tsm.tsm_ffi");
local TSMScreen = require("lj2tsm.TSMScreen")

local screen = TSMScreen();

print("Size: Default: ", screen:size())

screen:size(120,24);
print("Size(120, 24): ", screen:size())

--[[
typedef int (*tsm_screen_draw_cb) (struct tsm_screen *con,
				   uint32_t id,
				   const uint32_t *ch,
				   size_t len,
				   unsigned int width,
				   unsigned int posx,
				   unsigned int posy,
				   const struct tsm_screen_attr *attr,
				   tsm_age_t age,
				   void *data);
--]]
screen:size(80, 24)
local function drawScreen(screen, id, ch, len, width, posx, posy, attr, age, data)
	print("drawScreen: ", posx, posy, len, attr)

	return 0;
end
jit.off(drawScreen)

screen:draw(drawScreen)