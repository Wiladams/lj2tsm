

/*
 * PTY Helpers
 */


#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

ffi.cdef[[
/* pty */

struct shl_pty;

typedef void (*shl_pty_input_cb) (struct shl_pty *pty, char *u8,
				  size_t len, void *data);

pid_t shl_pty_open(struct shl_pty **out,
		   shl_pty_input_cb cb,
		   void *data,
		   unsigned short term_width,
		   unsigned short term_height);
void shl_pty_ref(struct shl_pty *pty);
void shl_pty_unref(struct shl_pty *pty);
void shl_pty_close(struct shl_pty *pty);

bool shl_pty_is_open(struct shl_pty *pty);
int shl_pty_get_fd(struct shl_pty *pty);
pid_t shl_pty_get_child(struct shl_pty *pty);

int shl_pty_dispatch(struct shl_pty *pty);
int shl_pty_write(struct shl_pty *pty, const char *u8, size_t len);
int shl_pty_signal(struct shl_pty *pty, int sig);
int shl_pty_resize(struct shl_pty *pty,
		   unsigned short term_width,
		   unsigned short term_height);
]]

ffi.cdef[[
/* pty bridge */

int shl_pty_bridge_new(void);
void shl_pty_bridge_free(int bridge);

int shl_pty_bridge_dispatch(int bridge, int timeout);
int shl_pty_bridge_add(int bridge, struct shl_pty *pty);
void shl_pty_bridge_remove(int bridge, struct shl_pty *pty);
]]

