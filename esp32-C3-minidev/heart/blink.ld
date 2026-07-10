/* Linker script for ATmega2560
 * Defines memory layout and section placement for bare-metal assembly
 */

ENTRY(_start) /* Define our custom entry point label */

MEMORY
{
  /* 256KB of internal Flash memory for code (r = read, x = execute) */
  flash (rx) : ORIGIN = 0x000000, LENGTH = 256K

  /* 8KB of internal SRAM for data (starts after hardware registers/extended IO) */
  ram   (rw) : ORIGIN = 0x000200, LENGTH = 8K
}

SECTIONS
{
  /* Force all code, literal pools, and constants strictly into Flash */
  .text :
  {
    *(.text*)
  } > flash
}
