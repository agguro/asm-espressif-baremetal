MEMORY
{
    iram (rwx) : ORIGIN = 0x40380000, LENGTH = 128K
}

SECTIONS
{
    . = 0x40380000;

    .text : {
        *(.text._start)
        *(.text)
        *(.text.*)
    } > iram

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    } > iram

    .data : {
        *(.data)
        *(.data.*)
    } > iram

    .bss : {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > iram
}
