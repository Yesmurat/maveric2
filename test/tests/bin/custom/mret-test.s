.section .text
.global _start

_start:
    # Point mtvec at the trap handler.
    la      t0, trap_handler
    csrw    mtvec, t0

    # First ecall: a0=2 so check() returns 0 and keeps running.
    # This triggers a trap -> trap_handler -> mret -> resumes at next instruction.
    li      a0, 2
    ecall

    # Execution resumes here after mret (handler advanced mepc past the ecall).
    # Second ecall: a0=0 -> PASS.
    li      a0, 0
    ecall

fail:
    li      a0, 1
    ecall

trap_handler:
    # Advance mepc past the ecall that triggered this trap (+4).
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    mret