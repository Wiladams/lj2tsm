-- TSMVte.lua
--[[
	TSM Virtual Terminal Emulator
	Maintains state, and is fed by keyboard activity
--]]

local ffi = require("ffi")
local tsm = require("lj2tsm.tsm_ffi")
local TSMScreen = require("lj2tsm.TSMScreen")


local TSMVte = {}
setmetatable(TSMVte, {
	__call = function(self, ...)
		return self:new(...);
	end,
})

local TSMVte_mt = {
	__index = TSMVte;
}

local function write_cb(vte, u8, len, data)
print("write_cb: ", u8, len, data)
end


function TSMVte.init(self, handle, screen)
	local obj = {
		Handle = handle;
		Screen = screen;
	}
	setmetatable(obj, TSMVte_mt)

	return obj;
end

function TSMVte.new(self)
	local screen, err = TSMScreen();
	if not screen then 
		return nil, err
	end

	local handle = ffi.new("struct tsm_vte*[1]")
	local logger = nil;
	local log_data = nil;
	local data = nil;
	local res = tsm.tsm_vte_new(handle, screen.Handle,
		write_cb, data,
		logger, log_data);

	if res ~= 0 then
		return nil, string.format("tsm_vte_new failed: %d", res)
	end

	handle = handle[0]
	ffi.gc(handle, tsm.tsm_vte_unref)

	return self:init(handle, screen)
end


function TSMVte.reset(self)
	tsm.tsm_vte_reset(self.Handle);
	
	return self;
end

function TSMVte.hardReset(self)
	tsm.tsm_vte_hard_reset(self.Handle);

	return self;
end

function TSMVte.input(self, buff, len)
	len = len or #buff

	tsm.tsm_vte_input(self.Handle, buff, len);

	return self;
end

function TSMVte.handleKeyboard(self, keysym, ascii, mods, unicode)
	local res = tsm.tsm_vte_handle_keyboard(self.Handle, keysym, ascii, mods, unicode);

	return res == 1
end


return TSMVte
