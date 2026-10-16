/* t4: t3 + WTOpen + packet handling (no interaction needed; timer ends it) */
#include <stdio.h>
#include <string.h>
#include <windows.h>
#include "wintab_min.h"

static HCTX gCtx;
static unsigned long gPackets;
static LONG gPressMax = -1;

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    switch (m) {
    case WT_PACKET: {
        WTPACKET pkt;
        if (gCtx && WTPacket(gCtx, (UINT)w, (LPVOID)&pkt)) {
            gPackets++;
            if ((LONG)pkt.pkNormalPressure > gPressMax) gPressMax = pkt.pkNormalPressure;
            if (gPackets <= 10)
                printf("PK x=%ld y=%ld pressure=%u btns=0x%x\n", pkt.pkX, pkt.pkY,
                       pkt.pkNormalPressure, pkt.pkButtons);
            fflush(stdout);
        }
        return 0;
    }
    case WM_TIMER:
        printf("SUMMARY packets=%lu max_pressure=%ld\n", gPackets, gPressMax);
        fflush(stdout);
        PostQuitMessage(0); return 0;
    case WM_DESTROY: PostQuitMessage(0); return 0;
    }
    return DefWindowProcA(h, m, w, l);
}
int main(void){
    LOGCONTEXTA lc; WNDCLASSA wc; HWND hwnd; MSG msg;
    if (!wintab_load()) { printf("FAIL load\n"); return 1; }
    UINT r = WTInfoA(WTI_DEFCONTEXT, 0, &lc);
    printf("ctx sz=%u inExt=(%ld,%ld)\n", r, lc.lcInExtX, lc.lcInExtY); fflush(stdout);
    lc.lcOptions |= CXO_MESSAGES;
    lc.lcPktData = PK_SERIAL_NUMBER | PK_BUTTONS | PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_TIME;
    lc.lcPktMode = 0;
    lc.lcMoveMask = PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_BUTTONS;
    lc.lcBtnUpMask = lc.lcBtnDnMask = 0;
    lc.lcOutOrgX = lc.lcOutOrgY = 0;
    lc.lcOutExtX = lc.lcInExtX; lc.lcOutExtY = lc.lcInExtY;
    sprintf(lc.lcName, "T4");

    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = WndProc; wc.lpszClassName = "T4"; wc.hInstance = GetModuleHandleA(NULL);
    if (!RegisterClassA(&wc)) { printf("FAIL reg\n"); return 1; }
    hwnd = CreateWindowA("T4", "t4 - draw here with the pen!", WS_OVERLAPPEDWINDOW|WS_VISIBLE, 50, 50, 320, 260, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("FAIL win\n"); return 1; }
    printf("window up\n"); fflush(stdout);
    gCtx = WTOpenA(hwnd, &lc, TRUE);
    printf("WTOpen=%s\n", gCtx ? "OK" : "FAILED"); fflush(stdout);

    SetTimer(hwnd, 1, 120000, NULL);
    while (GetMessageA(&msg, NULL, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageA(&msg); }
    WTClose(gCtx);
    printf("t4 done\n"); fflush(stdout);
    return 0;
}
