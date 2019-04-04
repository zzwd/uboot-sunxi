/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * armboot - Startup Code for OMAP3530/ARM Cortex CPU-core
 *
 * Copyright (c) 2004	Texas Instruments <r-woodruff2@ti.com>
 *
 * Copyright (c) 2001	Marius Gröger <mag@sysgo.de>
 * Copyright (c) 2002	Alex Züpke <azu@sysgo.de>
 * Copyright (c) 2002	Gary Jennejohn <garyj@denx.de>
 * Copyright (c) 2003	Richard Woodruff <r-woodruff2@ti.com>
 * Copyright (c) 2003	Kshitij <kshitij@ti.com>
 * Copyright (c) 2006-2008 Syed Mohammed Khasim <x0khasim@ti.com>
 */

#include <asm-offsets.h>
#include <config.h>
#include <asm/system.h>
#include <linux/linkage.h>
#include <asm/armv7.h>

/*************************************************************************
 *
 * Startup Code (reset vector)
 *
 * Do important init only if we do not start from memory!
 * Setup memory and board specific bits prior to relocation.
 * Relocate armboot to ram. Setup stack.
 * 启动代码（复位向量）
 * 只有当我们不从内存开始时才重要的初始化！
 * 在重定位之前设置内存和板特定位。
 * 将armboot重新安置到ram。 设置堆栈。
 *
 *************************************************************************/

	.globl	reset
	.globl	save_boot_params_ret
	.type   save_boot_params_ret,%function
#ifdef CONFIG_ARMV7_LPAE
	.global	switch_to_hypervisor_ret  

#endif

reset:
	/* Allow the board to save important registers */
	/*如果没有重新定义save_boot_params，则使用<arch/arm/cpu/armv7/start.S>中的save_boot_params。这里为弱引用其不做任何事情，直接返回。*/
	b	save_boot_params 	
save_boot_params_ret:
#ifdef CONFIG_ARMV7_LPAE
/*
 * check for Hypervisor support
 * 在某些SoC上，无法直接从u-boot 启用管理程序模式，因为ROM代码在跳转到引导加载程序后将芯片置于管理程序模式。
 * 因此，引入了一个弱函数，可以根据SoC类型覆盖，并以自定义方式切换到管理程序模式。switch_to_hypervisor为弱引用，这里直接返回
 */
	mrc	p15, 0, r0, c0, c1, 1		@ read ID_PFR1
	and	r0, r0, #CPUID_ARM_VIRT_MASK	@ mask virtualization bits
	cmp	r0, #(1 << CPUID_ARM_VIRT_SHIFT)
	beq	switch_to_hypervisor
switch_to_hypervisor_ret:
#endif
	/*
	 * disable interrupts (FIQ and IRQ), also set the cpu to SVC32 mode,
	 * except if in HYP mode already
	 * 禁用中断（FIQ和IRQ），同时将cpu设置为SVC32模式，除非已经处于HYP模式
	 */
	mrs	r0, cpsr 	 /*将cpsr寄存器的内容传送到r0寄存器*/
	and	r1, r0, #0x1f		@ mask mode bits /*标志位清零*/
	teq	r1, #0x1a		@ test for HYP mode /*测试处理器是否处于HYP模式，HYP是armv-7a为cortex-A15处理器提供硬件虚拟化引进的管理模式。*/
	bicne	r0, r0, #0x1f		@ clear all mode bits /*工作模式位清零*/
	orrne	r0, r0, #0x13		@ set SVC mode /*设置成SVC管理模式*/
	orr	r0, r0, #0xc0		@ disable FIQ and IRQ /*关闭FIQ和IRQ中断*/
	msr	cpsr,r0 	/*将r0的值赋给cpsr*/

/*
 * Setup vector:
 * (OMAP4 spl TEXT_BASE is not 32 byte aligned.
 * Continue to use ROM code vector only in OMAP4 spl)
 * 设置矢量：(OMAP4 spl TEXT_BASE不是32字节对齐的。继续在OMAP4 spl中使用ROM代码矢量)
 */
#if !(defined(CONFIG_OMAP44XX) && defined(CONFIG_SPL_BUILD))
	/* Set V=0 in CP15 SCTLR register - for VBAR to point to vector */
	/* 设置异常向量的基地址，正常异常模式下异常向量的基地址为0x00000000，高异常模式下异常向量的基地址为0xffff0000，
		这里V=0设置成正常异常模式
	*/
	mrc	p15, 0, r0, c1, c0, 0	@ Read CP15 SCTLR Register
	bic	r0, #CR_V		@ V = 0
	mcr	p15, 0, r0, c1, c0, 0	@ Write CP15 SCTLR Register

#ifdef CONFIG_HAS_VBAR
	/* Set vector address in CP15 VBAR register */
	/* 重新设置异常向量的基地址，只有上面V=0的情况下，这里才能去重新配置异常向量表的基地址！*/
	ldr	r0, =_start
	mcr	p15, 0, r0, c12, c0, 0	@Set VBAR
#endif
#endif

	/* the mask ROM code should have PLL and others stable */
#ifndef CONFIG_SKIP_LOWLEVEL_INIT
#ifdef CONFIG_CPU_V7A
	bl	cpu_init_cp15 /*初始化协处理器*/
#endif
#ifndef CONFIG_SKIP_LOWLEVEL_INIT_ONLY
	bl	cpu_init_crit 	/*初始化内存和锁相环*/
#endif
#endif

	bl	_main 	/*调用c代码*/

/*------------------------------------------------------------------------------*/

ENTRY(c_runtime_cpu_setup)
/*
 * If I-cache is enabled invalidate it
 */
#ifndef CONFIG_SYS_ICACHE_OFF
	mcr	p15, 0, r0, c7, c5, 0	@ invalidate icache
	mcr     p15, 0, r0, c7, c10, 4	@ DSB
	mcr     p15, 0, r0, c7, c5, 4	@ ISB
#endif

	bx	lr

ENDPROC(c_runtime_cpu_setup)

/*************************************************************************
 *
 * void save_boot_params(u32 r0, u32 r1, u32 r2, u32 r3)
 *	__attribute__((weak));
 *
 * Stack pointer is not yet initialized at this moment
 * Do not save anything to stack even if compiled with -O0
 *
 *************************************************************************/
ENTRY(save_boot_params)
	b	save_boot_params_ret		@ back to my caller
ENDPROC(save_boot_params)
	.weak	save_boot_params

#ifdef CONFIG_ARMV7_LPAE
ENTRY(switch_to_hypervisor)
	b	switch_to_hypervisor_ret
ENDPROC(switch_to_hypervisor)
	.weak	switch_to_hypervisor
#endif

/*************************************************************************
 *
 * cpu_init_cp15
 *
 * Setup CP15 registers (cache, MMU, TLBs). The I-cache is turned on unless
 * CONFIG_SYS_ICACHE_OFF is defined.
 *设置CP15寄存器（缓存，MMU，TLB）。 除非打开I-cache  CONFIG_SYS_ICACHE_OFF已定义。
 *************************************************************************/
ENTRY(cpu_init_cp15)
	/*
	 * Invalidate L1 I/D  使 L1 I/D 无效
	 */
	mov	r0, #0			@ set up for MCR
	mcr	p15, 0, r0, c8, c7, 0	@ invalidate TLBs /*禁止从TLB中取地址描述符,也就是禁止虚拟地址到物理地址的转换，因为刚开始操作的都是物理寄存器！*/
	mcr	p15, 0, r0, c7, c5, 0	@ invalidate icache  /*关闭指令cache*/
	mcr	p15, 0, r0, c7, c5, 6	@ invalidate BP array /*关闭分支预测*/
	mcr     p15, 0, r0, c7, c10, 4	@ DSB 	/*多核cpu之间进行数据同步*/
	mcr     p15, 0, r0, c7, c5, 4	@ ISB 	/*进行指令同步，放弃流水线中已经取到的指令，重新取指令*/

	/*
	 * disable MMU stuff and caches  关闭MMU和caches
	 */

/*******************************************************
1、为什么要关闭mmu？因为MMU是把虚拟地址转化为物理地址得作用而我们现在是要设置控制寄存器，
而控制寄存器本来就是实地址（物理地址），再使能MMU，不就是多此一举了吗？
********************************************************/

/*******************************************************
2、为什么要关闭cache？*catch和MMU是通过CP15管理的，刚上电的时候，CPU还不能管理他们。
所以上电的时候MMU必须关闭，指令cache可关闭，可不关闭，但数据cache一定要关闭
否则可能导致刚开始的代码里面，去取数据的时候，从catch里面取，而这时候RAM中数据还没有cache过来，导致数据预取异常
********************************************************/

	mrc	p15, 0, r0, c1, c0, 0
	bic	r0, r0, #0x00002000	@ clear bits 13 (--V-) /*设置成正常异常模式，即异常向量表的基地址为0x00000000*/
	bic	r0, r0, #0x00000007	@ clear bits 2:0 (-CAM)  /*关闭指令cache,关闭指令对齐检测，关闭mmu*/
	orr	r0, r0, #0x00000002	@ set bit 1 (--A-) Align /*使能对齐检测*/
	orr	r0, r0, #0x00000800	@ set bit 11 (Z---) BTB  /*使能分支预测*/
#ifdef CONFIG_SYS_ICACHE_OFF
	bic	r0, r0, #0x00001000	@ clear bit 12 (I) I-cache
#else
	orr	r0, r0, #0x00001000	@ set bit 12 (I) I-cache /*使能指令cache*/
#endif
	mcr	p15, 0, r0, c1, c0, 0

#ifdef CONFIG_ARM_ERRATA_716044
	mrc	p15, 0, r0, c1, c0, 0	@ read system control register
	orr	r0, r0, #1 << 11	@ set bit #11
	mcr	p15, 0, r0, c1, c0, 0	@ write system control register
#endif

#if (defined(CONFIG_ARM_ERRATA_742230) || defined(CONFIG_ARM_ERRATA_794072))
	mrc	p15, 0, r0, c15, c0, 1	@ read diagnostic register
	orr	r0, r0, #1 << 4		@ set bit #4
	mcr	p15, 0, r0, c15, c0, 1	@ write diagnostic register
#endif

#ifdef CONFIG_ARM_ERRATA_743622
	mrc	p15, 0, r0, c15, c0, 1	@ read diagnostic register
	orr	r0, r0, #1 << 6		@ set bit #6
	mcr	p15, 0, r0, c15, c0, 1	@ write diagnostic register
#endif

#ifdef CONFIG_ARM_ERRATA_751472
	mrc	p15, 0, r0, c15, c0, 1	@ read diagnostic register
	orr	r0, r0, #1 << 11	@ set bit #11
	mcr	p15, 0, r0, c15, c0, 1	@ write diagnostic register
#endif
#ifdef CONFIG_ARM_ERRATA_761320
	mrc	p15, 0, r0, c15, c0, 1	@ read diagnostic register
	orr	r0, r0, #1 << 21	@ set bit #21
	mcr	p15, 0, r0, c15, c0, 1	@ write diagnostic register
#endif

#ifdef CONFIG_ARM_ERRATA_845369
	mrc     p15, 0, r0, c15, c0, 1	@ read diagnostic register
	orr     r0, r0, #1 << 22	@ set bit #22
	mcr     p15, 0, r0, c15, c0, 1	@ write diagnostic register
#endif

	mov	r5, lr			@ Store my Caller
	mrc	p15, 0, r1, c0, c0, 0	@ r1 has Read Main ID Register (MIDR)
	mov	r3, r1, lsr #20		@ get variant field
	and	r3, r3, #0xf		@ r3 has CPU variant
	and	r4, r1, #0xf		@ r4 has CPU revision
	mov	r2, r3, lsl #4		@ shift variant field for combined value
	orr	r2, r4, r2		@ r2 has combined CPU variant + revision

/* Early stack for ERRATA that needs into call C code */
#if defined(CONFIG_SPL_BUILD) && defined(CONFIG_SPL_STACK)
	ldr	r0, =(CONFIG_SPL_STACK)
#else
	ldr	r0, =(CONFIG_SYS_INIT_SP_ADDR)
#endif
	bic	r0, r0, #7	/* 8-byte alignment for ABI compliance */
	mov	sp, r0

#ifdef CONFIG_ARM_ERRATA_798870
	cmp	r2, #0x30		@ Applies to lower than R3p0
	bge	skip_errata_798870      @ skip if not affected rev
	cmp	r2, #0x20		@ Applies to including and above R2p0
	blt	skip_errata_798870      @ skip if not affected rev

	mrc	p15, 1, r0, c15, c0, 0  @ read l2 aux ctrl reg
	orr	r0, r0, #1 << 7         @ Enable hazard-detect timeout
	push	{r1-r5}			@ Save the cpu info registers
	bl	v7_arch_cp15_set_l2aux_ctrl
	isb				@ Recommended ISB after l2actlr update
	pop	{r1-r5}			@ Restore the cpu info - fall through
skip_errata_798870:
#endif

#ifdef CONFIG_ARM_ERRATA_801819
	cmp	r2, #0x24		@ Applies to lt including R2p4
	bgt	skip_errata_801819      @ skip if not affected rev
	cmp	r2, #0x20		@ Applies to including and above R2p0
	blt	skip_errata_801819      @ skip if not affected rev
	mrc	p15, 0, r0, c0, c0, 6	@ pick up REVIDR reg
	and	r0, r0, #1 << 3		@ check REVIDR[3]
	cmp	r0, #1 << 3
	beq	skip_errata_801819	@ skip erratum if REVIDR[3] is set

	mrc	p15, 0, r0, c1, c0, 1	@ read auxilary control register
	orr	r0, r0, #3 << 27	@ Disables streaming. All write-allocate
					@ lines allocate in the L1 or L2 cache.
	orr	r0, r0, #3 << 25	@ Disables streaming. All write-allocate
					@ lines allocate in the L1 cache.
	push	{r1-r5}			@ Save the cpu info registers
	bl	v7_arch_cp15_set_acr
	pop	{r1-r5}			@ Restore the cpu info - fall through
skip_errata_801819:
#endif

#ifdef CONFIG_ARM_CORTEX_A15_CVE_2017_5715
	mrc	p15, 0, r0, c1, c0, 1	@ read auxilary control register
	orr	r0, r0, #1 << 0		@ Enable invalidates of BTB
	push	{r1-r5}			@ Save the cpu info registers
	bl	v7_arch_cp15_set_acr
	pop	{r1-r5}			@ Restore the cpu info - fall through
#endif

#ifdef CONFIG_ARM_ERRATA_454179
	mrc	p15, 0, r0, c1, c0, 1	@ Read ACR

	cmp	r2, #0x21		@ Only on < r2p1
	orrlt	r0, r0, #(0x3 << 6)	@ Set DBSM(BIT7) and IBE(BIT6) bits

	push	{r1-r5}			@ Save the cpu info registers
	bl	v7_arch_cp15_set_acr
	pop	{r1-r5}			@ Restore the cpu info - fall through
#endif

#if defined(CONFIG_ARM_ERRATA_430973) || defined (CONFIG_ARM_CORTEX_A8_CVE_2017_5715)
	mrc	p15, 0, r0, c1, c0, 1	@ Read ACR

#ifdef CONFIG_ARM_CORTEX_A8_CVE_2017_5715
	orr	r0, r0, #(0x1 << 6)	@ Set IBE bit always to enable OS WA
#else
	cmp	r2, #0x21		@ Only on < r2p1
	orrlt	r0, r0, #(0x1 << 6)	@ Set IBE bit
#endif
	push	{r1-r5}			@ Save the cpu info registers
	bl	v7_arch_cp15_set_acr
	pop	{r1-r5}			@ Restore the cpu info - fall through
#endif

#ifdef CONFIG_ARM_ERRATA_621766
	mrc	p15, 0, r0, c1, c0, 1	@ Read ACR

	cmp	r2, #0x21		@ Only on < r2p1
	orrlt	r0, r0, #(0x1 << 5)	@ Set L1NEON bit

	push	{r1-r5}			@ Save the cpu info registers
	bl	v7_arch_cp15_set_acr
	pop	{r1-r5}			@ Restore the cpu info - fall through
#endif

#ifdef CONFIG_ARM_ERRATA_725233
	mrc	p15, 1, r0, c9, c0, 2	@ Read L2ACR

	cmp	r2, #0x21		@ Only on < r2p1 (Cortex A8)
	orrlt	r0, r0, #(0x1 << 27)	@ L2 PLD data forwarding disable

	push	{r1-r5}			@ Save the cpu info registers
	bl	v7_arch_cp15_set_l2aux_ctrl
	pop	{r1-r5}			@ Restore the cpu info - fall through
#endif

#ifdef CONFIG_ARM_ERRATA_852421
	mrc	p15, 0, r0, c15, c0, 1	@ read diagnostic register
	orr	r0, r0, #1 << 24	@ set bit #24
	mcr	p15, 0, r0, c15, c0, 1	@ write diagnostic register
#endif

#ifdef CONFIG_ARM_ERRATA_852423
	mrc	p15, 0, r0, c15, c0, 1	@ read diagnostic register
	orr	r0, r0, #1 << 12	@ set bit #12
	mcr	p15, 0, r0, c15, c0, 1	@ write diagnostic register
#endif

	mov	pc, r5			@ back to my caller  /*cpu_init_cp15 程序返回*/
ENDPROC(cpu_init_cp15)

#if !defined(CONFIG_SKIP_LOWLEVEL_INIT) && \
	!defined(CONFIG_SKIP_LOWLEVEL_INIT_ONLY)
/*************************************************************************
 *
 * CPU_init_critical registers
 *
 * setup important registers
 * setup memory timing
 *设置重要寄存器，设置内存时序
 *************************************************************************/
ENTRY(cpu_init_crit)
	/*
	 * Jump to board specific initialization...
	 * The Mask ROM will have already initialized
	 * basic memory. Go here to bump up clock rate and handle
	 * wake up conditions.
	 * 跳转到板级初始化lowlevel_init函数，和硬件平台相关，对应平台的目录下找lowlevel_init.S文件，这里使用/arch/arm/cpu/armv7/
	 */
	b	lowlevel_init		@ go setup pll,mux,memory /*去设置PLL时钟，mux和内存*/
ENDPROC(cpu_init_crit)
#endif
