--[[
 * PTY Bridge
 * The PTY bridge wraps multiple ptys in a single file-descriptor. It is
 * enough for the caller to listen for read-events on the fd.
 *
 * This interface is provided to allow integration of PTYs into event-loops
 * that do not support edge-triggered interfaces. There is no other reason
 * to use this bridge.
 */
--]]

local function shl_pty_bridge_new()
	local fd = libc.epoll_create1(libc.EPOLL_CLOEXEC);
	if (fd < 0) then
		return -ffi.errno();
	end

	return fd;
end

local function shl_pty_bridge_free(bridge)
	libc.close(bridge);
end

local function shl_pty_bridge_dispatch(int bridge, int timeout)

	struct epoll_event up, ev;
	struct shl_pty *pty;
	int fd, r;

	r = epoll_wait(bridge, &ev, 1, timeout);
	if (r < 0) then
		if (errno == EAGAIN || errno == EINTR)
			return 0;

		return -ffi.errno();
	end

	if (r == 0) then
		return 0;
	end

	pty = ev.data.ptr;
	r = shl_pty_dispatch(pty);
	if (r == -libc.EAGAIN) then
		--[[ EAGAIN means we couldn't dispatch data fast enough. Modify
		 * the fd in the epoll-set so we get edge-triggered events
		 * next round. 
		--]]
		libc.memset(&up, 0, sizeof(up));
		up.events = bor(libc.EPOLLIN, libc.EPOLLOUT, libc.EPOLLET);
		up.data.ptr = pty;
		fd = shl_pty_get_fd(pty);
		libc.epoll_ctl(bridge, libc.EPOLL_CTL_ADD, fd, &up);
	end

	return 0;
end

local function shl_pty_bridge_add(int bridge, struct shl_pty *pty)

	struct epoll_event ev;
	int r, fd;

	libc.memset(&ev, 0, ffi.sizeof(ev));
	ev.events = bor(libc.EPOLLIN, libc.EPOLLOUT, libc.EPOLLET);
	ev.data.ptr = pty;
	fd = shl_pty_get_fd(pty);

	r = libc.epoll_ctl(bridge, libc.EPOLL_CTL_ADD, fd, &ev);
	if (r < 0) then
		return -ffi.errno();
	end

	return 0;
end

local function  shl_pty_bridge_remove(int bridge, struct shl_pty *pty)

	int fd;

	fd = shl_pty_get_fd(pty);
	libc.epoll_ctl(bridge, libc.EPOLL_CTL_DEL, fd, NULL);
end
