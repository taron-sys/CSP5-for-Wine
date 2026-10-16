/* Wintab LIVE test: window + WTOpen with pressure packets; user paints over it. */
#include <windows.h>
#include <stdio.h>
#include "wintab_min.h"

static HCTX gCtx;
static unsigned long gPackets;
static LONG gPressMin = 0x7fffffff, gPressMax = -1;
static LONG gLastX = -1, gLastY = -1;

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WT_PACKET: {
        WTPACKET pkt;
        if (gCtx && WTPacket(gCtx, (UINT)wp, (LPVOID)&pkt)) {
            gPackets++;
            if ((LONG)pkt.pkNormalPressure < gPressMin) gPressMin = pkt.pkNormalPressure;
            if ((LONG)pkt.pkNormalPressure > gPressMax) gPressMax = pkt.pkNormalPressure;
            gLastX = pkt.pkX; gLastY = pkt.pkY;
            if (gPackets <= 15)
                printf("PK serial=%lu x=%ld y=%ld pressure=%u buttons=0x%x\n",
                       (unsigned long)pkt.pkSerialNumber, pkt.pkX, pkt.pkY,
                       pkt.pkNormalPressure, pkt.pkButtons);
            fflush(stdout);
        }
        return 0;
    }
    case WT_INFOCHANGE: printf("WT_INFOCHANGE\n"); fflush(stdout); return 0;
    case WT_CTXOPEN:    printf("WT_CTXOPEN\n");    fflush(stdout); return 0;
    case WM_TIMER:
        printf("SUMMARY packets=%lu pressure_min=%ld pressure_max=%ld last=(%ld,%ld)\n",
               gPackets, gPackets ? gPressMin : -1, gPackets ? gPressMax : -1, gLastX, gLastY);
        fflush(stdout);
        PostQuitMessage(0);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

int main(void)
{
    LOGCONTEXTA lc;
    UINT r;
    WNDCLASSA wc;
    HWND hwnd;
    MSG msg;

    r = WTInfoA(WTI_DEFCONTEXT, 0, &lc);
    if (!r) { printf("FAIL: WTInfoA(DEFCONTEXT)=%u\n", r); return 1; }
    lc.lcOptions |= CXO_MESSAGES;
    lc.lcPktData = PK_SERIAL_NUMBER | PK_BUTTONS | PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_TIME;
    lc.lcPktMode = 0;
    lc.lcMoveMask = PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_BUTTONS;
    lc.lcBtnUpMask = lc.lcBtnDnMask = 0;
    lc.lcOutOrgX = lc.lcOutOrgY = 0;
    lc.lcOutExtX = lc.lcInExtX;
    lc.lcOutExtY = lc.lcInExtY;
    sprintf(lc.lcName, "WineTabLiveTest");

    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = WndProc;
    wc.lpszClassName = "WineTabLiveTest";
    wc.hInstance = GetModuleHandleA(NULL);
    wc.hCursor = LoadCursorA(NULL, (LPCSTR)IDC_CROSS);
    if (!RegisterClassA(&wc)) { printf("FAIL: RegisterClass %lu\n", GetLastError()); return 1; }
    hwnd = CreateWindowA("WineTabLiveTest", "wintab live test - DRAW HERE WITH THE PEN!",
                         WS_OVERLAPPEDWINDOW | WS_EX_TOPMOST, 40, 40, 320, 260,
                         NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("FAIL: CreateWindow\n"); return 1; }
    ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    SetForegroundWindow(hwnd);
    UpdateWindow(hwnd);

    gCtx = WTOpenA(hwnd, &lc, TRUE);
    printf("WTOpenA -> %s\n", gCtx ? "OK" : "FAILED"); fflush(stdout);
    if (!gCtx) return 1;

    SetTimer(hwnd, 1, 25000, NULL);
    while (GetMessageA(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }
    WTClose(gCtx);
    printf("closed\n");
    return 0;
}
