; recursive-descent disassembly of /tmp/ourdriver.bin
; base=0x00000000 size=9392 entries=100
; decoded 2259 instructions, 7012 bytes (74.7% of image) in 2292 steps
;
00000000:  600003d2             bra.w $3d4
00000004:  00000001             ori.b #$1, d0
00000008:  600003d0             bra.w $3da
0000000C:  2324                 move.l -(a4), -(a1)
0000000E:  0001002c             ori.b #$2c, d1
00000012:  00010001             ori.b #$1, d1
00000016:  000024b0             ori.b #$b0, d0
0000001A:  0000095e             ori.b #$5e, d0
0000001E:  6f000000             ble.w $20
00000022:  00000000             ori.b #$0, d0
00000026:  008200ba009a         ori.l #$ba009a, d2
0000002C:  00aa008a072e4153     ori.l #$8a072e, $4153(a2)
00000034:  5943                 subq.w #$4, d3
00000036:  303041bd30b00000     move.w ([$30b00000], d4.w), d0
0000003E:  00007665             ori.b #$65, d0
00000042:  7273                 moveq #$73, d1
00000044:  07358000             btst.l d3, (a5, a0.w)
00000048:  00000537             ori.b #$37, d0
0000004C:  2e332e35             move.l $35(a3, d2.l), d7
00000050:  27372e33             move.l $33(a7, d2.l), -(a3)
00000054:  2e352c20             move.l $20(a5, d2.l), d7
00000058:  ; ==== 38 bytes not reached as code ====
00000058:  a9 20 41 70 70 6c 65 20 43 6f 6d 70 75 74 65 72 |. Apple Computer|
00000068:  2c 20 49 6e 63 2e 20 31 39 38 38 2d 31 39 39 35 |, Inc. 1988-1995|
00000078:  a4 1f 60 00 03 d2                               |..`...|
0000007E:  200d                 move.l a5, d0
00000080:  2a6f0004             movea.l $4(a7), a5
00000084:  4e75                 rts
00000086:  41faffb4             lea.l $3c(pc), a0
0000008A:  30af0006             move.w $6(a7), (a0)
0000008E:  4e75                 rts
00000090:  487a00c2             pea.l $154(pc)
00000094:  201f                 move.l (a7)+, d0
00000096:  4e75                 rts
00000098:  487a01fa             pea.l $294(pc)
0000009C:  201f                 move.l (a7)+, d0
0000009E:  4e75                 rts
000000A0:  7000                 moveq #$0, d0
000000A2:  31400010             move.w d0, $10(a0)
000000A6:  6044                 bra.b $ec
000000A8:  2f0d                 move.l a5, -(a7)
000000AA:  2a690014             movea.l $14(a1), a5
000000AE:  2f08                 move.l a0, -(a7)
000000B0:  2f09                 move.l a1, -(a7)
000000B2:  4eba0d40             jsr $df4(pc)
000000B6:  602e                 bra.b $e6
000000B8:  2f0d                 move.l a5, -(a7)
000000BA:  2a690014             movea.l $14(a1), a5
000000BE:  2f08                 move.l a0, -(a7)
000000C0:  2f09                 move.l a1, -(a7)
000000C2:  4eba1320             jsr $13e4(pc)
000000C6:  601e                 bra.b $e6
000000C8:  2f0d                 move.l a5, -(a7)
000000CA:  2a690014             movea.l $14(a1), a5
000000CE:  2f08                 move.l a0, -(a7)
000000D0:  2f09                 move.l a1, -(a7)
000000D2:  4eba172c             jsr $1800(pc)
000000D6:  600e                 bra.b $e6
000000D8:  2f0d                 move.l a5, -(a7)
000000DA:  2a690014             movea.l $14(a1), a5
000000DE:  2f08                 move.l a0, -(a7)
000000E0:  2f09                 move.l a1, -(a7)
000000E2:  4eba0d86             jsr $e6a(pc)
000000E6:  225f                 movea.l (a7)+, a1
000000E8:  205f                 movea.l (a7)+, a0
000000EA:  2a5f                 movea.l (a7)+, a5
000000EC:  0c400001             cmpi.w #$1, d0
000000F0:  6604                 bne.b $f6
000000F2:  7000                 moveq #$0, d0
000000F4:  6014                 bra.b $10a
000000F6:  4a40                 tst.w d0
000000F8:  6704                 beq.b $fe
000000FA:  31c00142             move.w d0, $142.w
000000FE:  082800090006         btst.b #$9, $6(a0)
00000104:  6604                 bne.b $10a
00000106:  2f3808fc             move.l $8fc.w, -(a7)
0000010A:  4e75                 rts
0000010C:  2f2f0004             move.l $4(a7), -(a7)
00000110:  4eba105e             jsr $1170(pc)
00000114:  588f                 addq.l #$4, a7
00000116:  4a40                 tst.w d0
00000118:  6e1e                 bgt.b $138
0000011A:  6704                 beq.b $120
0000011C:  31c00142             move.w d0, $142.w
00000120:  48e73030             movem.l d2-d3/a2-a3, -(a7)
00000124:  2f00                 move.l d0, -(a7)
00000126:  6100103c             bsr.w $1164
0000012A:  2240                 movea.l d0, a1
0000012C:  201f                 move.l (a7)+, d0
0000012E:  247808fc             movea.l $8fc.w, a2
00000132:  4e92                 jsr (a2)
00000134:  4cdf0c0c             movem.l (a7)+, d2-d3/a2-a3
00000138:  205f                 movea.l (a7)+, a0
0000013A:  588f                 addq.l #$4, a7
0000013C:  4ed0                 jmp (a0)
0000013E:  206f0004             movea.l $4(a7), a0
00000142:  2008                 move.l a0, d0
00000144:  4a18                 tst.b (a0)+
00000146:  66fc                 bne.b $144
00000148:  226f0008             movea.l $8(a7), a1
0000014C:  5388                 subq.l #$1, a0
0000014E:  10d9                 move.b (a1)+, (a0)+
00000150:  66fc                 bne.b $14e
00000152:  4e75                 rts
00000154:  00000000             ori.b #$0, d0
00000158:  00000000             ori.b #$0, d0
0000015C:  00000000             ori.b #$0, d0
00000160:  00000000             ori.b #$0, d0
00000164:  00000000             ori.b #$0, d0
00000168:  00000000             ori.b #$0, d0
0000016C:  00000000             ori.b #$0, d0
00000170:  00000000             ori.b #$0, d0
00000174:  00000000             ori.b #$0, d0
00000178:  00000000             ori.b #$0, d0
0000017C:  00000000             ori.b #$0, d0
00000180:  00000000             ori.b #$0, d0
00000184:  00000000             ori.b #$0, d0
00000188:  00000000             ori.b #$0, d0
0000018C:  00000000             ori.b #$0, d0
00000190:  00000000             ori.b #$0, d0
00000194:  00000000             ori.b #$0, d0
00000198:  00000000             ori.b #$0, d0
0000019C:  ; ==== 100 bytes not reached as code ====
0000019C:  7f ff ff fe 80 00 00 01 80 00 00 01 80 00 00 01 |................|
000001AC:  80 00 00 01 80 00 00 01 80 00 00 01 88 00 00 01 |................|
000001BC:  80 00 00 01 80 00 00 01 7f ff ff fe 00 00 00 00 |................|
000001CC:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
000001DC:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
000001EC:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
000001FC:  00 00 00 00                                     |....|
00000200:  00000000             ori.b #$0, d0
00000204:  00000000             ori.b #$0, d0
00000208:  00000000             ori.b #$0, d0
0000020C:  00000000             ori.b #$0, d0
00000210:  00000000             ori.b #$0, d0
00000214:  00000000             ori.b #$0, d0
00000218:  00000000             ori.b #$0, d0
0000021C:  ; ==== 440 bytes not reached as code ====
0000021C:  7f ff ff fe ff ff ff ff ff ff ff ff ff ff ff ff |................|
0000022C:  ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
0000023C:  ff ff ff ff ff ff ff ff 7f ff ff fe 00 00 00 00 |................|
0000024C:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
0000025C:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
0000026C:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
0000027C:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
0000028C:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
0000029C:  00 00 00 00 00 00 00 00 03 fe 7f c0 02 02 40 40 |..............@@|
000002AC:  03 8e 71 c0 00 88 11 00 00 88 11 00 00 88 16 00 |..q.............|
000002BC:  00 88 16 00 00 80 16 00 0f 79 e6 70 1b 6d b6 d8 |.........y.p.m..|
000002CC:  1b 6d b6 f8 1b 6d b6 c0 0f 79 e6 70 00 61 91 00 |.m...m...y.p.a..|
000002DC:  7f 69 91 7e 80 69 91 01 80 88 11 01 80 88 11 01 |.i.~.i..........|
000002EC:  83 8e 71 c1 82 02 40 41 83 fe 7f c1 88 00 00 01 |..q...@A........|
000002FC:  80 00 00 01 80 00 00 01 7f ff ff fe 00 00 00 00 |................|
0000030C:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
0000031C:  00 00 00 00 07 ff ff e0 07 ff ff e0 07 ff ff e0 |................|
0000032C:  07 ff ff e0 07 ff ff e0 01 fc 3f 80 01 fc 3f 80 |..........?...?.|
0000033C:  01 fc 3f 80 1f ff ff f8 3f ff ff fc 3f ff ff fc |..?.....?...?...|
0000034C:  3f ff ff fc 3f ff ff fc 3f ff ff fc 1f ff ff f8 |?...?...?.......|
0000035C:  7f ff ff fe ff ff ff ff ff ff ff ff ff ff ff ff |................|
0000036C:  ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
0000037C:  ff ff ff ff ff ff ff ff 7f ff ff fe 00 00 00 00 |................|
0000038C:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
0000039C:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
000003AC:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
000003BC:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
000003CC:  00 00 00 00 00 00 00 00                         |........|
000003D4:  0885001d             bclr.b #$1d, d5
000003D8:  6004                 bra.b $3de
000003DA:  08c5001d             bset.b #$1d, d5
000003DE:  48e73f3e             movem.l d2-d7/a2-a6, -(a7)
000003E2:  4eba1b94             jsr $1f78(pc)
000003E6:  41fafc18             lea.l $0(pc), a0
000003EA:  203afc2a             move.l $16(pc), d0
000003EE:  ; ==== 16 bytes not reached as code ====
000003EE:  a0 20 70 00 72 00 30 38 01 d2 04 80 00 00 00 20 |. p.r.08....... |
000003FE:  2278011c             movea.l $11c.w, a1
00000402:  323801d2             move.w $1d2.w, d1
00000406:  e589                 lsl.l #$2, d1
00000408:  d2c1                 adda.w d1, a1
0000040A:  2421                 move.l -(a1), d2
0000040C:  671e                 beq.b $42c
0000040E:  2442                 movea.l d2, a2
00000410:  2052                 movea.l (a2), a0
00000412:  2450                 movea.l (a0), a2
00000414:  0caa41bd30b0001a     cmpi.l #$41bd30b0, $1a(a2)
0000041C:  660e                 bne.b $42c
0000041E:  b6aafffc             cmp.l -$4(a2), d3
00000422:  6608                 bne.b $42c
00000424:  41fafbda             lea.l $0(pc), a0
00000428:  4eea005a             jmp $5a(a2)
0000042C:  51c8ffdc             dbra d0, $40a
00000430:  4a85                 tst.l d5
00000432:  6b1a                 bmi.b $44e
00000434:  0805001d             btst.b #$1d, d5
00000438:  6614                 bne.b $44e
0000043A:  207802a6             movea.l $2a6.w, a0
0000043E:  2050                 movea.l (a0), a0
00000440:  41e83000             lea.l $3000(a0), a0
00000444:  2f380118             move.l $118.w, -(a7)
00000448:  ; ==== 6 bytes not reached as code ====
00000448:  a0 57 21 df 01 18                               |.W!...|
0000044E:  48e760e0             movem.l d1-d2/a0-a2, -(a7)
00000452:  2f05                 move.l d5, -(a7)
00000454:  4eba006c             jsr $4c2(pc)
00000458:  588f                 addq.l #$4, a7
0000045A:  4cdf0706             movem.l (a7)+, d1-d2/a0-a2
0000045E:  4a40                 tst.w d0
00000460:  6706                 beq.b $468
00000462:  3800                 move.w d0, d4
00000464:  4644                 not.w d4
00000466:  6008                 bra.b $470
00000468:  7020                 moveq #$20, d0
0000046A:  d045                 add.w d5, d0
0000046C:  3800                 move.w d0, d4
0000046E:  4640                 not.w d0
00000470:  ; ==== 82 bytes not reached as code ====
00000470:  a0 3d e5 44 22 78 01 1c 20 71 40 00 2c 50 a0 29 |.=.D"x.. q@.,P.)|
00000480:  41 fa fb 9c 2c 88 3d 58 00 04 2d 58 00 22 3d 58 |A...,.=X..-X."=X|
00000490:  00 26 08 ee 00 05 00 05 08 ae 00 06 00 05 70 01 |.&............p.|
000004A0:  08 05 00 1e 67 02 70 00 2f 05 2f 00 2f 0e 4e ba |....g.p./././.N.|
000004B0:  04 94 de fc 00 0c 4a 40 67 02 70 e9 4c df 7c fc |......J@g.p.L.|.|
000004C0:  4e 75                                           |Nu|
000004C2:  4e560000             link.w a6, #$0
000004C6:  2f07                 move.l d7, -(a7)
000004C8:  203c20000000         move.l #$20000000, d0
000004CE:  c0ae0008             and.l $8(a6), d0
000004D2:  6604                 bne.b $4d8
000004D4:  7000                 moveq #$0, d0
000004D6:  6014                 bra.b $4ec
000004D8:  422e0008             clr.b $8(a6)
000004DC:  2f2e0008             move.l $8(a6), -(a7)
000004E0:  4eba00fc             jsr $5de(pc)
000004E4:  3e00                 move.w d0, d7
000004E6:  48c7                 ext.l d7
000004E8:  2007                 move.l d7, d0
000004EA:  584f                 addq.w #$4, a7
000004EC:  2e2efffc             move.l -$4(a6), d7
000004F0:  4e5e                 unlk a6
000004F2:  4e75                 rts
000004F4:  4e56ff26             link.w a6, #$ff26
000004F8:  487800ac             pea.l $ac.w
000004FC:  486eff52             pea.l -$ae(a6)
00000500:  4eba1a3e             jsr $1f40(pc)
00000504:  2d6e0008ff5e         move.l $8(a6), -$a2(a6)
0000050A:  7000                 moveq #$0, d0
0000050C:  2d40ff66             move.l d0, -$9a(a6)
00000510:  1d7c0003ff5a         move.b #$3, -$a6(a6)
00000516:  2d40ff62             move.l d0, -$9e(a6)
0000051A:  3d7c00acff58         move.w #$ac, -$a8(a6)
00000520:  41eeff52             lea.l -$ae(a6), a0
00000524:  7001                 moveq #$1, d0
00000526:  ; ==== 124 bytes not reached as code ====
00000526:  a0 89 20 6d ff 9a 11 6e ff f7 00 28 20 6d ff 9a |.. m...n...( m..|
00000536:  11 6e ff f9 00 29 70 00 10 2e 00 0a 02 2e 00 07 |.n...)p.........|
00000546:  ff fe e7 08 81 2e ff fe 70 00 10 2e 00 0b 02 2e |........p.......|
00000556:  00 f8 ff fe 02 00 00 07 81 2e ff fe 20 6d ff 9a |............ m..|
00000566:  11 6e ff fe 00 32 70 2c 2f 00 48 6e ff 26 4e ba |.n...2p,/.Hn.&N.|
00000576:  19 ca 2d 6e 00 08 ff 32 3d 6e 00 0e ff 4a 1d 7c |..-n...2=n...J.||
00000586:  00 85 ff 2e 70 00 2d 40 ff 36 3d 7c 00 2c ff 2c |....p.-@.6=|.,.,|
00000596:  41 ee ff 26 70 01 a0 89 4e 5e 4e 75             |A..&p...N^Nu|
000005A2:  4e56ffd4             link.w a6, #$ffd4
000005A6:  4a2dfff8             tst.b -$8(a5)
000005AA:  672e                 beq.b $5da
000005AC:  702c                 moveq #$2c, d0
000005AE:  2f00                 move.l d0, -(a7)
000005B0:  486effd4             pea.l -$2c(a6)
000005B4:  4eba198a             jsr $1f40(pc)
000005B8:  2d6e0008ffe0         move.l $8(a6), -$20(a6)
000005BE:  1d7c0087ffdc         move.b #$87, -$24(a6)
000005C4:  7000                 moveq #$0, d0
000005C6:  2d40ffe4             move.l d0, -$1c(a6)
000005CA:  3d7c002cffda         move.w #$2c, -$26(a6)
000005D0:  41eeffd4             lea.l -$2c(a6), a0
000005D4:  7001                 moveq #$1, d0
000005D6:  ; ==== 4 bytes not reached as code ====
000005D6:  a0 89 50 4f                                     |..PO|
000005DA:  4e5e                 unlk a6
000005DC:  4e75                 rts
000005DE:  4e56ffd8             link.w a6, #$ffd8
000005E2:  48e70300             movem.l d6-d7, -(a7)
000005E6:  598f                 subq.l #$4, a7
000005E8:  3f3c0089             move.w #$89, -(a7)
000005EC:  7000                 moveq #$0, d0
000005EE:  1f00                 move.b d0, -(a7)
000005F0:  4eba1bda             jsr $21cc(pc)
000005F4:  598f                 subq.l #$4, a7
000005F6:  3f3c009f             move.w #$9f, -(a7)
000005FA:  7001                 moveq #$1, d0
000005FC:  1f00                 move.b d0, -(a7)
000005FE:  4eba1bcc             jsr $21cc(pc)
00000602:  201f                 move.l (a7)+, d0
00000604:  b09f                 cmp.l (a7)+, d0
00000606:  6604                 bne.b $60c
00000608:  7000                 moveq #$0, d0
0000060A:  607c                 bra.b $688
0000060C:  7028                 moveq #$28, d0
0000060E:  2f00                 move.l d0, -(a7)
00000610:  486effd8             pea.l -$28(a6)
00000614:  4eba192a             jsr $1f40(pc)
00000618:  7000                 moveq #$0, d0
0000061A:  102e000a             move.b $a(a6), d0
0000061E:  3d40fffc             move.w d0, -$4(a6)
00000622:  1d7c0080ffe0         move.b #$80, -$20(a6)
00000628:  7000                 moveq #$0, d0
0000062A:  2d40ffe8             move.l d0, -$18(a6)
0000062E:  3d7c0028ffde         move.w #$28, -$22(a6)
00000634:  41eeffd8             lea.l -$28(a6), a0
00000638:  7001                 moveq #$1, d0
0000063A:  ; ==== 78 bytes not reached as code ====
0000063A:  a0 89 4a 2e ff fe 50 4f 67 1a 10 2e 00 09 b0 2e |..J...POg.......|
0000064A:  ff e5 66 10 70 00 10 2e 00 0a d0 7c 00 20 46 40 |..f.p......|. F@|
0000065A:  48 c0 60 2a 7e 30 60 1a 2c 07 46 86 59 8f 3f 06 |H.`*~0`.,.F.Y.?.|
0000066A:  4e ba 1b 74 4a 9f 66 06 48 c6 20 06 60 10 20 07 |N..tJ.f.H. .`. .|
0000067A:  52 87 70 00 30 38 01 d2 b0 87 62 dc 70 00       |R.p.08....b.p.|
00000688:  4cee00c0ffd0         movem.l -$30(a6), d6-d7
0000068E:  4e5e                 unlk a6
00000690:  4e75                 rts
00000692:  4e560000             link.w a6, #$0
00000696:  2f0c                 move.l a4, -(a7)
00000698:  49edff8a             lea.l -$76(a5), a4
0000069C:  206dff86             movea.l -$7a(a5), a0
000006A0:  316e000a0006         move.w $a(a6), $6(a0)
000006A6:  206dff86             movea.l -$7a(a5), a0
000006AA:  216dffa2000c         move.l -$5e(a5), $c(a0)
000006B0:  206dff86             movea.l -$7a(a5), a0
000006B4:  117c00010008         move.b #$1, $8(a0)
000006BA:  206dff86             movea.l -$7a(a5), a0
000006BE:  42280067             clr.b $67(a0)
000006C2:  206dff86             movea.l -$7a(a5), a0
000006C6:  214c0030             move.l a4, $30(a0)
000006CA:  206dff86             movea.l -$7a(a5), a0
000006CE:  117c00100034         move.b #$10, $34(a0)
000006D4:  206dff86             movea.l -$7a(a5), a0
000006D8:  42280066             clr.b $66(a0)
000006DC:  206dff86             movea.l -$7a(a5), a0
000006E0:  117c000a0035         move.b #$a, $35(a0)
000006E6:  206dff86             movea.l -$7a(a5), a0
000006EA:  42280045             clr.b $45(a0)
000006EE:  206dff86             movea.l -$7a(a5), a0
000006F2:  4228004a             clr.b $4a(a0)
000006F6:  206dff86             movea.l -$7a(a5), a0
000006FA:  4228004d             clr.b $4d(a0)
000006FE:  7000                 moveq #$0, d0
00000700:  102dffee             move.b -$12(a5), d0
00000704:  0c400002             cmpi.w #$2, d0
00000708:  662a                 bne.b $734
0000070A:  206dff86             movea.l -$7a(a5), a0
0000070E:  316dffe80070         move.w -$18(a5), $70(a0)
00000714:  7000                 moveq #$0, d0
00000716:  302dffe8             move.w -$18(a5), d0
0000071A:  223c00000200         move.l #$200, d1
00000720:  9280                 sub.l d0, d1
00000722:  206dff86             movea.l -$7a(a5), a0
00000726:  31410072             move.w d1, $72(a0)
0000072A:  206dff86             movea.l -$7a(a5), a0
0000072E:  42680074             clr.w $74(a0)
00000732:  6012                 bra.b $746
00000734:  206dff86             movea.l -$7a(a5), a0
00000738:  317c02000070         move.w #$200, $70(a0)
0000073E:  206dff86             movea.l -$7a(a5), a0
00000742:  42680072             clr.w $72(a0)
00000746:  286efffc             movea.l -$4(a6), a4
0000074A:  4e5e                 unlk a6
0000074C:  4e75                 rts
0000074E:  4e56ff54             link.w a6, #$ff54
00000752:  487800ac             pea.l $ac.w
00000756:  486eff54             pea.l -$ac(a6)
0000075A:  4eba17e4             jsr $1f40(pc)
0000075E:  2d6dffa2ff60         move.l -$5e(a5), -$a0(a6)
00000764:  7000                 moveq #$0, d0
00000766:  2d40ff68             move.l d0, -$98(a6)
0000076A:  2d40ff64             move.l d0, -$9c(a6)
0000076E:  3d7c00acff5a         move.w #$ac, -$a6(a6)
00000774:  1d7c0003ff5c         move.b #$3, -$a4(a6)
0000077A:  41eeff54             lea.l -$ac(a6), a0
0000077E:  7001                 moveq #$1, d0
00000780:  ; ==== 110 bytes not reached as code ====
00000780:  a0 89 2b 7c 00 04 00 00 ff 76 3b 7c 02 00 ff 74 |..+|.....v;|...t|
00000790:  42 2d ff 72 20 3c 00 40 00 00 c0 ae ff a0 67 20 |B-.r <.@......g |
000007A0:  4a 2d ff 7e 66 0e 4a 2d ff 7c 67 14 70 02 c0 ae |J-.~f.J-.|g.p...|
000007B0:  ff 84 67 0c 1b 7c 00 01 ff 72 00 6d 01 00 ff 74 |..g..|...r.m...t|
000007C0:  4a 2d ff 80 67 06 00 6d 00 02 ff 74 4a 2d ff 7a |J-..g..m...tJ-.z|
000007D0:  67 08 00 ad 00 00 00 04 ff 76 20 2e ff a0 c1 ad |g........v .....|
000007E0:  ff 76 30 2e ff a4 c1 6d ff 74 4e 5e 4e 75       |.v0....m.tN^Nu|
000007EE:  4e560000             link.w a6, #$0
000007F2:  48e71108             movem.l d3/d7/a4, -(a7)
000007F6:  49edf652             lea.l -$9ae(a5), a4
000007FA:  4247                 clr.w d7
000007FC:  7614                 moveq #$14, d3
000007FE:  2007                 move.l d7, d0
00000800:  ed40                 asl.w #$6, d0
00000802:  0c74ffff0016         cmpi.w #$ffff, $16(a4, d0.w)
00000808:  6606                 bne.b $810
0000080A:  48c7                 ext.l d7
0000080C:  2007                 move.l d7, d0
0000080E:  600a                 bra.b $81a
00000810:  3007                 move.w d7, d0
00000812:  5247                 addq.w #$1, d7
00000814:  b647                 cmp.w d7, d3
00000816:  6ee6                 bgt.b $7fe
00000818:  70ff                 moveq #$ff, d0
0000081A:  4cee1088fff4         movem.l -$c(a6), d3/d7/a4
00000820:  4e5e                 unlk a6
00000822:  4e75                 rts
00000824:  4e560000             link.w a6, #$0
00000828:  2f07                 move.l d7, -(a7)
0000082A:  1e2e000b             move.b $b(a6), d7
0000082E:  7000                 moveq #$0, d0
00000830:  1007                 move.b d7, d0
00000832:  0c000061             cmpi.b #$61, d0
00000836:  6518                 bcs.b $850
00000838:  7000                 moveq #$0, d0
0000083A:  1007                 move.b d7, d0
0000083C:  0c00007a             cmpi.b #$7a, d0
00000840:  620e                 bhi.b $850
00000842:  7000                 moveq #$0, d0
00000844:  1007                 move.b d7, d0
00000846:  323c00df             move.w #$df, d1
0000084A:  c200                 and.b d0, d1
0000084C:  1001                 move.b d1, d0
0000084E:  6002                 bra.b $852
00000850:  1007                 move.b d7, d0
00000852:  2e2efffc             move.l -$4(a6), d7
00000856:  4e5e                 unlk a6
00000858:  4e75                 rts
0000085A:  4e56fffc             link.w a6, #$fffc
0000085E:  48e71318             movem.l d3/d6-d7/a3-a4, -(a7)
00000862:  266e0008             movea.l $8(a6), a3
00000866:  49edf648             lea.l -$9b8(a5), a4
0000086A:  4246                 clr.w d6
0000086C:  4247                 clr.w d7
0000086E:  2006                 move.l d6, d0
00000870:  e540                 asl.w #$2, d0
00000872:  41edf630             lea.l -$9d0(a5), a0
00000876:  2d700000fffc         move.l (a0, d0.w), -$4(a6)
0000087C:  6068                 bra.b $8e6
0000087E:  3007                 move.w d7, d0
00000880:  5247                 addq.w #$1, d7
00000882:  206efffc             movea.l -$4(a6), a0
00000886:  7200                 moveq #$0, d1
00000888:  12300000             move.b (a0, d0.w), d1
0000088C:  4a81                 tst.l d1
0000088E:  6656                 bne.b $8e6
00000890:  3006                 move.w d6, d0
00000892:  6724                 beq.b $8b8
00000894:  5340                 subq.w #$1, d0
00000896:  6706                 beq.b $89e
00000898:  5940                 subq.w #$4, d0
0000089A:  670e                 beq.b $8aa
0000089C:  6044                 bra.b $8e2
0000089E:  206e000c             movea.l $c(a6), a0
000008A2:  4250                 clr.w (a0)
000008A4:  7002                 moveq #$2, d0
000008A6:  60000092             bra.w $93a
000008AA:  206e000c             movea.l $c(a6), a0
000008AE:  30bc0100             move.w #$100, (a0)
000008B2:  7004                 moveq #$4, d0
000008B4:  60000084             bra.w $93a
000008B8:  4247                 clr.w d7
000008BA:  6012                 bra.b $8ce
000008BC:  3007                 move.w d7, d0
000008BE:  5247                 addq.w #$1, d7
000008C0:  7200                 moveq #$0, d1
000008C2:  12340000             move.b (a4, d0.w), d1
000008C6:  4a81                 tst.l d1
000008C8:  6604                 bne.b $8ce
000008CA:  7001                 moveq #$1, d0
000008CC:  606c                 bra.b $93a
000008CE:  7000                 moveq #$0, d0
000008D0:  10337010             move.b $10(a3, d7.w), d0
000008D4:  2f00                 move.l d0, -(a7)
000008D6:  4ebaff4c             jsr $824(pc)
000008DA:  b0347000             cmp.b (a4, d7.w), d0
000008DE:  584f                 addq.w #$4, a7
000008E0:  67da                 beq.b $8bc
000008E2:  7003                 moveq #$3, d0
000008E4:  6054                 bra.b $93a
000008E6:  206efffc             movea.l -$4(a6), a0
000008EA:  2f08                 move.l a0, -(a7)
000008EC:  7000                 moveq #$0, d0
000008EE:  10337030             move.b $30(a3, d7.w), d0
000008F2:  2f00                 move.l d0, -(a7)
000008F4:  4ebaff2e             jsr $824(pc)
000008F8:  588f                 addq.l #$4, a7
000008FA:  205f                 movea.l (a7)+, a0
000008FC:  b0307000             cmp.b (a0, d7.w), d0
00000900:  6700ff7c             beq.w $87e
00000904:  3006                 move.w d6, d0
00000906:  5246                 addq.w #$1, d6
00000908:  0c460005             cmpi.w #$5, d6
0000090C:  6f00ff5e             ble.w $86c
00000910:  3c2b0002             move.w $2(a3), d6
00000914:  48c6                 ext.l d6
00000916:  0c860000fffe         cmpi.l #$fffe, d6
0000091C:  6604                 bne.b $922
0000091E:  7003                 moveq #$3, d0
00000920:  6018                 bra.b $93a
00000922:  0c460100             cmpi.w #$100, d6
00000926:  6e0a                 bgt.b $932
00000928:  206e000c             movea.l $c(a6), a0
0000092C:  30bcffff             move.w #$ffff, (a0)
00000930:  6006                 bra.b $938
00000932:  206e000c             movea.l $c(a6), a0
00000936:  3086                 move.w d6, (a0)
00000938:  7004                 moveq #$4, d0
0000093A:  4cee18c8ffe8         movem.l -$18(a6), d3/d6-d7/a3-a4
00000940:  4e5e                 unlk a6
00000942:  4e75                 rts
00000944:  4e56fd12             link.w a6, #$fd12
00000948:  48e70f18             movem.l d4-d7/a3-a4, -(a7)
0000094C:  206e0008             movea.l $8(a6), a0
00000950:  4aa80014             tst.l $14(a0)
00000954:  6712                 beq.b $968
00000956:  2f280014             move.l $14(a0), -(a7)
0000095A:  4ebaf722             jsr $7e(pc)
0000095E:  2d40fd18             move.l d0, -$2e8(a6)
00000962:  584f                 addq.w #$4, a7
00000964:  60000098             bra.w $9fe
00000968:  ; ==== 150 bytes not reached as code ====
00000968:  a1 1a 2d 48 fd 1c 20 78 02 a6 a0 1b 4e ba 18 ca |..-H.. x....N...|
00000978:  2d 40 fd 14 20 6e fd 1c a0 1b 4a ae fd 14 66 06 |-@.. n....J...f.|
00000988:  70 ff 60 00 04 5e 2f 2e fd 14 4e ba 18 7c 20 6e |p.`..^/...N..| n|
00000998:  00 08 21 6e fd 14 00 14 4e ba f6 dc 2d 40 fd 18 |..!n....N...-@..|
000009A8:  20 38 02 ae 50 80 20 40 1b 50 ff fe 70 00 10 2d | 8..P. @.P..p..-|
000009B8:  ff fe 4a 80 58 4f 66 06 42 2d ff fc 60 18 1b 7c |..J.XOf.B-..`..||
000009C8:  00 01 ff fc 70 00 10 2d ff fe 0c 00 00 03 65 06 |....p..-......e.|
000009D8:  1b 7c 00 02 ff fe 42 2d ff f2 7c 00 60 12 20 06 |.|....B-..|.`. .|
000009E8:  ed 40 41 ed f6 52 31 bc ff ff 00 16 20 06 52 86 |.@A..R1..... .R.|
000009F8:  70 14 b0 86 62 e8                               |p...b.|
000009FE:  206e0008             movea.l $8(a6), a0
00000A02:  2b48ff9a             move.l a0, -$66(a5)
00000A06:  006800040004         ori.w #$4, $4(a0)
00000A0C:  422dfff8             clr.b -$8(a5)
00000A10:  7000                 moveq #$0, d0
00000A12:  2b40ff86             move.l d0, -$7a(a5)
00000A16:  223c20000000         move.l #$20000000, d1
00000A1C:  c2ae0010             and.l $10(a6), d1
00000A20:  661e                 bne.b $a40
00000A22:  70ff                 moveq #$ff, d0
00000A24:  2b40ffa2             move.l d0, -$5e(a5)
00000A28:  223c000000ff         move.l #$ff, d1
00000A2E:  c2ae0010             and.l $10(a6), d1
00000A32:  3d41fd20             move.w d1, -$2e0(a6)
00000A36:  7400                 moveq #$0, d2
00000A38:  3401                 move.w d1, d2
00000A3A:  2b42ffa6             move.l d2, -$5a(a5)
00000A3E:  601c                 bra.b $a5c
00000A40:  2b6e0010ffa2         move.l $10(a6), -$5e(a5)
00000A46:  422dffa2             clr.b -$5e(a5)
00000A4A:  7000                 moveq #$0, d0
00000A4C:  102e0012             move.b $12(a6), d0
00000A50:  3d40fd20             move.w d0, -$2e0(a6)
00000A54:  7200                 moveq #$0, d1
00000A56:  3200                 move.w d0, d1
00000A58:  2b41ffa6             move.l d1, -$5a(a5)
00000A5C:  598f                 subq.l #$4, a7
00000A5E:  3f3c0089             move.w #$89, -(a7)
00000A62:  7000                 moveq #$0, d0
00000A64:  1f00                 move.b d0, -(a7)
00000A66:  4eba1764             jsr $21cc(pc)
00000A6A:  598f                 subq.l #$4, a7
00000A6C:  3f3c009f             move.w #$9f, -(a7)
00000A70:  7001                 moveq #$1, d0
00000A72:  1f00                 move.b d0, -(a7)
00000A74:  4eba1756             jsr $21cc(pc)
00000A78:  201f                 move.l (a7)+, d0
00000A7A:  b09f                 cmp.l (a7)+, d0
00000A7C:  670000d6             beq.w $b54
00000A80:  203c20000000         move.l #$20000000, d0
00000A86:  c0ae0010             and.l $10(a6), d0
00000A8A:  6642                 bne.b $ace
00000A8C:  7028                 moveq #$28, d0
00000A8E:  2f00                 move.l d0, -(a7)
00000A90:  486efdd8             pea.l -$228(a6)
00000A94:  4eba14aa             jsr $1f40(pc)
00000A98:  203c000000ff         move.l #$ff, d0
00000A9E:  c0ae0010             and.l $10(a6), d0
00000AA2:  3d40fdfc             move.w d0, -$204(a6)
00000AA6:  1d7c0080fde0         move.b #$80, -$220(a6)
00000AAC:  7000                 moveq #$0, d0
00000AAE:  2d40fde8             move.l d0, -$218(a6)
00000AB2:  3d7c0028fdde         move.w #$28, -$222(a6)
00000AB8:  41eefdd8             lea.l -$228(a6), a0
00000ABC:  7001                 moveq #$1, d0
00000ABE:  ; ==== 16 bytes not reached as code ====
00000ABE:  a0 89 4a 2e fd fe 50 4f 67 06 2b 6e fd e4 ff a2 |..J...POg.+n....|
00000ACE:  70ff                 moveq #$ff, d0
00000AD0:  b0adffa2             cmp.l -$5e(a5), d0
00000AD4:  677e                 beq.b $b54
00000AD6:  487800ac             pea.l $ac.w
00000ADA:  486efd2c             pea.l -$2d4(a6)
00000ADE:  4eba1460             jsr $1f40(pc)
00000AE2:  2d6dffa2fd38         move.l -$5e(a5), -$2c8(a6)
00000AE8:  7000                 moveq #$0, d0
00000AEA:  2d40fd40             move.l d0, -$2c0(a6)
00000AEE:  1d7c0003fd34         move.b #$3, -$2cc(a6)
00000AF4:  2d40fd3c             move.l d0, -$2c4(a6)
00000AF8:  3d7c00acfd32         move.w #$ac, -$2ce(a6)
00000AFE:  41eefd2c             lea.l -$2d4(a6), a0
00000B02:  7001                 moveq #$1, d0
00000B04:  ; ==== 80 bytes not reached as code ====
00000B04:  a0 89 4a 6e fd 36 50 4f 66 46 70 00 10 2e fd 60 |..Jn.6POfFp....`|
00000B14:  0c 40 00 2b 66 3a 70 00 30 2e fd 58 a7 1e 2b 48 |.@.+f:p.0..X..+H|
00000B24:  ff 86 20 08 67 2a 1b 7c 00 01 ff f8 20 6e 00 08 |.. .g*.|.... n..|
00000B34:  30 28 00 18 48 c0 2f 00 2f 2d ff a2 4e ba f9 b2 |0(..H././-..N...|
00000B44:  70 00 30 2e fd 58 2f 00 4e ba fb 44 4f ef 00 0c |p.0..X/.N..DO...|
00000B54:  7000                 moveq #$0, d0
00000B56:  102dfff8             move.b -$8(a5), d0
00000B5A:  4a80                 tst.l d0
00000B5C:  6606                 bne.b $b64
00000B5E:  70ff                 moveq #$ff, d0
00000B60:  2b40ffa2             move.l d0, -$5e(a5)
00000B64:  7000                 moveq #$0, d0
00000B66:  2f00                 move.l d0, -(a7)
00000B68:  4eba0dcc             jsr $1936(pc)
00000B6C:  422efd23             clr.b -$2dd(a6)
00000B70:  7001                 moveq #$1, d0
00000B72:  2d40fd26             move.l d0, -$2da(a6)
00000B76:  426efd24             clr.w -$2dc(a6)
00000B7A:  7c01                 moveq #$1, d6
00000B7C:  584f                 addq.w #$4, a7
00000B7E:  600001de             bra.w $d5e
00000B82:  7000                 moveq #$0, d0
00000B84:  2f00                 move.l d0, -(a7)
00000B86:  486efe00             pea.l -$200(a6)
00000B8A:  2f06                 move.l d6, -(a7)
00000B8C:  7201                 moveq #$1, d1
00000B8E:  2f01                 move.l d1, -(a7)
00000B90:  2f00                 move.l d0, -(a7)
00000B92:  4eba06b0             jsr $1244(pc)
00000B96:  3800                 move.w d0, d4
00000B98:  4fef0014             lea.l $14(a7), a7
00000B9C:  6708                 beq.b $ba6
00000B9E:  0c44fffc             cmpi.w #$fffc, d4
00000BA2:  660001b6             bne.w $d5a
00000BA6:  7000                 moveq #$0, d0
00000BA8:  302efe00             move.w -$200(a6), d0
00000BAC:  0c800000504d         cmpi.l #$504d, d0
00000BB2:  660001a6             bne.w $d5a
00000BB6:  7001                 moveq #$1, d0
00000BB8:  b086                 cmp.l d6, d0
00000BBA:  6606                 bne.b $bc2
00000BBC:  2d6efe04fd26         move.l -$1fc(a6), -$2da(a6)
00000BC2:  486efd12             pea.l -$2ee(a6)
00000BC6:  486efe00             pea.l -$200(a6)
00000BCA:  4ebafc8e             jsr $85a(pc)
00000BCE:  3a00                 move.w d0, d5
00000BD0:  5340                 subq.w #$1, d0
00000BD2:  504f                 addq.w #$8, a7
00000BD4:  6b000184             bmi.w $d5a
00000BD8:  0c400003             cmpi.w #$3, d0
00000BDC:  6e00017c             bgt.w $d5a
00000BE0:  d040                 add.w d0, d0
00000BE2:  303b0006             move.w $bea(pc, d0.w), d0
00000BE6:  4efb0000             jmp $be8(pc,d0.w)
00000BEA:  ; ==== 2 bytes not reached as code ====
00000BEA:  00 0a                                           |..|
00000BEC:  007601720076         ori.w #$172, $76(a6, d0.w)
00000BF2:  4a2efd23             tst.b -$2dd(a6)
00000BF6:  66000162             bne.w $d5a
00000BFA:  0cae00010600fe88     cmpi.l #$10600, -$178(a6)
00000C02:  670c                 beq.b $c10
00000C04:  0cae00010500fe88     cmpi.l #$10500, -$178(a6)
00000C0C:  6600014c             bne.w $d5a
00000C10:  1d7c0001fd23         move.b #$1, -$2dd(a6)
00000C16:  7000                 moveq #$0, d0
00000C18:  102efe8f             move.b -$171(a6), d0
00000C1C:  3b40ffe8             move.w d0, -$18(a5)
00000C20:  1b6efe93ffee         move.b -$16d(a6), -$12(a5)
00000C26:  1b6efe95ffea         move.b -$16b(a6), -$16(a5)
00000C2C:  1b6efe8cfff6         move.b -$174(a6), -$a(a5)
00000C32:  1b6efe8dfff4         move.b -$173(a6), -$c(a5)
00000C38:  1b6efe8eff80         move.b -$172(a6), -$80(a5)
00000C3E:  1b6efe98ff7e         move.b -$168(a6), -$82(a5)
00000C44:  1b6efe99ff7c         move.b -$167(a6), -$84(a5)
00000C4A:  1b6efe9aff7a         move.b -$166(a6), -$86(a5)
00000C50:  7000                 moveq #$0, d0
00000C52:  102efe9b             move.b -$165(a6), d0
00000C56:  2b40ff6e             move.l d0, -$92(a5)
00000C5A:  600000fe             bra.w $d5a
00000C5E:  4ebafb8e             jsr $7ee(pc)
00000C62:  3d40fd2a             move.w d0, -$2d6(a6)
00000C66:  70ff                 moveq #$ff, d0
00000C68:  b06efd2a             cmp.w -$2d6(a6), d0
00000C6C:  670000ec             beq.w $d5a
00000C70:  302efd2a             move.w -$2d6(a6), d0
00000C74:  ed40                 asl.w #$6, d0
00000C76:  41edf652             lea.l -$9ae(a5), a0
00000C7A:  49f00000             lea.l (a0, d0.w), a4
00000C7E:  7e08                 moveq #$8, d7
00000C80:  2678030a             movea.l $30a.w, a3
00000C84:  6016                 bra.b $c9c
00000C86:  7000                 moveq #$0, d0
00000C88:  3007                 move.w d7, d0
00000C8A:  322b0006             move.w $6(a3), d1
00000C8E:  48c1                 ext.l d1
00000C90:  b280                 cmp.l d0, d1
00000C92:  6606                 bne.b $c9a
00000C94:  3007                 move.w d7, d0
00000C96:  5247                 addq.w #$1, d7
00000C98:  60e6                 bra.b $c80
00000C9A:  2653                 movea.l (a3), a3
00000C9C:  200b                 move.l a3, d0
00000C9E:  66e6                 bne.b $c86
00000CA0:  4254                 clr.w (a4)
00000CA2:  7020                 moveq #$20, d0
00000CA4:  c0aefe58             and.l -$1a8(a6), d0
00000CA8:  6704                 beq.b $cae
00000CAA:  7000                 moveq #$0, d0
00000CAC:  6006                 bra.b $cb4
00000CAE:  203c00000080         move.l #$80, d0
00000CB4:  19400002             move.b d0, $2(a4)
00000CB8:  197c00080003         move.b #$8, $3(a4)
00000CBE:  197c00010004         move.b #$1, $4(a4)
00000CC4:  422c0005             clr.b $5(a4)
00000CC8:  397c0001000a         move.w #$1, $a(a4)
00000CCE:  7000                 moveq #$0, d0
00000CD0:  29400006             move.l d0, $6(a4)
00000CD4:  396efd120010         move.w -$2ee(a6), $10(a4)
00000CDA:  426c0024             clr.w $24(a4)
00000CDE:  0c450002             cmpi.w #$2, d5
00000CE2:  6614                 bne.b $cf8
00000CE4:  4aae000c             tst.l $c(a6)
00000CE8:  670e                 beq.b $cf8
00000CEA:  102dfff2             move.b -$e(a5), d0
00000CEE:  522dfff2             addq.b #$1, -$e(a5)
00000CF2:  397c00010024         move.w #$1, $24(a4)
00000CF8:  0c450004             cmpi.w #$4, d5
00000CFC:  6606                 bne.b $d04
00000CFE:  3d7c0001fd24         move.w #$1, -$2dc(a6)
00000D04:  396efe560012         move.w -$1aa(a6), $12(a4)
00000D0A:  202efe54             move.l -$1ac(a6), d0
00000D0E:  4240                 clr.w d0
00000D10:  4840                 swap d0
00000D12:  39400014             move.w d0, $14(a4)
00000D16:  202efe50             move.l -$1b0(a6), d0
00000D1A:  d0aefe08             add.l -$1f8(a6), d0
00000D1E:  29400018             move.l d0, $18(a4)
00000D22:  2940001c             move.l d0, $1c(a4)
00000D26:  296efe540020         move.l -$1ac(a6), $20(a4)
00000D2C:  39470016             move.w d7, $16(a4)
00000D30:  206e0008             movea.l $8(a6), a0
00000D34:  3f280018             move.w $18(a0), -(a7)
00000D38:  3f07                 move.w d7, -(a7)
00000D3A:  486c0006             pea.l $6(a4)
00000D3E:  4eba14ba             jsr $21fa(pc)
00000D42:  4aae000c             tst.l $c(a6)
00000D46:  6712                 beq.b $d5a
00000D48:  4a6c0024             tst.w $24(a4)
00000D4C:  670c                 beq.b $d5a
00000D4E:  307c0007             movea.w #$7, a0
00000D52:  7000                 moveq #$0, d0
00000D54:  3007                 move.w d7, d0
00000D56:  4a80                 tst.l d0
00000D58:  ; ==== 2 bytes not reached as code ====
00000D58:  a0 2f                                           |./|
00000D5A:  2006                 move.l d6, d0
00000D5C:  5286                 addq.l #$1, d6
00000D5E:  bcaefd26             cmp.l -$2da(a6), d6
00000D62:  6300fe1e             bls.w $b82
00000D66:  4a6efd24             tst.w -$2dc(a6)
00000D6A:  672e                 beq.b $d9a
00000D6C:  598f                 subq.l #$4, a7
00000D6E:  3f3c00ac             move.w #$ac, -(a7)
00000D72:  7000                 moveq #$0, d0
00000D74:  1f00                 move.b d0, -(a7)
00000D76:  4eba1454             jsr $21cc(pc)
00000D7A:  598f                 subq.l #$4, a7
00000D7C:  3f3c009f             move.w #$9f, -(a7)
00000D80:  7001                 moveq #$1, d0
00000D82:  1f00                 move.b d0, -(a7)
00000D84:  4eba1446             jsr $21cc(pc)
00000D88:  201f                 move.l (a7)+, d0
00000D8A:  b09f                 cmp.l (a7)+, d0
00000D8C:  670c                 beq.b $d9a
00000D8E:  558f                 subq.l #$2, a7
00000D90:  7001                 moveq #$1, d0
00000D92:  3f00                 move.w d0, -(a7)
00000D94:  4eba11d2             jsr $1f68(pc)
00000D98:  381f                 move.w (a7)+, d4
00000D9A:  4a2efd23             tst.b -$2dd(a6)
00000D9E:  6604                 bne.b $da4
00000DA0:  78fe                 moveq #$fe, d4
00000DA2:  6012                 bra.b $db6
00000DA4:  1b7c0001fffa         move.b #$1, -$6(a5)
00000DAA:  4244                 clr.w d4
00000DAC:  4a2dfff8             tst.b -$8(a5)
00000DB0:  6704                 beq.b $db6
00000DB2:  4ebaf99a             jsr $74e(pc)
00000DB6:  4a44                 tst.w d4
00000DB8:  6722                 beq.b $ddc
00000DBA:  2678030a             movea.l $30a.w, a3
00000DBE:  6018                 bra.b $dd8
00000DC0:  206e0008             movea.l $8(a6), a0
00000DC4:  30280018             move.w $18(a0), d0
00000DC8:  b06b0008             cmp.w $8(a3), d0
00000DCC:  6608                 bne.b $dd6
00000DCE:  204b                 movea.l a3, a0
00000DD0:  327c0308             movea.w #$308, a1
00000DD4:  ; ==== 2 bytes not reached as code ====
00000DD4:  a9 6e                                           |.n|
00000DD6:  2653                 movea.l (a3), a3
00000DD8:  200b                 move.l a3, d0
00000DDA:  66e4                 bne.b $dc0
00000DDC:  2f2efd18             move.l -$2e8(a6), -(a7)
00000DE0:  4eba1458             jsr $223a(pc)
00000DE4:  48c4                 ext.l d4
00000DE6:  2004                 move.l d4, d0
00000DE8:  584f                 addq.w #$4, a7
00000DEA:  4cee18f0fcfa         movem.l -$306(a6), d4-d7/a3-a4
00000DF0:  4e5e                 unlk a6
00000DF2:  4e75                 rts
00000DF4:  4e560000             link.w a6, #$0
00000DF8:  48e71118             movem.l d3/d7/a3-a4, -(a7)
00000DFC:  47edf652             lea.l -$9ae(a5), a3
00000E00:  2f2dffa2             move.l -$5e(a5), -(a7)
00000E04:  4ebaf79c             jsr $5a2(pc)
00000E08:  7e00                 moveq #$0, d7
00000E0A:  584f                 addq.w #$4, a7
00000E0C:  2007                 move.l d7, d0
00000E0E:  ed40                 asl.w #$6, d0
00000E10:  49f30000             lea.l (a3, d0.w), a4
00000E14:  204c                 movea.l a4, a0
00000E16:  5c88                 addq.l #$6, a0
00000E18:  327c0308             movea.w #$308, a1
00000E1C:  ; ==== 78 bytes not reached as code ====
00000E1C:  a9 6e 39 7c ff ff 00 16 70 00 30 2c 00 24 72 01 |.n9|....p.0,.$r.|
00000E2C:  b2 80 66 08 10 2d ff f2 53 2d ff f2 20 07 52 87 |..f..-..S-.. .R.|
00000E3C:  70 14 b0 87 6e ca a1 1a 26 48 20 78 02 a6 a0 1b |p...n...&H x....|
00000E4C:  20 6e 00 08 2f 28 00 14 4e ba 13 fa 20 4b a0 1b | n../(..N... K..|
00000E5C:  70 00 58 4f 4c ee 18 88 ff f0 4e 5e 4e 75       |p.XOL.....N^Nu|
00000E6A:  4e56fffe             link.w a6, #$fffe
00000E6E:  48e71f18             movem.l d3-d7/a3-a4, -(a7)
00000E72:  266e000c             movea.l $c(a6), a3
00000E76:  422efffe             clr.b -$2(a6)
00000E7A:  7000                 moveq #$0, d0
00000E7C:  102b0007             move.b $7(a3), d0
00000E80:  0c400003             cmpi.w #$3, d0
00000E84:  57c3                 seq.b d3
00000E86:  4403                 neg.b d3
00000E88:  4883                 ext.w d3
00000E8A:  48c3                 ext.l d3
00000E8C:  2803                 move.l d3, d4
00000E8E:  303c0100             move.w #$100, d0
00000E92:  c06b002c             and.w $2c(a3), d0
00000E96:  671c                 beq.b $eb4
00000E98:  49eb002e             lea.l $2e(a3), a4
00000E9C:  202c0002             move.l $2(a4), d0
00000EA0:  ef88                 lsl.l #$7, d0
00000EA2:  7209                 moveq #$9, d1
00000EA4:  342c0006             move.w $6(a4), d2
00000EA8:  e26a                 lsr.w d1, d2
00000EAA:  7200                 moveq #$0, d1
00000EAC:  3202                 move.w d2, d1
00000EAE:  2e01                 move.l d1, d7
00000EB0:  de80                 add.l d0, d7
00000EB2:  6008                 bra.b $ebc
00000EB4:  7009                 moveq #$9, d0
00000EB6:  2e2b002e             move.l $2e(a3), d7
00000EBA:  e0af                 lsr.l d0, d7
00000EBC:  7009                 moveq #$9, d0
00000EBE:  2a2b0024             move.l $24(a3), d5
00000EC2:  e0ad                 lsr.l d0, d5
00000EC4:  4246                 clr.w d6
00000EC6:  7614                 moveq #$14, d3
00000EC8:  2006                 move.l d6, d0
00000ECA:  ed40                 asl.w #$6, d0
00000ECC:  41edf652             lea.l -$9ae(a5), a0
00000ED0:  49f00000             lea.l (a0, d0.w), a4
00000ED4:  7000                 moveq #$0, d0
00000ED6:  302c0016             move.w $16(a4), d0
00000EDA:  322b0016             move.w $16(a3), d1
00000EDE:  48c1                 ext.l d1
00000EE0:  b280                 cmp.l d0, d1
00000EE2:  6708                 beq.b $eec
00000EE4:  3006                 move.w d6, d0
00000EE6:  5246                 addq.w #$1, d6
00000EE8:  b646                 cmp.w d6, d3
00000EEA:  6edc                 bgt.b $ec8
00000EEC:  0c460014             cmpi.w #$14, d6
00000EF0:  6606                 bne.b $ef8
00000EF2:  7cc8                 moveq #$c8, d6
00000EF4:  60000124             bra.w $101a
00000EF8:  4a84                 tst.l d4
00000EFA:  670c                 beq.b $f08
00000EFC:  4a2c0002             tst.b $2(a4)
00000F00:  6706                 beq.b $f08
00000F02:  7cd4                 moveq #$d4, d6
00000F04:  60000114             bra.w $101a
00000F08:  203c000001ff         move.l #$1ff, d0
00000F0E:  c0ab0024             and.l $24(a3), d0
00000F12:  6610                 bne.b $f24
00000F14:  4aac001c             tst.l $1c(a4)
00000F18:  6710                 beq.b $f2a
00000F1A:  2007                 move.l d7, d0
00000F1C:  d085                 add.l d5, d0
00000F1E:  b0ac0020             cmp.l $20(a4), d0
00000F22:  6306                 bls.b $f2a
00000F24:  7cce                 moveq #$ce, d6
00000F26:  600000f2             bra.w $101a
00000F2A:  2b4bff9e             move.l a3, -$62(a5)
00000F2E:  2b6b0020fb5e         move.l $20(a3), -$4a2(a5)
00000F34:  2b45fb5a             move.l d5, -$4a6(a5)
00000F38:  202c001c             move.l $1c(a4), d0
00000F3C:  d087                 add.l d7, d0
00000F3E:  2b40fb56             move.l d0, -$4aa(a5)
00000F42:  2b44fb52             move.l d4, -$4ae(a5)
00000F46:  303c0200             move.w #$200, d0
00000F4A:  c06b0006             and.w $6(a3), d0
00000F4E:  1d40ffff             move.b d0, -$1(a6)
00000F52:  7e00                 moveq #$0, d7
00000F54:  7000                 moveq #$0, d0
00000F56:  2b40ff82             move.l d0, -$7e(a5)
00000F5A:  60000096             bra.w $ff2
00000F5E:  4a2effff             tst.b -$1(a6)
00000F62:  664c                 bne.b $fb0
00000F64:  4a2dfff6             tst.b -$a(a5)
00000F68:  6646                 bne.b $fb0
00000F6A:  4a2dfff8             tst.b -$8(a5)
00000F6E:  6728                 beq.b $f98
00000F70:  487af19a             pea.l $10c(pc)
00000F74:  2f2b0020             move.l $20(a3), -(a7)
00000F78:  2f2dfb56             move.l -$4aa(a5), -(a7)
00000F7C:  2f05                 move.l d5, -(a7)
00000F7E:  2f04                 move.l d4, -(a7)
00000F80:  4eba00a6             jsr $1028(pc)
00000F84:  3c00                 move.w d0, d6
00000F86:  0c460001             cmpi.w #$1, d6
00000F8A:  4fef0014             lea.l $14(a7), a7
00000F8E:  6646                 bne.b $fd6
00000F90:  48c6                 ext.l d6
00000F92:  2006                 move.l d6, d0
00000F94:  60000088             bra.w $101e
00000F98:  2f2b0020             move.l $20(a3), -(a7)
00000F9C:  2f2dfb56             move.l -$4aa(a5), -(a7)
00000FA0:  2f05                 move.l d5, -(a7)
00000FA2:  2f04                 move.l d4, -(a7)
00000FA4:  4eba02ec             jsr $1292(pc)
00000FA8:  3c00                 move.w d0, d6
00000FAA:  4fef0010             lea.l $10(a7), a7
00000FAE:  6026                 bra.b $fd6
00000FB0:  7000                 moveq #$0, d0
00000FB2:  2f00                 move.l d0, -(a7)
00000FB4:  2f2b0020             move.l $20(a3), -(a7)
00000FB8:  2f2dfb56             move.l -$4aa(a5), -(a7)
00000FBC:  2f05                 move.l d5, -(a7)
00000FBE:  2f04                 move.l d4, -(a7)
00000FC0:  4eba0282             jsr $1244(pc)
00000FC4:  3c00                 move.w d0, d6
00000FC6:  0c460001             cmpi.w #$1, d6
00000FCA:  4fef0014             lea.l $14(a7), a7
00000FCE:  6606                 bne.b $fd6
00000FD0:  48c6                 ext.l d6
00000FD2:  2006                 move.l d6, d0
00000FD4:  6048                 bra.b $101e
00000FD6:  4a46                 tst.w d6
00000FD8:  6608                 bne.b $fe2
00000FDA:  1d7c0001fffe         move.b #$1, -$2(a6)
00000FE0:  6018                 bra.b $ffa
00000FE2:  0c46fff8             cmpi.w #$fff8, d6
00000FE6:  6608                 bne.b $ff0
00000FE8:  4eba0cde             jsr $1cc8(pc)
00000FEC:  3c00                 move.w d0, d6
00000FEE:  660a                 bne.b $ffa
00000FF0:  5287                 addq.l #$1, d7
00000FF2:  7010                 moveq #$10, d0
00000FF4:  b087                 cmp.l d7, d0
00000FF6:  6e00ff66             bgt.w $f5e
00000FFA:  4a2efffe             tst.b -$2(a6)
00000FFE:  6712                 beq.b $1012
00001000:  206e0008             movea.l $8(a6), a0
00001004:  202b0024             move.l $24(a3), d0
00001008:  27400028             move.l d0, $28(a3)
0000100C:  d1a80010             add.l d0, $10(a0)
00001010:  6008                 bra.b $101a
00001012:  7cdc                 moveq #$dc, d6
00001014:  7000                 moveq #$0, d0
00001016:  27400028             move.l d0, $28(a3)
0000101A:  48c6                 ext.l d6
0000101C:  2006                 move.l d6, d0
0000101E:  4cee18f8ffe2         movem.l -$1e(a6), d3-d7/a3-a4
00001024:  4e5e                 unlk a6
00001026:  4e75                 rts
00001028:  4e560000             link.w a6, #$0
0000102C:  48e70f18             movem.l d4-d7/a3-a4, -(a7)
00001030:  2a2e0008             move.l $8(a6), d5
00001034:  266e0014             movea.l $14(a6), a3
00001038:  2c2e0010             move.l $10(a6), d6
0000103C:  2e2e000c             move.l $c(a6), d7
00001040:  286dff86             movea.l -$7a(a5), a4
00001044:  0c870000ffff         cmpi.l #$ffff, d7
0000104A:  632a                 bls.b $1076
0000104C:  2007                 move.l d7, d0
0000104E:  90bc0000ffff         sub.l #$ffff, d0
00001054:  2b40ff6a             move.l d0, -$96(a5)
00001058:  2e3c0000ffff         move.l #$ffff, d7
0000105E:  2807                 move.l d7, d4
00001060:  7009                 moveq #$9, d0
00001062:  2204                 move.l d4, d1
00001064:  e1a9                 lsl.l d0, d1
00001066:  d28b                 add.l a3, d1
00001068:  2b41ff62             move.l d1, -$9e(a5)
0000106C:  2006                 move.l d6, d0
0000106E:  d084                 add.l d4, d0
00001070:  2b40ff66             move.l d0, -$9a(a5)
00001074:  6044                 bra.b $10ba
00001076:  7000                 moveq #$0, d0
00001078:  2b40ff6a             move.l d0, -$96(a5)
0000107C:  4aadff6e             tst.l -$92(a5)
00001080:  6738                 beq.b $10ba
00001082:  4aae0018             tst.l $18(a6)
00001086:  6732                 beq.b $10ba
00001088:  4a85                 tst.l d5
0000108A:  662e                 bne.b $10ba
0000108C:  7009                 moveq #$9, d0
0000108E:  b087                 cmp.l d7, d0
00001090:  6428                 bcc.b $10ba
00001092:  7010                 moveq #$10, d0
00001094:  b087                 cmp.l d7, d0
00001096:  6322                 bls.b $10ba
00001098:  2007                 move.l d7, d0
0000109A:  7209                 moveq #$9, d1
0000109C:  9081                 sub.l d1, d0
0000109E:  2b40ff6a             move.l d0, -$96(a5)
000010A2:  7e09                 moveq #$9, d7
000010A4:  2807                 move.l d7, d4
000010A6:  7009                 moveq #$9, d0
000010A8:  2404                 move.l d4, d2
000010AA:  e1aa                 lsl.l d0, d2
000010AC:  d48b                 add.l a3, d2
000010AE:  2b42ff62             move.l d2, -$9e(a5)
000010B2:  2006                 move.l d6, d0
000010B4:  d084                 add.l d4, d0
000010B6:  2b40ff66             move.l d0, -$9a(a5)
000010BA:  29460046             move.l d6, $46(a4)
000010BE:  2007                 move.l d7, d0
000010C0:  e188                 lsl.l #$8, d0
000010C2:  2940004a             move.l d0, $4a(a4)
000010C6:  296dff760014         move.l -$8a(a5), $14(a4)
000010CC:  396dff74005e         move.w -$8c(a5), $5e(a4)
000010D2:  4a2dff72             tst.b -$8e(a5)
000010D6:  670c                 beq.b $10e4
000010D8:  00ac004000000014     ori.l #$400000, $14(a4)
000010E0:  422dff72             clr.b -$8e(a5)
000010E4:  4a85                 tst.l d5
000010E6:  670e                 beq.b $10f6
000010E8:  002c00800014         ori.b #$80, $14(a4)
000010EE:  197c002a0044         move.b #$2a, $44(a4)
000010F4:  600e                 bra.b $1104
000010F6:  00ac400000000014     ori.l #$40000000, $14(a4)
000010FE:  197c00280044         move.b #$28, $44(a4)
00001104:  294b0028             move.l a3, $28(a4)
00001108:  7009                 moveq #$9, d0
0000110A:  2207                 move.l d7, d1
0000110C:  e1a9                 lsl.l d0, d1
0000110E:  2941002c             move.l d1, $2c(a4)
00001112:  4aae0018             tst.l $18(a6)
00001116:  671a                 beq.b $1132
00001118:  296e00180010         move.l $18(a6), $10(a4)
0000111E:  204c                 movea.l a4, a0
00001120:  7001                 moveq #$1, d0
00001122:  ; ==== 16 bytes not reached as code ====
00001122:  a0 89 4a 40 67 06 2f 0c 4e ba ef e0 70 01 60 28 |..J@g./.N...p.`(|
00001132:  7000                 moveq #$0, d0
00001134:  29400010             move.l d0, $10(a4)
00001138:  204c                 movea.l a4, a0
0000113A:  7001                 moveq #$1, d0
0000113C:  ; ==== 40 bytes not reached as code ====
0000113C:  a0 89 70 00 10 2c 00 3c 0c 40 00 02 66 04 70 f8 |..p..,.<.@..f.p.|
0000114C:  60 0c 4a 6c 00 0a 67 04 70 fd 60 02 70 00 4c ee |`.Jl..g.p.`.p.L.|
0000115C:  18 f0 ff e8 4e 5e 4e 75                         |....N^Nu|
00001164:  4e560000             link.w a6, #$0
00001168:  202dff9a             move.l -$66(a5), d0
0000116C:  4e5e                 unlk a6
0000116E:  4e75                 rts
00001170:  4e56fffc             link.w a6, #$fffc
00001174:  48e70118             movem.l d7/a3-a4, -(a7)
00001178:  286e0008             movea.l $8(a6), a4
0000117C:  266dff9e             movea.l -$62(a5), a3
00001180:  2d6dff9afffc         move.l -$66(a5), -$4(a6)
00001186:  4a6c000a             tst.w $a(a4)
0000118A:  663c                 bne.b $11c8
0000118C:  4aadff6a             tst.l -$96(a5)
00001190:  6722                 beq.b $11b4
00001192:  487aef78             pea.l $10c(pc)
00001196:  2f2dff62             move.l -$9e(a5), -(a7)
0000119A:  2f2dff66             move.l -$9a(a5), -(a7)
0000119E:  2f2dff6a             move.l -$96(a5), -(a7)
000011A2:  7000                 moveq #$0, d0
000011A4:  2f00                 move.l d0, -(a7)
000011A6:  4ebafe80             jsr $1028(pc)
000011AA:  7001                 moveq #$1, d0
000011AC:  4fef0014             lea.l $14(a7), a7
000011B0:  60000088             bra.w $123a
000011B4:  206efffc             movea.l -$4(a6), a0
000011B8:  202b0024             move.l $24(a3), d0
000011BC:  27400028             move.l d0, $28(a3)
000011C0:  d1a80010             add.l d0, $10(a0)
000011C4:  7000                 moveq #$0, d0
000011C6:  6072                 bra.b $123a
000011C8:  202dff82             move.l -$7e(a5), d0
000011CC:  52adff82             addq.l #$1, -$7e(a5)
000011D0:  7210                 moveq #$10, d1
000011D2:  b280                 cmp.l d0, d1
000011D4:  6404                 bcc.b $11da
000011D6:  70dc                 moveq #$dc, d0
000011D8:  6060                 bra.b $123a
000011DA:  7000                 moveq #$0, d0
000011DC:  102c003c             move.b $3c(a4), d0
000011E0:  4a80                 tst.l d0
000011E2:  6620                 bne.b $1204
000011E4:  487aef26             pea.l $10c(pc)
000011E8:  2f2dfb5e             move.l -$4a2(a5), -(a7)
000011EC:  2f2dfb56             move.l -$4aa(a5), -(a7)
000011F0:  2f2dfb5a             move.l -$4a6(a5), -(a7)
000011F4:  2f2dfb52             move.l -$4ae(a5), -(a7)
000011F8:  4ebafe2e             jsr $1028(pc)
000011FC:  7001                 moveq #$1, d0
000011FE:  4fef0014             lea.l $14(a7), a7
00001202:  6036                 bra.b $123a
00001204:  7000                 moveq #$0, d0
00001206:  302c0024             move.w $24(a4), d0
0000120A:  7202                 moveq #$2, d1
0000120C:  c240                 and.w d0, d1
0000120E:  6728                 beq.b $1238
00001210:  4eba0ab6             jsr $1cc8(pc)
00001214:  3e00                 move.w d0, d7
00001216:  6620                 bne.b $1238
00001218:  487aeef2             pea.l $10c(pc)
0000121C:  2f2dfb5e             move.l -$4a2(a5), -(a7)
00001220:  2f2dfb56             move.l -$4aa(a5), -(a7)
00001224:  2f2dfb5a             move.l -$4a6(a5), -(a7)
00001228:  2f2dfb52             move.l -$4ae(a5), -(a7)
0000122C:  4ebafdfa             jsr $1028(pc)
00001230:  7001                 moveq #$1, d0
00001232:  4fef0014             lea.l $14(a7), a7
00001236:  6002                 bra.b $123a
00001238:  70dc                 moveq #$dc, d0
0000123A:  4cee1880fff0         movem.l -$10(a6), d7/a3-a4
00001240:  4e5e                 unlk a6
00001242:  4e75                 rts
00001244:  4e560000             link.w a6, #$0
00001248:  48e70708             movem.l d5-d7/a4, -(a7)
0000124C:  286e0014             movea.l $14(a6), a4
00001250:  2a2e0010             move.l $10(a6), d5
00001254:  2c2e000c             move.l $c(a6), d6
00001258:  2e2e0008             move.l $8(a6), d7
0000125C:  4a2dfff8             tst.b -$8(a5)
00001260:  6716                 beq.b $1278
00001262:  2f2e0018             move.l $18(a6), -(a7)
00001266:  2f0c                 move.l a4, -(a7)
00001268:  2f05                 move.l d5, -(a7)
0000126A:  2f06                 move.l d6, -(a7)
0000126C:  2f07                 move.l d7, -(a7)
0000126E:  4ebafdb8             jsr $1028(pc)
00001272:  4fef0014             lea.l $14(a7), a7
00001276:  6010                 bra.b $1288
00001278:  2f0c                 move.l a4, -(a7)
0000127A:  2f05                 move.l d5, -(a7)
0000127C:  2f06                 move.l d6, -(a7)
0000127E:  2f07                 move.l d7, -(a7)
00001280:  4eba0010             jsr $1292(pc)
00001284:  4fef0010             lea.l $10(a7), a7
00001288:  4cee10e0fff0         movem.l -$10(a6), d5-d7/a4
0000128E:  4e5e                 unlk a6
00001290:  4e75                 rts
00001292:  4e56fff6             link.w a6, #$fff6
00001296:  48e70f18             movem.l d4-d7/a3-a4, -(a7)
0000129A:  47edffaa             lea.l -$56(a5), a3
0000129E:  2a2e0010             move.l $10(a6), d5
000012A2:  2c2e000c             move.l $c(a6), d6
000012A6:  49eefff6             lea.l -$a(a6), a4
000012AA:  4a2dfffa             tst.b -$6(a5)
000012AE:  6712                 beq.b $12c2
000012B0:  422dfffa             clr.b -$6(a5)
000012B4:  7000                 moveq #$0, d0
000012B6:  102dfffc             move.b -$4(a5), d0
000012BA:  2f00                 move.l d0, -(a7)
000012BC:  4eba0678             jsr $1936(pc)
000012C0:  584f                 addq.w #$4, a7
000012C2:  700a                 moveq #$a, d0
000012C4:  2f00                 move.l d0, -(a7)
000012C6:  4aae0008             tst.l $8(a6)
000012CA:  6704                 beq.b $12d0
000012CC:  722a                 moveq #$2a, d1
000012CE:  6002                 bra.b $12d2
000012D0:  7228                 moveq #$28, d1
000012D2:  2f01                 move.l d1, -(a7)
000012D4:  2f0c                 move.l a4, -(a7)
000012D6:  4eba08e8             jsr $1bc0(pc)
000012DA:  276e00140002         move.l $14(a6), $2(a3)
000012E0:  4fef000c             lea.l $c(a7), a7
000012E4:  600000ec             bra.w $13d2
000012E8:  422c0001             clr.b $1(a4)
000012EC:  2005                 move.l d5, d0
000012EE:  4240                 clr.w d0
000012F0:  4840                 swap d0
000012F2:  e048                 lsr.w #$8, d0
000012F4:  19400002             move.b d0, $2(a4)
000012F8:  2005                 move.l d5, d0
000012FA:  4240                 clr.w d0
000012FC:  4840                 swap d0
000012FE:  19400003             move.b d0, $3(a4)
00001302:  2005                 move.l d5, d0
00001304:  e088                 lsr.l #$8, d0
00001306:  19400004             move.b d0, $4(a4)
0000130A:  19450005             move.b d5, $5(a4)
0000130E:  422c0006             clr.b $6(a4)
00001312:  422c0009             clr.b $9(a4)
00001316:  7000                 moveq #$0, d0
00001318:  102dfff0             move.b -$10(a5), d0
0000131C:  4a80                 tst.l d0
0000131E:  6604                 bne.b $1324
00001320:  7e01                 moveq #$1, d7
00001322:  6054                 bra.b $1378
00001324:  4a6dffe6             tst.w -$1a(a5)
00001328:  671c                 beq.b $1346
0000132A:  2e3c00007fff         move.l #$7fff, d7
00001330:  ce86                 and.l d6, d7
00001332:  302dffe6             move.w -$1a(a5), d0
00001336:  48c0                 ext.l d0
00001338:  d080                 add.l d0, d0
0000133A:  2200                 move.l d0, d1
0000133C:  e588                 lsl.l #$2, d0
0000133E:  d081                 add.l d1, d0
00001340:  27870006             move.l d7, $6(a3, d0.w)
00001344:  600c                 bra.b $1352
00001346:  2e06                 move.l d6, d7
00001348:  7009                 moveq #$9, d0
0000134A:  2206                 move.l d6, d1
0000134C:  e1a9                 lsl.l d0, d1
0000134E:  27410006             move.l d1, $6(a3)
00001352:  4aae0008             tst.l $8(a6)
00001356:  6620                 bne.b $1378
00001358:  7009                 moveq #$9, d0
0000135A:  b087                 cmp.l d7, d0
0000135C:  641a                 bcc.b $1378
0000135E:  7010                 moveq #$10, d0
00001360:  b087                 cmp.l d7, d0
00001362:  6314                 bls.b $1378
00001364:  7e09                 moveq #$9, d7
00001366:  302dffe6             move.w -$1a(a5), d0
0000136A:  48c0                 ext.l d0
0000136C:  d080                 add.l d0, d0
0000136E:  2200                 move.l d0, d1
00001370:  e588                 lsl.l #$2, d0
00001372:  d081                 add.l d1, d0
00001374:  27870006             move.l d7, $6(a3, d0.w)
00001378:  2007                 move.l d7, d0
0000137A:  e088                 lsr.l #$8, d0
0000137C:  19400007             move.b d0, $7(a4)
00001380:  19470008             move.b d7, $8(a4)
00001384:  48782a30             pea.l $2a30.w
00001388:  7000                 moveq #$0, d0
0000138A:  102dffec             move.b -$14(a5), d0
0000138E:  2f00                 move.l d0, -(a7)
00001390:  2f2e0008             move.l $8(a6), -(a7)
00001394:  2f0b                 move.l a3, -(a7)
00001396:  700a                 moveq #$a, d0
00001398:  2f00                 move.l d0, -(a7)
0000139A:  2f0c                 move.l a4, -(a7)
0000139C:  4eba069c             jsr $1a3a(pc)
000013A0:  3800                 move.w d0, d4
000013A2:  4fef0018             lea.l $18(a7), a7
000013A6:  6726                 beq.b $13ce
000013A8:  0c440002             cmpi.w #$2, d4
000013AC:  6706                 beq.b $13b4
000013AE:  48c4                 ext.l d4
000013B0:  2004                 move.l d4, d0
000013B2:  6026                 bra.b $13da
000013B4:  7010                 moveq #$10, d0
000013B6:  2f00                 move.l d0, -(a7)
000013B8:  486dff8a             pea.l -$76(a5)
000013BC:  4eba077a             jsr $1b38(pc)
000013C0:  4a80                 tst.l d0
000013C2:  504f                 addq.w #$8, a7
000013C4:  6704                 beq.b $13ca
000013C6:  70f9                 moveq #$f9, d0
000013C8:  6010                 bra.b $13da
000013CA:  70f8                 moveq #$f8, d0
000013CC:  600c                 bra.b $13da
000013CE:  9c87                 sub.l d7, d6
000013D0:  da87                 add.l d7, d5
000013D2:  4a86                 tst.l d6
000013D4:  6200ff12             bhi.w $12e8
000013D8:  7000                 moveq #$0, d0
000013DA:  4cee18f0ffde         movem.l -$22(a6), d4-d7/a3-a4
000013E0:  4e5e                 unlk a6
000013E2:  4e75                 rts
000013E4:  4e56ff28             link.w a6, #$ff28
000013E8:  48e70318             movem.l d6-d7/a3-a4, -(a7)
000013EC:  4246                 clr.w d6
000013EE:  206e000c             movea.l $c(a6), a0
000013F2:  7041                 moveq #$41, d0
000013F4:  b068001a             cmp.w $1a(a0), d0
000013F8:  66000160             bne.w $155a
000013FC:  4a2dfff8             tst.b -$8(a5)
00001400:  660000e0             bne.w $14e2
00001404:  598f                 subq.l #$4, a7
00001406:  3f3c0089             move.w #$89, -(a7)
0000140A:  7000                 moveq #$0, d0
0000140C:  1f00                 move.b d0, -(a7)
0000140E:  4eba0dbc             jsr $21cc(pc)
00001412:  598f                 subq.l #$4, a7
00001414:  3f3c009f             move.w #$9f, -(a7)
00001418:  7001                 moveq #$1, d0
0000141A:  1f00                 move.b d0, -(a7)
0000141C:  4eba0dae             jsr $21cc(pc)
00001420:  201f                 move.l (a7)+, d0
00001422:  b09f                 cmp.l (a7)+, d0
00001424:  670000bc             beq.w $14e2
00001428:  7028                 moveq #$28, d0
0000142A:  2f00                 move.l d0, -(a7)
0000142C:  486effd8             pea.l -$28(a6)
00001430:  4eba0b0e             jsr $1f40(pc)
00001434:  3d6dffa8fffc         move.w -$58(a5), -$4(a6)
0000143A:  1d7c0080ffe0         move.b #$80, -$20(a6)
00001440:  7000                 moveq #$0, d0
00001442:  2d40ffe8             move.l d0, -$18(a6)
00001446:  3d7c0028ffde         move.w #$28, -$22(a6)
0000144C:  41eeffd8             lea.l -$28(a6), a0
00001450:  7001                 moveq #$1, d0
00001452:  ; ==== 144 bytes not reached as code ====
00001452:  a0 89 4a 2e ff fe 50 4f 67 00 00 86 48 78 00 ac |..J...POg...Hx..|
00001462:  48 6e ff 2c 4e ba 0a d8 2b 6e ff e4 ff a2 2d 6d |Hn.,N...+n....-m|
00001472:  ff a2 ff 38 70 00 2d 40 ff 40 1d 7c 00 03 ff 34 |...8p.-@.@.|...4|
00001482:  2d 40 ff 3c 3d 7c 00 ac ff 32 41 ee ff 2c 70 01 |-@.<=|...2A..,p.|
00001492:  a0 89 4a 6e ff 36 50 4f 66 46 70 00 10 2e ff 60 |..Jn.6POfFp....`|
000014A2:  0c 40 00 2b 66 3a 70 00 30 2e ff 58 a7 1e 2b 48 |.@.+f:p.0..X..+H|
000014B2:  ff 86 20 08 67 2a 1b 7c 00 01 ff f8 20 2d ff a6 |.. .g*.|.... -..|
000014C2:  72 20 d0 81 46 80 2f 00 2f 2d ff a2 4e ba f0 24 |r ..F././-..N..$|
000014D2:  70 00 30 2e ff 58 2f 00 4e ba f1 b6 4f ef 00 0c |p.0..X/.N...O...|
000014E2:  4a2dfff8             tst.b -$8(a5)
000014E6:  6704                 beq.b $14ec
000014E8:  4ebaf264             jsr $74e(pc)
000014EC:  4247                 clr.w d7
000014EE:  2007                 move.l d7, d0
000014F0:  ed40                 asl.w #$6, d0
000014F2:  41edf652             lea.l -$9ae(a5), a0
000014F6:  49f00000             lea.l (a0, d0.w), a4
000014FA:  7000                 moveq #$0, d0
000014FC:  302c0016             move.w $16(a4), d0
00001500:  0c800000ffff         cmpi.l #$ffff, d0
00001506:  6714                 beq.b $151c
00001508:  4a6c0024             tst.w $24(a4)
0000150C:  670e                 beq.b $151c
0000150E:  307c0007             movea.w #$7, a0
00001512:  7000                 moveq #$0, d0
00001514:  302c0016             move.w $16(a4), d0
00001518:  4a80                 tst.l d0
0000151A:  ; ==== 2 bytes not reached as code ====
0000151A:  a0 2f                                           |./|
0000151C:  3007                 move.w d7, d0
0000151E:  5247                 addq.w #$1, d7
00001520:  0c470014             cmpi.w #$14, d7
00001524:  6dc8                 blt.b $14ee
00001526:  7000                 moveq #$0, d0
00001528:  102dfffc             move.b -$4(a5), d0
0000152C:  4a80                 tst.l d0
0000152E:  661c                 bne.b $154c
00001530:  203c00ffffff         move.l #$ffffff, d0
00001536:  c0b80c54             and.l $c54.w, d0
0000153A:  b0b802ae             cmp.l $2ae.w, d0
0000153E:  640c                 bcc.b $154c
00001540:  1b7c0001fffc         move.b #$1, -$4(a5)
00001546:  1b7c0001fffa         move.b #$1, -$6(a5)
0000154C:  206e0008             movea.l $8(a6), a0
00001550:  02684fff0004         andi.w #$4fff, $4(a0)
00001556:  6000022a             bra.w $1782
0000155A:  4247                 clr.w d7
0000155C:  2007                 move.l d7, d0
0000155E:  ed40                 asl.w #$6, d0
00001560:  41edf652             lea.l -$9ae(a5), a0
00001564:  49f00000             lea.l (a0, d0.w), a4
00001568:  7000                 moveq #$0, d0
0000156A:  302c0016             move.w $16(a4), d0
0000156E:  4a80                 tst.l d0
00001570:  206e000c             movea.l $c(a6), a0
00001574:  32280016             move.w $16(a0), d1
00001578:  48c1                 ext.l d1
0000157A:  b280                 cmp.l d0, d1
0000157C:  670a                 beq.b $1588
0000157E:  3007                 move.w d7, d0
00001580:  5247                 addq.w #$1, d7
00001582:  0c470014             cmpi.w #$14, d7
00001586:  6dd4                 blt.b $155c
00001588:  0c470014             cmpi.w #$14, d7
0000158C:  6606                 bne.b $1594
0000158E:  7cc8                 moveq #$c8, d6
00001590:  600001f0             bra.w $1782
00001594:  206e000c             movea.l $c(a6), a0
00001598:  3028001a             move.w $1a(a0), d0
0000159C:  5b40                 subq.w #$5, d0
0000159E:  670001e2             beq.w $1782
000015A2:  5340                 subq.w #$1, d0
000015A4:  670001dc             beq.w $1782
000015A8:  5340                 subq.w #$1, d0
000015AA:  670001c6             beq.w $1772
000015AE:  0440000a             subi.w #$a, d0
000015B2:  6708                 beq.b $15bc
000015B4:  5940                 subq.w #$4, d0
000015B6:  6728                 beq.b $15e0
000015B8:  600001c6             bra.w $1780
000015BC:  206e000c             movea.l $c(a6), a0
000015C0:  7000                 moveq #$0, d0
000015C2:  3028001c             move.w $1c(a0), d0
000015C6:  7201                 moveq #$1, d1
000015C8:  b280                 cmp.l d0, d1
000015CA:  660a                 bne.b $15d6
000015CC:  7000                 moveq #$0, d0
000015CE:  2940001c             move.l d0, $1c(a4)
000015D2:  600001ae             bra.w $1782
000015D6:  296c0018001c         move.l $18(a4), $1c(a4)
000015DC:  600001a4             bra.w $1782
000015E0:  0c6c01000010         cmpi.w #$100, $10(a4)
000015E6:  6608                 bne.b $15f0
000015E8:  4ebaeaae             jsr $98(pc)
000015EC:  2640                 movea.l d0, a3
000015EE:  6006                 bra.b $15f6
000015F0:  4ebaea9e             jsr $90(pc)
000015F4:  2640                 movea.l d0, a3
000015F6:  206e000c             movea.l $c(a6), a0
000015FA:  214b001c             move.l a3, $1c(a0)
000015FE:  200b                 move.l a3, d0
00001600:  d0bc00000100         add.l #$100, d0
00001606:  2d40ff28             move.l d0, -$d8(a6)
0000160A:  2040                 movea.l d0, a0
0000160C:  4210                 clr.b (a0)
0000160E:  4a2dfff8             tst.b -$8(a5)
00001612:  670000f8             beq.w $170c
00001616:  487800ac             pea.l $ac.w
0000161A:  486eff2c             pea.l -$d4(a6)
0000161E:  4eba0920             jsr $1f40(pc)
00001622:  2d6dffa2ff38         move.l -$5e(a5), -$c8(a6)
00001628:  7000                 moveq #$0, d0
0000162A:  2d40ff40             move.l d0, -$c0(a6)
0000162E:  1d7c0003ff34         move.b #$3, -$cc(a6)
00001634:  2d40ff3c             move.l d0, -$c4(a6)
00001638:  3d7c00acff32         move.w #$ac, -$ce(a6)
0000163E:  41eeff2c             lea.l -$d4(a6), a0
00001642:  7001                 moveq #$1, d0
00001644:  ; ==== 200 bytes not reached as code ====
00001644:  a0 89 70 00 10 2e ff 70 4a 80 50 4f 67 5c 70 00 |..p....pJ.POg\p.|
00001654:  10 2d ff a3 0c 00 00 0a 65 34 47 fa 01 62 70 00 |.-......e4G..bp.|
00001664:  10 2d ff a3 48 c0 81 fc 00 0a 48 c0 72 30 d0 81 |.-..H.....H.r0..|
00001674:  17 40 00 04 70 00 10 2d ff a3 48 c0 81 fc 00 0a |.@..p..-..H.....|
00001684:  48 40 48 80 d0 7c 00 30 17 40 00 05 60 10 47 fa |H@H..|.0.@..`.G.|
00001694:  01 26 10 2d ff a3 72 30 d0 01 17 40 00 04 2f 0b |.&.-..r0...@../.|
000016A4:  2f 2e ff 28 4e ba ea 94 50 4f 47 fa 00 fe 70 00 |/..(N...POG...p.|
000016B4:  10 2d ff a4 0c 00 00 0a 65 30 70 00 10 2d ff a4 |.-......e0p..-..|
000016C4:  48 c0 81 fc 00 0a 48 c0 72 30 d0 81 17 40 00 08 |H.....H.r0...@..|
000016D4:  70 00 10 2d ff a4 48 c0 81 fc 00 0a 48 40 48 80 |p..-..H.....H@H.|
000016E4:  d0 7c 00 30 17 40 00 09 60 10 10 2d ff a4 72 30 |.|.0.@..`..-..r0|
000016F4:  d0 01 17 40 00 08 42 2b 00 09 2f 0b 2f 2e ff 28 |...@..B+.././..(|
00001704:  4e ba ea 38 50 4f 60 1c                         |N..8PO`.|
0000170C:  47fa0096             lea.l $17a4(pc), a3
00001710:  102dffa9             move.b -$57(a5), d0
00001714:  7230                 moveq #$30, d1
00001716:  d001                 add.b d1, d0
00001718:  17400008             move.b d0, $8(a3)
0000171C:  2f0b                 move.l a3, -(a7)
0000171E:  2f2eff28             move.l -$d8(a6), -(a7)
00001722:  4ebaea1a             jsr $13e(pc)
00001726:  504f                 addq.w #$8, a7
00001728:  487a0076             pea.l $17a0(pc)
0000172C:  2f2eff28             move.l -$d8(a6), -(a7)
00001730:  4ebaea0c             jsr $13e(pc)
00001734:  487a0064             pea.l $179a(pc)
00001738:  2f2eff28             move.l -$d8(a6), -(a7)
0000173C:  4ebaea00             jsr $13e(pc)
00001740:  4a2dfff8             tst.b -$8(a5)
00001744:  4fef0010             lea.l $10(a7), a7
00001748:  670e                 beq.b $1758
0000174A:  487a0046             pea.l $1792(pc)
0000174E:  2f2eff28             move.l -$d8(a6), -(a7)
00001752:  4ebae9ea             jsr $13e(pc)
00001756:  504f                 addq.w #$8, a7
00001758:  487a0036             pea.l $1790(pc)
0000175C:  2f2eff28             move.l -$d8(a6), -(a7)
00001760:  4ebae9dc             jsr $13e(pc)
00001764:  2f2eff28             move.l -$d8(a6), -(a7)
00001768:  4eba0a34             jsr $219e(pc)
0000176C:  4fef000c             lea.l $c(a7), a7
00001770:  6010                 bra.b $1782
00001772:  307c0007             movea.w #$7, a0
00001776:  7000                 moveq #$0, d0
00001778:  302c0016             move.w $16(a4), d0
0000177C:  4a80                 tst.l d0
0000177E:  ; ==== 2 bytes not reached as code ====
0000177E:  a0 2f                                           |./|
00001780:  7cef                 moveq #$ef, d6
00001782:  48c6                 ext.l d6
00001784:  2006                 move.l d6, d0
00001786:  4cee18c0ff18         movem.l -$e8(a6), d6-d7/a3-a4
0000178C:  4e5e                 unlk a6
0000178E:  4e75                 rts
00001790:  2900                 move.l d0, -(a4)
00001792:  2c20                 move.l -(a0), d6
00001794:  6173                 bsr.b $1809
00001796:  ; ==== 54 bytes not reached as code ====
00001796:  79 6e 63 00 37 2e 33 2e 35 00 20 28 76 00 53 43 |ync.7.3.5. (v.SC|
000017A6:  53 49 20 49 44 20 3f 00 53 43 53 49 20 49 44 20 |SI ID ?.SCSI ID |
000017B6:  3f 3f 00 00 42 75 73 20 3f 2c 20 00 42 75 73 20 |??..Bus ?, .Bus |
000017C6:  3f 3f 2c 20 00 00                               |??, ..|
000017CC:  4e560000             link.w a6, #$0
000017D0:  2f07                 move.l d7, -(a7)
000017D2:  1e2e000b             move.b $b(a6), d7
000017D6:  7000                 moveq #$0, d0
000017D8:  1007                 move.b d7, d0
000017DA:  48c0                 ext.l d0
000017DC:  81fc000a             divs.w #$a, d0
000017E0:  48c0                 ext.l d0
000017E2:  e988                 lsl.l #$4, d0
000017E4:  7200                 moveq #$0, d1
000017E6:  1207                 move.b d7, d1
000017E8:  48c1                 ext.l d1
000017EA:  83fc000a             divs.w #$a, d1
000017EE:  4841                 swap d1
000017F0:  4881                 ext.w d1
000017F2:  48c1                 ext.l d1
000017F4:  8280                 or.l d0, d1
000017F6:  1001                 move.b d1, d0
000017F8:  2e2efffc             move.l -$4(a6), d7
000017FC:  4e5e                 unlk a6
000017FE:  4e75                 rts
00001800:  4e56fffc             link.w a6, #$fffc
00001804:  48e71318             movem.l d3/d6-d7/a3-a4, -(a7)
00001808:  266e000c             movea.l $c(a6), a3
0000180C:  4246                 clr.w d6
0000180E:  4247                 clr.w d7
00001810:  7614                 moveq #$14, d3
00001812:  2007                 move.l d7, d0
00001814:  ed40                 asl.w #$6, d0
00001816:  41edf652             lea.l -$9ae(a5), a0
0000181A:  49f00000             lea.l (a0, d0.w), a4
0000181E:  7000                 moveq #$0, d0
00001820:  302c0016             move.w $16(a4), d0
00001824:  322b0016             move.w $16(a3), d1
00001828:  48c1                 ext.l d1
0000182A:  b280                 cmp.l d0, d1
0000182C:  6708                 beq.b $1836
0000182E:  3007                 move.w d7, d0
00001830:  5247                 addq.w #$1, d7
00001832:  b647                 cmp.w d7, d3
00001834:  6edc                 bgt.b $1812
00001836:  0c470014             cmpi.w #$14, d7
0000183A:  6606                 bne.b $1842
0000183C:  7cc8                 moveq #$c8, d6
0000183E:  600000e8             bra.w $1928
00001842:  302b001a             move.w $1a(a3), d0
00001846:  5140                 subq.w #$8, d0
00001848:  670a                 beq.b $1854
0000184A:  04400023             subi.w #$23, d0
0000184E:  671a                 beq.b $186a
00001850:  600000d4             bra.w $1926
00001854:  7016                 moveq #$16, d0
00001856:  2f00                 move.l d0, -(a7)
00001858:  2f0c                 move.l a4, -(a7)
0000185A:  486b001c             pea.l $1c(a3)
0000185E:  4eba0336             jsr $1b96(pc)
00001862:  4fef000c             lea.l $c(a7), a7
00001866:  600000c0             bra.w $1928
0000186A:  202b001c             move.l $1c(a3), d0
0000186E:  0480626f6f74         subi.l #$626f6f74, d0
00001874:  672a                 beq.b $18a0
00001876:  04801109feef         subi.l #$1109feef, d0
0000187C:  670c                 beq.b $188a
0000187E:  048002ec0410         subi.l #$2ec0410, d0
00001884:  6740                 beq.b $18c6
00001886:  60000094             bra.w $191c
0000188A:  4a2dfff8             tst.b -$8(a5)
0000188E:  6708                 beq.b $1898
00001890:  422efffc             clr.b -$4(a6)
00001894:  60000088             bra.w $191e
00001898:  1d7c0001fffc         move.b #$1, -$4(a6)
0000189E:  607e                 bra.b $191e
000018A0:  4a2dfff8             tst.b -$8(a5)
000018A4:  671c                 beq.b $18c2
000018A6:  206e0008             movea.l $8(a6), a0
000018AA:  1d680032fffc         move.b $32(a0), -$4(a6)
000018B0:  1d47fffd             move.b d7, -$3(a6)
000018B4:  1d680028fffe         move.b $28(a0), -$2(a6)
000018BA:  1d680029ffff         move.b $29(a0), -$1(a6)
000018C0:  605c                 bra.b $191e
000018C2:  7cee                 moveq #$ee, d6
000018C4:  6058                 bra.b $191e
000018C6:  7007                 moveq #$7, d0
000018C8:  2f00                 move.l d0, -(a7)
000018CA:  4ebaff00             jsr $17cc(pc)
000018CE:  1d40fffc             move.b d0, -$4(a6)
000018D2:  7003                 moveq #$3, d0
000018D4:  2f00                 move.l d0, -(a7)
000018D6:  4ebafef4             jsr $17cc(pc)
000018DA:  7200                 moveq #$0, d1
000018DC:  1200                 move.b d0, d1
000018DE:  022e000ffffd         andi.b #$f, -$3(a6)
000018E4:  e909                 lsl.b #$4, d1
000018E6:  832efffd             or.b d1, -$3(a6)
000018EA:  7005                 moveq #$5, d0
000018EC:  2f00                 move.l d0, -(a7)
000018EE:  4ebafedc             jsr $17cc(pc)
000018F2:  7200                 moveq #$0, d1
000018F4:  1200                 move.b d0, d1
000018F6:  022e00f0fffd         andi.b #$f0, -$3(a6)
000018FC:  0201000f             andi.b #$f, d1
00001900:  832efffd             or.b d1, -$3(a6)
00001904:  1d7c0080fffe         move.b #$80, -$2(a6)
0000190A:  7000                 moveq #$0, d0
0000190C:  2f00                 move.l d0, -(a7)
0000190E:  4ebafebc             jsr $17cc(pc)
00001912:  1d40ffff             move.b d0, -$1(a6)
00001916:  4fef0010             lea.l $10(a7), a7
0000191A:  6002                 bra.b $191e
0000191C:  7cee                 moveq #$ee, d6
0000191E:  276efffc0020         move.l -$4(a6), $20(a3)
00001924:  6002                 bra.b $1928
00001926:  7cee                 moveq #$ee, d6
00001928:  48c6                 ext.l d6
0000192A:  2006                 move.l d6, d0
0000192C:  4cee18c8ffe8         movem.l -$18(a6), d3/d6-d7/a3-a4
00001932:  4e5e                 unlk a6
00001934:  4e75                 rts
00001936:  4e560000             link.w a6, #$0
0000193A:  48e70108             movem.l d7/a4, -(a7)
0000193E:  2e2e0008             move.l $8(a6), d7
00001942:  49edffaa             lea.l -$56(a5), a4
00001946:  7001                 moveq #$1, d0
00001948:  b087                 cmp.l d7, d0
0000194A:  661a                 bne.b $1966
0000194C:  7000                 moveq #$0, d0
0000194E:  102dffea             move.b -$16(a5), d0
00001952:  122dfffe             move.b -$2(a5), d1
00001956:  7401                 moveq #$1, d2
00001958:  e3aa                 lsl.l d1, d2
0000195A:  c480                 and.l d0, d2
0000195C:  6708                 beq.b $1966
0000195E:  1b7c0001ffec         move.b #$1, -$14(a5)
00001964:  6004                 bra.b $196a
00001966:  422dffec             clr.b -$14(a5)
0000196A:  38bc0001             move.w #$1, (a4)
0000196E:  4a87                 tst.l d7
00001970:  670a                 beq.b $197c
00001972:  7000                 moveq #$0, d0
00001974:  102dffee             move.b -$12(a5), d0
00001978:  4a80                 tst.l d0
0000197A:  6616                 bne.b $1992
0000197C:  422dfff0             clr.b -$10(a5)
00001980:  297c000002000006     move.l #$200, $6(a4)
00001988:  397c0007000a         move.w #$7, $a(a4)
0000198E:  600000a0             bra.w $1a30
00001992:  1b6dffeefff0         move.b -$12(a5), -$10(a5)
00001998:  102dfff0             move.b -$10(a5), d0
0000199C:  5300                 subq.b #$1, d0
0000199E:  6708                 beq.b $19a8
000019A0:  5300                 subq.b #$1, d0
000019A2:  6726                 beq.b $19ca
000019A4:  6000008a             bra.w $1a30
000019A8:  297c000002000006     move.l #$200, $6(a4)
000019B0:  397c0005000a         move.w #$5, $a(a4)
000019B6:  70f6                 moveq #$f6, d0
000019B8:  2940000c             move.l d0, $c(a4)
000019BC:  397c00070014         move.w #$7, $14(a4)
000019C2:  3b7c0001ffe6         move.w #$1, -$1a(a5)
000019C8:  6066                 bra.b $1a30
000019CA:  7000                 moveq #$0, d0
000019CC:  302dffe8             move.w -$18(a5), d0
000019D0:  29400006             move.l d0, $6(a4)
000019D4:  397c0004000a         move.w #$4, $a(a4)
000019DA:  204c                 movea.l a4, a0
000019DC:  5488                 addq.l #$2, a0
000019DE:  2948000c             move.l a0, $c(a4)
000019E2:  41ec0016             lea.l $16(a4), a0
000019E6:  29480010             move.l a0, $10(a4)
000019EA:  397c00010014         move.w #$1, $14(a4)
000019F0:  7000                 moveq #$0, d0
000019F2:  302dffe8             move.w -$18(a5), d0
000019F6:  223c00000200         move.l #$200, d1
000019FC:  9280                 sub.l d0, d1
000019FE:  2941001a             move.l d1, $1a(a4)
00001A02:  397c0004001e         move.w #$4, $1e(a4)
00001A08:  41ec0016             lea.l $16(a4), a0
00001A0C:  29480020             move.l a0, $20(a4)
00001A10:  204c                 movea.l a4, a0
00001A12:  5488                 addq.l #$2, a0
00001A14:  29480024             move.l a0, $24(a4)
00001A18:  397c00050028         move.w #$5, $28(a4)
00001A1E:  70d8                 moveq #$d8, d0
00001A20:  2940002a             move.l d0, $2a(a4)
00001A24:  397c00070032         move.w #$7, $32(a4)
00001A2A:  3b7c0004ffe6         move.w #$4, -$1a(a5)
00001A30:  4cee1080fff8         movem.l -$8(a6), d7/a4
00001A36:  4e5e                 unlk a6
00001A38:  4e75                 rts
00001A3A:  4e56fffc             link.w a6, #$fffc
00001A3E:  48e70708             movem.l d5-d7/a4, -(a7)
00001A42:  3a2e0016             move.w $16(a6), d5
00001A46:  286e0010             movea.l $10(a6), a4
00001A4A:  4246                 clr.w d6
00001A4C:  4247                 clr.w d7
00001A4E:  558f                 subq.l #$2, a7
00001A50:  3f3c0001             move.w #$1, -(a7)
00001A54:  ; ==== 228 bytes not reached as code ====
00001A54:  a8 15 4a 5f 67 1a 30 07 52 47 0c 47 00 03 6f ea |..J_g.0.RG.G..o.|
00001A64:  55 8f 3f 3c 00 0a a8 15 70 40 c0 5f 66 f2 60 d8 |U.?<....p@._f.`.|
00001A74:  55 8f 3f 2d ff a8 3f 3c 00 02 a8 15 4a 5f 67 06 |U.?-..?<....J_g.|
00001A84:  70 fe 60 00 00 a6 42 47 55 8f 2f 2e 00 08 3f 2e |p.`...BGU./...?.|
00001A94:  00 0e 3f 3c 00 03 a8 15 4a 5f 67 0e 30 07 52 47 |..?<....J_g.0.RG|
00001AA4:  0c 47 00 03 6f e2 7c fd 60 4c 20 0c 67 48 4a 6e |.G..o.|.`L .gHJn|
00001AB4:  00 1a 67 22 4a 45 67 0e 55 8f 2f 0c 3f 3c 00 09 |..g"JEg.U./.?<..|
00001AC4:  a8 15 30 1f 60 0c 55 8f 2f 0c 3f 3c 00 08 a8 15 |..0.`.U./.?<....|
00001AD4:  30 1f 3c 00 60 20 4a 45 67 0e 55 8f 2f 0c 3f 3c |0.<.` JEg.U./.?<|
00001AE4:  00 06 a8 15 30 1f 60 0c 55 8f 2f 0c 3f 3c 00 05 |....0.`.U./.?<..|
00001AF4:  a8 15 30 1f 3c 00 55 8f 48 6e ff fc 48 6e ff fe |..0.<.U.Hn..Hn..|
00001B04:  2f 2e 00 1c 3f 3c 00 04 a8 15 4a 5f 67 04 70 fc |/...?<....J_g.p.|
00001B14:  60 18 4a 46 67 0e 70 02 b0 6e ff fc 67 06 48 c6 |`.JFg.p..n..g.H.|
00001B24:  20 06 60 06 30 2e ff fc 48 c0 4c ee 10 e0 ff ec | .`.0...H.L.....|
00001B34:  4e 5e 4e 75                                     |N^Nu|
00001B38:  4e56ffe6             link.w a6, #$ffe6
00001B3C:  48e70118             movem.l d7/a3-a4, -(a7)
00001B40:  3e2e000e             move.w $e(a6), d7
00001B44:  47eefffa             lea.l -$6(a6), a3
00001B48:  49eeffe6             lea.l -$1a(a6), a4
00001B4C:  7006                 moveq #$6, d0
00001B4E:  2f00                 move.l d0, -(a7)
00001B50:  7203                 moveq #$3, d1
00001B52:  2f01                 move.l d1, -(a7)
00001B54:  2f0b                 move.l a3, -(a7)
00001B56:  4eba0068             jsr $1bc0(pc)
00001B5A:  17470004             move.b d7, $4(a3)
00001B5E:  38bc0002             move.w #$2, (a4)
00001B62:  296e00080002         move.l $8(a6), $2(a4)
00001B68:  7000                 moveq #$0, d0
00001B6A:  3007                 move.w d7, d0
00001B6C:  29400006             move.l d0, $6(a4)
00001B70:  397c0007000a         move.w #$7, $a(a4)
00001B76:  48780258             pea.l $258.w
00001B7A:  7000                 moveq #$0, d0
00001B7C:  2f00                 move.l d0, -(a7)
00001B7E:  2f00                 move.l d0, -(a7)
00001B80:  2f0c                 move.l a4, -(a7)
00001B82:  7206                 moveq #$6, d1
00001B84:  2f01                 move.l d1, -(a7)
00001B86:  2f0b                 move.l a3, -(a7)
00001B88:  4ebafeb0             jsr $1a3a(pc)
00001B8C:  4cee1880ffda         movem.l -$26(a6), d7/a3-a4
00001B92:  4e5e                 unlk a6
00001B94:  4e75                 rts
00001B96:  4e560000             link.w a6, #$0
00001B9A:  48e70118             movem.l d7/a3-a4, -(a7)
00001B9E:  266e000c             movea.l $c(a6), a3
00001BA2:  286e0008             movea.l $8(a6), a4
00001BA6:  2e2e0010             move.l $10(a6), d7
00001BAA:  6006                 bra.b $1bb2
00001BAC:  18db                 move.b (a3)+, (a4)+
00001BAE:  2007                 move.l d7, d0
00001BB0:  5387                 subq.l #$1, d7
00001BB2:  4a87                 tst.l d7
00001BB4:  66f6                 bne.b $1bac
00001BB6:  4cee1880fff4         movem.l -$c(a6), d7/a3-a4
00001BBC:  4e5e                 unlk a6
00001BBE:  4e75                 rts
00001BC0:  4e560000             link.w a6, #$0
00001BC4:  48e71308             movem.l d3/d6-d7/a4, -(a7)
00001BC8:  3c2e0012             move.w $12(a6), d6
00001BCC:  286e0008             movea.l $8(a6), a4
00001BD0:  48c6                 ext.l d6
00001BD2:  2e06                 move.l d6, d7
00001BD4:  5387                 subq.l #$1, d7
00001BD6:  7600                 moveq #$0, d3
00001BD8:  6008                 bra.b $1be2
00001BDA:  42347800             clr.b (a4, d7.l)
00001BDE:  2007                 move.l d7, d0
00001BE0:  5387                 subq.l #$1, d7
00001BE2:  b687                 cmp.l d7, d3
00001BE4:  6ff4                 ble.b $1bda
00001BE6:  18ae000f             move.b $f(a6), (a4)
00001BEA:  4cee10c8fff0         movem.l -$10(a6), d3/d6-d7/a4
00001BF0:  4e5e                 unlk a6
00001BF2:  4e75                 rts
00001BF4:  4e56fffe             link.w a6, #$fffe
00001BF8:  48e70f18             movem.l d4-d7/a3-a4, -(a7)
00001BFC:  47edfb62             lea.l -$49e(a5), a3
00001C00:  49edfd62             lea.l -$29e(a5), a4
00001C04:  4245                 clr.w d5
00001C06:  426efffe             clr.w -$2(a6)
00001C0A:  7c00                 moveq #$0, d6
00001C0C:  60000096             bra.w $1ca4
00001C10:  7000                 moveq #$0, d0
00001C12:  2f00                 move.l d0, -(a7)
00001C14:  2f0c                 move.l a4, -(a7)
00001C16:  2f2e0008             move.l $8(a6), -(a7)
00001C1A:  7201                 moveq #$1, d1
00001C1C:  2f01                 move.l d1, -(a7)
00001C1E:  2f00                 move.l d0, -(a7)
00001C20:  4ebaf622             jsr $1244(pc)
00001C24:  3e00                 move.w d0, d7
00001C26:  7000                 moveq #$0, d0
00001C28:  102dff8c             move.b -$74(a5), d0
00001C2C:  720f                 moveq #$f, d1
00001C2E:  c200                 and.b d0, d1
00001C30:  7800                 moveq #$0, d4
00001C32:  1801                 move.b d1, d4
00001C34:  0c47fff8             cmpi.w #$fff8, d7
00001C38:  4fef0014             lea.l $14(a7), a7
00001C3C:  6644                 bne.b $1c82
00001C3E:  7000                 moveq #$0, d0
00001C40:  102dff8a             move.b -$76(a5), d0
00001C44:  323c0080             move.w #$80, d1
00001C48:  c200                 and.b d0, d1
00001C4A:  6736                 beq.b $1c82
00001C4C:  2004                 move.l d4, d0
00001C4E:  5380                 subq.l #$1, d0
00001C50:  670e                 beq.b $1c60
00001C52:  5580                 subq.l #$2, d0
00001C54:  671e                 beq.b $1c74
00001C56:  5380                 subq.l #$1, d0
00001C58:  671a                 beq.b $1c74
00001C5A:  5580                 subq.l #$2, d0
00001C5C:  6742                 beq.b $1ca0
00001C5E:  601e                 bra.b $1c7e
00001C60:  48780200             pea.l $200.w
00001C64:  2f0c                 move.l a4, -(a7)
00001C66:  2f0b                 move.l a3, -(a7)
00001C68:  4ebaff2c             jsr $1b96(pc)
00001C6C:  3005                 move.w d5, d0
00001C6E:  5245                 addq.w #$1, d5
00001C70:  4fef000c             lea.l $c(a7), a7
00001C74:  302efffe             move.w -$2(a6), d0
00001C78:  526efffe             addq.w #$1, -$2(a6)
00001C7C:  6022                 bra.b $1ca0
00001C7E:  7002                 moveq #$2, d0
00001C80:  603c                 bra.b $1cbe
00001C82:  4a47                 tst.w d7
00001C84:  6616                 bne.b $1c9c
00001C86:  48780200             pea.l $200.w
00001C8A:  2f0c                 move.l a4, -(a7)
00001C8C:  2f0b                 move.l a3, -(a7)
00001C8E:  4ebaff06             jsr $1b96(pc)
00001C92:  3005                 move.w d5, d0
00001C94:  5245                 addq.w #$1, d5
00001C96:  4fef000c             lea.l $c(a7), a7
00001C9A:  6004                 bra.b $1ca0
00001C9C:  7002                 moveq #$2, d0
00001C9E:  601e                 bra.b $1cbe
00001CA0:  2006                 move.l d6, d0
00001CA2:  5286                 addq.l #$1, d6
00001CA4:  bcae000c             cmp.l $c(a6), d6
00001CA8:  6d00ff66             blt.w $1c10
00001CAC:  4a45                 tst.w d5
00001CAE:  670c                 beq.b $1cbc
00001CB0:  7000                 moveq #$0, d0
00001CB2:  4a6efffe             tst.w -$2(a6)
00001CB6:  56c0                 sne.b d0
00001CB8:  4400                 neg.b d0
00001CBA:  6002                 bra.b $1cbe
00001CBC:  7002                 moveq #$2, d0
00001CBE:  4cee18f0ffe6         movem.l -$1a(a6), d4-d7/a3-a4
00001CC4:  4e5e                 unlk a6
00001CC6:  4e75                 rts
00001CC8:  4e56fffc             link.w a6, #$fffc
00001CCC:  48e71318             movem.l d3/d6-d7/a3-a4, -(a7)
00001CD0:  47edff8a             lea.l -$76(a5), a3
00001CD4:  49edfb62             lea.l -$49e(a5), a4
00001CD8:  7000                 moveq #$0, d0
00001CDA:  1013                 move.b (a3), d0
00001CDC:  323c0080             move.w #$80, d1
00001CE0:  c200                 and.b d0, d1
00001CE2:  67000108             beq.w $1dec
00001CE6:  7000                 moveq #$0, d0
00001CE8:  102b0002             move.b $2(a3), d0
00001CEC:  720f                 moveq #$f, d1
00001CEE:  c200                 and.b d0, d1
00001CF0:  7c00                 moveq #$0, d6
00001CF2:  1c01                 move.b d1, d6
00001CF4:  2006                 move.l d6, d0
00001CF6:  5380                 subq.l #$1, d0
00001CF8:  6712                 beq.b $1d0c
00001CFA:  5580                 subq.l #$2, d0
00001CFC:  670e                 beq.b $1d0c
00001CFE:  5380                 subq.l #$1, d0
00001D00:  670a                 beq.b $1d0c
00001D02:  5580                 subq.l #$2, d0
00001D04:  670000e2             beq.w $1de8
00001D08:  600000de             bra.w $1de8
00001D0C:  7004                 moveq #$4, d0
00001D0E:  2f00                 move.l d0, -(a7)
00001D10:  486b0003             pea.l $3(a3)
00001D14:  486efffc             pea.l -$4(a6)
00001D18:  4ebafe7c             jsr $1b96(pc)
00001D1C:  202efffc             move.l -$4(a6), d0
00001D20:  b0adfb56             cmp.l -$4aa(a5), d0
00001D24:  4fef000c             lea.l $c(a7), a7
00001D28:  650e                 bcs.b $1d38
00001D2A:  202dfb5a             move.l -$4a6(a5), d0
00001D2E:  d0adfb56             add.l -$4aa(a5), d0
00001D32:  b0aefffc             cmp.l -$4(a6), d0
00001D36:  6406                 bcc.b $1d3e
00001D38:  7000                 moveq #$0, d0
00001D3A:  600000b2             bra.w $1dee
00001D3E:  7005                 moveq #$5, d0
00001D40:  2f00                 move.l d0, -(a7)
00001D42:  2f2efffc             move.l -$4(a6), -(a7)
00001D46:  4ebafeac             jsr $1bf4(pc)
00001D4A:  3c00                 move.w d0, d6
00001D4C:  0c460002             cmpi.w #$2, d6
00001D50:  504f                 addq.w #$8, a7
00001D52:  6606                 bne.b $1d5a
00001D54:  7000                 moveq #$0, d0
00001D56:  60000096             bra.w $1dee
00001D5A:  7000                 moveq #$0, d0
00001D5C:  2f00                 move.l d0, -(a7)
00001D5E:  2f0c                 move.l a4, -(a7)
00001D60:  2f2efffc             move.l -$4(a6), -(a7)
00001D64:  7201                 moveq #$1, d1
00001D66:  2f01                 move.l d1, -(a7)
00001D68:  2f01                 move.l d1, -(a7)
00001D6A:  4ebaf4d8             jsr $1244(pc)
00001D6E:  4a80                 tst.l d0
00001D70:  4fef0014             lea.l $14(a7), a7
00001D74:  6616                 bne.b $1d8c
00001D76:  7001                 moveq #$1, d0
00001D78:  2f00                 move.l d0, -(a7)
00001D7A:  2f2efffc             move.l -$4(a6), -(a7)
00001D7E:  4ebafe74             jsr $1bf4(pc)
00001D82:  4a80                 tst.l d0
00001D84:  504f                 addq.w #$8, a7
00001D86:  6604                 bne.b $1d8c
00001D88:  7000                 moveq #$0, d0
00001D8A:  6062                 bra.b $1dee
00001D8C:  7c00                 moveq #$0, d6
00001D8E:  2f2efffc             move.l -$4(a6), -(a7)
00001D92:  4eba0064             jsr $1df8(pc)
00001D96:  4a80                 tst.l d0
00001D98:  584f                 addq.w #$4, a7
00001D9A:  663e                 bne.b $1dda
00001D9C:  7e00                 moveq #$0, d7
00001D9E:  7000                 moveq #$0, d0
00001DA0:  2f00                 move.l d0, -(a7)
00001DA2:  2f0c                 move.l a4, -(a7)
00001DA4:  2f2efffc             move.l -$4(a6), -(a7)
00001DA8:  7201                 moveq #$1, d1
00001DAA:  2f01                 move.l d1, -(a7)
00001DAC:  2f01                 move.l d1, -(a7)
00001DAE:  4ebaf494             jsr $1244(pc)
00001DB2:  4a80                 tst.l d0
00001DB4:  4fef0014             lea.l $14(a7), a7
00001DB8:  6616                 bne.b $1dd0
00001DBA:  7001                 moveq #$1, d0
00001DBC:  2f00                 move.l d0, -(a7)
00001DBE:  2f2efffc             move.l -$4(a6), -(a7)
00001DC2:  4ebafe30             jsr $1bf4(pc)
00001DC6:  4a80                 tst.l d0
00001DC8:  504f                 addq.w #$8, a7
00001DCA:  6604                 bne.b $1dd0
00001DCC:  7000                 moveq #$0, d0
00001DCE:  601e                 bra.b $1dee
00001DD0:  2007                 move.l d7, d0
00001DD2:  5287                 addq.l #$1, d7
00001DD4:  7003                 moveq #$3, d0
00001DD6:  b087                 cmp.l d7, d0
00001DD8:  6ec4                 bgt.b $1d9e
00001DDA:  2006                 move.l d6, d0
00001DDC:  5286                 addq.l #$1, d6
00001DDE:  7002                 moveq #$2, d0
00001DE0:  b086                 cmp.l d6, d0
00001DE2:  6eaa                 bgt.b $1d8e
00001DE4:  70dc                 moveq #$dc, d0
00001DE6:  6006                 bra.b $1dee
00001DE8:  7000                 moveq #$0, d0
00001DEA:  6002                 bra.b $1dee
00001DEC:  7000                 moveq #$0, d0
00001DEE:  4cee18c8ffe8         movem.l -$18(a6), d3/d6-d7/a3-a4
00001DF4:  4e5e                 unlk a6
00001DF6:  4e75                 rts
00001DF8:  4e56fff8             link.w a6, #$fff8
00001DFC:  48e70318             movem.l d6-d7/a3-a4, -(a7)
00001E00:  2e2e0008             move.l $8(a6), d7
00001E04:  47eefff8             lea.l -$8(a6), a3
00001E08:  4a2dfff8             tst.b -$8(a5)
00001E0C:  660c                 bne.b $1e1a
00001E0E:  2f07                 move.l d7, -(a7)
00001E10:  4eba00bc             jsr $1ece(pc)
00001E14:  584f                 addq.w #$4, a7
00001E16:  600000ac             bra.w $1ec4
00001E1A:  206dff86             movea.l -$7a(a5), a0
00001E1E:  49e80044             lea.l $44(a0), a4
00001E22:  18bc0007             move.b #$7, (a4)
00001E26:  426c0004             clr.w $4(a4)
00001E2A:  426c0002             clr.w $2(a4)
00001E2E:  422c0001             clr.b $1(a4)
00001E32:  422b0002             clr.b $2(a3)
00001E36:  4253                 clr.w (a3)
00001E38:  177c00040003         move.b #$4, $3(a3)
00001E3E:  27470004             move.l d7, $4(a3)
00001E42:  206dff86             movea.l -$7a(a5), a0
00001E46:  217c800000000014     move.l #$80000000, $14(a0)
00001E4E:  206dff86             movea.l -$7a(a5), a0
00001E52:  00a8000400000014     ori.l #$40000, $14(a0)
00001E5A:  206dff86             movea.l -$7a(a5), a0
00001E5E:  117c00060035         move.b #$6, $35(a0)
00001E64:  206dff86             movea.l -$7a(a5), a0
00001E68:  214b0028             move.l a3, $28(a0)
00001E6C:  206dff86             movea.l -$7a(a5), a0
00001E70:  7008                 moveq #$8, d0
00001E72:  2140002c             move.l d0, $2c(a0)
00001E76:  206dff86             movea.l -$7a(a5), a0
00001E7A:  117c00010067         move.b #$1, $67(a0)
00001E80:  206dff86             movea.l -$7a(a5), a0
00001E84:  7200                 moveq #$0, d1
00001E86:  21410010             move.l d1, $10(a0)
00001E8A:  206dff86             movea.l -$7a(a5), a0
00001E8E:  7001                 moveq #$1, d0
00001E90:  ; ==== 52 bytes not reached as code ====
00001E90:  a0 89 20 6d ff 86 1e 28 00 3c 3c 28 00 0a 70 00 |.. m...(.<<(..p.|
00001EA0:  30 28 00 06 2f 00 4e ba e7 ea 70 00 10 07 0c 40 |0(../.N...p....@|
00001EB0:  00 02 58 4f 66 04 70 f8 60 0a 4a 46 67 04 70 fd |..XOf.p.`.JFg.p.|
00001EC0:  60 02 70 00                                     |`.p.|
00001EC4:  4cee18c0ffe8         movem.l -$18(a6), d6-d7/a3-a4
00001ECA:  4e5e                 unlk a6
00001ECC:  4e75                 rts
00001ECE:  4e56ffde             link.w a6, #$ffde
00001ED2:  48e70018             movem.l a3-a4, -(a7)
00001ED6:  47eefff8             lea.l -$8(a6), a3
00001EDA:  49eeffde             lea.l -$22(a6), a4
00001EDE:  7006                 moveq #$6, d0
00001EE0:  2f00                 move.l d0, -(a7)
00001EE2:  7207                 moveq #$7, d1
00001EE4:  2f01                 move.l d1, -(a7)
00001EE6:  486efff2             pea.l -$e(a6)
00001EEA:  4ebafcd4             jsr $1bc0(pc)
00001EEE:  7008                 moveq #$8, d0
00001EF0:  2f00                 move.l d0, -(a7)
00001EF2:  7200                 moveq #$0, d1
00001EF4:  2f01                 move.l d1, -(a7)
00001EF6:  2f0b                 move.l a3, -(a7)
00001EF8:  4ebafcc6             jsr $1bc0(pc)
00001EFC:  177c00040003         move.b #$4, $3(a3)
00001F02:  38bc0002             move.w #$2, (a4)
00001F06:  294b0002             move.l a3, $2(a4)
00001F0A:  7008                 moveq #$8, d0
00001F0C:  29400006             move.l d0, $6(a4)
00001F10:  397c0007000a         move.w #$7, $a(a4)
00001F16:  276e00080004         move.l $8(a6), $4(a3)
00001F1C:  48780e10             pea.l $e10.w
00001F20:  7000                 moveq #$0, d0
00001F22:  2f00                 move.l d0, -(a7)
00001F24:  7201                 moveq #$1, d1
00001F26:  2f01                 move.l d1, -(a7)
00001F28:  2f0c                 move.l a4, -(a7)
00001F2A:  7006                 moveq #$6, d0
00001F2C:  2f00                 move.l d0, -(a7)
00001F2E:  486efff2             pea.l -$e(a6)
00001F32:  4ebafb06             jsr $1a3a(pc)
00001F36:  4cee1800ffd6         movem.l -$2a(a6), a3-a4
00001F3C:  4e5e                 unlk a6
00001F3E:  4e75                 rts
00001F40:  4e560000             link.w a6, #$0
00001F44:  48e71108             movem.l d3/d7/a4, -(a7)
00001F48:  286e0008             movea.l $8(a6), a4
00001F4C:  3e2e000e             move.w $e(a6), d7
00001F50:  7600                 moveq #$0, d3
00001F52:  6006                 bra.b $1f5a
00001F54:  421c                 clr.b (a4)+
00001F56:  3007                 move.w d7, d0
00001F58:  5347                 subq.w #$1, d7
00001F5A:  b647                 cmp.w d7, d3
00001F5C:  6df6                 blt.b $1f54
00001F5E:  4cee1088fff4         movem.l -$c(a6), d3/d7/a4
00001F64:  4e5e                 unlk a6
00001F66:  4e75                 rts
00001F68:  306f0004             movea.w $4(a7), a0
00001F6C:  7004                 moveq #$4, d0
00001F6E:  ; ==== 10 bytes not reached as code ====
00001F6E:  a0 ac 20 5f 54 8f 3e 80 4e d0                   |.. _T.>.N.|
00001F78:  6000009e             bra.w $2018
00001F7C:  6006                 bra.b $1f84
00001F7E:  4ef912345678         jmp $12345678.l
00001F84:  0cae123456780010     cmpi.l #$12345678, $10(a6)
00001F8C:  66f0                 bne.b $1f7e
00001F8E:  9cfc008c             suba.w #$8c, a6
00001F92:  284e                 movea.l a6, a4
00001F94:  584f                 addq.w #$4, a7
00001F96:  42aa00ac             clr.l $ac(a2)
00001F9A:  4eb912345678         jsr $12345678.l
00001FA0:  4dee008c             lea.l $8c(a6), a6
00001FA4:  4cde180a             movem.l (a6)+, d1/d3/a3-a4
00001FA8:  584e                 addq.w #$4, a6
00001FAA:  4a40                 tst.w d0
00001FAC:  6706                 beq.b $1fb4
00001FAE:  4ef912345678         jmp $12345678.l
00001FB4:  2278034e             movea.l $34e.w, a1
00001FB8:  322a00a6             move.w $a6(a2), d1
00001FBC:  2031100c             move.l $c(a1, d1.w), d0
00001FC0:  ec88                 lsr.l #$6, d0
00001FC2:  4ef912345678         jmp $12345678.l
00001FC8:  ; ==== 20 bytes not reached as code ====
00001FC8:  0c 97 12 34 56 78 66 06 2a 31 00 0c e8 8d 4e f9 |...4Vxf.*1....N.|
00001FD8:  12 34 56 78                                     |.4Vx|
00001FDC:  4e560000             link.w a6, #$0
00001FE0:  203a0032             move.l $2014(pc), d0
00001FE4:  6718                 beq.b $1ffe
00001FE6:  4267                 clr.w -(a7)
00001FE8:  2f2e000c             move.l $c(a6), -(a7)
00001FEC:  2f2e0008             move.l $8(a6), -(a7)
00001FF0:  2040                 movea.l d0, a0
00001FF2:  4e90                 jsr (a0)
00001FF4:  4a5f                 tst.w (a7)+
00001FF6:  6606                 bne.b $1ffe
00001FF8:  206e0008             movea.l $8(a6), a0
00001FFC:  6006                 bra.b $2004
00001FFE:  206e0008             movea.l $8(a6), a0
00002002:  4290                 clr.l (a0)
00002004:  08d0001f             bset.b #$1f, (a0)
00002008:  426e0010             clr.w $10(a6)
0000200C:  4e5e                 unlk a6
0000200E:  205f                 movea.l (a7)+, a0
00002010:  504f                 addq.w #$8, a7
00002012:  4ed0                 jmp (a0)
00002014:  ; ==== 4 bytes not reached as code ====
00002014:  00 00 00 00                                     |....|
00002018:  48e770c0             movem.l d1-d3/a0-a1, -(a7)
0000201C:  303ca89f             move.w #$a89f, d0
00002020:  ; ==== 26 bytes not reached as code ====
00002020:  a7 46 26 08 30 3c a1 ad a3 46 96 88 67 16 20 3c |.F&.0<...F..g. <|
00002030:  62 75 67 7a a1 ad 67 02 91 c8                   |bugz..g...|
0000203A:  2008                 move.l a0, d0
0000203C:  0800001f             btst.b #$1f, d0
00002040:  660000ec             bne.w $212e
00002044:  207802ae             movea.l $2ae.w, a0
00002048:  2408                 move.l a0, d2
0000204A:  30280008             move.w $8(a0), d0
0000204E:  323c0010             move.w #$10, d1
00002052:  0c40037a             cmpi.w #$37a, d0
00002056:  6722                 beq.b $207a
00002058:  5941                 subq.w #$4, d1
0000205A:  0c40067c             cmpi.w #$67c, d0
0000205E:  671a                 beq.b $207a
00002060:  5941                 subq.w #$4, d1
00002062:  0c400178             cmpi.w #$178, d0
00002066:  6712                 beq.b $207a
00002068:  5941                 subq.w #$4, d1
0000206A:  0c400276             cmpi.w #$276, d0
0000206E:  670a                 beq.b $207a
00002070:  5941                 subq.w #$4, d1
00002072:  0c400075             cmpi.w #$75, d0
00002076:  660000ba             bne.w $2132
0000207A:  41fa00be             lea.l $213a(pc), a0
0000207E:  20301000             move.l (a0, d1.w), d0
00002082:  d082                 add.l d2, d0
00002084:  41faff16             lea.l $1f9c(pc), a0
00002088:  2080                 move.l d0, (a0)
0000208A:  41fa00c2             lea.l $214e(pc), a0
0000208E:  20301000             move.l (a0, d1.w), d0
00002092:  d082                 add.l d2, d0
00002094:  41faff1a             lea.l $1fb0(pc), a0
00002098:  2080                 move.l d0, (a0)
0000209A:  41fa00c6             lea.l $2162(pc), a0
0000209E:  20301000             move.l (a0, d1.w), d0
000020A2:  d082                 add.l d2, d0
000020A4:  41fafee0             lea.l $1f86(pc), a0
000020A8:  2080                 move.l d0, (a0)
000020AA:  41fa00de             lea.l $218a(pc), a0
000020AE:  20301000             move.l (a0, d1.w), d0
000020B2:  d082                 add.l d2, d0
000020B4:  41faff14             lea.l $1fca(pc), a0
000020B8:  2080                 move.l d0, (a0)
000020BA:  41fa00ba             lea.l $2176(pc), a0
000020BE:  20301000             move.l (a0, d1.w), d0
000020C2:  d082                 add.l d2, d0
000020C4:  41fafefe             lea.l $1fc4(pc), a0
000020C8:  2080                 move.l d0, (a0)
000020CA:  41fafeb4             lea.l $1f80(pc), a0
000020CE:  20380770             move.l $770.w, d0
000020D2:  2080                 move.l d0, (a0)
000020D4:  41faff02             lea.l $1fd8(pc), a0
000020D8:  20380748             move.l $748.w, d0
000020DC:  2080                 move.l d0, (a0)
000020DE:  4a83                 tst.l d3
000020E0:  6708                 beq.b $20ea
000020E2:  223c0000009c         move.l #$9c, d1
000020E8:  6002                 bra.b $20ec
000020EA:  7260                 moveq #$60, d1
000020EC:  2001                 move.l d1, d0
000020EE:  ; ==== 64 bytes not reached as code ====
000020EE:  a5 1e 66 40 22 48 41 fa fe 86 20 01 a0 2e 21 c9 |..f@"HA... ...!.|
000020FE:  07 70 d2 fc 00 4c 21 c9 07 48 4a 83 67 22 d2 fc |.p...L!..HJ.g"..|
0000210E:  00 14 20 49 20 3c 62 75 67 7a a5 ad 67 0c 20 49 |.. I <bugz..g. I|
0000211E:  20 3c 62 75 67 7a a3 ad 60 06 d2 fc 00 38 22 88 | <bugz..`....8".|
0000212E:  7000                 moveq #$0, d0
00002130:  6002                 bra.b $2134
00002132:  70ff                 moveq #$ff, d0
00002134:  4cdf030e             movem.l (a7)+, d1-d3/a0-a1
00002138:  4e75                 rts
0000213A:  00006678             ori.b #$78, d0
0000213E:  0000813e             ori.b #$3e, d0
00002142:  0000bc02             ori.b #$2, d0
00002146:  00012fde             ori.b #$de, d1
0000214A:  0000d5a8             ori.b #$a8, d0
0000214E:  00003158             ori.b #$58, d0
00002152:  00004ba6             ori.b #$a6, d0
00002156:  0000865a             ori.b #$5a, d0
0000215A:  0000f970             ori.b #$70, d0
0000215E:  00009f5c             ori.b #$5c, d0
00002162:  000031e4             ori.b #$e4, d0
00002166:  00004c64             ori.b #$64, d0
0000216A:  00008720             ori.b #$20, d0
0000216E:  0000fa36             ori.b #$36, d0
00002172:  0000a022             ori.b #$22, d0
00002176:  000031fa             ori.b #$fa, d0
0000217A:  00004c7a             ori.b #$7a, d0
0000217E:  00008736             ori.b #$36, d0
00002182:  0000fa4c             ori.b #$4c, d0
00002186:  0000a038             ori.b #$38, d0
0000218A:  00003306             ori.b #$6, d0
0000218E:  00004d86             ori.b #$86, d0
00002192:  00008842             ori.b #$42, d0
00002196:  0000fb58             ori.b #$58, d0
0000219A:  0000a144             ori.b #$44, d0
0000219E:  202f0004             move.l $4(a7), d0
000021A2:  671c                 beq.b $21c0
000021A4:  2040                 movea.l d0, a0
000021A6:  2240                 movea.l d0, a1
000021A8:  343c00ff             move.w #$ff, d2
000021AC:  1210                 move.b (a0), d1
000021AE:  10c0                 move.b d0, (a0)+
000021B0:  1001                 move.b d1, d0
000021B2:  57cafff8             dbeq d2, $21ac
000021B6:  2208                 move.l a0, d1
000021B8:  2009                 move.l a1, d0
000021BA:  9280                 sub.l d0, d1
000021BC:  5301                 subq.b #$1, d1
000021BE:  1281                 move.b d1, (a1)
000021C0:  4e75                 rts
000021C2:  8663                 or.w -(a3), d3
000021C4:  3270737472000000     movea.w $72000000(a0, invalid.w), a1
000021CC:  225f                 movea.l (a7)+, a1
000021CE:  121f                 move.b (a7)+, d1
000021D0:  301f                 move.w (a7)+, d0
000021D2:  4a01                 tst.b d1
000021D4:  6704                 beq.b $21da
000021D6:  ; ==== 36 bytes not reached as code ====
000021D6:  a7 46 60 02 a3 46 2e 88 4e d1 20 5f 30 1f 42 97 |.F`..F..N. _0.B.|
000021E6:  46 40 b0 78 01 d2 64 0a e5 48 22 78 01 1c 2e b1 |F@.x..d..H"x....|
000021F6:  00 00 4e d0                                     |..N.|
000021FA:  225f                 movea.l (a7)+, a1
000021FC:  205f                 movea.l (a7)+, a0
000021FE:  201f                 move.l (a7)+, d0
00002200:  ; ==== 4 bytes not reached as code ====
00002200:  a0 4e 4e d1                                     |.NN.|
00002204:  4eba0058             jsr $225e(pc)
00002208:  068000000020         addi.l #$20, d0
0000220E:  4e75                 rts
00002210:  2f0d                 move.l a5, -(a7)
00002212:  200d                 move.l a5, d0
00002214:  08000000             btst.b #$0, d0
00002218:  660c                 bne.b $2226
0000221A:  206f0008             movea.l $8(a7), a0
0000221E:  7007                 moveq #$7, d0
00002220:  20dd                 move.l (a5)+, (a0)+
00002222:  51c8fffc             dbra d0, $2220
00002226:  2a6f0008             movea.l $8(a7), a5
0000222A:  4eba003a             jsr $2266(pc)
0000222E:  2a5f                 movea.l (a7)+, a5
00002230:  4e75                 rts
00002232:  200d                 move.l a5, d0
00002234:  2a6f0004             movea.l $4(a7), a5
00002238:  4e75                 rts
0000223A:  2a6f0004             movea.l $4(a7), a5
0000223E:  4e75                 rts
00002240:  4ebaffc2             jsr $2204(pc)
00002244:  ; ==== 12 bytes not reached as code ====
00002244:  a1 1e 2f 08 4e ba 00 14 d0 9f 4e 75             |../.N.....Nu|
00002250:  4eba000c             jsr $225e(pc)
00002254:  206f0004             movea.l $4(a7), a0
00002258:  91c0                 suba.l d0, a0
0000225A:  ; ==== 4 bytes not reached as code ====
0000225A:  a0 1f 4e 75                                     |..Nu|
0000225E:  41fa01b4             lea.l $2414(pc), a0
00002262:  2010                 move.l (a0), d0
00002264:  4e75                 rts
00002266:  48e77ff8             movem.l d1-d7/a0-a4, -(a7)
0000226A:  49fa01a8             lea.l $2414(pc), a4
0000226E:  302c0004             move.w $4(a4), d0
00002272:  5340                 subq.w #$1, d0
00002274:  6704                 beq.b $227a
00002276:  70ff                 moveq #$ff, d0
00002278:  6032                 bra.b $22ac
0000227A:  264d                 movea.l a5, a3
0000227C:  97d4                 suba.l (a4), a3
0000227E:  2f0b                 move.l a3, -(a7)
00002280:  2f14                 move.l (a4), -(a7)
00002282:  6100014c             bsr.w $23d0
00002286:  202c0008             move.l $8(a4), d0
0000228A:  48740800             pea.l (a4, d0.l)
0000228E:  2f0b                 move.l a3, -(a7)
00002290:  6100002e             bsr.w $22c0
00002294:  504f                 addq.w #$8, a7
00002296:  202c000c             move.l $c(a4), d0
0000229A:  48740800             pea.l (a4, d0.l)
0000229E:  2f0b                 move.l a3, -(a7)
000022A0:  2f0d                 move.l a5, -(a7)
000022A2:  610000d0             bsr.w $2374
000022A6:  4fef000c             lea.l $c(a7), a7
000022AA:  7000                 moveq #$0, d0
000022AC:  4cdf1ffe             movem.l (a7)+, d1-d7/a0-a4
000022B0:  4e75                 rts
000022B2:  ; ==== 14 bytes not reached as code ====
000022B2:  80 09 5f 44 41 54 41 49 4e 49 54 00 00 00       |.._DATAINIT...|
000022C0:  226f0004             movea.l $4(a7), a1
000022C4:  206f0008             movea.l $8(a7), a0
000022C8:  48e71800             movem.l d3-d4, -(a7)
000022CC:  7601                 moveq #$1, d3
000022CE:  7200                 moveq #$0, d1
000022D0:  1218                 move.b (a0)+, d1
000022D2:  2401                 move.l d1, d2
000022D4:  0241000f             andi.w #$f, d1
000022D8:  660a                 bne.b $22e4
000022DA:  61000044             bsr.w $2320
000022DE:  2200                 move.l d0, d1
000022E0:  6724                 beq.b $2306
000022E2:  6002                 bra.b $22e6
000022E4:  d241                 add.w d1, d1
000022E6:  024200f0             andi.w #$f0, d2
000022EA:  6608                 bne.b $22f4
000022EC:  61000032             bsr.w $2320
000022F0:  2400                 move.l d0, d2
000022F2:  6002                 bra.b $22f6
000022F4:  e64a                 lsr.w #$3, d2
000022F6:  d3c2                 adda.l d2, a1
000022F8:  2801                 move.l d1, d4
000022FA:  12d8                 move.b (a0)+, (a1)+
000022FC:  5384                 subq.l #$1, d4
000022FE:  66fa                 bne.b $22fa
00002300:  5383                 subq.l #$1, d3
00002302:  66f2                 bne.b $22f6
00002304:  60c6                 bra.b $22cc
00002306:  4cdf0018             movem.l (a7)+, d3-d4
0000230A:  4e75                 rts
0000230C:  8010                 or.b (a0), d0
0000230E:  ; ==== 18 bytes not reached as code ====
0000230E:  75 6e 63 6f 6d 70 72 65 73 73 5f 77 6f 72 6c 64 |uncompress_world|
0000231E:  00 00                                           |..|
00002320:  7000                 moveq #$0, d0
00002322:  1018                 move.b (a0)+, d0
00002324:  6a42                 bpl.b $2368
00002326:  08000006             btst.b #$6, d0
0000232A:  6734                 beq.b $2360
0000232C:  08000005             btst.b #$5, d0
00002330:  6720                 beq.b $2352
00002332:  08000004             btst.b #$4, d0
00002336:  670a                 beq.b $2342
00002338:  61e6                 bsr.b $2320
0000233A:  2600                 move.l d0, d3
0000233C:  61e2                 bsr.b $2320
0000233E:  c143                 exg.l d0, d3
00002340:  4e75                 rts
00002342:  1018                 move.b (a0)+, d0
00002344:  e180                 asl.l #$8, d0
00002346:  1018                 move.b (a0)+, d0
00002348:  e180                 asl.l #$8, d0
0000234A:  1018                 move.b (a0)+, d0
0000234C:  e180                 asl.l #$8, d0
0000234E:  1018                 move.b (a0)+, d0
00002350:  4e75                 rts
00002352:  0200001f             andi.b #$1f, d0
00002356:  e180                 asl.l #$8, d0
00002358:  1018                 move.b (a0)+, d0
0000235A:  e180                 asl.l #$8, d0
0000235C:  1018                 move.b (a0)+, d0
0000235E:  4e75                 rts
00002360:  0200003f             andi.b #$3f, d0
00002364:  e180                 asl.l #$8, d0
00002366:  1018                 move.b (a0)+, d0
00002368:  4e75                 rts
0000236A:  8006                 or.b d6, d0
0000236C:  6765                 beq.b $23d3
0000236E:  745f                 moveq #$5f, d2
00002370:  726c                 moveq #$6c, d1
00002372:  0000222f             ori.b #$2f, d0
00002376:  0004226f             ori.b #$6f, d4
0000237A:  ; ==== 2 bytes not reached as code ====
0000237A:  00 08                                           |..|
0000237C:  206f000c             movea.l $c(a7), a0
00002380:  7401                 moveq #$1, d2
00002382:  7000                 moveq #$0, d0
00002384:  1018                 move.b (a0)+, d0
00002386:  670c                 beq.b $2394
00002388:  6a26                 bpl.b $23b0
0000238A:  08800007             bclr.b #$7, d0
0000238E:  e188                 lsl.l #$8, d0
00002390:  1018                 move.b (a0)+, d0
00002392:  601c                 bra.b $23b0
00002394:  1018                 move.b (a0)+, d0
00002396:  6724                 beq.b $23bc
00002398:  6a0e                 bpl.b $23a8
0000239A:  e188                 lsl.l #$8, d0
0000239C:  1018                 move.b (a0)+, d0
0000239E:  e188                 lsl.l #$8, d0
000023A0:  1018                 move.b (a0)+, d0
000023A2:  e188                 lsl.l #$8, d0
000023A4:  1018                 move.b (a0)+, d0
000023A6:  6008                 bra.b $23b0
000023A8:  2400                 move.l d0, d2
000023AA:  6100ff74             bsr.w $2320
000023AE:  c142                 exg.l d0, d2
000023B0:  d080                 add.l d0, d0
000023B2:  d3c0                 adda.l d0, a1
000023B4:  d391                 add.l d1, (a1)
000023B6:  5382                 subq.l #$1, d2
000023B8:  66f8                 bne.b $23b2
000023BA:  60c4                 bra.b $2380
000023BC:  4e75                 rts
000023BE:  ; ==== 18 bytes not reached as code ====
000023BE:  80 0e 72 65 6c 6f 63 61 74 65 5f 77 6f 72 6c 64 |..relocate_world|
000023CE:  00 00                                           |..|
000023D0:  7400                 moveq #$0, d2
000023D2:  205f                 movea.l (a7)+, a0
000023D4:  201f                 move.l (a7)+, d0
000023D6:  225f                 movea.l (a7)+, a1
000023D8:  6728                 beq.b $2402
000023DA:  3209                 move.w a1, d1
000023DC:  02410003             andi.w #$3, d1
000023E0:  6708                 beq.b $23ea
000023E2:  12c2                 move.b d2, (a1)+
000023E4:  5380                 subq.l #$1, d0
000023E6:  66f2                 bne.b $23da
000023E8:  6018                 bra.b $2402
000023EA:  2200                 move.l d0, d1
000023EC:  e489                 lsr.l #$2, d1
000023EE:  6706                 beq.b $23f6
000023F0:  22c2                 move.l d2, (a1)+
000023F2:  5381                 subq.l #$1, d1
000023F4:  66fa                 bne.b $23f0
000023F6:  02400003             andi.w #$3, d0
000023FA:  6002                 bra.b $23fe
000023FC:  12c2                 move.b d2, (a1)+
000023FE:  51c8fffc             dbra d0, $23fc
00002402:  4ed0                 jmp (a0)
00002404:  ; ==== 16 bytes not reached as code ====
00002404:  80 0a 5a 45 52 4f 42 55 46 46 45 52 00 00 00 00 |..ZEROBUFFER....|
00002414:  00000a26             ori.b #$26, d0
00002418:  00010000             ori.b #$0, d1
0000241C:  00000014             ori.b #$14, d0
00002420:  0000008e             ori.b #$8e, d0
00002424:  00000000             ori.b #$0, d0
00002428:  06004150             addi.b #$50, d0
0000242C:  504c                 addq.w #$8, a4
0000242E:  ; ==== 130 bytes not reached as code ====
0000242E:  45 5f 50 52 4f 44 4f 53 1c 41 50 50 4c 45 5f 53 |E_PRODOS.APPLE_S|
0000243E:  43 52 41 54 43 48 00 41 50 50 4c 45 5f 46 52 45 |CRATCH.APPLE_FRE|
0000244E:  45 10 2c 41 50 50 4c 45 5f 50 41 52 54 49 54 49 |E.,APPLE_PARTITI|
0000245E:  4f 4e 5f 4d 41 50 00 41 50 50 4c 45 5f 48 46 53 |ON_MAP.APPLE_HFS|
0000246E:  00 41 50 50 4c 45 5f 44 52 49 56 45 52 34 33 10 |.APPLE_DRIVER43.|
0000247E:  21 ff ff f6 20 ff ff f6 16 ff ff f6 02 ff ff f5 |!... ...........|
0000248E:  f6 ff ff f5 e8 ff ff f5 da 4d 41 43 49 4e 54 4f |.........MACINTO|
0000249E:  53 48 10 00 2b 00 02 05 00 00 00 00 24 14 6d 70 |SH..+.......$.mp|
000024AE:  77 64                                           |wd|
