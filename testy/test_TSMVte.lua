package.path = "../?.lua;"..package.path

local ffi = require ("ffi")

local TSMVte = require("lj2tsm.TSMVte")

local vte, err = TSMVte();
print("vte: ", vte, err)


local function drawScreen(screen, id, ch, len, width, posx, posy, attr, age, data)
	io.write(string.format("drawScreen: %d %d %d ==> ", tonumber(posx), tonumber(posy), tonumber(len)))
	if len > 0 then
		io.write(string.char(ch[0]))
	end
	io.write('\n')

	return 0;
end
jit.off(drawScreen)

vte:input("Hello My World!")
vte.Screen:draw(drawScreen)
