/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * (C) Copyright 2012
 * Allwinner Technology Co., Ltd. <www.allwinnertech.com>
 * Tom Cubie <tangliang@allwinnertech.com>
 *
 * Based on omap-common/u-boot-spl.lds:
 *
 * (C) Copyright 2002
 * Gary Jennejohn, DENX Software Engineering, <garyj@denx.de>
 *
 * (C) Copyright 2010
 * Texas Instruments, <www.ti.com>
 *	Aneesh V <aneesh@ti.com>
 */
MEMORY { .sram : ORIGIN = IMAGE_TEXT_BASE,\
		LENGTH = IMAGE_MAX_SIZE }	/*定义sram起始地址和范围*/
MEMORY { .sdram : ORIGIN = CONFIG_SPL_BSS_START_ADDR, \
		LENGTH = CONFIG_SPL_BSS_MAX_SIZE }	/*定义sdram起始地址和范围*/

OUTPUT_FORMAT("elf32-littlearm", "elf32-littlearm", "elf32-littlearm") /*指定输出可执行文件是elf格式,32位ARM指令,小端*/
OUTPUT_ARCH(arm)	/*指定输出可执行文件的平台为ARM*/
ENTRY(_start)		/*指定输出可执行文件执行入口_start*/
SECTIONS
{
	.text      :
	{
		__image_copy_start = .;  	/*映像文件复制起始地址*/
		*(.vectors)		/*代码段执行的第一个文件arch/arm/lib/vectors.S，该文件包含执行入口_start标志*/
		arch/arm/cpu/armv7/start.o	(.text) /*接着执行arch/arm/cpu/armv7/start.S文件*/
		*(.text*)
	} > .sram 											/*指定代码段在sram内*/

	. = ALIGN(4);	/*代码以4字节对齐*/
	.rodata : { *(SORT_BY_ALIGNMENT(.rodata*)) } >.sram /*指定rodata段在sram内*/

	. = ALIGN(4);
	.data : { *(SORT_BY_ALIGNMENT(.data*)) } >.sram 	/*指定data段在sram内*/

	. = ALIGN(4);
	.u_boot_list : {
		KEEP(*(SORT(.u_boot_list*)));
	} > .sram 											/*指定u_boot_list在sram内*/

	. = ALIGN(4);
	__image_copy_end = .;	/*映像文件复制结束地址*/
	_end = .;

	.bss :
	{
		. = ALIGN(4);
		__bss_start = .;
		*(.bss*)
		. = ALIGN(4);
		__bss_end = .;
	} > .sdram 											/*指定bss段在sdram内*/
}
