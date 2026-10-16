/* winrt-probe.exe — checks whether Wine provides the WinRT classes CSP needs.
 * Usage: wine winrt-probe.exe        (return: 0 = all ok, 2 = RadialController missing) */
#include <windows.h>
#include <stdio.h>

typedef struct HSTRING__ { int unused; } *HSTRING;
typedef HRESULT (WINAPI *pWindowsCreateString)(const WCHAR*, UINT32, HSTRING*);
typedef HRESULT (WINAPI *pWindowsDeleteString)(HSTRING);
typedef HRESULT (WINAPI *pRoGetActivationFactory)(HSTRING, const IID*, void**);
typedef HRESULT (WINAPI *pRoInitialize)(int);

/* IInspectable: always implemented by WinRT objects */
static const IID IID_IInspectable_ =
    {0xaf86e2e0,0xb12d,0x4c6a,{0x9c,0x5a,0xd7,0xaa,0x65,0x10,0x1e,0x90}};

static const WCHAR *classes[] = {
    L"Windows.UI.Input.RadialController",
    L"Windows.UI.Input.RadialControllerConfiguration",
    L"Windows.UI.Input.RadialControllerMenuItem",
    L"Windows.Storage.StorageFile",
    L"Windows.Storage.Streams.RandomAccessStreamReference",
    NULL
};

int main(void)
{
    HMODULE cm = LoadLibraryA("combase.dll");
    pWindowsCreateString create;
    pWindowsDeleteString del;
    pRoGetActivationFactory getfact;
    pRoInitialize roinit;
    int missing = 0, checked = 0;

    if (!cm) { printf("ERROR: combase.dll cannot be loaded\n"); return 1; }
    create  = (pWindowsCreateString)(void*)GetProcAddress(cm, "WindowsCreateString");
    del     = (pWindowsDeleteString)(void*)GetProcAddress(cm, "WindowsDeleteString");
    getfact = (pRoGetActivationFactory)(void*)GetProcAddress(cm, "RoGetActivationFactory");
    roinit  = (pRoInitialize)(void*)GetProcAddress(cm, "RoInitialize");
    if (!create || !del || !getfact) { printf("ERROR: WinRT functions missing in combase\n"); return 1; }
    if (roinit) roinit(1); /* RO_INIT_MULTITHREADED */

    printf("wine: %s\n", (GetModuleHandleA("ntdll.dll") ? "ok" : "?"));
    for (int i = 0; classes[i]; i++) {
        HSTRING hs = NULL;
        void *obj = NULL;
        HRESULT hr;
        if (FAILED(create(classes[i], (UINT32)wcslen(classes[i]), &hs))) { printf("  %S: WindowsCreateString failed\n", classes[i]); continue; }
        hr = getfact(hs, &IID_IInspectable_, &obj);
        del(hs);
        checked++;
        if (SUCCEEDED(hr) && obj) {
            printf("  %-52S OK\n", classes[i]);
            ((IUnknown*)obj)->lpVtbl->Release(obj);
        } else {
            printf("  %-52S MISSING (hr=0x%08lx)\n", classes[i], (unsigned long)hr);
            missing++;
        }
    }
    printf("Result: %d classes checked, %d missing\n", checked, missing);
    return missing ? 2 : 0;
}
