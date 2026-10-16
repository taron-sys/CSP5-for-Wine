/* Presentation test under wine for LAYERED|NRB child windows (WebView2-like).
   Creates top-level "Chrome_WidgetWin_0-like" window + intermediate child
   (class 'Intermediate D3D Window'), then tests:
     1. GDI SetDIBitsToDevice to child DC                -> persistence?
     2. UpdateLayeredWindow on child                     -> persistence?
     3. GDI blit to PARENT DC at child offset            -> persistence?
   Screenshot: parent window is a plain wine window; user takes spectacle shots
   or we just rely on wine window being composited. Simpler: draw into each,
   wait, repaint parent surface region with a different pattern via GDI to
   simulate Chromium wipe, redraw child, check visually over time.
   Log results to C:\disp-test.log
*/
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

static FILE *logf;
#define LOG(...) do { fprintf(logf, __VA_ARGS__); fflush(logf);} while(0)

static int checker(BYTE *buf, int w, int h, DWORD c1, DWORD c2)
{
    for (int y=0;y<h;y++) for (int x=0;x<w;x++) {
        BYTE *p = buf + (y*w+x)*4;
        DWORD *d = (DWORD*)p;
        *d = (((x/16)+(y/16)) & 1) ? c1 : c2;
    }
    return 1;
}

static void blit_dib(HDC hdc, BYTE *buf, int w, int h)
{
    BITMAPINFO bmi = {};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = w; bmi.bmiHeader.biHeight = -h;
    bmi.bmiHeader.biPlanes = 1; bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;
    SetDIBitsToDevice(hdc, 0, 0, w, h, 0, 0, 0, h, buf, &bmi, DIB_RGB_COLORS);
}

static HBITMAP make_dib(HDC memdc, BYTE **bits, int w, int h)
{
    BITMAPINFO bmi = {};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = w; bmi.bmiHeader.biHeight = -h;
    bmi.bmiHeader.biPlanes = 1; bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;
    VOID *b = NULL;
    HBITMAP hb = CreateDIBSection(memdc, &bmi, DIB_RGB_COLORS, &b, NULL, 0);
    *bits = (BYTE*)b;
    return hb;
}

LRESULT CALLBACK ChildProc(HWND h, UINT m, WPARAM wp, LPARAM lp)
{
    if (m == WM_PAINT) { ValidateRect(h, NULL); return 0; }
    return DefWindowProcA(h, m, wp, lp);
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
    logf = fopen("C:\\disp-test.log", "w");
    if (!logf) return 1;

    WNDCLASSA wc = {};
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = inst;
    wc.lpszClassName = "DispTestParent";
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    RegisterClassA(&wc);
    WNDCLASSA wc2 = {};
    wc2.lpfnWndProc = ChildProc;
    wc2.hInstance = inst;
    wc2.lpszClassName = "Intermediate D3D Window";
    RegisterClassA(&wc2);
    WNDCLASSA wc3 = {};
    wc3.lpfnWndProc = DefWindowProcA;
    wc3.hInstance = inst;
    wc3.lpszClassName = "PlainChild";
    RegisterClassA(&wc3);

    RECT wr = {100, 100, 740, 520};
    HWND parent = CreateWindowExA(0, "DispTestParent", "DispTest",
        WS_OVERLAPPEDWINDOW|WS_VISIBLE, 200, 200, 640, 420, NULL, NULL, inst, NULL);
    if (!parent) { LOG("parent create failed %lu\n", GetLastError()); return 1; }

    /* WebView2-style intermediate child */
    HWND child = CreateWindowExA(0x00280024 /* LAYERED|NRB|TRANSPARENT|NOPARENTNOTIFY */,
        "Intermediate D3D Window", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_CLIPCHILDREN, 50,
        50, 400, 300, parent, NULL, inst, NULL);
    LOG("child=%p err=%lu\n", child, GetLastError());

    /* plain non-layered child for comparison */
    HWND child2 = CreateWindowExA(0, "PlainChild", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_CLIPCHILDREN, 50,
        50, 400, 300, parent, NULL, inst, NULL);
    LOG("child2=%p err=%lu\n", child2, GetLastError());

    BYTE *buf = malloc(500*400*4);
    BYTE *bufp = malloc(500*400*4);
    checker(bufp, 450, 350, 0x0000ffff, 0xffff0000);
    checker(buf, 400, 300, 0xff00ff00, 0xff000000);   /* green/white checker */
    Sleep(1500);

    LOG("child exstyle=%08lx style=%08lx parent ex=%08lx st=%08lx vis=%ld iconic=%ld\n",
        GetWindowLong(child, GWL_EXSTYLE), GetWindowLong(child, GWL_STYLE),
        GetWindowLong(parent, GWL_EXSTYLE), GetWindowLong(parent, GWL_STYLE),
        IsWindowVisible(child), IsIconic(child));

    /* 1. GDI to child DC */
    HDC cdc = GetDC(child);
    LOG("GetDC(child)=%p\n", cdc);
    blit_dib(cdc, buf, 400, 300);
    ReleaseDC(child, cdc);
    LOG("T+0s after GDI child blit\n"); Sleep(3000);
    LOG("T+3s GDI child blit visible?\n");

    /* 2. ULW on child */
    HDC screen = GetDC(NULL);
    HDC memdc = CreateCompatibleDC(screen);
    BYTE *ubits = NULL;
    HBITMAP udib = make_dib(memdc, &ubits, 400, 300);
    memcpy(ubits, buf, 400*300*4);
    HGDIOBJ old = SelectObject(memdc, udib);
    SIZE sz = {400,300}; POINT pt = {0,0};
    BLENDFUNCTION bf = { AC_SRC_OVER, 0, 255, AC_SRC_ALPHA };
    BOOL ok = UpdateLayeredWindow(child, screen, NULL, &sz, memdc, &pt, 0, &bf, ULW_ALPHA);
    LOG("ULW(child)=%ld err=%lu\n", ok, GetLastError());
    SelectObject(memdc, old);
    DeleteObject(udib); DeleteDC(memdc); ReleaseDC(NULL, screen);
    Sleep(3000);
    LOG("T+6s ULW visible?\n");

    /* 3. GDI to parent DC at child offset */
    HDC pdc = GetDC(parent);
    blit_dib(pdc, bufp, 50+400, 50+300);   /* covers top-left incl child region */
    checker(bufp, 450, 350, 0x0000ffff, 0xffff0000);   /* yellow/red */
    /* actually blit checker pattern */
    blit_dib(pdc, bufp, 450, 350);
    ReleaseDC(parent, pdc);
    LOG("T+6.1s parent-offset blit done\n"); Sleep(3000);
    LOG("T+9s parent-offset visible (incl child region)?\n");

    /* 4. RedrawWindow full child */
    RedrawWindow(child, NULL, NULL, RDW_INVALIDATE|RDW_UPDATENOW|RDW_ALLCHILDREN|RDW_FRAME);
    Sleep(3000);
    LOG("T+12s after RedrawWindow\n");

    /* force parent paint simulation: resize child by 1px to trigger re-composite */
    MoveWindow(child, 50, 51, 400, 300, TRUE);
    Sleep(3000);
    LOG("T+15s after MoveWindow(+1px y)\n");

    /* final: repaint child via GDI again to confirm it can be revived */
    cdc = GetDC(child);
    blit_dib(cdc, buf, 400, 300);
    ReleaseDC(child, cdc);
    Sleep(2000);
    LOG("T+17s final GDI blit\n");
    LOG("done\n");
    fclose(logf);
    return 0;
}
