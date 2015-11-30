--[[

 * SHL - PTY Helpers
 *
 * Copyright (c) 2011-2013 David Herrmann <dh.herrmann@gmail.com>
 * Dedicated to the Public Domain

--]]

--[[
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pty.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/ioctl.h>
#include <sys/uio.h>
#include <termios.h>
#include <unistd.h>
--]]

local libc = require("tinylibc")
require "shl_pty_ffi"
local ringbuffer = require ("ring_buffer")


local close = libc.close;
local dup2 = libc.dup2;
local ioctl = libc.ioctl;
local free = libc.free;
local read = libc.read;
local write = libc.write;
local memset = libc.memset;


local int = ffi.typeof("int")


ffi.cdef[[
static const int SHL_PTY_BUFSIZE = 16384;
]]


--[[
 * PTY
 * A PTY object represents a single PTY connection between a master and a
 * child. The child process is fork()ed so the caller controls what program
 * will be run.
 *
 * Programs like /bin/login tend to perform a vhangup() on their TTY
 * before running the login procedure. This also causes the pty master
 * to get a EPOLLHUP event as long as no client has the TTY opened.
 * This means, we cannot use the TTY connection as reliable way to track
 * the client. Instead, we _must_ rely on the PID of the client to track
 * them.
 * However, this has the side effect that if the client forks and the
 * parent exits, we loose them and restart the client. But this seems to
 * be the expected behavior so we implement it here.
 *
 * Unfortunately, epoll always polls for EPOLLHUP so as long as the
 * vhangup() is ongoing, we will _always_ get EPOLLHUP and cannot sleep.
 * This gets worse if the client closes the TTY but doesn't exit.
 * Therefore, we the fd must be edge-triggered in the epoll-set so we
 * only get the events once they change. This has to be taken into by the
 * user of shl_pty. As many event-loops don't support edge-triggered
 * behavior, you can use the shl_pty_bridge interface.
 *
 * Note that shl_pty does not track SIGHUP, you need to do that yourself
 * and call shl_pty_close() once the client exited.
--]]



ffi.cdef[[
struct shl_pty {
	unsigned long ref;
	int fd;
	pid_t child;
	char in_buf[SHL_PTY_BUFSIZE];
	struct ringbuffer out_buf;

	shl_pty_input_cb cb;
	void *data;
};
]]

local 	SHL_PTY_FAILED = 0
local	SHL_PTY_SETUP = 1



local function pty_recv(int fd)

	local r = 0;
	local d = ffi.new("char[1]");

	repeat
		r = read(fd, d, 1);
	until (r >= 0 or (ffi.errno() ~= libc.EINTR and ffi.errno() ~= libc.EAGAIN));

	if r <= 0 then
		return SHL_PTY_FAILED
	end

	return d[0]
end

local function pty_send(int fd, char d)

	local r = 0;

	repeat
		r = write(fd, &d, 1);
	until (r >= 0 or (ffi.errno() ~= libc.EINTR and ffi.errno() ~= libc.EAGAIN));

	if r == 1 then return 0 end

	return -libc.EINVAL;

end

local function pty_setup_child(int slave,
			   term_width,
			   term_height)

	local attr = libc["struct termios"]();
	local ws = libc["struct winsize"]();

	-- get terminal attributes
	if (libc.tcgetattr(slave, attr) < 0) then
		return -ffi.errno();
	end

	-- erase character should be normal backspace, PLEASEEE!
	attr.c_cc[VERASE] = octal('010');

	-- set changed terminal attributes
	if (libc.tcsetattr(slave, libc.TCSANOW, attr) < 0) then
		return -ffi.errno();
	end


	memset(ws, 0, ffi.sizeof(ws));
	ws.ws_col = term_width;
	ws.ws_row = term_height;

	if (ioctl(slave, libc.TIOCSWINSZ, ws) < 0) then
		return -ffi.errno();
	end

	if (libc.dup2(slave, libc.STDIN_FILENO) ~= libc.STDIN_FILENO or
	    libc.dup2(slave, libc.STDOUT_FILENO) ~= libc.STDOUT_FILENO or
	    libc.dup2(slave, libc.STDERR_FILENO) ~= libc.STDERR_FILENO) then
		return -ffi.errno();
	end

	return 0;
end

static int pty_init_child(int fd)
{
	int r;
	sigset_t sigset;
	char *slave_name;
	int slave, i;
	pid_t pid;

	--[[ unlockpt() requires unset signal-handlers --]]
	sigemptyset(&sigset);
	r = sigprocmask(SIG_SETMASK, &sigset, NULL);
	if (r < 0)
		return -errno;

	for (i = 1; i < SIGUNUSED; ++i)
		signal(i, SIG_DFL);

	r = grantpt(fd);
	if (r < 0)
		return -errno;

	r = unlockpt(fd);
	if (r < 0)
		return -errno;

	slave_name = ptsname(fd);
	if (!slave_name)
		return -errno;

	--[[ open slave-TTY --]]
	slave = open(slave_name, O_RDWR | O_CLOEXEC | O_NOCTTY);
	if (slave < 0)
		return -errno;

	--[[ open session so we loose our controlling TTY --]]
	pid = setsid();
	if (pid < 0) {
		close(slave);
		return -errno;
	}

	--[[ set controlling TTY --]]
	r = ioctl(slave, TIOCSCTTY, 0);
	if (r < 0) {
		close(slave);
		return -errno;
	}

	return slave;
}

local function shl_pty_open(struct shl_pty **out,
		   shl_pty_input_cb cb,
		   void *data,
		   term_width,
		   term_height)

	struct shl_pty *pty;
	pid_t pid;
	int fd, comm[2], slave, r;
	char d;

	pty = calloc(1, sizeof(*pty));
	if (!pty)
		return -ENOMEM;

	fd = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC | O_NONBLOCK);
	if (fd < 0) {
		free(pty);
		return -errno;
	}

	r = pipe2(comm, O_CLOEXEC);
	if (r < 0) {
		r = -errno;
		close(fd);
		free(pty);
		return r;
	}

	pid = fork();
	if (pid < 0) {
		--[[ error --]]
		pid = -errno;
		close(comm[0]);
		close(comm[1]);
		close(fd);
		free(pty);
		return pid;
	} elseif (!pid) {
		--[[ child --]]
		close(comm[0]);
		free(pty);

		slave = pty_init_child(fd);
		close(fd);

		if (slave < 0)
			exit(1);

		r = pty_setup_child(slave, term_width, term_height);
		if (r < 0)
			exit(1);

		--[[ close slave if it's not one of the std-fds --]]
		if (slave > 2)
			close(slave);

		--[[ wake parent --]]
		pty_send(comm[1], SHL_PTY_SETUP);
		close(comm[1]);

		*out = NULL;
		return pid;
	}

	--[[ parent --]]
	close(comm[1]);

	pty.ref = 1;
	pty.fd = fd;
	pty.child = pid;
	pty.cb = cb;
	pty.data = data;

	--[[ wait for child setup --]]
	d = pty_recv(comm[0]);
	if (d ~= SHL_PTY_SETUP) then
		close(comm[0]);
		close(fd);
		free(pty);
		return -libc.EINVAL;
	end

	close(comm[0]);
	--*out = pty;

	return pid, pty;
end

local function shl_pty_ref(pty)

	if ((pty == nil) or pty.ref == 0) then
		return;
	end

	pty.ref = pty.ref + 1;
end

local function shl_pty_unref(struct shl_pty *pty)
	if pty == nil or ptr.ref == 0 then
		return;
	end

	pty.ref = pty.ref - 1;
	if ptr.ref > 0 then
		-- there are still outstanding references
		return;
	end

	shl_pty_close(pty);
	free(pty.out_buf.buf);
	free(pty);
end

local function shl_pty_close(pty)
	if (pty.fd < 0) then
		return;
	end

	close(pty.fd);
	pty.fd = -1;
end

local function shl_pty_is_open(pty)
	return pty.fd >= 0;
end

local function shl_pty_get_fd(pty)
	return pty.fd;
end

local function shl_pty_get_child(pty)
	return pty.child;
end

local function pty_write(pty)

	local vec = ffi.new("struct iovec[2]");

	local num = pty.out_buf:peek(vec);

	if (num == 0) then
		return;
	end

	-- ignore errors in favor of SIGCHLD; (we're edge-triggered, anyway)
	local r = writev(pty.fd, vec, int(num));
	if (r >= 0) then
		pty.out_buf:pop(r);
	end
end

local function pty_read(struct shl_pty *pty)

	local len=0;

	--[[
	 We're edge-triggered, means we need to read the whole queue. This,
	 * however, might cause us to stall if the writer is faster than we
	 * are. Therefore, we have some rather arbitrary limit on how fast
	 * we read. If we reach it, we simply return EAGAIN to the caller and
	 * let them deal with it.
	--]]

	local num = 50;
	repeat
		len = read(pty.fd, pty.in_buf, sizeof(pty.in_buf));
		if (len > 0) then
			pty.cb(pty, pty.in_buf, len, pty.data);
		end
	until (len <= 0 or --num ~= 0);

	if num == 0 then
		return -libc.EAGAIN;
	end

	return 0;
end

local function shl_pty_dispatch(pty)

	local r = pty_read(pty);
	pty_write(pty);

	return r;
end

local function shl_pty_write(struct shl_pty *pty, const char *u8, size_t len)

	if (!shl_pty_is_open(pty))
		return -ENODEV;

	return ring_push(&pty.out_buf, u8, len);
end

local function shl_pty_signal(struct shl_pty *pty, int sig)

	local r=0;

	if (shl_pty_is_open(pty) == 0) then
		return -libc.ENODEV;
	end

	r = ioctl(pty.fd, libc.TIOCSIG, sig);
	if r < 0 then
		return -ffi.errno()
	end

	return 0;
end

local function shl_pty_resize(pty, term_width, term_height)

	local ws = libc["struct winsize"];
	local r=0;

	if (shl_pty_is_open(pty)==0) then
		return -libc.ENODEV;
	end

	memset(ws, 0, ffi.sizeof(ws));
	ws.ws_col = term_width;
	ws.ws_row = term_height;

	--[[
	 * This will send SIGWINCH to the pty slave foreground process group.
	 * We will also get one, but we don't need it.
	--]]
	r = ioctl(pty.fd, libc.TIOCSWINSZ, ws);
	return (r < 0) ? -errno : 0;
end

