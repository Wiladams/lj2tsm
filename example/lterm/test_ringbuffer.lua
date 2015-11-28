--test_ringbuffer.lua
local ffi = require("ffi")
local ringbuffer = require("ring_buffer")

local rb = ringbuffer();

print("push: ", rb:push("Hello World!"))

local count = 1;

local vec = ffi.new("struct iovec[2]")
local res = rb:peek(vec)

print("vec: ", res)
while res > 0 do
	print(ffi.string(vec[res-1].iov_base, vec[res-1].iov_len ))
	res = res - 1;
end


