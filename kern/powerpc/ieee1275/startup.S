/* startup.S - Startup code for the PowerPC.  */
/*
 *  GRUB  --  GRand Unified Bootloader
 *  Copyright (C) 2003,2004,2005,2007,2008  Free Software Foundation, Inc.
 *
 *  GRUB is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  GRUB is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with GRUB.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <grub/symbol.h>
#include <grub/offsets.h>

.extern __bss_start
.extern _end

	.text
	.align	2
	.globl	start, _start
start:
_start:
	b	codestart

	. = _start + GRUB_KERNEL_MACHINE_PREFIX

VARIABLE(grub_prefix)
	/* to be filled by grub-mkelfimage */

	/*
	 *  Leave some breathing room for the prefix.
	 */

	. = _start + GRUB_KERNEL_MACHINE_DATA_END

codestart:
	li      2, 0
	li      13, 0

	/* Stage1 won't zero BSS for us. In other cases, why not do it again?  */
	lis	6, (__bss_start - 4)@h
	ori	6, 6, (__bss_start - 4)@l
	lis	7, (_end - 4)@h
	ori	7, 7, (_end - 4)@l
	subf	7, 6, 7
	srwi	7, 7, 2 /* We store 4 bytes at a time.  */
	mtctr	7
2:	stwu	2, 4(6) /* We know r2 is already 0 from above.  */
	bdnz	2b

	/* Store r5 in grub_ieee1275_entry_fn.  */
	lis	9, grub_ieee1275_entry_fn@ha
	stw	5, grub_ieee1275_entry_fn@l(9)

	bl	grub_main
1:	b	1b
