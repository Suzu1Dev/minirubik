/*
 * crt0.S - minimal freestanding start-up code for running a GCC-compiled
 * RV32I C program as an ELF in the Ripes simulator (used by
 * scripts/refbuild.sh --elf).  Toolchain glue only; not homework code.
 *
 *   _start:  gp <- __global_pointer$   (the linker may relax small-data
 *                                       accesses to gp-relative form)
 *            sp <- __stack_top         (0x7ffffff0, Ripes' default sp)
 *            a0 <- main()
 *            a7 <- 93; ecall           (Ripes "Exit2": prints
 *                                       "Program exited with code: <a0>")
 *   7 instructions are executed here (call relaxes to a single jal).
 *
 * Placement: this code is in section .ripes_crt0, which tools/rv32/ripes.ld
 * puts at the END of the single output section .text, so the exit ecall is
 * the last instruction in .text.  Ripes starts at e_entry (= _start), not at
 * the start of .text.  Reason: Ripes RV32_ISS (5b8a616) executes and counts
 * one more instruction after an exit ecall when the next PC is still inside
 * .text (RV32_SS/RV32_5S do not).  With the ecall last, the next PC leaves
 * .text and every model reports the same retired count.
 *
 * .bss is NOT cleared: Ripes models memory as a sparse map that reads 0 for
 * any byte never written and is cleared on every reset, so a clearing loop
 * would only add retired instructions.  Do not reuse this crt0 on a loader
 * that does not zero memory.
 *
 * __crt0_start/__crt0_end bracket these bytes so refbuild.sh can report the
 * crt0 share of the linked .text (after linker relaxation).
 */
	.section .ripes_crt0, "ax", @progbits
	.globl	_start
	.globl	__crt0_start
	.globl	__crt0_end
	.type	_start, @function
_start:
__crt0_start:
	.option push
	.option norelax		/* gp is not valid yet: never relax this la */
	la	gp, __global_pointer$
	.option pop
	la	sp, __stack_top
	call	main
	li	a7, 93		/* Ripes Exit2: exit with status a0 */
	ecall			/* must stay the last instruction in .text */
__crt0_end:
	.size	_start, . - _start
