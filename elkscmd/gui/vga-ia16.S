// Routines to draw pixels and lines for EGA/VGA 16 color 4 planes modes.
// High speed version for ia16-elf-gcc using GAS assembly
// Supports  the following EGA and VGA 16 color modes:
//       640x480 16 color (mode 0x12)
//       640x350 16 color (mode 0x10)
//
// The algorithms for some of these routines are taken from the book:
// Programmer's Guide to PC and PS/2 Video Systems by Richard Wilton.
//
// Copyright (c) 1999 Greg Haerr <greg@censoft.com>
// Copyright (c) 1991 David I. Bell
// Permission is granted to use, distribute, or modify this source,
// provided that this copyright notice remains intact.
//
// 1 Feb 2025 Greg Haerr rewritten for ELKS AS86
// 4 Apr 2025 Greg Haerr written for ELKS ia16-elf-gcc
//
        .code16
        .text
#define BYTESPERLN  80                // number of bytes in scan line (640/8)
#define arg1        4                 // small model

//
// void vga_init(void)
//
// C version:
//   set_enable_sr(0xff);
//   set_op(0);
//   set_write_mode(0);
//
    .global vga_init
vga_init:
        mov     $0x03ce, %dx    // graphics controller port address
        mov     $0xff01, %ax    // set enable set/reset register 1 mask FF
        out     %ax, %dx
        mov     $0x0003, %ax    // data rotate register 3 NOP 0
        out     %ax, %dx
        mov     $0x0005, %ax    // set graphics mode register 5 write mode 0
        out     %ax, %dx        // [load value 0 into mode register 5]
        ret

//
// Draw an individual pixel.
// void vga_drawpixel(int x, int y, int color)
//
// C version:
//   static unsigned char mask[8] = { 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01 };
//   set_color(c);
//   set_mask(mask[x&7]);
//
        .global  vga_drawpixel
vga_drawpixel:
        push    %bp
        mov     %sp, %bp

        mov     arg1(%bp), %cx  // CX := x
        mov     %cx, %bx        // BX := x
        mov     arg1+2(%bp), %ax// AX := y

        shl     $1, %ax         // AX := [y * 80] (= y*64 + y*16)
        shl     $1, %ax
        shl     $1, %ax
        shl     $1, %ax
        mov     %ax, %dx
        shl     $1, %dx
        shl     $1, %dx
        add     %dx, %ax

        and     $7, %cl         // CL := x & 7
        xor     $7, %cl         // CL := 7 - (x & 7)
        mov     $1, %ch         // CH := 1 << (7 - (x & 7))
        shl     %cl, %ch        // CH is mask

        shr     $1, %bx         // BX := x / 8
        shr     $1, %bx
        shr     $1, %bx
        add     %ax, %bx        // BX := [y * BYTESPERLN] + [x / 8]

        mov     $0x03ce, %dx    // graphics controller port address
        xor     %ax, %ax        // set color register 0
        mov     arg1+4(%bp), %ah// color pixel value
        out     %ax, %dx

        mov     $8, %al         // set bit mask register 8
        mov     %ch, %ah        // [load bit mask into register 8]
        out     %ax, %dx

        mov     %ds, %cx
        mov     $0xA000, %ax    // DS := EGA buffer segment address
        mov     %ax, %ds
        or      %al,(%bx)       // quick rmw to set pixel
        mov     %cx, %ds        // restore registers and return

        pop     %bp
        ret

//
// Draw a horizontal line from x1,y to x2,y including final point
// void vga_drawhine(int x1, int x2, int y, int color)
//
// C version:
//   set_color(c);
//   char far *dst = EGA_BASE + x1 / 8 + y * BYTESPERLN;
//   if ((x1 >> 3) == (x2 >> 3)) {
//       set_mask((0xff >> (x1 & 7)) & (0xff << (7 - (x2 & 7))));
//       *dst |= 1;
//   } else {
//       set_mask(0xff >> (x1 & 7));
//       *dst++ |= 1;
//       set_mask(0xff);
//       last = EGA_BASE + x2 / 8 + y * BYTESPERLN;
//       while (dst < last)
//           *dst++ |= 1;
//       set_mask(0xff << (7 - x2 & 7));
//       *dst |= 1;
//   }

#define x1      arg1            // first X coordinate
#define x2      arg1 + 2        // second X coordinate
#define y       arg1 + 4        // second Y coordinate
#define color   arg1 + 6        // pixel value

        .global vga_drawhline
vga_drawhline:
        push    %bp             // setup stack frame and preserve registers
        mov     %sp,%bp
        push    %si
        push    %di
        push    %es
        push    %ds

        mov     $0x03ce, %dx    // Graphics Controller port address
        xor     %al, %al        // set Set/Reset register 0 with color
        mov     color(%bp), %ah
        out     %ax, %dx

        mov     $0x0f01, %ax    // AH := bit plane mask for Enable Set/Reset
        out     %ax, %dx        // AL := Enable Set/Reset register 1

        mov     y(%bp), %ax
        mov     x1(%bp), %bx

        // compute pixel address
        shl     $1, %ax         // AX := [row * 80] (= row*64 + row*16)
        shl     $1, %ax
        shl     $1, %ax
        shl     $1, %ax
        mov     %ax, %dx
        shl     $1, %dx
        shl     $1, %dx
        add     %dx, %ax

        mov     %bl, %cl        // save low order column bits
        shr     $1, %bx         // BX := [col / 8]
        shr     $1, %bx
        shr     $1, %bx
        add     %ax, %bx        // BX := [row * BYTESPERLN] + [col / 8]
        and     $7, %cl         // CL := [col & 7]
        xor     $7, %cl         // CL := 7 - [col & 7]
        mov     $1, %ah         // AH := 1 << [7 - [col & 7]]    [mask]
        mov     $0xA000, %dx    // ES := EGA buffer segment address
        mov     %dx, %es        // ES:BX -> video buffer
                                // AH := bit mask
                                // CL := number bits to shift left
        mov     %bx, %di        // ES:DI -> buffer
        mov     %ah, %dh        // DH := unshifted bit mask for left byte

        not     %dh
        shl     %cl, %dh        // DH := reverse bit mask for first byte
        not     %dh             // DH := bit mask for first byte

        mov     x2(%bp), %cx
        and     $7, %cl
        xor     $7, %cl         // CL := number of bits to shift left
        mov     $0xff, %dl      // DL := unshifted bit mask for right byte
        shl     %cl, %dl        // DL := bit mask for last byte

        // determine byte offset of first and last pixel in the line
        mov     x2(%bp), %ax    // AX := x2
        mov     x1(%bp), %bx    // BX := x1

        shr     $1, %ax         // AX := byte offset of X2
        shr     $1, %ax
        shr     $1, %ax
        shr     $1, %bx         // BX: byte offset of X1
        shr     $1, %bx
        shr     $1, %bx
        mov     %ax, %cx
        sub     %bx, %cx        // CX := [number of bytes in line] - 1

        // get Graphics Controller port address into DX
        mov     %dx, %bx        // BH := bit mask for first byte
                                // BL := bit mask for last byte
        mov     $0x03ce, %dx    // DX := Graphics Controller port
        mov     $8, %al         // AL := Bit mask Register number

        // make video buffer addressable through DS:SI
        push    %es
        pop     %ds
        mov     %di, %si        // DS:SI -> video buffer

        // set pixels in leftmost byte of the line
        or      %bh, %bh
        js      L43             // jump if byte-aligned [x1 is leftmost]

        or      %cx, %cx
        jnz     L42             // jump if more than one byte in the line

        and     %bh, %bl        // BL := bit mask for the line
        jmp     L44

L42:    mov     %bh, %ah        // AH := bit mask for first byte
        out     %ax, %dx        // update graphics controller

        movsb                   // update bit planes
        dec     %cx

        // use a fast 8086 machine instruction to draw the remainder of the line
L43:    mov     $0xff, %ah      // AH := bit mask
        out     %ax, %dx        // update Bit Mask register
        rep
        movsb                   // update all pixels in the line

        // set pixels in the rightmost byte of the line
L44:    mov     %bl, %ah        // AH := bit mask for last byte
        out     %ax, %dx        // update Graphics Controller
        movsb                   // update bit planes

        pop     %ds
        pop     %es
        pop     %di
        pop     %si
        pop     %bp
        ret

//
// Draw a vertical line from x,y1 to x,y2 including final point
// void vga_drawvline(int x, int y1, int y2, int color)
//
// C version:
//   set_color(c);
//   set_mask(mask[x&7]);
//   char far *dst = EGA_BASE + x / 8 + y1 * BYTESPERLN;
//   char far *last = EGA_BASE + x / 8 + y2 * BYTESPERLN;
//   while (dst < last) {
//       *dst |= 1;
//       dst += BYTESPERLN;
//   }
//

#define x       arg1            // first X coordinate
#define y1      arg1 + 2        // first Y coordinate
#define y2      arg1 + 4        // second Y coordinate
#define color   arg1 + 6        // pixel value

        .global  vga_drawvline
vga_drawvline:
        push    %bp             // setup stack frame and preserve registers
        mov     %sp, %bp
        push    %ds

        mov     $0x03ce, %dx    // DX := Graphics Controller port address
        xor     %al, %al        // set Set/Reset register 0 with color
        mov     color(%bp), %ah
        out     %ax, %dx

        mov     $0x0f01, %ax    // AH := bit plane mask for Enable Set/Reset
        out     %ax, %dx        // AL := Enable Set/Reset register number

        // prepare to draw vertical line
        mov     y1(%bp), %ax    // AX := y1
        mov     y2(%bp), %cx    // BX := y2
        sub     %ax, %cx        // CX := dy

L311:   inc     %cx             // CX := number of pixels to draw
        mov     x(%bp), %bx     // BX := x
        push    %cx             // save register

        // compute pixel address
        shl     $1, %ax         // AX := [row * 80] (= row*64 + row*16)
        shl     $1, %ax
        shl     $1, %ax
        shl     $1, %ax
        mov     %ax, %dx
        shl     $1, %dx
        shl     $1, %dx
        add     %dx, %ax

        mov     %bl, %cl        // save low order column bits
        shr     $1, %bx         // BX := [col / 8]
        shr     $1, %bx
        shr     $1, %bx
        add     %ax, %bx        // BX := [row * BYTESPERLN] + [col / 8]
        and     $7, %cl         // CL := [col & 7]
        xor     $7, %cl         // CL := 7 - [col & 7]
        mov     $1, %ah         // AH := 1 << [7 - [col & 7]]    [mask]
        mov     $0x0A000, %dx   // DS := EGA buffer segment address
        mov     %dx ,%ds        // DS:BX -> video buffer
                                // AH := bit mask
                                // CL := number bits to shift left
        // set up Graphics controller
        mov     $0x03ce, %dx    // DX := Graphics Controller port address
        shl     %cl, %ah        // AH := bit mask in proper position
        mov     $8, %al         // AL := Bit Mask register number 8
        out     %ax, %dx

        pop     %cx             // restore number of pixels to draw

        // draw the line
        mov     $BYTESPERLN, %dx // increment for video buffer
L1111:  or      %al, (%bx)      // set pixel
        add     %dx, %bx        // increment to next line
        loop    L1111

        pop     %ds
        pop     %bp
        ret

//
// Read the value of an individual pixel.
// int ega_readpixel(int x, int y)
//
        .global vga_readpixel
vga_readpixel:
        push    %bp
        mov     %sp, %bp
        push    %si
        push    %ds

        mov     arg1+2(%bp), %ax// AX := y
        mov     arg1(%bp), %bx  // BX := x
        shl     $1, %ax         // AX := [y * 80] (= y*64 + y*16)
        shl     $1, %ax
        shl     $1, %ax
        shl     $1, %ax
        mov     %ax, %dx
        shl     $1, %dx
        shl     $1, %dx
        add     %dx, %ax

        mov     %bl, %cl        // save low order column bits
        shr     $1, %bx         // BX := [x / 8]
        shr     $1, %bx
        shr     $1, %bx
        add     %ax, %bx        // BX := [y * BYTESPERLN] + [x / 8]

        and     $7, %cl         // CL := [x & 7]
        xor     $7, %cl         // CL := 7 - [x & 7]

        mov     $0xA000, %dx    // DS := EGA buffer segment address
        mov     %dx, %ds

        mov     $1, %ch         // CH := 1 << [7 - [col & 7]]
        shl     %cl, %ch        // CH := bit mask in proper position

        mov     %bx, %si        // DS:SI -> region buffer byte
        xor     %bl, %bl        // BL is used to accumulate the pixel value

        mov     $0x03ce, %dx    // DX := Graphics Controller port
        mov     $0x0304, %ax    // AH := initial bit plane number 3
                                // AL := Read Map Select register number 4

L112:   out     %ax, %dx        // select bit plane
        mov     (%si), %bh      // BH := byte from current bit plane
        and     %ch, %bh        // mask one bit
        neg     %bh             // bit 7 of BH := 1 if masked bit = 1
                                // bit 7 of BH := 0 if masked bit = 0
        rol     $1, %bx         // bit 0 of BL := next bit from pixel value
        dec     %ah             // AH := next bit plane number
        jge     L112

        xor     %ax, %ax        // AL := pixel value
        mov     %bl, %al

        pop     %ds
        pop     %si
        pop     %bp      
        ret

// void fdstmemcpy (word_t dst_off, seg_t dst_seg, char *src_off, word_t count)
// Copy near source to far destination
// segment parameter after offset to allow LES from the stack

#define ARG0    2
#define ARG1    4
#define ARG2    6
#define ARG3    8

        .global fdstmemcpy
fdstmemcpy:
        mov    %si, %ax
        mov    %di, %dx
        mov    %es, %bx
        mov    %sp, %si

        mov    ARG3(%si), %cx   // byte count
        les    ARG0(%si), %di   // far destination pointer
        mov    ARG2(%si), %si   // near far source pointer
        cld
        shr    $1, %cx          // copy words
        rep
        movsw
        rcl    $1, %cx          // then possibly final byte
        rep
        movsb

        mov    %bx, %es
        mov    %dx, %di
        mov    %ax, %si
        ret
