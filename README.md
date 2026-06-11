# MAVERIC Core 2.0

MAVERIC Core 2.0 is a 5-stage in-order, single-issue CPU which implements the 64-bit RISC-V instruction set. It fully implements I and M extensions as specified in Volume I: User-Level ISA V 2.3. M, S, U privilege modes support is work in-progress.

---

## Quick Start

```bash
# Run a single test with Dromajo co-simulation
python3 run_tests.py -s am-add --cosim-only

# Run the full test suite (am + rv-tests + rv-arch-test + snippy)
python3 run_tests.py -a

# Sweep cache geometry (BLOCK_WIDTH × SET_COUNT × associativity) for one test
python3 run_tests.py -s am-matrix-mul -v

# Generate a waveform for a single test
python3 run_tests.py -s am-bubble-sort -t

# Generate line + toggle coverage across all tests
python3 run_tests.py -a --coverage-all

# Clean generated artifacts before a commit
python3 run_tests.py -p
```

Pass/fail results → `results/result.txt`
Performance counters → `results/perf_result.txt`

---

## ISA Support

| Feature | Status |
|---|---|
| RV64I base integer | Implemented |
| RV64M multiply (`mul`, `mulh`, `mulhsu`, `mulhu`, `mulw`) | Implemented |
| `W`-variant 32-bit ops (`addw`, `subw`, `sllw`, …) | Implemented |
| `ECALL` / `EBREAK` and cause-code generation | Implemented |
| M divide/remainder (`div`, `divu`, `rem`, `remu`, …) | Implemented |
| C (compressed 16-bit instructions) | **Not implemented** |
| Zicsr (CSR instructions) | **Not implemented** |
| A (atomics), F/D (floating point) | **Not implemented** |
| Interrupts / full privilege levels | **Not implemented** |

The Spike reference model is configured as
`rv64i2p1_m2p0_a2p1_f2p2_d2p2_zicsr2p0_zifencei2p0_zmmul1p0`. Only
instructions the DUT actually executes are compared, so using a superset ISA
string in Spike is safe.

---

## Processor Overview

- **Data / address width**: 64-bit addressing, 32-bit fixed-width instructions.
- **Pipeline**: 5 stages — Fetch → Decode → Execute → Memory → Write-Back —
  with a dedicated pipeline register between every stage.
- **Register file**: 32 × 64-bit integer registers; synchronous write,
  asynchronous read.
- **Hazard handling**: RAW forwarding (EX/MEM and MEM/WB paths), load-use
  interlock, branch-misprediction flush.
- **Branch prediction**: BTB (4-way, 16 sets) + BHT (64-entry 2-bit saturating
  counters). Predictions resolved in Execute; mispredictions flush IF + ID.
- **I-cache**: direct-mapped, 16 blocks, 512-bit lines (parameterisable).
- **D-cache**: 4-way set-associative, 4 sets, 512-bit lines, write-back /
  write-allocate (parameterisable).
- **Memory interface**: AXI4-Lite master; cache lines transferred as
  `BLOCK_WIDTH / 32` 32-bit beats.
- **Performance counters**: hardware counters for cycles, retired instructions,
  stall cycles, I$/D$ hit/miss, and branch mispredictions; reported via DPI-C
  at end of simulation.

---

## Microarchitecture

### Pipeline Stage-by-Stage

**Fetch (IF)** — `rtl/fetch_stage.sv` drives the PC, consults the I-cache, and
asks the branch predictor for a next-PC override on taken branches / BTB hits.
The predicted target, direction, and BTB way flow down the pipeline so that
Execute can validate them and drive training updates back.

**Decode (ID)** — `rtl/decode_stage.sv` splits the 32-bit instruction into
fields via `instr_decoder`, derives ALU / memory / branch control signals from
`main_decoder` + `alu_decoder`, reads GPRs from `register_file`, and
sign-/zero-extends the immediate through `extend_imm`.

**Execute (EX)** — `rtl/execute_stage.sv` houses the 64-bit `alu`, a three-way
forwarding mux (no-forward / EX-MEM / MEM-WB), and branch resolution. A
misprediction detected here drives `branch_mispred_exec_o`, flushes IF + ID,
and retargets the PC.

**Memory (MEM)** — `rtl/memory_stage.sv` accesses the D-cache for loads and
stores. Store widths are encoded as `SB=00`, `SH=01`, `SW=10`, `SD=11`;
misaligned stores raise `store_addr_ma`. Loads are re-aligned and
sign-/zero-extended by `load_mux`.

**Write-Back (WB)** — `rtl/write_back_stage.sv` selects the result from ALU
output, load data, PC+4 (JAL/JALR), or immediate, then commits to the register
file. DPI-C hooks here drive Dromajo co-simulation, execution trace logging, and
the end-of-test self-check.

### Hazard, Forwarding, and Stall Logic

`rtl/hazard_unit.sv` centralises all pipeline-control policy:

- **RAW forwarding**: 2-bit select per source register — `10` forwards from
  EX/MEM, `01` from MEM/WB, `00` uses the register-file read. Both `rs1` and
  `rs2` are handled independently, prioritising the younger producer.
- **Load-use interlock**: when an EX-stage load's destination matches a
  Decode-stage source, IF/ID are stalled and a bubble is inserted into EX.
- **Branch-misprediction flush**: flushes ID and EX; the front-end is
  redirected to the correct target computed in EX.
- **Cache stalls**: `stall_cache_i` from the cache FSM freezes every pipeline
  stage during an I-cache or D-cache miss.

### Branch Prediction

`rtl/branch_pred_unit.sv` couples a Branch Target Buffer and a Branch History
Table so that taken branches and indirect jumps can be resolved in IF without
waiting for EX.

- **BTB** (`rtl/btb.sv`) — 4-way set-associative, 16 sets. Each entry stores a
  60-bit tag (branch instruction address), the 64-bit target, and a valid bit.
  The hit way is forwarded to EX so that training updates the correct entry.
- **BHT** (`rtl/bht.sv`) — 64-entry table of 2-bit saturating counters
  (`00` = strongly not-taken … `11` = strongly taken). Updated in EX; consulted
  in IF in parallel with the BTB lookup.
- **Resolution**: EX compares the predicted direction and target against the
  resolved values; a mismatch triggers a flush and a BTB/BHT training write.

### Caches and Memory Hierarchy

Both caches use a 512-bit refill line by default (configurable via `BLOCK_WIDTH`
at elaboration time).

- **I-cache** (`rtl/icache.sv`) — direct-mapped, 16 blocks; read-only from the
  pipeline's perspective; refilled by the cache FSM on a miss.
- **D-cache** (`rtl/dcache.sv`) — 4-way set-associative, write-back /
  write-allocate, with a dirty bit per way. An eviction of a dirty line
  transitions through `WRITE_BACK` before re-allocating.
- **Cache FSM** (`rtl/cache_fsm.sv`) — 4-state controller:
  `IDLE → ALLOCATE_I → IDLE`, `IDLE → ALLOCATE_D → IDLE`, and
  `IDLE → WRITE_BACK → ALLOCATE_D → IDLE`. D-cache misses take priority over
  I-cache misses.
- **Reconfigurability**: `run_tests.py -v` sweeps `BLOCK_WIDTH` (128–1024 b),
  `SET_COUNT` (2–16), and D-cache associativity (2–8-way) and records
  performance data for every combination.

### Performance Counters

`rtl/perf_counters.sv` accumulates eight 64-bit hardware counters that are
driven directly from pipeline signals in `rtl/top.sv`:

| Counter | Source signal |
|---|---|
| Cycle count | `clk_i` (every posedge after reset) |
| Retired instructions | `log_trace_wb` from `pipeline_reg_write_back` (1 pulse per commit) |
| Stall cycles | `stall_fetch_s` (whole pipeline stalled) |
| I$ hits | `icache_hit_s & ~stall_fetch_s` |
| I$ misses | Rising edge of `axi_read_start_icache_s` (one per fill) |
| D$ hits | `dcache_hit_s & mem_access_s` |
| D$ misses | Rising edge of `axi_read_start_dcache_s` (one per fill) |
| Branch mispredictions | `branch_mispred_exec_s` |

At simulation end, a `final` block in `perf_counters.sv` calls `report_perf()`
via DPI-C (`test/tb/report_perf.c`), which prints:

```
========== Performance Counters ==========
Cycles              : <n>
Instructions retired: <n>
Stall cycles        : <n>
I$ hits / misses    : <n> / <n>
D$ hits / misses    : <n> / <n>
Branch mispredicts  : <n>
------------------------------------------
CPI                 : <x.xxxx>
Pipeline CPI        : <x.xxxx>   ← (cycles - stalls) / instructions
I$ hit rate         : <xx.xx>%
D$ hit rate         : <xx.xx>%
==========================================
```

`run_tests.py` extracts Pipeline CPI, I$/D$ hit rates, and miss counts into
`results/perf_result.txt` alongside the existing branch-accuracy line.

### AXI4-Lite Memory Interface

- **Master**: `rtl/axi4_lite_master.sv`, split into
  `axi4_lite_master_read.sv` and `axi4_lite_master_write.sv`.
- **Slave**: matching read/write pair provided for simulation.
- **Widths**: 64-bit address, 32-bit data per beat. Cache lines are streamed as
  `BLOCK_WIDTH / 32` beats; `cache_data_transfer.sv` generates the beat counter
  and asserts `count_done` to close the transaction.
- **Memory model**: `rtl/mem_simulated.sv` loads the test image from a hex file
  and uses an 8-bit LFSR to generate pseudo-random per-word access latency
  (1–255 cycles), stress-testing the cache fill and stall logic.

---

## Repository Layout

```
rtl/                  SystemVerilog source — core, caches, AXI interface,
│                     performance counters
│   perf_counters.sv  Hardware performance counter module (DPI-C reporting)
test/tb/              Verilator testbench and DPI-C helpers
│   tb_test_env.cpp   Top-level testbench driver
│   check.c           Self-check and branch-accuracy DPI function
│   log_trace.c       Per-instruction trace DPI function
│   report_perf.c     Performance counter report DPI function
│   dromajo_cosim.cpp Dromajo per-instruction co-simulation
test/tests/           Prebuilt ELF binaries and test lists
scripts/              ELF→disasm, disasm→mem, Spike trace comparison helpers
tools/snippy/         Snippy config and test-generation script
results/              Auto-populated: result.txt, perf_result.txt
tests_perf_results.txt  Summary of all 188 tests with per-test metrics
run_tests.py          Top-level driver: verilate, build, simulate, grade
```

---

## Verification

Every test must satisfy two independent pass criteria: a *self-check* on
architectural end-state and a *trace-compare* against the Spike golden reference.
A run is only reported `PASS` when both agree.

### Test Sources

| Group | Count | Source | Description |
|---|---|---|---|
| `am` | 26 | [NJU-ProjectN/am-kernels](https://github.com/NJU-ProjectN/am-kernels) | Hand-written programs covering ISA corner cases and library routines |
| `rv-tests` | 57 | [riscv-software-src/riscv-tests](https://github.com/riscv-software-src/riscv-tests) | Per-instruction regression suite |
| `rv-arch-test` | 54 | [riscv/riscv-arch-test](https://github.com/riscv/riscv-arch-test) | Official RISC-V architectural compliance suite |
| `snippy` | 51 | [syntacore/snippy](https://github.com/syntacore/snippy) | 500-instruction random programs across 10 functions, full RV64IM histogram |

### Co-Simulation (Dromajo)

`test/tb/dromajo_cosim.cpp` steps the Dromajo instruction-accurate model in
lockstep with the RTL on every instruction retirement. A PC, instruction, or
write-data mismatch is flagged immediately, making it possible to pinpoint the
exact instruction where the DUT diverges from the ISA model.

### Trace-Compare (Spike)

`scripts/tracecomp.py` spawns Spike in commit-log mode on the same ELF, strips
interactive shell noise, and normalises each committed instruction into a
`PC / instruction / register write / memory access` record. `run_tests.py` then
diffs the RTL and Spike logs line-by-line; the first mismatch (up to ten lines)
is saved to `temp.txt`.

### Self-Check

`test/tb/check.c` is called once the simulation finishes:

- `a0 = 0` → PASS; `a0 = 1` → FAIL.
- `mcause`: `11`/`3` = normal `ECALL`/`EBREAK` exit; `2` = illegal instruction;
  `0`, `4`, `6` = instruction / load / store address-misaligned fault.
- Branch-predictor counters (`branch_total`, `branch_mispred`) are printed next
  to the verdict so predictor regressions are visible immediately.

Snippy tests have no fixed expected output, so their self-check is *Not
Applicable*; they rely on trace-compare and Dromajo co-simulation instead.

### Coverage

Re-verilate with coverage enabled and pass the coverage flags to any test run:

```bash
python3 run_tests.py -a --coverage-all    # line + toggle
python3 run_tests.py -g rv-tests -cl      # line only
python3 run_tests.py -s am-add -ct        # toggle only
```

Per-test `.dat` files are merged by `verilator_coverage` and annotated into
`coverage_annotated/`.

---

## Requirements

- Verilator (with `--trace` and `--coverage` support)
- RISC-V GNU toolchain
- Spike (`riscv-isa-sim`)
- Dromajo (built as `tools/dromajo/build/libdromajo_cosim.a`)
- Python 3, GCC, Make
