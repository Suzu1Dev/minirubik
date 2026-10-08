/*
 * ripes.ld - GNU ld script for freestanding RV32I ELF files that are loaded
 * into Ripes (used by scripts/refbuild.sh --elf).  Toolchain glue only.
 *
 * Ripes' ELF loader (src/cli/programutilities.cpp, Ripes 5b8a616) copies
 * every non-.debug section to its sh_addr, starts at e_entry, and treats only
 * the section literally named ".text" as executable: the run ends when the
 * PC leaves .text or an exit ecall executes.  The map below mirrors the
 * Ripes assembler defaults so reference ELFs and hand-written assembly use
 * the same address ranges:
 *
 *   .text            0x00000000  (Ripes assembler text start); the program
 *                                 starts at e_entry = _start, which is
 *                                 the crt0 placed at the END of .text
 *   .rodata .data .srodata .sdata .sbss .bss
 *                    0x10000000  (Ripes assembler data start; also Ripes'
 *                                 default gp value)
 *   stack top        0x7ffffff0  (Ripes' default sp; grows down)
 *
 * The Ripes assembler puts .bss at 0x11000000; here .bss simply follows the
 * initialised data, which does not change any section size.
 *
 * Caveat (Ripes quirk): Ripes also "loads" non-allocated sections such as
 * .symtab/.strtab/.comment/.riscv.attributes at their address 0.  It applies
 * sections in alphabetical name order, and ".text" sorts after those names, so
 * the code at address 0 is written last and stays intact.  Nothing else
 * may be placed near address 0.
 *
 * All code must end up in the one output section ".text".  refbuild.sh
 * rejects a link that produces any other executable section.
 *
 * crt0 (section .ripes_crt0) goes last so that its exit ecall is the final
 * instruction of .text.  Ripes RV32_ISS (5b8a616) executes and counts one more
 * instruction after an exit ecall when the next PC is still inside .text.
 * Keeping the ecall last makes RV32_ISS, RV32_SS and RV32_5S report the same
 * instructions-retired count.  Nothing may be placed after it.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;
  .text : {
    *(.text.unlikely .text.unlikely.*)
    *(.text.startup .text.startup.*)  /* GCC puts main() here at -O2 */
    *(.text.hot .text.hot.*)
    *(.text .text.*)
    KEEP(*(.ripes_crt0))              /* crt0 LAST: its ecall ends .text */
  }

  . = 0x10000000;
  .rodata : {
    *(.rodata .rodata.*)
  }
  .data : {
    __DATA_BEGIN__ = .;
    *(.data .data.*)
  }
  /* Small data is kept together after .data (same order as GNU ld's default
   * elf32lriscv script: .srodata, .sdata, .sbss, then .bss). */
  .srodata : {
    __SDATA_BEGIN__ = .;
    *(.srodata.cst16) *(.srodata.cst8) *(.srodata.cst4) *(.srodata.cst2)
    *(.srodata .srodata.*)
  }
  .sdata : {
    *(.sdata .sdata.*)
  }
  .sbss : {
    *(.sbss .sbss.*) *(.scommon)
  }
  .bss : {
    *(.bss .bss.*) *(COMMON)
  }
  . = ALIGN(4);
  __BSS_END__ = .;
  /* gp: the exact formula of GNU ld's default RISC-V script (binutils 2.47,
   * `riscv64-elf-ld -m elf32lriscv --verbose`).  ld relaxes an absolute
   * lui+addi/lw/sw pair to one gp-relative instruction when the target is
   * within the 12-bit signed range of gp, so this choice changes the linked
   * .text size and instruction count.  Using the default formula makes those
   * numbers match a default-script link of the same objects (for the smoke
   * programs they are equal).  Note: .rodata sits right below .data here but
   * far away in the default layout; like the default, gp is never placed to
   * reach it (__DATA_BEGIN__ is the start of .data). */
  __global_pointer$ = MIN(__SDATA_BEGIN__ + 0x800,
                          MAX(__DATA_BEGIN__ + 0x800, __BSS_END__ - 0x800));
  . = ALIGN(16);
  _end = .;

  __stack_top = 0x7ffffff0;
}
