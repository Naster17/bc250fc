# Changelog

## 0.2.1 - 2026-11-10

- Add a sticky CLI override record at `/run/bc250-fan/cli`. The daemon reads it
  before the shared control file, so `doas fan 100` can no longer be erased by
  a fresh Decky heartbeat.
- `fan auto` leaves a sticky auto CLI record; the Decky plugin backend yields
  and stays disabled until it is explicitly enabled again.
- The plugin's enable path removes the CLI record and claims control back.

## 0.2.0 - 2026-11-10

- Make `bc250-fan-curve` the single writer of CPU_FAN1 (`pwm2`).
- Add `/run/bc250-fan/control` arbiter for manual/automatic requests.
- `fan <percent>` and `fan auto` now update the control file instead of
  stopping/starting the daemon; J4003 channels remain direct writes.
- Add `source=decky` heartbeat with a 5 second fail-safe timeout.
- Add runtime-directory setup to the OpenRC and systemd units.
- Document the Steam Headless BC-250 `fantastic-bc250` Decky plugin and the
  shared control protocol.
