#include "freestanding.h"

/* Terminal reporter for fline_shim.s: paint the un-emulatable opcode +
 * fault PC where a photo can read them; the asm halts after we return.
 * Row 40 is free during the corpus run (header 4, test 16, tally 28). */

extern void paint_string(u32 row, u32 col_byte, const char *s, u32 max_chars);

static char hexc(u32 v) { return (char)(v < 10 ? '0' + v : 'A' + v - 10); }

void fline_shim_report(u32 op, u32 pc)
{
    char buf[24];
    u32 i;
    for (i = 0; i < 4; i++) buf[i]     = hexc((op >> (12 - 4 * i)) & 0xF);
    buf[4] = ' ';
    for (i = 0; i < 8; i++) buf[5 + i] = hexc((pc >> (28 - 4 * i)) & 0xF);
    buf[13] = 0;
    paint_string(40, 4, "FLINE OP+PC:", 12);
    paint_string(40, 17, buf, 13);
}
