/* XI1 probe: exactly what Wine's wintab.c sees via XListInputDevices */
#include <X11/Xlib.h>
#include <X11/extensions/XInput.h>
#include <stdio.h>

int main(void)
{
    Display *dpy = XOpenDisplay(":1");
    if (!dpy) { printf("FAIL: no display\n"); return 1; }
    XDeviceInfo *devs, *d;
    int n, i, j;
    devs = XListInputDevices(dpy, &n);
    if (!devs) { printf("XListInputDevices: NULL (0 devices)\n"); return 1; }
    printf("XListInputDevices: %d devices\n", n);
    for (i = 0; i < n; i++) {
        d = &devs[i];
        char *tname = d->type ? XGetAtomName(dpy, d->type) : NULL;
        printf("  [%d] %-38s type=atom-%lu(%s)  use=%d classes=%d\n",
               i, d->name ? d->name : "(null)", (unsigned long)d->type, tname ? tname : "(none)", d->use, d->num_classes);
        if (tname) XFree(tname);
        XAnyClassPtr ic = d->inputclassinfo;
        for (j = 0; j < d->num_classes; j++) {
            XAnyClassInfo *c = (XAnyClassInfo *)ic;
            if ((int)c->class == ValuatorClass) {
                XValuatorInfo *v = (XValuatorInfo *)c;
                printf("      valuator: axes=%d mode=%s\n", v->num_axes, v->mode == Absolute ? "Absolute" : "Relative");
                for (int a = 0; a < v->num_axes; a++) {
                    XAxisInfo *ax = &v->axes[a];
                    printf("        axis %d: min=%d max=%d res=%d\n", a, ax->min_value, ax->max_value, ax->resolution);
                }
            }
            ic = (XAnyClassPtr)((char *)ic + c->length);
        }
    }
    XFreeDeviceList(devs);
    XCloseDisplay(dpy);
    return 0;
}
