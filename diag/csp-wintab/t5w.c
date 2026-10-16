/* t5w: W-function live test against the PATCHED WineTab DLL (as CSP calls it). */
#include <stdio.h>
#include <string.h>
#include <windows.h>
#include "wintab.h"   /* WineTab's own header: matches the patched dll exactly */

typedef UINT  (API *pWTInfoW_fn)(UINT, UINT, LPVOID);
typedef HCTX  (API *pWTOpenW_fn)(HWND, LPLOGCONTEXTW, BOOL);
typedef BOOL  (API *pWTPacket_fn)(HCTX, UINT, LPVOID);
typedef BOOL  (API *pWTClose_fn)(HCTX);
static pWTInfoW_fn  fn_WTInfoW;
static pWTOpenW_fn  fn_WTOpenW;
static pWTPacket_fn fn_WTPacket;
static pWTClose_fn  fn_WTClose;

static HCTX gCtx;
static unsigned long gPackets;
static LONG gPressMin = 0x7fffffff, gPressMax = -1;
static LONG gLastX = -1, gLastY = -1;
static UINT gLastSerial;

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    switch (m) {
    case WT_PACKET: {
        /* CSP-style PACKET (ser/buttons/x/y/pressure/time) */
        struct { UINT ser; UINT btns; LONG x; LONG y; UINT pressure; DWORD time; } pkt;
        if (gCtx && fn_WTPacket(gCtx, (UINT)w, (LPVOID)&pkt)) {
            gPackets++;
            if ((LONG)pkt.pressure < gPressMin) gPressMin = pkt.pressure;
            if ((LONG)pkt.pressure > gPressMax) gPressMax = pkt.pressure;
            gLastX = pkt.x; gLastY = pkt.y; gLastSerial = pkt.ser;
            if (gPackets <= 10 || (gPackets % 100) == 0)
                printf("PK#%lu serial=%u x=%ld y=%ld pressure=%u\n",
                       gPackets, pkt.ser, pkt.x, pkt.y, pkt.pressure);
            fflush(stdout);
        }
        return 0;
    }
    case WM_ERASEBKGND: {
        RECT rc; GetClientRect(h, &rc);
        FillRect((HDC)(INT_PTR)w, &rc, (HBRUSH)GetStockObject(BLACK_BRUSH));
        return 1;
    }
    case WM_PAINT: {
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps);
        char buf[96];
        SetTextColor(dc, RGB(255,255,0)); SetBkMode(dc, TRANSPARENT);
        TextOutA(dc, 30, 130, ">>> NOW DRAW WITH THE PEN! <<<", 32);
        sprintf(buf, "packets: %lu  pressure_max: %ld", gPackets, gPressMax);
        TextOutA(dc, 30, 160, buf, (int)strlen(buf));
        EndPaint(h, &ps);
        return 0;
    }
    case WM_TIMER:
        printf("SUMMARY packets=%lu pressure_min=%ld pressure_max=%ld last=(%ld,%ld) serial=%u\n",
               gPackets, gPackets ? gPressMin : -1, gPackets ? gPressMax : -1,
               gPackets ? gLastX : -1, gPackets ? gLastY : -1, gLastSerial);
        fflush(stdout);
        PostQuitMessage(0); return 0;
    case WM_DESTROY: PostQuitMessage(0); return 0;
    }
    return DefWindowProcA(h, m, w, l);
}

int main(void)
{
    HMODULE w = LoadLibraryA("wintab32.dll");
    LOGCONTEXTW lc;
    WNDCLASSA wc; MSG msg;
    HBRUSH red = CreateSolidBrush(RGB(170, 0, 0));

    if (!w) { printf("FAIL load dll\n"); return 1; }
    fn_WTInfoW  = (pWTInfoW_fn)(void *)GetProcAddress(w, "WTInfoW");
    fn_WTOpenW  = (pWTOpenW_fn)(void *)GetProcAddress(w, "WTOpenW");
    fn_WTPacket = (pWTPacket_fn)(void *)GetProcAddress(w, "WTPacket");
    fn_WTClose  = (pWTClose_fn)(void *)GetProcAddress(w, "WTClose");
    printf("procs: info=%p open=%p packet=%p close=%p\n",
           (void*)fn_WTInfoW, (void*)fn_WTOpenW, (void*)fn_WTPacket, (void*)fn_WTClose);
    fflush(stdout);
    if (!fn_WTInfoW || !fn_WTOpenW || !fn_WTPacket || !fn_WTClose) return 1;

    UINT r = fn_WTInfoW(WTI_DEFCONTEXT, 0, &lc);
    printf("ctx sz=%u inExt=(%ld,%ld) pktRate=%u\n", r, lc.lcInExtX, lc.lcInExtY, lc.lcPktRate);
    fflush(stdout);
    lc.lcOptions |= CXO_MESSAGES;
    lc.lcPktData = PK_SERIAL_NUMBER | PK_BUTTONS | PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_TIME;
    lc.lcPktMode = 0;
    lc.lcMoveMask = PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_BUTTONS;
    lc.lcBtnUpMask = lc.lcBtnDnMask = 0;
    lc.lcOutOrgX = lc.lcOutOrgY = 0;
    lc.lcOutExtX = lc.lcInExtX; lc.lcOutExtY = lc.lcInExtY;

    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = WndProc; wc.lpszClassName = "T5W"; wc.hInstance = GetModuleHandleA(NULL);
    wc.hbrBackground = red;
    if (!RegisterClassA(&wc)) { printf("FAIL reg\n"); return 1; }
    HWND hwnd = CreateWindowExA(WS_EX_TOPMOST, "T5W", ">>> wintab-W TEST: DRAW HERE <<<",
                 WS_OVERLAPPEDWINDOW|WS_VISIBLE, 120, 120, 560, 420, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("FAIL win\n"); return 1; }
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW);
    SetForegroundWindow(hwnd);
    MessageBeep(0xFFFFFFFF);
    printf("window up\n"); fflush(stdout);

    gCtx = fn_WTOpenW(hwnd, &lc, TRUE);
    printf("WTOpenW=%s\n", gCtx ? "OK" : "FAILED"); fflush(stdout);

    SetTimer(hwnd, 1, 120000, NULL);
    while (GetMessageA(&msg, NULL, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageA(&msg); }
    fn_WTClose(gCtx);
    printf("closed\n");
    return 0;
}
