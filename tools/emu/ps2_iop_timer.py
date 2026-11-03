#!/usr/bin/env python3
"""Read the restricted PS2 IOP timer-5 counter value.

API: ``read_timer5_count(state, committed_cycle) -> (u32_value, new_state)``.
The caller supplies timer state and the committed IOP cycle. The input state is
immutable. Unsupported states raise ``Unsupported`` before returning any update.

This models only the simple timer-5 path described in
``docs/consoles/ps2-functions.md``: rate 1, gate disabled, running, with no
pending timer event to process. It is not an IOP, timer scheduler, or hardware
emulator. Source behavior is based on PCSX2 v2.8.2, local revision fd9d310,
``pcsx2/IopCounters.cpp`` (``psxRcntSync`` and ``psxRcntRcount32``).
"""

from dataclasses import dataclass, replace


U32_MASK = (1 << 32) - 1
U64_MASK = (1 << 64) - 1
MODE_GATE_ENABLE = 1 << 0
MODE_INTR_ENABLE = 1 << 10
MODE_RATE_MASK = 3 << 13
MODE_STOPPED = 1 << 15


class Unsupported(ValueError):
    """The timer state is outside this model's supported path."""


@dataclass(frozen=True)
class Timer5State:
    """Fields read or updated by the modeled timer-5 sync path.

    ``mode`` retains the complete 32-bit mode word so unmodified flags survive
    a read. ``event_due`` is the caller's explicit indication that timer event
    processing is required; this model refuses such a state.
    """

    count: int
    start_cycle: int
    rate: int
    mode: int
    current_repeat: bool = False
    current_toggle: bool = False
    event_due: bool = False


def _uint(name, value, maximum):
    if type(value) is not int or not 0 <= value <= maximum:
        raise Unsupported(f"{name} must be an integer in [0, {maximum}]")


def _bool(name, value):
    if type(value) is not bool:
        raise Unsupported(f"{name} must be bool")


def read_timer5_count(state, committed_cycle):
    """Return timer-5's low 32-bit count and a new synchronized state.

    ``change`` follows PCSX2's ``u32`` conversion after dividing elapsed
    cycles by the rate. The timer count and cycle accumulator then wrap as
    unsigned 64-bit fields; the returned register value wraps to 32 bits.

    Raises ``Unsupported`` without changing ``state`` for invalid values,
    rates other than 1, enabled gates, stopped timers, or a due event.
    """
    if type(state) is not Timer5State:
        raise Unsupported("state must be Timer5State")
    _uint("count", state.count, U64_MASK)
    _uint("start_cycle", state.start_cycle, U64_MASK)
    _uint("rate", state.rate, U32_MASK)
    _uint("mode", state.mode, U32_MASK)
    _uint("committed_cycle", committed_cycle, U64_MASK)
    _bool("current_repeat", state.current_repeat)
    _bool("current_toggle", state.current_toggle)
    _bool("event_due", state.event_due)

    if state.rate != 1:
        raise Unsupported("only timer rate 1 is modeled")
    if state.mode & MODE_RATE_MASK:
        raise Unsupported("mode prescale bits do not select rate 1")
    if state.mode & MODE_GATE_ENABLE:
        raise Unsupported("gate-enabled timers are not modeled")
    if state.mode & MODE_STOPPED:
        raise Unsupported("stopped timers are not modeled")
    if state.event_due:
        raise Unsupported("timer event processing is outside this model")
    if committed_cycle < state.start_cycle:
        raise Unsupported("committed cycle precedes timer start cycle")

    # IopCounters.cpp: psxRcntSync stores the quotient in u32 before adding it.
    change = (committed_cycle - state.start_cycle) & U32_MASK
    new_count = (state.count + change) & U64_MASK
    new_start = (state.start_cycle + change) & U64_MASK
    new_mode = state.mode
    if state.current_repeat and not state.current_toggle:
        new_mode |= MODE_INTR_ENABLE

    updated = replace(state, count=new_count, start_cycle=new_start, mode=new_mode)
    return new_count & U32_MASK, updated
