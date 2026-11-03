# PS2 function verification

This fork adds a small backend to GameFrame's existing `re-trace` → `re-emulate` →
`re-port` → `re-verify` workflow. It compares **behavior**, not compiled code bytes.
Original instructions execute under Unicorn; reconstructed code runs on the host.
`tools/verify/bitcompare.py` compares their resulting raw state without changes.

## NixOS setup

```sh
nix develop
python tests/test_ps2_emu.py
```

The flake pins Python, Unicorn and the native compiler, plus tools needed by the
upstream tests. No DOS installation, PS2 SDK or historical compiler is needed for
this backend. DOS and Windows support remain available upstream features.

## First run

Trace the function first: identify its bounds, inputs, memory layout and callees.
Choose an integer leaf routine for this backend. Keep original executables,
reconstructed game code, dumps and ground truth outside this public framework.
The ELF's SHA-256 is mandatory; wrong or missing inputs fail.

```python
import struct
import sys
sys.path.insert(0, 'tools/emu')
from ps2_emu import Emu

emu = Emu('/external/game.elf', 'the verified executable SHA-256')
emu.write(0x00800000, struct.pack('<I', 123))
# Substitute the traced function's actual bounds and arguments.
result = emu.call(start, end, 0x00800000)
state = emu.read(0x00800000, 4)
print(result, state.hex(), sorted(emu.written))
```

CPU state resets between calls. RAM persists: restore every input and any state
changed by the previous call, or use a fresh `Emu` per independent case. `written`
includes every byte written by the original during the last call. Compare all
relevant state, and reject unexpected writes outside the modeled objects.
`read_addresses` records data reads. Unspecified RAM starts zeroed; supply and
justify all state read by the function rather than treating those zeros as a
capture of a running game.
The CLI accepts one JSON case; `python tools/emu/ps2_emu.py --help` prints its format.

Run reconstructed C/C++ with a native compiler, or call a reconstruction in another
language. Give it the same inputs and serialize its state in the original layout.
Use the existing comparator:

```sh
python tools/verify/bitcompare.py u32 /external/expected.bin /external/actual.bin
```

Require a positive case count and the expected dump sizes. Include boundaries,
aliases and random inputs within the known caller domain. Also test a deliberately
incorrect reconstruction: the comparison must fail. Keep the input generator,
seed, input hash, candidate source, compiler command, backend revision, dependency
versions and outputs with the report. Label synthetic inputs as synthetic.

## Last Raven pilot

The first local experiment executes USA `SLUS_213.38`, SHA-256
`a2094bee85cbdf069d1c5afee39013e3dfd8633ef19972cbf1456e284c682dea`,
at `[0x001e9820, 0x001e9844)`. Its observed operations store an input word at a
counter-selected word slot, then increment the counter. The nominal purpose and
real caller domain remain unconfirmed.

10,000 synthetic states exercise indices 0–31, 32-bit input values and input aliases
to the destination or counter. Native C compiled with GCC `-O2` agrees on all
650,000 compared 32-bit words (the entire 256-byte object plus the external input
word per case). A counter-increment-by-two mutant differs in all 10,000 cases.
The existing GameFrame comparator accepts the candidate and rejects the mutant.
The void routine's unspecified return register is not compared.

Game-specific source, generator and raw reports stay in the external lr-og data
directory: `$HOME/.local/share/lr-og/persistent/game-frame/first-function/`.
`run.py FRAMEWORK ELF CANDIDATE_C OUTPUT_DIR` reproduces the experiment inside
`nix develop`; it reads the existing lr-og `main_001e9820.c` candidate. No compiler
byte comparison or historical compiler is used. This is agreement for these inputs,
not a proof for all inputs or a demonstration of running gameplay.

## Supported boundary

### SIF1 RAM data plane

`tools/emu/ps2_sif1_data.c` provides a bounded host-side copy for a caller that
already has a finite EE SIF1 REF/REFE tag stream in base-zero physical RAM. It
reads sequential, 16-byte-aligned EE tags, concatenates their QWC-sized source
segments, then parses 16-byte IOP headers and copies each declared payload to
the header's low-24-bit IOP destination. The payload byte count is
`(words & 0xffffc) * 4`. It accepts only REF (ID 3) tags followed by REFE (ID
0), aligned source/destination spans, exact 32 MiB EE and 2 MiB IOP buffers,
and at most 4096 tags and 65536 packets. Header counts with nonzero low two
bits are rejected. A stop marker (IRQ or ID bit 2) is allowed only on the last
packet, with no trailing stream bytes. A finite exactly consumed stream without
a stop marker is also accepted and reports `final_stop_requested == 0`.

The helper validates the complete chain, packet stream and all IOP destinations
before changing IOP RAM or the result structure. Its only success status is
`GF_PS2_SIF1_DATA_COPIED`: this reports a byte copy, not IOP transfer or device
completion. The caller must provide stable base-zero physical RAM buffers and
ensure SIF1 TTE is disabled. The helper does not model other DMA tag IDs,
MMIO, FIFO occupancy or timing, cache visibility, scheduling, syscalls,
interrupts, receiver execution or hardware behavior.

The support boundary follows the local PCSX2 v2.8.2 source at revision
`fd9d310ccbb6b8b62c976da8886a3c8fd3a10ff3`: `Sif1.cpp` reads REF/REFE
segments and IOP headers; `Hw.cpp` advances the selected chain tags; `Dmac.h`
defines TTE and tag fields. The implementation is an independent byte-stream
model, not copied emulator code. It deliberately leaves the timing and
interleaving behavior in `SIF1Dma` outside this API.

### DMA9/SIF0 synchronous launch

`tools/emu/ps2_sif0/` models one bounded synchronous source path for an IOP
DMA9 start while an EE SIF0 chain is already active. It reads live IOP DMA
descriptors and source words, moves words through the serialized SIF FIFO,
consumes embedded EE tags into direct EE RAM destinations, updates the modeled
DMA/channel fields, and schedules the selected IOP event. The public `launch`
call validates and stages every supplied state object before committing it, so
unsupported inputs leave those objects unchanged.

This is a source-qualified software model, not an emulator backend or a
physical-console guarantee. The synchronous path follows PCSX2 v2.8.2 at
revision `fd9d310ccbb6b8b62c976da8886a3c8fd3a10ff3`, chiefly `Sif0.cpp`,
`Sif.h`, `IopDma.cpp`, and the IOP hardware write path. It supports the stated
fixed IOP/EE RAM and hardware buffer sizes, direct RAM windows, a bounded
well-formed tag stream, and the documented scheduler state. Resumed/nonempty
channel states, wrapped memory spans, EE aliases or scratchpad destinations,
unsupported scheduler domains, and malformed or cyclic streams are refused.

Use `from tools.emu.ps2_sif0 import launch`, then call
`launch(iop_ram, iop_hw, ee_ram, ee_hw, sif0, scheduler, chcr=0x01000701)`.
The five distinct `bytearray` objects contain exactly 2 MiB IOP RAM, 64 KiB
IOP hardware registers, 32 MiB EE RAM, 64 KiB EE hardware registers and the
580-byte serialized SIF0 state from this source revision, respectively.
The scheduler dictionary requires integer `cycle`, `interrupt`, `event_start`,
`event_delta` and `next_event` fields: these are the IOP cycle, interrupt mask,
SIF0 event start/delay and next-event cycle. Cycles use unsigned 64-bit values,
the mask uses unsigned 32-bit values and the delay uses signed 32-bit values.
Optional `iop_cycle_ee` enables the bridge and requires `ee_cycle` and
`ee_next_event`; the former is signed 32-bit, while EE cycles are unsigned
64-bit. Supply authentic state for every included field. Unsupported native
conversion or overflow domains are refused.

A result has `status` equal to `completed` or `refused`. Successful calls mutate
the buffers and scheduler and return descriptor-derived `transfers` and a loop
count. Refused calls return a reason and preserve the inputs. The API accepts
only a started, PCR2-enabled DMA9, an empty FIFO and idle IOP channel, with an
already active EE chain. `python3 -m tools.emu.ps2_sif0 --help` prints API usage;
there is no standalone state-file format.

Other source files used to derive the scheduler bridge are `R3000A.cpp`,
`R3000A.h`, and `IopMem.h` from that same revision. The implementation is an
independent Python model; it does not include PCSX2 source. Its synthetic test
is run by `tests/run.sh` and can also be run directly with
`python3 tests/test_ps2_sif0_launch.py`.

The API stops when the synchronous launch has no more modeled progress. It
does not model concurrent execution, host scheduling or timing, later EE
completion and interrupt delivery, receiver code, graphics/audio/input, or
physical PS2 behavior. A completed call therefore means only that this bounded
source path was modeled; it does not mean that a hardware transfer or the
rest of the emulator completed. Synthetic checks are regressions for the
documented model, not gameplay evidence.

### IOP timer-5 COUNT read

`tools/emu/ps2_iop_timer.py` provides `read_timer5_count(state,
committed_cycle)`. It returns the low 32 bits of the timer count and a new
immutable `Timer5State`. The caller supplies the timer's current count, start
cycle, rate, complete mode word, current repeat/toggle behavior, and whether a
timer event needs processing. Inputs are validated before an updated state is
returned; unsupported calls raise `Unsupported` and leave the supplied state
unchanged.

This is a source-qualified arithmetic model of the simple timer-5 path in
PCSX2 v2.8.2, revision
`fd9d310ccbb6b8b62c976da8886a3c8fd3a10ff3`, chiefly
`pcsx2/IopCounters.cpp` functions `psxRcntSync` and `psxRcntRcount32`, with the
mode fields defined in `pcsx2/IopCounters.h`. It supports a running timer with
rate 1, prescale bits selecting rate 1, gate disabled, nondecreasing committed
cycle, and no due timer event. Elapsed cycles are first narrowed to unsigned
32 bits, then added to the unsigned 64-bit count and start cycle. The returned
count is narrowed to unsigned 32 bits. In repeat/pulsed mode the interrupt
enable bit is set even when the narrowed elapsed change is zero; other mode
bits and the remaining modeled fields are preserved.

The caller's `event_due=False` is an explicit precondition, not a scheduler
calculation. This helper does not determine whether an event is due, process
timer interrupts, emulate other rates or gate modes, update next-event timing,
or model the IOP timer device. The behavior is independently implemented; no
PCSX2 source is included. Synthetic boundary tests run by `tests/run.sh` and
directly with `python3 tests/test_ps2_iop_timer.py` are arithmetic regressions,
not evidence of gameplay behavior.

### Integer execution backend

`ps2_emu.py` loads little-endian ELF32 MIPS executable segments into 32 MiB of RAM.
Its default is the listed common MIPS32 integer subset: word arithmetic, shifts,
logic, comparisons, ordinary conditional branches, byte/halfword/word
loads/stores and `jr ra`. It also admits `DADDU` only when one source register is
`$zero`; this copies the modeled register value. In MIPS32 mode that is the low
word. In optional MIPS64 mode it is the full doubleword. This narrow `DADDU`
form is rejected in a delay slot in MIPS32 mode, where the backend must emulate
it. MIPS64 mode lets Unicorn execute the same restricted form natively, so its
scheduled delay-slot behavior is preserved. Other `DADDU` arithmetic is
unsupported. Other supported instructions in delay slots execute. Both modes
support at most four register arguments.

Pass `mode='mips64'` to `Emu` or add `--mips64` to the CLI to opt into Unicorn's
64-bit MIPS register model. This mode adds only `DSLL32`, `DSRL32`, `DADDIU` and
naturally aligned `LD`/`SD` accesses wholly inside the 32 MiB RAM mapping. The
loads and stores transfer a full 64-bit GPR value and use the sign-extended
16-bit address offset. Unicorn executes them natively, including when `SD` is
in a branch delay slot; an effective address that is unaligned or outside RAM
is rejected before execution. Around an `SD` delay slot, the backend briefly
disables Unicorn's write observer, which faults on some branch-to-control
sequences. It records that store from the same checked effective address and
restores the observer at the next instruction; Unicorn still executes the
branch and store. The shifts execute as 64-bit doubleword shifts
with shift amounts `32 + sa`. `DADDIU` sign-extends its 16-bit immediate and
performs a 64-bit addition without an integer-overflow trap. These instructions follow the
[MIPS64 instruction set reference](https://s3-eu-west-1.amazonaws.com/downloads-mips/documents/MD00087-2B-MIPS64BIS-AFP-05.04.pdf).
The mode also executes the admitted zero-source `DADDU` form natively. Other
doubleword loads/stores, arithmetic, MMI and 128-bit operations remain
unsupported. It returns a 64-bit
value and reports `return_u64` in CLI output, while retaining `return_u32` as its
low word. Inputs are full 64-bit register values in this mode. A 32-bit signed
argument must be passed sign-extended when the original caller does so; this
tool does not infer ABI extension rules.

Unicorn's generic MIPS CPU is **not a complete R5900/PS2 model**. The optional
mode uses MIPS64 semantics for the admitted shifts and aligned RAM doubleword
accesses; this is not evidence that
the generic CPU models all R5900 behavior. This backend does not support other
64/128-bit operations, MMI, FPU, VU, syscalls, callees, MMIO, interrupts, timing
or hardware side effects. Unsupported instructions, escaped control flow,
invalid accesses, timeouts and instruction-budget exhaustion fail; they never
become passing comparisons. The instruction allowlist is deliberately small,
not an automatic promise of PS2 equivalence for arbitrary input states.

Functions needing PS2-specific execution require an appropriate backend, such as
captures from a full PS2 emulator. Do not substitute generic IEEE floating point
or fabricated device results and describe those as original PS2 behavior. Keep
using GameFrame's tracing, state capture and output comparison strategy as the
execution backend expands.
