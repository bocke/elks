####################################################################################
# BIOS INT 15H Block Move and A20 enable for IBM PC
# Nov 2021 Greg Haerr
#
# void bios_block_movew(struct gdt_table *gdtp, size_t words)
#
#	Move words to/from anywhere in physical memory using BIOS INT 15h AH=87h.
#	Normally used to move data to/from extended memory (> 1M) because
#	real mode addressing can only address the first 1M of RAM, unless
#	using unreal mode. Protected mode is used for the copy, and interrupts
#	are disabled the whole time.
#
#	This is a substitute function for linear32_fmemcpyw which requires unreal mode,
#	and uses a int15_fmemcpy wrapper above it to prefill the passed GDT table.

	.arch	i8086, nojumps
	.code16
	.text

	.global	bios_block_movew
	.global	enable_a20_gate

# IBM PC A20 gate functions shared with setup.S
#include "a20-ibm.inc"

#
# void bios_block_movew(struct gdt_table *gdtp, size_t words)
# Uses BIOS INT 15h AH=87h Block Move
# NOTE: BIOS disables A20 during call, won't work with HMA kernel
bios_block_movew:
	push	%es
	push	%si
	push	%bp
	mov	%sp,%bp

	mov	10(%bp),%cx	# word count -> CX
	mov	8(%bp),%si	# gdtp -> ES:SI
	push	%ds
	pop	%es

	mov	$0x87,%ah	# BIOS Block Move
	int	$0x15
	sti			# re-enable interrupts from int15_fmemcpy
	pop	%bp
	pop	%si
	pop	%es
	ret

#if UNUSED
#
# Test functions
#
int0Dh:	push	%bp
	push	%ax
	mov	%sp,%bp
	mov	4(%bp),%ax
	inc	%ax
	//inc	%ax
	mov	%ax,4(%bp)
	pop	%ax
	pop	%bp
	iret

setgpf:	push	%ds
	xor	%ax,%ax
	mov	%ax,%ds
	mov	$0x0D*4,%bx
	mov	$int0Dh,%ax
	mov	%ax,(%bx)
	add	$2,%bx
	push	%cs
	pop	%ax
	mov	%ax,(%bx)
	pop	%ds
	ret

	.global	get_extmem
get_extmem:
	mov	$0x88,%ah
	int	$0x15
	jc	1f
	ret
1:	mov	$-1,%ax
	ret
#endif
