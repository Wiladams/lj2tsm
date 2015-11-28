local ffi = require("ffi")
local bit = require("bit")
local lshift, rshift, band, bor = bit.lshift, bit.rshift, bit.band, bit.bor
local libc = require("tinylibc")

ffi.cdef[[
/*
 * Ring Buffer
 * Our PTY helper buffers outgoing data so the caller can rely on write
 * operations to always succeed (except for OOM). To buffer data in a PTY we
 * use a fast ring buffer to avoid heavy re-allocations on every write.
 *
 * Note that this allows users to use pty-writes for small data without
 * causing heavy allocations in the PTY layer. This is quite important for
 * keyboard-handling or other DEC-VT emulations.
*/

struct ringbuffer {
	char *buf;
	size_t size;
	size_t start;
	size_t ending;
} ringbuffer_t;
]]
local ringbuffer_t = ffi.typeof("struct ringbuffer")
local ringbuffer_mt = {}
ffi.metatype(ringbuffer_t, {
	__index = ringbuffer_mt;
})

local  function RING_MASK(_r, _v) 
	return band(_v, (_r.size - 1))
end

-- Compute next higher power-of-2 of @v. Returns 4096 in case v is 0. --]]
local function  ring_pow2(v)
	if (v == 0) then
		return 4096;
	end

	v = v - 1;

	local i = 1;
	while i < 8 * ffi.sizeof("size_t") do
		v = bor(v, rshift(v, i));
		i = i * 2;
	end

	return v+1;
end

--[[
 Resize ring-buffer to size @nsize. @nsize must be a power-of-2, otherwise
 ring operations will behave incorrectly.
--]]

function ringbuffer_mt.resize(r, nsize)

	local buf = ffi.cast("char *", libc.malloc(nsize));
	if (buf == nil) then
		return false, -libc.ENOMEM;
	end

	if (r.ending == r.start) then
		r.ending = 0;
		r.start = 0;
	elseif (r.ending > r.start) then
		libc.memcpy(buf, r.buf+r.start, r.ending - r.start);

		r.ending = r.ending - r.start;
		r.start = 0;
	else 
		libc.memcpy(buf, r.buf+r.start, r.size - r.start);
		libc.memcpy(buf+(r.size - r.start), r.buf, r.ending);

		r.ending = r.ending + r.size - r.start;
		r.start = 0;
	end

	libc.free(r.buf);
	r.buf = buf;
	r.size = nsize;

	return true;
end



--[[
 * Resize ring-buffer to provide enough room for @add bytes of new data. This
 * resizes the buffer if it is too small. It returns -ENOMEM on OOM and 0 on
 * success.
--]]
function ringbuffer_mt.grow(r, add)

	local len=0;

	--[[
	 * Note that "end == start" means "empty buffer". Hence, we can never
	 * fill the last byte of a buffer. That means, we must account for an
	 * additional byte here ("end == start"-byte).
	--]]

	if (r.ending < r.start) then
		len = r.start - r.ending;
	else
		len = r.start + r.size - r.ending;
	end

	-- don't use ">=" as "end == start" would be ambigious
	if (len > add) then
		return true;
	end

	-- +1 for additional "end == start" byte
	len = r.size + add - len + 1;
	len = ring_pow2(len);

	if (len <= r.size) then
		return false, -libc.ENOMEM;
	end

	return r:resize(len);
end

--[[
 * Push @len bytes from @u8 into the ring buffer. The buffer is resized if it
 * is too small. -ENOMEM is returned on OOM, 0 on success.
--]]
function ringbuffer_mt.push(r, u8, len)
	len = len or #u8
	u8 = ffi.cast("const char *", u8)
	local err=0;
	local l=0;

	local success, err = r:grow(len);
	if not success then
		return false, err;
	end

	if (r.start <= r.ending) then
		l = r.size - r.ending;
		if (l > len) then
			l = len;
		end

		libc.memcpy(r.buf+r.ending, u8, l);
		r.ending = RING_MASK(r, r.ending + l);

		len = len - l;
		u8 = u8 + l;
	end

	-- it was all copied in the trailing segment
	-- so we can return now.
	if (len == 0) then
		return true;
	end

	-- not all was copied, so copy into 
	-- the leading segment
	libc.memcpy(r.buf+r.ending, u8, len);
	r.ending = RING_MASK(r, r.ending + len);

	return true;
end

--[[
 * Get data pointers for current ring-buffer data. @vec must be an array of 2
 * iovec objects. They are filled according to the data available in the
 * ring-buffer. 0, 1 or 2 is returned according to the number of iovec objects
 * that were filled (0 meaning buffer is empty).
 *
 * Hint: "struct iovec" is defined in <sys/uio.h> and looks like this:
 *     struct iovec {
 *         void *iov_base;
 *         size_t iov_len;
 *     };
 --]]
function ringbuffer_mt.peek(r, vec)

	if (r.ending > r.start) then
		vec[0].iov_base = r.buf +r.start;
		vec[0].iov_len = r.ending - r.start;
		
		return 1;
	elseif (r.ending < r.start) then
		vec[0].iov_base = r.buf+r.start;
		vec[0].iov_len = r.size - r.start;
		vec[1].iov_base = r.buf;
		vec[1].iov_len = r.ending;
		return 2;
	else 
		return 0;
	end
end

--[[
 * Remove @len bytes from the start of the ring-buffer. Note that we protect
 * against overflows so removing more bytes than available is safe.
--]]
function ringbuffer_mt.pop(r, len)
	len = len or 1
	local l=0;

	if (r.start > r.ending) then
		l = r.size - r.start;
		if (l > len) then
			l = len;
		end

		r.start = RING_MASK(r, r.start + l);
		len = len - l;
	end

	if (len == 0) then
		return ;
	end

	l = r.ending - r.start;
	if (l > len) then
		l = len;
	end

	r.start = RING_MASK(r, r.start + l);
end

return ringbuffer_t;
