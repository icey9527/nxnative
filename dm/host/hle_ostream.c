// The game logs through a std::ostream built in its static initialisers. On this build the
// stream reaches std::ostream::write without a vtable (see the bring-up log: sdk+0x5e193c,
// ldur x8,[x8,#-0x18] with x8 = 0), so the first log line aborts the process. The text is
// diagnostic only: drop it and let initialisation continue, until the stream's construction
// is understood (docs/agents/03-bringup.md).
#include "hle.h"
#include <mach/mach.h>

HLE_FORCE("_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE5writeEPKcl",
          "log text: the game's ostream is not materialised on this build; forwarded to the log",
          void *, h_ostream_write, void *self, const char *s, long n) {
    if (s && n > 0) { long k = n > 4000 ? 4000 : n; fprintf(stderr, "[game] %.*s", (int)k, s); }
    return self;
}
