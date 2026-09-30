#include "lowlevel.h"
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <signal.h>
#include <spawn.h>
#include <unistd.h>

extern char **environ;

void wakeDisplay(void)
{
    static IOPMAssertionID assertionID;
    IOPMAssertionDeclareUserActivity(CFSTR("BLEUnlock"), kIOPMUserActiveLocal, &assertionID);
}

void sleepDisplay(void)
{
    // The old IODisplayWrangler "IORequestIdle" hack is only an idle hint, so
    // any PreventUserIdleDisplaySleep assertion (e.g. Parsec hosting) blocks
    // it. "pmset displaysleepnow" forces a user-initiated display sleep that
    // such assertions can't prevent. The delay lets the lock transition
    // settle first, otherwise loginwindow activity can cancel the sleep.
    static char *argv[] = {"/bin/sh", "-c",
                           "sleep 1; /usr/bin/pmset displaysleepnow", NULL};
    static int reaper_installed = 0;
    if (!reaper_installed) {
        signal(SIGCHLD, SIG_IGN);
        reaper_installed = 1;
    }
    pid_t pid;
    posix_spawn(&pid, "/bin/sh", NULL, NULL, argv, environ);
}
