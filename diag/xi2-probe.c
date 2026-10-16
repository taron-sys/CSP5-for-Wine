/* X11 XInput2 probe: list devices, their classes and valuator labels —
 * shows exactly what Wine's tablet.c sees on your X server (XWayland).
 * Usage: ./xi2-probe [DISPLAY]   (without argument: $DISPLAY) */
#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    const char *display = (argc > 1 && argv[1][0] != '-') ? argv[1] : NULL;
    Display *dpy = XOpenDisplay(display);   /* NULL = $DISPLAY (not hard-coded :1!) */
    if (!dpy) { printf("FAIL: cannot open display %s\n",
                      display ? display : (getenv("DISPLAY") ? getenv("DISPLAY") : "(DISPLAY unset)")); return 1; }
    int opcode, event, err;
    if (!XQueryExtension(dpy, "XInputExtension", &opcode, &event, &err)) {
        printf("FAIL: no XInputExtension\n"); return 1;
    }
    int major = 2, minor = 2;
    if (XIQueryVersion(dpy, &major, &minor) != Success) {
        printf("FAIL: XIQueryVersion\n"); return 1;
    }
    printf("XInput2 %d.%d\n\n", major, minor);

    XIDeviceInfo *info, *dev;
    int ndevs;
    info = XIQueryDevice(dpy, XIAllDevices, &ndevs);
    for (int i = 0; i < ndevs; i++) {
        dev = &info[i];
        int interesting = 0;
        for (int c = 0; c < dev->num_classes; c++)
            if (dev->classes[c]->type == XIValuatorClass) { interesting = 1; break; }
        if (!interesting) continue; /* skip keyboards etc. */
        printf("device %-3d %-40s use=%d attached=%d\n",
               dev->deviceid, dev->name, dev->use, dev->attachment);
        for (int c = 0; c < dev->num_classes; c++) {
            XIAnyClassInfo *cl = dev->classes[c];
            if (cl->type == XIValuatorClass) {
                XIValuatorClassInfo *v = (XIValuatorClassInfo *)cl;
                char *lbl = v->label ? XGetAtomName(dpy, v->label) : NULL;
                printf("   valuator %-14s min=%-10.0f max=%-10.0f mode=%s%s\n",
                       lbl ? lbl : "(UNLABELED!)", v->min, v->max,
                       v->mode == XIModeAbsolute ? "abs" : "rel",
                       v->mode == XIModeAbsolute ? "" : "");
                if (lbl) XFree(lbl);
            } else if (cl->type == XITouchClass) {
                XITouchClassInfo *t = (XITouchClassInfo *)cl;
                printf("   touch class (%s)\n", t->mode == XIDirectTouch ? "direct" : "dependent");
            }
        }
        printf("\n");
    }
    XIFreeDeviceInfo(info);
    XCloseDisplay(dpy);
    return 0;
}