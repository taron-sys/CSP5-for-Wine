/* xdlg.c — small X helper for CSP under Wine/Xwayland.
 * Used by run-csp.sh (dismiss dialog) and verify.sh --panels (menu probe);
 * built with gcc. Only libX11 + libXtst, no further package needed.
 *
 *   xdlg dismiss N   Clicks away the dialog "CLIP STUDIO was not closed properly
 *                    last time".
 *                    The dialog is WM_CLASS=clipstudio.exe, _NET_WM_NAME="CLIP STUDIO",
 *                    596x116 in size and blocks the app until it is gone — as long as it
 *                    is open, WebView2 does not start (Hub/menu stay empty).
 *                    Searches for N*0.5 s.
 *                    NOTE: only works if the click hits the right spot —
 *                    Wine swallows clicks on unfocused windows. Several candidate
 *                    positions are tried; after that it gives up (the button can
 *                    always be clicked by hand).
 *
 *   xdlg grid N      Opens the Hub menu: first waits ~20 s (WebView2 needs that long),
 *                    then clicks the grid icon at the top right of the Hub window
 *                    (width >= 700) and checks whether the menu window appears.
 *                    Repeats that up to N times (every 3 s). Exit 0 = menu open,
 *                    1 = not open, 2 = no X display.
 *
 *   xdlg check N     like `grid N` (kept for compatibility).
 */
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <X11/keysym.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* --- small helpers ------------------------------------------------------- */

static char *prop(Display *d, Window w, const char *name, long *n)
{
    Atom a = XInternAtom(d, name, False), type; int fmt; unsigned long ni, ba;
    unsigned char *v = NULL; *n = 0;
    if (a == None) return NULL;
    if (XGetWindowProperty(d, w, a, 0, 1024, False, AnyPropertyType,
                           &type, &fmt, &ni, &ba, &v) != Success || !v) return NULL;
    *n = ni; return (char *)v;
}

static int is_clipstudio(Display *d, Window w)
{
    long n = 0; char *cls = prop(d, w, "WM_CLASS", &n);
    int ok = cls && n && strstr(cls, "clipstudio");
    if (cls) free(cls);
    return ok;
}

/* --- three kinds of windows --------------------------------------------- */

/* Dialog "not closed properly": height 90..200
 *
 * Two ways, in this order:
 *   1) Raise the window, set input focus on it, send `Return`. This is the
 *      reliable way — a plain mouse click on the button is swallowed by Wine
 *      as long as the window does not have input focus (verified empirically:
 *      `XRaiseWindow` + `XSetInputFocus` + `Return` closes the dialog, a click
 *      alone does not — not even several in a row).
 *   2) Fallback: click the button "Open CLIP STUDIO" directly (at 596x116 roughly
 *      42 % of the width and 20 px above the bottom edge).
 * After both ways it is checked whether the dialog is really gone; otherwise
 * "dialog-open" is reported honestly instead of faking success. */
static int hit_dialog(Display *d, Window w)
{
    XWindowAttributes at;
    if (is_clipstudio(d, w) && XGetWindowAttributes(d, w, &at)
        && at.map_state == IsViewable && at.height > 90 && at.height < 200
        && at.width > 300) {
        int rx, ry; Window ch;
        XWindowAttributes a2;

        /* First: raise the window, set the input focus on it and send Return.
         * This is the reliable way — a plain mouse click on the button is
         * swallowed by Wine as long as the window does not have the focus
         * (verified empirically: XRaiseWindow + XSetInputFocus + Return closes the
         * dialog, a click alone does not). */
        XRaiseWindow(d, w);
        XSetInputFocus(d, w, RevertToPointerRoot, CurrentTime);
        XSync(d, False);
        usleep(400000);
        XTestFakeKeyEvent(d, XK_Return, True, 0);
        XTestFakeKeyEvent(d, XK_Return, False, 0);
        XSync(d, False);
        usleep(900000);
        if (!XGetWindowAttributes(d, w, &a2) || a2.map_state != IsViewable) {
            printf("dismissed %dx%d (fokus+Return)\n", at.width, at.height); fflush(stdout);
            return 1;
        }

        /* Fallback: click the button "Open CLIP STUDIO" directly. */
        XTranslateCoordinates(d, w, at.root,
                              (int)(at.width * 0.42), at.height - 20, &rx, &ry, &ch);
        XTestFakeMotionEvent(d, -1, rx, ry, 0);
        XTestFakeButtonEvent(d, 1, True, 0);
        XTestFakeButtonEvent(d, 1, False, 0);
        XSync(d, False);
        usleep(900000);
        if (!XGetWindowAttributes(d, w, &a2) || a2.map_state != IsViewable) {
            printf("dismissed %dx%d (button %d,%d)\n", at.width, at.height, rx, ry);
            fflush(stdout);
            return 1;
        }

        printf("dialog-open %dx%d (button stayed open)\n", at.width, at.height); fflush(stdout);
        return 0;
    }
    return 0;
}

/* Hub window: wide and tall; optionally click the grid icon */
static int hit_hub(Display *d, Window w, int do_click)
{
    XWindowAttributes at;
    if (is_clipstudio(d, w) && XGetWindowAttributes(d, w, &at)
        && at.map_state == IsViewable && at.width >= 700 && at.height >= 400) {
        if (do_click) {
            int rx, ry; Window ch;
            XTranslateCoordinates(d, w, at.root, at.width - 32, 56, &rx, &ry, &ch);
            XTestFakeMotionEvent(d, -1, rx, ry, 0);
            XTestFakeButtonEvent(d, 1, True, 0);
            XTestFakeButtonEvent(d, 1, False, 0);
            printf("grid %dx%d -> click %d,%d\n", at.width, at.height, rx, ry); fflush(stdout);
        }
        return 1;
    }
    return 0;
}

/* Menu window: small, but with real area (113x2 = broken, 496x704 = good) */
static int hit_menu(Display *d, Window w, int *mw, int *mh)
{
    XWindowAttributes at;
    if (is_clipstudio(d, w) && XGetWindowAttributes(d, w, &at)
        && at.map_state == IsViewable && at.width >= 200 && at.width <= 700
        && at.height >= 300) {
        if (at.width > *mw) { *mw = at.width; *mh = at.height; }
        return 1;
    }
    return 0;
}

/* --- recursive walk ---------------------------------------------------- */

static int dismissed = 0;   /* only dismiss the first dialog */

static int walk(Display *d, Window w, int mode, int *mw, int *mh)
{
    Window r, p, *ch = NULL; unsigned int i, k;
    int hits = 0;

    switch (mode) {
    case 0: hits += hit_dialog(d, w);            break;
    case 1: hits += hit_hub(d, w, 1);             break;
    case 2: if (!dismissed) hits += hit_dialog(d, w);
            hits += hit_hub(d, w, 0);
            hits += hit_menu(d, w, mw, mh);       break;
    }
    if (!XQueryTree(d, w, &r, &p, &ch, &k)) return hits;
    for (i = 0; i < k; i++) hits += walk(d, ch[i], mode, mw, mh);
    if (ch) XFree(ch);
    return hits;
}

/* --- main program ------------------------------------------------------ */

int main(int argc, char **argv)
{
    int mode = 2, tries = 40, i;
    Display *d;

    if (argc > 1) {
        if (!strcmp(argv[1], "dismiss"))   mode = 0;
        else if (!strcmp(argv[1], "grid")) mode = 1;
        else                               mode = 2;
    }
    if (argc > 2) tries = atoi(argv[2]);

    d = XOpenDisplay(NULL);
    if (!d) return 2;

    if (mode == 0) {                       /* only dismiss the dialog */
        for (i = 0; i < tries; i++) {
            if (walk(d, DefaultRootWindow(d), 0, NULL, NULL)) break;
            XFlush(d);
            usleep(500000);
        }
        XCloseDisplay(d);
        return 0;
    }

    if (mode == 1) {                       /* open the menu (with start-up delay for WebView2) */
        usleep(20000000);                 /* ~20 s: let WebView2 start up */
        for (i = 0; i < tries; i++) {
            int mw = 0, mh = 0;
            walk(d, DefaultRootWindow(d), 1, NULL, NULL);   /* click the grid */
            XFlush(d);
            usleep(1500000);
            walk(d, DefaultRootWindow(d), 2, &mw, &mh);      /* menu there? */
            if (mw) {
                printf("menu-ok %dx%d\n", mw, mh); fflush(stdout);
                XCloseDisplay(d);
                return 0;
            }
            usleep(1500000);
        }
        printf("menu-missing\n"); fflush(stdout);
        XCloseDisplay(d);
        return 1;
    }

    /* mode 2: dismiss dialog, find Hub, click the grid (repeatedly), measure the menu */
    {
        int clicked = 0, mw, mh, waited = 0;
        dismissed = 0;
        for (i = 0; i < tries; i++) {
            mw = mh = 0;
            walk(d, DefaultRootWindow(d), 2, &mw, &mh);   /* dialog gone + look for the menu */
            XFlush(d);
            if (mw) {
                printf("menu-ok %dx%d\n", mw, mh); fflush(stdout);
                XCloseDisplay(d);
                return 0;
            }
            if (!dismissed) { dismissed = 1; usleep(400000); continue; }
            /* WebView2 needs ~20 s; then try a click every 10 s */

            waited += 1;
            if (waited >= 40 && (waited % 20) == 0) {
                if (walk(d, DefaultRootWindow(d), 1, NULL, NULL))
                    printf("click #%d\n", waited / 20);
                fflush(stdout);
                XFlush(d);
                usleep(1500000);
                clicked = 1;
            }
            (void)clicked;
            usleep(500000);
        }
    }
    printf("menu-missing\n"); fflush(stdout);
    XCloseDisplay(d);
    return 1;
}
