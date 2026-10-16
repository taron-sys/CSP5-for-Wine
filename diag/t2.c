#include <stdio.h>
#include "wintab_min.h"
int main(void){
    printf("t2: load..."); fflush(stdout);
    int ok = wintab_load();
    printf(" %d\n", ok); fflush(stdout);
    LOGCONTEXTA lc; ZeroMemory(&lc, sizeof(lc));
    UINT r = WTInfoA(WTI_DEFCONTEXT, 0, &lc);
    printf("WTInfo(3,0)=%u; lcInExtX=%ld lcInExtY=%ld\n", r, lc.lcInExtX, lc.lcInExtY); fflush(stdout);
    fflush(stdout); return 0;
}
