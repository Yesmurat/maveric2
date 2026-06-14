.section .text
.global _start

_start:
    # Point mtvec at the trap handler.
    la      t0, trap_handler
    csrw    mtvec, t0

    # Set MIE=1 in mstatus so we can verify MPIE captures the old MIE.
    # WARL keeps MPP=11, so written value 8 becomes 0x1808.
    li      t0, 8
    csrw    mstatus, t0

    # Trigger trap with ecall.
    # a0=2 is the sentinel: check() returns 0 (continue) instead of $finish,
    # allowing the trap handler below to execute.
    li      a0, 2
ecall_site:
    ecall

    # Unreachable if trap redirected PC correctly.
fail:
    li      a0, 1
    ecall

trap_handler:
    # mepc must equal the PC of the ecall instruction.
    csrr    t0, mepc
    la      t1, ecall_site
    bne     t0, t1, trap_fail

    # mcause must be 11 (environment call from M-mode).
    csrr    t0, mcause
    li      t1, 11
    bne     t0, t1, trap_fail

    # mstatus: MIE (bit 3) must be 0, MPIE (bit 7) must be 1 (captured old MIE).
    csrr    t0, mstatus
    andi    t1, t0, 8
    bnez    t1, trap_fail       # MIE must be 0
    andi    t1, t0, 0x80
    beqz    t1, trap_fail       # MPIE must be 1

    li      a0, 0
    ecall

trap_fail:
    li      a0, 1
    ecall
