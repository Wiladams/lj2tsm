# lj2tsm
LuaJIT binding to libtsm

tsm provides a fairly complete terminal emulation library.  There are two parts.
* Screen - this is the basic grid which represents what would actually be displayed
on a physical display.  libtsm doesn't actually perform any rendering operations, but
it does put characters in cells of this virtual screen, leaving the rendering to some other module.

* Terminal - This module takes keyboard and other input, which can contain terminal'
control sequences, and turns them into operations on the screen.  It essentially acts 
as a state machine, accumulating keyboard input until something interesting needs to 
happen to the associated screen.

You can use this binding in two different ways.  At the very least, you can use 
it as if you were programming in C, with a few enhancements.

```lua
local tsm = require("lj2tsm.tsm_ffi")

-- create a screen context
local handle = ffi.new("struct tsm_screen*[1]")
local logger = nil;
local log_data = nil;
local res = tsm.tsm_screen_new(handle, logger, log_data);

handle = handle[0];
ffi.gc(handle, tsm.tsm_screen_unref);

-- now go ahead and use the handle to perform other 
-- functions
-- change the size of the screen
local res = tsm.tsm_screen_resize(handle, 120, 32);
```

Programming this way would be fairly familiar to someone already
using libtsm, or C programmers in general.  Lua has a lot more to offer
in terms of convenience though.  The better way of doing things would be 
to use the convenient TSMScreen wrapper:

```lua
local TSMScreen = require("lj2tsm.TSMScreen")

local screen = TSMScreen();
screen:size(120,24);
print("Size(120, 24): ", screen:size())
```

In this case, an instance of a screen is created, using whatever defaults are
appropriate.  The properties on the screen are also treated using simple 
combined property set/get, such as the screen() function.  If you pass in 
parameters, it will assume you want to set the values.  If you don't pass in 
any parameters, it will assume you want to read the current value of the 
property.  

The screen by itself maintains a grid of cells.  Each cell contains a single
character, and attributes (color, underlining, whatever).  The screen maintains a 
cursor, and a size configurable 'history' buffer.  The screen can be scrolled, cleared, and the like.  The cursor position can be moved to explicitly, and 
characters written into the screen will automatically update the cursor location.

