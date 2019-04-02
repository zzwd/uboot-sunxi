/* SPDX-License-Identifier: GPL-2.0+ */
/*
 *  vectors - Generic ARM exception table code
 *
 *  Copyright (c) 1998	Dan Malek <dmalek@jlc.net>
 *  Copyright (c) 1999	Magnus Damm <kieraypc01.p.y.kie.era.ericsson.se>
 *  Copyright (c) 2000	Wolfgang Denk <wd@denx.de>
 *  Copyright (c) 2001	Alex Züpke <azu@sysgo.de>
 *  Copyright (c) 2001	Marius Gröger <mag@sysgo.de>
 *  Copyright (c) 2002	Alex Züpke <azu@sysgo.de>
 *  Copyright (c) 2002	Gary Jennejohn <garyj@denx.de>
 *  Copyright (c) 2002	Kyle Harris <kharris@nexus-tech.net>
 */

#include <config.h>	/*头文件，实际包含的是include/configs/sunxi-common.h*/

/*
 * A macro to allow insertion of an ARM exception vector either
 * for the non-boot0 case or by a boot0-header.
 *	允许插入ARM异常向量的宏对于非boot0情况或boot0-header。
 */
        .macro ARM_VECTORS  /*_start 会调用到ARM_VECTORS设置异常向量表*/
#ifdef CONFIG_ARCH_K3
	ldr     pc, _reset
#else
	b	reset
#endif
	ldr	pc, _undefined_instruction
	ldr	pc, _software_interrupt
	ldr	pc, _prefetch_abort
	ldr	pc, _data_abort
	ldr	pc, _not_used
	ldr	pc, _irq
	ldr	pc, _fiq
	.endm


/*
 *************************************************************************
 *
 * Symbol _start is referenced elsewhere, so make it global
 *	符号_start在别处引用，因此将其设为全局
 *************************************************************************
 */

.globl _start

/*
 *************************************************************************
 *
 * Vectors have their own section so linker script can map them easily
 * 向量有自己的部分，因此链接描述文件可以轻松映射它们
 *************************************************************************
 */

	.section ".vectors", "ax"

#if defined(CONFIG_ENABLE_ARM_SOC_BOOT0_HOOK)
/*
 * Various SoCs need something special and SoC-specific up front in
 * order to boot, allow them to set that in their boot0.h file and then
 * use it here.
 *
 * To allow a boot0 hook to insert a 'special' sequence after the vector
 * table (e.g. for the socfpga), the presence of a boot0 hook supresses
 * the below vector table and assumes that the vector table is filled in
 * by the boot0 hook.  The requirements for a boot0 hook thus are:
 *   (1) defines '_start:' as appropriate
 *   (2) inserts the vector table using ARM_VECTORS as appropriate
 *	各种SoC需要一些特殊的，特别是SoC特定的要启动，允许他们在boot0.h文件中设置它然后在这里使用它。
 *  允许boot0挂钩在向量之后插入“特殊”序列
 *  table（例如对于socfpga），boot0钩子的存在
 *  下面的向量表并假设填充了向量表
 *  通过boot0钩子。 因此boot0挂钩的要求是：
 *    （1）酌情定义'_start：'
 *    （2）根据需要使用ARM_VECTORS插入向量表
 */
#include <asm/arch/boot0.h>

#else

/*
 *************************************************************************
 *
 * Exception vectors as described in ARM reference manuals
 *
 * Uses indirect branch to allow reaching handlers anywhere in memory.
 *
 *************************************************************************
 */

_start:
#ifdef CONFIG_SYS_DV_NOR_BOOT_CFG
	.word	CONFIG_SYS_DV_NOR_BOOT_CFG
#endif
	ARM_VECTORS 	/*调用ARM_VECTORS设置中断向量异常表*/
#endif /* !defined(CONFIG_ENABLE_ARM_SOC_BOOT0_HOOK) */

/*
 *************************************************************************
 *
 * Indirect vectors table
 *
 * Symbols referenced here must be defined somewhere else
 * 间接向量表，此处引用的符号必须在其他位置定义
 * reset定义在文件arch/arm/cpu/armv7/start.S中
 *************************************************************************
 */

	.globl  _reset
	.globl	_undefined_instruction
	.globl	_software_interrupt
	.globl	_prefetch_abort
	.globl	_data_abort
	.globl	_not_used
	.globl	_irq
	.globl	_fiq

#ifdef CONFIG_ARCH_K3
_reset:			.word reset
#endif
_undefined_instruction:	.word undefined_instruction
_software_interrupt:	.word software_interrupt
_prefetch_abort:	.word prefetch_abort
_data_abort:		.word data_abort
_not_used:		.word not_used
_irq:			.word irq
_fiq:			.word fiq

	.balignl 16,0xdeadbeef
	/*.balignl 16,0xdeadbeef 表示下面的代码开始16字节对齐，即当上段的代码运行完后不是16字节对齐，
	就填充0xdeadbeef，直到使下段的代码开始处16字节对齐。*/

/*
 *************************************************************************
 *
 * Interrupt handling
 *
 *************************************************************************
 */

/* SPL interrupt handling: just hang  在SPL过程中发生异常挂起*/

#ifdef CONFIG_SPL_BUILD

	.align	5
undefined_instruction:
software_interrupt:
prefetch_abort:
data_abort:
not_used:
irq:
fiq:
1:
	b	1b			/* hang and never return 挂起并永远不返回*/

#else	/* !CONFIG_SPL_BUILD */

/* IRQ stack memory (calculated at run-time) + 8 bytes 
 *不能确定堆栈指针地址，所以填充无效数字0x0badc0de，当堆栈指针确定以后，将其加8填充到这里
 */
.globl IRQ_STACK_START_IN
IRQ_STACK_START_IN:
#ifdef IRAM_BASE_ADDR
	.word   IRAM_BASE_ADDR + 0x20
#else
	.word	0x0badc0de
#endif


/*
 *下面是异常处理，通过bl调用相应的异常处理函数，如bl do_irq
 *会调用到do_irq()函数
 */

@
@ IRQ stack frame.
@
#define S_FRAME_SIZE	72

#define S_OLD_R0	68
#define S_PSR		64
#define S_PC		60
#define S_LR		56
#define S_SP		52

#define S_IP		48
#define S_FP		44
#define S_R10		40
#define S_R9		36
#define S_R8		32
#define S_R7		28
#define S_R6		24
#define S_R5		20
#define S_R4		16
#define S_R3		12
#define S_R2		8
#define S_R1		4
#define S_R0		0

#define MODE_SVC 0x13
#define I_BIT	 0x80

/*
 * use bad_save_user_regs for abort/prefetch/undef/swi ...
 * use irq_save_user_regs / irq_restore_user_regs for IRQ/FIQ handling
 */

	.macro	bad_save_user_regs
	@ carve out a frame on current user stack
	sub	sp, sp, #S_FRAME_SIZE
	stmia	sp, {r0 - r12}	@ Save user registers (now in svc mode) r0-r12
	ldr	r2, IRQ_STACK_START_IN
	@ get values for "aborted" pc and cpsr (into parm regs)
	ldmia	r2, {r2 - r3}
	add	r0, sp, #S_FRAME_SIZE		@ grab pointer to old stack
	add	r5, sp, #S_SP
	mov	r1, lr
	stmia	r5, {r0 - r3}	@ save sp_SVC, lr_SVC, pc, cpsr
	mov	r0, sp		@ save current stack into r0 (param register)
	.endm

	.macro	irq_save_user_regs
	sub	sp, sp, #S_FRAME_SIZE
	stmia	sp, {r0 - r12}			@ Calling r0-r12
	@ !!!! R8 NEEDS to be saved !!!! a reserved stack spot would be good.
	add	r8, sp, #S_PC
	stmdb	r8, {sp, lr}^		@ Calling SP, LR
	str	lr, [r8, #0]		@ Save calling PC
	mrs	r6, spsr
	str	r6, [r8, #4]		@ Save CPSR
	str	r0, [r8, #8]		@ Save OLD_R0
	mov	r0, sp
	.endm

	.macro	irq_restore_user_regs
	ldmia	sp, {r0 - lr}^			@ Calling r0 - lr
	mov	r0, r0
	ldr	lr, [sp, #S_PC]			@ Get PC
	add	sp, sp, #S_FRAME_SIZE
	subs	pc, lr, #4		@ return & move spsr_svc into cpsr
	.endm

	.macro get_bad_stack
	ldr	r13, IRQ_STACK_START_IN		@ setup our mode stack

	str	lr, [r13]	@ save caller lr in position 0 of saved stack
	mrs	lr, spsr	@ get the spsr
	str	lr, [r13, #4]	@ save spsr in position 1 of saved stack
	mov	r13, #MODE_SVC	@ prepare SVC-Mode
	@ msr	spsr_c, r13
	msr	spsr, r13	@ switch modes, make sure moves will execute
	mov	lr, pc		@ capture return pc
	movs	pc, lr		@ jump to next instruction & switch modes.
	.endm

	.macro get_irq_stack			@ setup IRQ stack
	ldr	sp, IRQ_STACK_START
	.endm

	.macro get_fiq_stack			@ setup FIQ stack
	ldr	sp, FIQ_STACK_START
	.endm

/*
 * exception handlers
 */

	.align  5
undefined_instruction:
	get_bad_stack
	bad_save_user_regs
	bl	do_undefined_instruction

	.align	5
software_interrupt:
	get_bad_stack
	bad_save_user_regs
	bl	do_software_interrupt

	.align	5
prefetch_abort:
	get_bad_stack
	bad_save_user_regs
	bl	do_prefetch_abort

	.align	5
data_abort:
	get_bad_stack
	bad_save_user_regs
	bl	do_data_abort

	.align	5
not_used:
	get_bad_stack
	bad_save_user_regs
	bl	do_not_used


	.align	5
irq:
	get_bad_stack
	bad_save_user_regs
	bl	do_irq

	.align	5
fiq:
	get_bad_stack
	bad_save_user_regs
	bl	do_fiq

#endif	/* CONFIG_SPL_BUILD */
