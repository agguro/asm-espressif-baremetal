MEMORY
{
    iram (rwx) : ORIGIN = 0x40380000, LENGTH = 64K
    dram (rwx) : ORIGIN = 0x3FC80000, LENGTH = 320K
}

SECTIONS
{
    . = 0x40380000;

    .text : {
        *(.text.entry)
        *(.text .text.*)
    } > iram

    .rodata : {
        *(.rodata .rodata.*)
    } > iram

    .data : {
        *(.data .data.*)
    } > iram

    .bss : {
        *(.bss .bss.*)
        *(COMMON)
    } > iram
}
