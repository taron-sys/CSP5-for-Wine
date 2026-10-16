/* t5: UNMISSABLE Wintab live diagnostics: red window, beep, live output. */
#include <stdio.h>
#include <string.h>
#include <windows.h>
#include "wintab_min.h"

static HCTX gCtx;
static unsigned long gPackets;
static LONG gPressMin = 0x7fffffff, gPressMax = -1;
static LONG gLastX, gLastY;

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    switch (m) {
    case WT_PACKET: {
        WTPACKET pkt;
        if (gCtx && WTPacket(gCtx, (UINT)w, (LPVOID)&pkt)) {
            gPackets++;
            if ((LONG)pkt.pkNormalPressure < gPressMin) gPressMin = pkt.pkNormalPressure;
            if ((LONG)pkt.pkNormalPressure > gPressMax) gPressMax = pkt.pkNormalPressure;
            gLastX = pkt.pkX; gLastY = pkt.pkY;
            if (gPackets <= 8 || (gPackets % 100) == 0)
                printf("PK#%lu x=%ld y=%ld pressure=%u\n", gPackets, pkt.pkX, pkt.pkY, pkt.pkNormalPressure);
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
        SetTextColor(dc, RGB(255,255,0)); SetBkMode(dc, TRANSPARENT);
        TextOutA(dc, 30, 130, ">>> NOW DRAW WITH THE PEN! <<<", 32);
        char buf[80];
        sprintf(buf, "packets: %lu  pressure_max: %ld", gPackets, gPressMax);
        TextOutA(dc, 30, 160, buf, (int)strlen(buf));
        EndPaint(h, &ps);
        return 0;
    }
    case WM_TIMER: {
        printf("SUMMARY packets=%lu pressure_min=%ld pressure_max=%ld last_xy=(%ld,%ld)\n",
               gPackets, gPackets ? gPressMin : -1, gPackets ? gPressMax : -1,
               gPackets ? gLastX : -1, gPackets ? gLastY : -1);
        fflush(stdout);
        PostQuitMessage(0); return 0;
    }
    case WM_DESTROY: PostQuitMessage(0); return 0;
    }
    return DefWindowProcA(h, m, w, l);
}

int main(void){
    LOGCONTEXTA lc; WNDCLASSA wc; MSG msg;
    HBRUSH red = CreateSolidBrush(RGB(170, 0, 0));
    if (!wintab_load()) { printf("FAIL wintab load\n"); return 1; }

    UINT r = WTInfoA(WTI_DEFCONTEXT, 0, &lc);
    printf("ctx=%u inExt=(%ld,%ld)\n", r, lc.lcInExtX, lc.lcInExtY); fflush(stdout);
    lc.lcOptions |= CXO_MESSAGES;
    lc.lcPktData = PK_SERIAL_NUMBER | PK_BUTTONS | PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_TIME;
    lc.lcPktMode = 0;
    lc.lcMoveMask = PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_BUTTONS;
    lc.lcBtnUpMask = lc.lcBtnDnMask = 0;
    lc.lcOutOrgX = lc.lcOutOrgY = 0;
    lc.lcOutExtX = lc.lcInExtX; lc.lcOutExtY = lc.lcInExtY;
    sprintf(lc.lcName, "WineTabLive5");

    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = WndProc; wc.lpszClassName = "T5"; wc.hInstance = GetModuleHandleA(NULL);
    wc.hbrBackground = red;
    if (!RegisterClassA(&wc)) { printf("FAIL reg\n"); return 1; }
    HWND hwnd = CreateWindowExA(WS_EX_TOPMOST, "T5", ">>> wintab TEST: DRAW HERE WITH THE PEN <<<",
                 WS_OVERLAPPEDWINDOW|WS_VISIBLE, 120, 120, 560, 420, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("FAIL win\n"); return 1; }
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW);
    ShowWindow(hwnd, SW_SHOWNORMAL);
    SetForegroundWindow(hwnd);
    MessageBeep(0xFFFFFFFF); /* ping - audible! */
    printf("window up + beeped\n"); fflush(stdout);

    gCtx = WTOpenA(hwnd, &lc, TRUE);
    printf("WTOpen=%s\n", gCtx ? "OK" : "FAILED"); fflush(stdout);

    InvalidateRect(hwnd, NULL, TRUE); UpdateWindow(hwnd);
    SetTimer(hwnd, 1, 180000, NULL);
    while (GetMessageA(&msg, NULL, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageA(&msg); }
    WTClose(gCtx);
    printf("closed\n");
    return 0;
}
