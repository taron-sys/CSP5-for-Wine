#include <stdio.h>
#include <string.h>
#include <windows.h>
static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    switch (m) {
    case WM_TIMER: printf("TIMER-SUMMARY\n"); fflush(stdout); PostQuitMessage(0); return 0;
    case WM_DESTROY: PostQuitMessage(0); return 0;
    }
    return DefWindowProcA(h, m, w, l);
}
int main(void){
    WNDCLASSA wc; HWND hwnd; MSG msg;
    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = WndProc; wc.lpszClassName = "T3"; wc.hInstance = GetModuleHandleA(NULL);
    if (!RegisterClassA(&wc)) { printf("FAIL reg %lu\n", GetLastError()); return 1; }
    hwnd = CreateWindowA("T3", "t3 window", WS_OVERLAPPEDWINDOW|WS_VISIBLE, 50, 50, 300, 240, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("FAIL win %lu\n", GetLastError()); return 1; }
    printf("window up\n"); fflush(stdout);
    SetTimer(hwnd, 1, 8000, NULL);
    while (GetMessageA(&msg, NULL, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageA(&msg); }
    printf("t3 done\n"); fflush(stdout);
    return 0;
}
