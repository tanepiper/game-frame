"""Synthetic boundary tests for the restricted IOP timer-5 count model."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools" / "emu"))
from ps2_iop_timer import (  # noqa: E402
    MODE_GATE_ENABLE,
    MODE_INTR_ENABLE,
    MODE_RATE_MASK,
    MODE_STOPPED,
    U32_MASK,
    U64_MASK,
    Timer5State,
    Unsupported,
    read_timer5_count,
)


class Timer5CountTests(unittest.TestCase):
    def state(self, **changes):
        values = dict(count=7, start_cycle=100, rate=1, mode=0)
        values.update(changes)
        return Timer5State(**values)

    def test_simple_running_read_advances_count_and_cycle(self):
        state = self.state(count=0x1234, start_cycle=100)
        value, updated = read_timer5_count(state, 137)
        self.assertEqual(value, 0x1259)
        self.assertEqual(updated, self.state(count=0x1259, start_cycle=137))
        self.assertEqual(state, self.state(count=0x1234, start_cycle=100))

    def test_elapsed_delta_is_truncated_to_u32(self):
        for delta, applied in ((U32_MASK, U32_MASK), (1 << 32, 0), ((1 << 32) + 1, 1)):
            with self.subTest(delta=delta):
                state = self.state(count=0x20, start_cycle=3)
                value, updated = read_timer5_count(state, 3 + delta)
                self.assertEqual(updated.count, 0x20 + applied)
                self.assertEqual(updated.start_cycle, 3 + applied)
                self.assertEqual(value, (0x20 + applied) & U32_MASK)

    def test_count_add_wraps_u64_and_return_wraps_u32(self):
        state = self.state(count=U64_MASK - 0x0F, start_cycle=0)
        value, updated = read_timer5_count(state, 0x20)
        self.assertEqual(updated.count, 0x10)
        self.assertEqual(value, 0x10)

    def test_start_cycle_near_u64_limit_remains_bounded(self):
        state = self.state(count=0, start_cycle=U64_MASK - 1)
        value, updated = read_timer5_count(state, U64_MASK)
        self.assertEqual(value, 1)
        self.assertEqual(updated.start_cycle, U64_MASK)

    def test_intr_enable_repeat_pulsed_semantics_preserve_other_mode_bits(self):
        unrelated = (1 << 20) | (1 << 7)
        state = self.state(mode=unrelated, current_repeat=True, current_toggle=False)
        _, updated = read_timer5_count(state, 100)
        self.assertEqual(updated.mode, unrelated | MODE_INTR_ENABLE)
        self.assertEqual(updated.rate, state.rate)
        self.assertEqual(updated.current_repeat, state.current_repeat)
        self.assertEqual(updated.current_toggle, state.current_toggle)
        self.assertEqual(updated.event_due, state.event_due)

        toggle = self.state(mode=unrelated, current_repeat=True, current_toggle=True)
        _, updated_toggle = read_timer5_count(toggle, 100)
        self.assertEqual(updated_toggle.mode, unrelated)

    def test_intr_enable_may_change_when_delta_truncates_to_zero(self):
        state = self.state(current_repeat=True, current_toggle=False)
        _, updated = read_timer5_count(state, 100 + (1 << 32))
        self.assertEqual(updated.count, state.count)
        self.assertEqual(updated.start_cycle, state.start_cycle)
        self.assertTrue(updated.mode & MODE_INTR_ENABLE)

    def test_refuses_unsupported_timer_modes_without_mutation(self):
        cases = (
            self.state(rate=8),
            self.state(mode=MODE_RATE_MASK & (1 << 13)),
            self.state(mode=MODE_GATE_ENABLE),
            self.state(mode=MODE_STOPPED),
            self.state(event_due=True),
        )
        for state in cases:
            with self.subTest(state=state):
                before = state
                with self.assertRaises(Unsupported):
                    read_timer5_count(state, 101)
                self.assertIs(state, before)

    def test_refuses_clock_regression_without_mutation(self):
        state = self.state(start_cycle=101)
        with self.assertRaises(Unsupported):
            read_timer5_count(state, 100)
        self.assertEqual(state.start_cycle, 101)

    def test_rejects_noncanonical_boolean_values_without_mutation(self):
        for kwargs in ({"current_repeat": 0}, {"current_toggle": 1}, {"event_due": 0}):
            with self.subTest(kwargs=kwargs):
                state = self.state(**kwargs)
                with self.assertRaises(Unsupported):
                    read_timer5_count(state, 101)
                self.assertEqual(state, self.state(**kwargs))

    def test_rejects_wrong_types_and_out_of_range_values(self):
        invalid = (
            (self.state(count=True), 101),
            (self.state(start_cycle=-1), 101),
            (self.state(mode=1 << 32), 101),
            (self.state(rate=True), 101),
            (self.state(current_repeat=1), 101),
            (self.state(), True),
            (self.state(), 1 << 64),
            (object(), 101),
        )
        for state, cycle in invalid:
            with self.subTest(state=state, cycle=cycle):
                with self.assertRaises(Unsupported):
                    read_timer5_count(state, cycle)


if __name__ == "__main__":
    unittest.main()
