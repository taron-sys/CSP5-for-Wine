/* Minimal WinTab 1.1 declarations (ASCII only), exact LOGCONTEXTA layout,
 * resolved at runtime via GetProcAddress (no import lib needed). */
#ifndef WINTAB_MIN_H
#define WINTAB_MIN_H
#include <windows.h>

typedef DWORD WTPKT;
typedef DWORD FIX32;
typedef HANDLE HCTX;

/* messages */
#define WT_DEFBASE     0x7FF0
#define WT_PACKET      (WT_DEFBASE + 0)
#define WT_CTXOPEN     (WT_DEFBASE + 1)
#define WT_CTXCLOSE    (WT_DEFBASE + 2)
#define WT_CTXUPDATE   (WT_DEFBASE + 3)
#define WT_CTXOVERLAP  (WT_DEFBASE + 4)
#define WT_PROXIMITY   (WT_DEFBASE + 5)
#define WT_INFOCHANGE  (WT_DEFBASE + 6)
#define WT_CSRCHANGE   (WT_DEFBASE + 7)

/* context options */
#define CXO_SYSTEM       0x0001
#define CXO_PEN          0x0002
#define CXO_MESSAGES     0x0004
#define CXO_CSRMESSAGES  0x0008

/* packet fields */
#define PK_CONTEXT          0x0001
#define PK_STATUS           0x0002
#define PK_TIME             0x0004
#define PK_CHANGED          0x0008
#define PK_SERIAL_NUMBER    0x0010
#define PK_CURSOR           0x0020
#define PK_BUTTONS          0x0040
#define PK_X                0x0080
#define PK_Y                0x0100
#define PK_Z                0x0200
#define PK_NORMAL_PRESSURE  0x0400
#define PK_TANGENT_PRESSURE 0x0800
#define PK_ORIENTATION      0x1000

/* categories + indices */
#define WTI_DEFCONTEXT   3u
#define WTI_DEFSYSCTX    4u
#define WTI_DEVICES      100u
#define WTI_CURSORS      200u
#define DVC_NAME         1u
#define DVC_PKTRATE      5u
#define DVC_PKTDATA      6u
#define DVC_XDATA        12u
#define DVC_YDATA        13u
#define DVC_ZDATA        14u
#define DVC_NPRESSURE    15u
#define DVC_TPRESSURE    16u
#define CSR_NAME         1u
#define CSR_TYPE         2u
#define CSR_NBTN         5u
#define CSR_TYPE_PEN     0x801
#define CSR_TYPE_ERASER  0x802

typedef struct tagAXIS {
    LONG  axMin;
    LONG  axMax;
    UINT  axUnits;
    DWORD axResolution;
} AXIS;

typedef struct tagLOGCONTEXTA {
    char  lcName[40];
    UINT  lcOptions;
    UINT  lcStatus;
    UINT  lcLocks;
    UINT  lcMsgBase;
    UINT  lcDevice;
    UINT  lcPktRate;
    WTPKT lcPktData;
    WTPKT lcPktMode;
    WTPKT lcMoveMask;
    DWORD lcBtnDnMask;
    DWORD lcBtnUpMask;
    LONG  lcInOrgX, lcInOrgY, lcInOrgZ;
    LONG  lcInExtX, lcInExtY, lcInExtZ;
    LONG  lcOutOrgX, lcOutOrgY, lcOutOrgZ;
    LONG  lcOutExtX, lcOutExtY, lcOutExtZ;
    FIX32 lcSensX, lcSensY, lcSensZ;
    BOOL  lcSysMode;
    int   lcSysOrgX, lcSysOrgY;
    int   lcSysExtX, lcSysExtY;
    FIX32 lcSysSensX, lcSysSensY;
} LOGCONTEXTA, *PLOGCONTEXTA, *LPLOGCONTEXTA;

/* packet layout for our chosen PACKETDATA (serial/buttons/x/y/pressure/time) */
typedef struct tagWTPACKET {
    UINT  pkSerialNumber;   /* PK_SERIAL_NUMBER */
    UINT  pkButtons;        /* PK_BUTTONS */
    LONG  pkX;              /* PK_X */
    LONG  pkY;              /* PK_Y */
    UINT  pkNormalPressure; /* PK_NORMAL_PRESSURE */
    DWORD pkTime;           /* PK_TIME */
} WTPACKET, *PWTPACKET;

typedef UINT  (WINAPI *pWTInfoA)(UINT, UINT, LPVOID);
typedef HCTX  (WINAPI *pWTOpenA)(HWND, PLOGCONTEXTA, BOOL);
typedef BOOL  (WINAPI *pWTPacket)(HCTX, UINT, LPVOID);
typedef BOOL  (WINAPI *pWTClose)(HCTX);
static pWTInfoA  WTInfoA;
static pWTOpenA  WTOpenA;
static pWTPacket WTPacket;
static pWTClose  WTClose;

static HMODULE gWinTab;

static int wintab_load(void)
{
    gWinTab = LoadLibraryA("wintab32.dll");
    if (!gWinTab) return 0;
    WTInfoA  = (pWTInfoA)(void *)GetProcAddress(gWinTab, "WTInfoA");
    WTOpenA  = (pWTOpenA)(void *)GetProcAddress(gWinTab, "WTOpenA");
    WTPacket = (pWTPacket)(void *)GetProcAddress(gWinTab, "WTPacket");
    WTClose  = (pWTClose)(void *)GetProcAddress(gWinTab, "WTClose");
    if (WTInfoA && WTOpenA && WTPacket && WTClose) return 1;
    gWinTab = NULL;
    return 0;
}
#endif