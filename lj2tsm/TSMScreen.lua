--TSMScreen.lua]
local ffi = require("ffi")
local tsm = require("lj2tsm.tsm_ffi")

local TSMScreen = {}
setmetatable(TSMScreen, {
	__call = function(self, ...)
		return self:new(...);
	end,
})
local TSMScreen_mt = {
	__index = TSMScreen;
}

function TSMScreen.init(self, handle)
	local obj = {
		Handle = handle;
	}
	setmetatable(obj, TSMScreen_mt)

	return obj;
end

function TSMScreen.new(self, ...)
	local handle = ffi.new("struct tsm_screen*[1]")
	local logger = nil;
	local log_data = nil;
	local res = tsm.tsm_screen_new(handle, logger, log_data);

	if res ~= 0 then
		return nil;
	end

	handle = handle[0];
	ffi.gc(handle, tsm.tsm_screen_unref);
	return self:init(handle)
end

function TSMScreen.reset(self)
	tsm.tsm_screen_sb_reset(self.Handle);
end

function TSMScreen.clear(self)
	tsm.tsm_screen_clear_sb(self.Handle);

	return self;
end

function TSMScreen.size(self, width, height)
	if not width then
		return tsm.tsm_screen_get_width(self.Handle), tsm.tsm_screen_get_height(self.Handle)
	end

	if width and height then
		local res = tsm.tsm_screen_resize(self.Handle, width, height);
		return self;
	end

	return false;
end

function TSMScreen.cursorPosition(self, x, y)
	if not x then
		return tsm.tsm_screen_get_cursor_x(self.Handle),
			tsm.tsm_screen_get_cursor_y(self.Handle);
	end

	return self:moveTo(x, y)
end

function TSMScreen.moveTo(self, x, y)
	tsm.tsm_screen_move_to(self.Handle, x, y);
	return self;
end

function TSMScreen.moveUp(self, num, scroll)
	num = num or 1
	if scroll then scroll = 1 else scroll = 0 end

	tsm.tsm_screen_move_up(self.Handle, num, scroll);

	return self;
end

function TSMScreen.moveDown(self, num, scroll)
	num = num or 1
	if scroll then scroll = 1 else scroll = 0 end

	tsm.tsm_screen_move_down(self.Handle, num, scroll);

	return self;
end

function TSMScreen.moveRight(self, num)
	num = num or 1
	tsm.tsm_screen_move_right(self.Handle, num);

	return self;
end

function TSMScreen.moveLeft(self, num)
	num = num or 1;
	tsm.tsm_screen_move_left(self.Handle, num);

	return self;
end


--[[
	Writing to the screen
--]]
function TSMScreen.writeSymbol(self, ch, attr)
	if not attr then
		attr = tsm["struct tsm_screen_attr"]()
		attr.fccode = -1;
		attr.fb = 255;
	end

	ch = ch or 0
	if type(ch) == "string" then
		ch = string.byte(ch)
	end
	tsm.tsm_screen_write(self.Handle, ch, attr);

	return self;
end

function TSMScreen.draw(self, draw_cb)	

	local res = tsm.tsm_screen_draw(self.Handle, draw_cb, nil);

	return self;
end


function TSMScreen.writeString(self, str)
	for i=1,#str do
		self:writeSymbol(str:sub(i))
	end

	return self;
end


--[[
up
down
pageUp
pageDown
scrollUp
scrollDown


moveLineHome
moveLineEnd

moveTabRight
moveTabLeft
--]]


return TSMScreen
