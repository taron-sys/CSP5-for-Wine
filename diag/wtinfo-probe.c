/* wtinfo-probe.c — dumps WTInfoW over all relevant categories/indices.
 *
 * Purpose: determine and compare reference values.
 *   * Wine's BUILT-IN wintab32 (fresh prefix without DllOverride) = expected semantics
 *   * our patched DLL                                              = actual semantics
 * Usage:   wine wtinfo-probe.exe            (loads wintab32.dll in the standard search order)
 *          wine wtinfo-probe.exe -v         (additionally show "unhandled"/empty categories)
 *
 * Also checks for buffer overruns: the buffer is filled with 0xAA; bytes
 * beyond the returned length are reported (write errors in the DLL).
 *
 * Build (repo root):
 *   x86_64-w64-mingw32-gcc -O2 -Idiag/csp-wintab -o diag/wtinfo-probe.exe \
 *       diag/wtinfo-probe.c -luser32
 */
#include <stdio.h>
#include <string.h>
#include <windows.h>
#include "csp-wintab/wintab.h"

typedef UINT (API *pWTInfoW_fn)(UINT, UINT, LPVOID);

#define BUFSZ 4096
static unsigned char g_buf[BUFSZ];

static pWTInfoW_fn fn_WTInfoW;
static int g_verbose;

/* ---- Decoding ------------------------------------------------------------- */

static int is_ascii(const unsigned char *p, UINT n) {
    for (UINT i = 0; i < n; i++)
        if (p[i] && (p[i] < 0x20 || p[i] > 0x7e)) return 0;
    return n > 0;
}

static void print_wstr(const unsigned char *p, UINT max) {
    WCHAR w[260]; UINT n = 0;
    for (UINT i = 0; i + 1 < max && i / 2 < 259; i += 2) {
        WCHAR c = (WCHAR)(p[i] | (p[i + 1] << 8));
        if (!c) break;
        w[n++] = c;
    }
    w[n] = 0;
    printf("  wstr=\"%ls\"\n", w);
}

static void print_astr(const unsigned char *p, UINT max) {
    char s[260]; UINT n = 0;
    for (UINT i = 0; i < max && i < 259; i++) {
        if (!p[i]) break;
        s[n++] = (char)p[i];
    }
    s[n] = 0;
    printf("  astr=\"%s\"\n", s);
}

static void print_axis(const unsigned char *p) {
    AXIS ax;
    memcpy(&ax, p, sizeof(ax));
    printf("  AXIS min=%ld max=%ld units=0x%x res=%lu\n",
           (long)ax.axMin, (long)ax.axMax, ax.axUnits, (unsigned long)ax.axResolution);
}

/* Buffer overrun: first differing byte beyond len */
static void check_overrun(UINT len) {
    if (len >= BUFSZ) { printf("  !! len >= buffer size\n"); return; }
    for (UINT i = len; i < BUFSZ; i++) {
        if (g_buf[i] != 0xAA) {
            printf("  !! buffer overrun: byte %u (0x%02x) written beyond len=%u\n",
                   i, g_buf[i], len);
            return;
        }
    }
}

static void probe(const char *name, UINT cat, UINT idx, UINT maxidx) {
    UINT len;
    char label[64];
    memset(g_buf, 0xAA, BUFSZ);
    len = fn_WTInfoW(cat, idx, g_buf);

    if (!len && !g_verbose) return;

    if (maxidx) snprintf(label, sizeof(label), "%s", name);
    else        snprintf(label, sizeof(label), "%s+%u", name, idx);
    printf("cat=%3u idx=%2u %-22s len=%3u\n", cat, idx, label, len);

    if (!len) return;
    check_overrun(len);

    /* decode known single values */
    if (cat == WTI_DEVICES && idx == DVC_NAME) { print_wstr(g_buf, len); return; }
    if (cat == WTI_INTERFACE && idx == IFC_WINTABID) { print_wstr(g_buf, len); return; }
    if (cat >= WTI_CURSORS && cat < WTI_CURSORS + 10 && idx == CSR_NAME) {
        print_wstr(g_buf, len); return;
    }
    if (cat >= WTI_EXTENSIONS && cat < WTI_EXTENSIONS + 10 &&
        (idx == EXT_NAME)) { print_astr(g_buf, len); return; }
    if (cat == WTI_DEVICES && (idx == DVC_X || idx == DVC_Y || idx == DVC_NPRESSURE ||
                               idx == DVC_TPRESSURE || idx == DVC_Z)) {
        print_axis(g_buf); return;
    }
    if (cat == WTI_DEVICES && idx == DVC_PKTDATA) {
        WTPKT m; memcpy(&m, g_buf, sizeof(m));
        printf("  WTPKT mask=0x%08lx\n", (unsigned long)m); return;
    }
    if (cat == WTI_DEVICES && idx == DVC_ORIENTATION) {
        printf("  %u AXIS structures\n", len / (UINT)sizeof(AXIS));
        for (UINT i = 0; i < len / sizeof(AXIS) && i < 4; i++) {
            printf("   [%u]", i);
            print_axis(g_buf + i * sizeof(AXIS));
        }
        return;
    }
    if (len == 2) { WORD v; memcpy(&v, g_buf, 2); printf("  word=%u (0x%04x)\n", v, v); return; }
    if (len == 4) { DWORD v; memcpy(&v, g_buf, 4); printf("  dword=%lu (0x%08lx)\n",
                                                         (unsigned long)v, (unsigned long)v); return; }
    /* unknown: hexdump of the first 32 bytes */
    printf("  raw:");
    for (UINT i = 0; i < len && i < 32; i++) printf(" %02x", g_buf[i]);
    if (len > 32) printf(" …");
    printf("\n");
    if (is_ascii(g_buf, len > 32 ? 32 : len)) print_astr(g_buf, len);
}

static void range(const char *name, UINT base, UINT from, UINT to) {
    for (UINT i = from; i <= to; i++)
        probe(name, base, i, 0);
}

int main(int argc, char **argv)
{
    HMODULE w;
    WCHAR path[MAX_PATH] = L"?";

    for (int i = 1; i < argc; i++)
        if (!strcmp(argv[i], "-v")) g_verbose = 1;

    w = LoadLibraryA("wintab32.dll");
    if (!w) { printf("FAIL: wintab32.dll cannot be loaded (err=%lu)\n", GetLastError()); return 1; }
    GetModuleFileNameW(w, path, MAX_PATH);
    printf("wintab32.dll: %ls\n", path);
    fn_WTInfoW = (pWTInfoW_fn)(void *)GetProcAddress(w, "WTInfoW");
    if (!fn_WTInfoW) { printf("FAIL: no WTInfoW export\n"); return 1; }

    printf("--- (0,0) probe (size of the context, 0 = no tablet) ---\n");
    probe("probe00", 0, 0, 1);

    printf("--- WTI_INTERFACE (1) ---\n");
    range("IFC", WTI_INTERFACE, 0, 12);

    printf("--- WTI_STATUS (2) ---\n");
    range("STA", WTI_STATUS, 0, 9);

    printf("--- WTI_DEFCONTEXT (3) / WTI_DEFSYSCTX (4) / WTI_DDCTXS (400): CTX_* ---\n");
    range("DEFCTX", WTI_DEFCONTEXT, 0, CTX_MAX);
    range("DEFSYS", WTI_DEFSYSCTX, 0, CTX_MAX);
    range("DDCTXS", WTI_DDCTXS, 0, CTX_MAX);

    printf("--- WTI_DEVICES (100) ---\n");
    range("DVC", WTI_DEVICES, 0, 20);

    printf("--- WTI_CURSORS+0..2 (200..202) ---\n");
    for (UINT c = 0; c < 3; c++) {
        char nm[32]; snprintf(nm, sizeof(nm), "CSR(c%u)", c);
        range(nm, WTI_CURSORS + c, 0, 21);
    }

    printf("--- WTI_EXTENSIONS+0..3 (300..303) ---\n");
    for (UINT e = 0; e < 4; e++) {
        char nm[32]; snprintf(nm, sizeof(nm), "EXT(e%u)", e);
        range(nm, WTI_EXTENSIONS + e, 0, 8);
    }

    printf("--- WTI_DSCTXS (500) ---\n");
    probe("DSCTXS", WTI_DSCTXS, 0, 1);

    /* Spec: lpOutput == NULL means "only ask for the size" (no writing).
     * Must return the same lengths as with a buffer and must not crash. */
    printf("--- NULL buffer (size only) ---\n");
    {
        static const struct { UINT cat, idx; } q[] = {
            { 0, 0 },
            { WTI_INTERFACE, IFC_WINTABID }, { WTI_INTERFACE, IFC_NDEVICES },
            { WTI_INTERFACE, IFC_SPECVERSION },
            { WTI_DEVICES, DVC_NAME }, { WTI_DEVICES, DVC_X },
            { WTI_DEVICES, DVC_ORIENTATION }, { WTI_DEVICES, DVC_PKTDATA },
            { WTI_DEFCONTEXT, CTX_NAME }, { WTI_DEFCONTEXT, 0 },
            { WTI_DDCTXS, 0 }, { WTI_DDCTXS, CTX_INEXTX },
            { WTI_CURSORS + 1, CSR_NAME },
            { WTI_EXTENSIONS, EXT_TAG },
        };
        for (unsigned i = 0; i < sizeof(q) / sizeof(q[0]); i++)
            printf("cat=%3u idx=%2u -> len=%u\n", q[i].cat, q[i].idx,
                   fn_WTInfoW(q[i].cat, q[i].idx, NULL));
    }

    printf("done\n");
    FreeLibrary(w);
    return 0;
}
