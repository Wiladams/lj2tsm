package.path = "../?.lua;"..package.path

local ffi = require ("ffi")

local TSMScreen = require("lj2tsm.TSMScreen")

local screen = TSMScreen();



local function drawScreen(screen, id, ch, len, width, posx, posy, attr, age, data)
	io.write(string.format("drawScreen: %d %d %d ==> ", tonumber(posx), tonumber(posy), tonumber(len)))
	if len > 0 then
		io.write(string.char(ch[0]))
	end
	io.write('\n')

	return 0;
end
jit.off(drawScreen)


screen:writeString("Hello World!")
screen:draw(drawScreen)
