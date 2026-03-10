# ESP32 Firmware Testing

## Goal

Validate parser stability and rendering safety for long-running serial traffic.

## Minimal host-side harness (recommended)

1. Extract parser functions into a host-compiled translation unit (or compile the sketch with Arduino host mocks).
2. Feed line-based fixtures (UTF-8 text) that mirror real app traffic.
3. Assert resulting state after each line.

## Golden input suites

Create and replay these fixture groups:

- `fixtures/normal-session.txt`: typical route/time/pomo/tasks/habits/game updates.
- `fixtures/noisy-session.txt`: unknown commands, malformed payloads, empty fields.
- `fixtures/overflow-session.txt`: lines longer than `RX_LINE_MAX` to verify discard-until-newline behavior.

## Assertions to enforce

- No parser crash on malformed or oversized lines.
- `RX overflow` handling discards remainder of the line and recovers on next newline.
- Bounded string fields remain within expected limits.
- State transitions only happen for valid commands.

## Manual smoke test on device

- Run firmware for >=30 minutes with continuous serial updates at 115200 baud.
- Verify UI remains responsive and does not degrade after repeated long titles/hints.
- Monitor serial debug output for repeated overflow storms.
