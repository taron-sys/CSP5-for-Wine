/* WinTab diagnostics (Wine): only the queries relevant for pressure. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

typedef struct tagAXIS {
    LONG axMin;
    LONG axMax;
    UINT axUnits;
    DWORD axResolution;
} AXIS;

#define WTI_INTERFACE   1u
#define WTI_DEVICES     100u
#define WTI_CURSORS     200u
#define IFC_SPECVERSION 2u
#define IFC_IMPLVERSION 3u
#define IFC_NDEVICES    4u
#define IFC_NCURSORS    5u
#define DVC_NAME        1u
#define DVC_PKTRATE     5u
#define DVC_XDATA       12u
#define DVC_YDATA       13u
#define DVC_NPRESSURE   15u
#define DVC_TPRESSURE   16u
#define CSR_NAME        1u

typedef UINT (WINAPI *WTInfoA_t)(UINT, UINT, LPVOID);

static void dump_axis(WTInfoA_t fn, UINT cat, UINT idx, const char *label)
{
    AXIS ax;
    UINT r;
    ZeroMemory(&ax, sizeof(ax));
    r = fn(cat, idx, &ax);
    if (r == 0)
        printf("  %-10s : (not present)\n", label);
    else
        printf("  %-10s : min=%ld max=%ld units=%u res=%lu\n",
               label, ax.axMin, ax.axMax, ax.axUnits, (unsigned long)ax.axResolution);
    fflush(stdout);
}

int main(void)
{
    HMODULE w = LoadLibraryA("wintab32.dll");
    WTInfoA_t fn;
    UINT r;
    WORD spec = 0, impl = 0;
    UINT ndev = 0, ncur = 0;
    char name[264];

    if (!w) { printf("FAIL: LoadLibrary wintab32: %lu\n", GetLastError()); return 1; }
    fn = (WTInfoA_t)(void *)GetProcAddress(w, "WTInfoA");
    if (!fn) { printf("FAIL: no WTInfoA\n"); return 1; }

    r = fn(WTI_INTERFACE, IFC_SPECVERSION, &spec);
    printf("spec        : %u.%u (ret=%u)\n", spec >> 8, spec & 0xFF, r); fflush(stdout);
    fn(WTI_INTERFACE, IFC_IMPLVERSION, &impl);
    printf("implversion : 0x%04x\n", impl); fflush(stdout);
    r = fn(WTI_INTERFACE, IFC_NDEVICES, &ndev);
    printf("ndevices    : %u (ret=%u)\n", ndev, r); fflush(stdout);
    fn(WTI_INTERFACE, IFC_NCURSORS, &ncur);
    printf("ncursors    : %u\n", ncur); fflush(stdout);

    for (UINT d = 0; d < ndev && d < 8; d++) {
        UINT cat = WTI_DEVICES + d;
        ZeroMemory(name, sizeof(name));
        printf("device %u:\n", d); fflush(stdout);
        r = fn(cat, DVC_NAME, name);
        printf("  name       : ret=%u '%s'\n", r, name); fflush(stdout);
        dump_axis(fn, cat, DVC_XDATA, "XDATA");
        dump_axis(fn, cat, DVC_YDATA, "YDATA");
        dump_axis(fn, cat, DVC_NPRESSURE, "NPRESSURE");
        dump_axis(fn, cat, DVC_TPRESSURE, "TPRESSURE");
    }
    /* Cursor names (Wintab cursor types: pen/eraser/puck) */
    for (UINT c = 0; c < ncur && c < 6; c++) {
        UINT cat = WTI_CURSORS + c;
        ZeroMemory(name, sizeof(name));
        r = fn(cat, CSR_NAME, name);
        printf("cursor %u   : ret=%u '%s'\n", c, r, name);
        fflush(stdout);
    }
    printf("done\n"); fflush(stdout);
    return 0;
}
