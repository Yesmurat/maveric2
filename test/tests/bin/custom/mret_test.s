.section .text
.global _start

_start:
    auipc t0, 0          # t0 = start of program (0x80000000)
    addi  t0, t0, 36     # t0 = 0x80000024 = trap_handler
    csrw  mtvec, t0      # mtvec = trap_handler
    li    a0, 2          # sentinel: check() returns 0 (continue)
    ecall                # triggers trap; PC → mtvec = trap_handler

    # Reached via mret (mepc advanced to here by trap handler)
    li    a0, 0          # PASS
    ecall

    li    a0, 1          # FAIL (unreachable)
    ecall

trap_handler:            # must be at offset 36 = 0x24 from _start
    csrr  t0, mepc       # t0 = mepc (PC of ecall = 0x80000010)
    addi  t0, t0, 4      # advance past ecall
    csrw  mepc, t0       # mepc = 0x80000014 (li a0, 0)
    mret                 # PC → mepc
