/* xi2-devname.c — prints the name of the X11 tablet device the WinTab helper
 * attaches to (one line on stdout, no decoration).
 *
 * Background: WineTab/XWinTab selects its device by name (default: a
 * substring "stylus"; overridable with $XWINTAB_DEVICE). Exactly the same rule
 * applies here, so that the printed name really describes the device in use.
 * The installer writes the output to
 * <CSP app directory>/XWinTabDeviceName.txt; the patched wintab32.dll reads
 * it for WTInfo(WTI_DEVICES, DVC_NAME) — so CSP reports a real device name
 * instead of a placeholder (see CSP-TABLET-FIX.md §7).
 *
 * Build:  gcc -O2 xi2-devname.c -o xi2-devname -lX11 -lXi
 * Usage:  ./xi2-devname              # name of the stylus (exit 1 if there is none)
 *         ./xi2-devname --list       # all devices, "*" = selected
 *         ./xi2-devname --all        # like --list, plus "pen" fallback
 *         DISPLAY=:0 ./xi2-devname   # other display ($DISPLAY is honoured)
 */
#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

static int has_valuator(XIDeviceInfo *dev)
{
    for (int c = 0; c < dev->num_classes; c++)
        if (dev->classes[c]->type == XIValuatorClass)
            return 1;
    return 0;
}

static int name_matches(const char *name, const char *needle)
{
    return name && needle && *needle && strcasestr(name, needle) != NULL;
}

int main(int argc, char **argv)
{
    const char *selector = getenv("XWINTAB_DEVICE");
    const char *display = NULL;
    int list = 0, allow_pen = 0, chosen = -1, pen_fallback = -1;
    Display *dpy;
    XIDeviceInfo *info;
    int ndevs;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--list"))       list = 1;
        else if (!strcmp(argv[i], "--all"))  { list = 1; allow_pen = 1; }
        else if (argv[i][0] != '-')           display = argv[i];
    }
    if (!selector || !*selector)
        selector = "stylus";           /* default of the helper */
    allow_pen = allow_pen || getenv("XWINTAB_DEVICE") == NULL;

    dpy = XOpenDisplay(display);
    if (!dpy) {
        fprintf(stderr, "xi2-devname: no X display (%s)\n",
                display ? display : (getenv("DISPLAY") ? getenv("DISPLAY") : "DISPLAY not set"));
        return 2;
    }
    {
        int opcode, event, err;
        if (!XQueryExtension(dpy, "XInputExtension", &opcode, &event, &err)) {
            fprintf(stderr, "xi2-devname: no XInput extension\n");
            XCloseDisplay(dpy);
            return 2;
        }
    }
    info = XIQueryDevice(dpy, XIAllDevices, &ndevs);
    if (!info) {
        fprintf(stderr, "xi2-devname: XIQueryDevice fehlgeschlagen\n");
        XCloseDisplay(dpy);
        return 2;
    }

    for (int i = 0; i < ndevs; i++) {
        if (!has_valuator(&info[i]))
            continue;
        if (chosen < 0 && name_matches(info[i].name, selector))
            chosen = i;
        else if (pen_fallback < 0 && name_matches(info[i].name, "pen"))
            pen_fallback = i;
    }
    if (chosen < 0 && pen_fallback >= 0)
        chosen = pen_fallback;          /* "pen" in the name, no "stylus" */

    if (list) {
        printf("Selection criterion: name contains \"%s\"%s\n", selector,
               chosen == pen_fallback && pen_fallback >= 0 ? " (Fallback: \"pen\")" : "");
        for (int i = 0; i < ndevs; i++) {
            if (!has_valuator(&info[i]))
                continue;
            printf("%s device %-3d %s\n", i == chosen ? "*" : " ", info[i].deviceid, info[i].name);
        }
    }

    int rc = 1;
    if (chosen >= 0) {
        printf("%s\n", info[chosen].name);
        rc = 0;
    } else if (!list) {
        fprintf(stderr, "xi2-devname: no device with \"%s\" in its name found "
                        "(tablet connected? --list shows all devices)\n", selector);
    }
    XIFreeDeviceInfo(info);
    XCloseDisplay(dpy);
    return rc;
}
