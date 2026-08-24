# bc250fc — Fan Control for the AMD BC-250

Ready-to-run software fan control for the [AMD BC-250](https://github.com/elektricM/amd-bc250-docs) board: a temperature-based fan curve daemon plus a small CLI for manual control of **every fan output the board has** — the CPU_FAN1 header and all five fan pins of the J4003 multi-fan header. No GUI required, works over SSH.

The fans are driven by a Nuvoton NCT6686D Super I/O chip. The in-kernel `nct6683` driver can only *read* sensors — to *write* PWM you need the out-of-tree [`nct6687`](https://github.com/Fred78290/nct6687d) driver. This repo wires the whole chain up for you: driver build → module loading → curve daemon → manual override CLI.

> Full documentation lives in the [Fan Control guide](https://elektricm.github.io/amd-bc250-docs/system/fan-control/) of the AMD BC250 Documentation project.

## Distro support

| Distro | Status | Notes |
|--------|--------|-------|
| Alpine Linux | ✅ verified on hardware | OpenRC service, tested end-to-end |
| Debian / Ubuntu | ✅ supported | installs `linux-headers-amd64`, systemd |
| Fedora / Bazzite* | ✅ supported | installs `kernel-devel`, systemd |
| Arch / CachyOS / Manjaro | ✅ supported | installs `linux-headers`, systemd |

\* immutable Bazzite images need the [nct6687 workarounds](https://elektricm.github.io/amd-bc250-docs/system/sensors.md/#immutable-atomic-distros-bazzite-silverblue-fedora-coreos) from the BC250 docs (read-only `/usr/lib/modules`).

## What you get

| File | Purpose |
|------|---------|
| `scripts/bc250-fan-curve` | Daemon: maps GPU edge temperature → CPU_FAN1 PWM every 2 s, with a 95 °C+ full-speed emergency override |
| `scripts/fan` | CLI: `fan 60` (CPU_FAN1 to 60 %), `fan 3 40` (J4003 channel 3 to 40 %), `fan status`, `fan auto` |
| `init/bc250-fan-curve.openrc` | OpenRC service (Alpine, Gentoo) |
| `init/bc250-fan-curve.service` | systemd unit (Fedora, Bazzite, Arch, Debian, ...) |
| `install.sh` | One-shot setup: installs build deps with your package manager, builds/loads `nct6687`, makes it persistent, installs scripts + service |

## Requirements

- AMD BC-250 board running Linux, root access (`doas` or `sudo`)
- The `nct6687` driver — `install.sh` builds it automatically if the kernel does not ship it (needs `git`, `make`, `gcc` and kernel headers, which it installs for you)
- `lm-sensors` recommended for a human-readable view (installed by `install.sh` when missing)

## Install

```sh
git clone https://github.com/Naster17/bc250fc.git
cd bc250fc
sudo sh install.sh          # or: doas sh install.sh
```

That's it. The daemon starts immediately and at boot. Verify:

```sh
fan status
# gpu edge : 48 C
# pwm2 (CPU_FAN1 ): 110/255 (43%)  rpm=2357   enable=1
# pwm1 (J4003 fan):   0/255 ( 0%)  rpm=0      enable=1
# ...
# mode: curve daemon running (pwm2)
```

## Usage

```sh
doas fan 95        # CPU_FAN1 to 95% — automatically stops the curve daemon
doas fan 40        # quiet mode
doas fan status    # all channels: PWM / RPM / mode
doas fan auto      # hand CPU_FAN1 back to the curve daemon
doas fan 3 60      # J4003 fan on channel 3 to 60%
```

Watch it live:

```sh
watch -n 1 'fan status'
```

## Fan channels on the board

The NCT6686D exposes 8 PWM channels; on the BC-250 five of them are wired:

| Channel | Connected to | Notes |
|---------|--------------|-------|
| `pwm2` | **CPU_FAN1** (4-pin header) | the main fan, managed by the curve daemon |
| `pwm1` | J4003 fan pin | "BIOS fan 5" |
| `pwm3` | J4003 fan pin | "BIOS fan 2" |
| `pwm4` | J4003 fan pin | "BIOS fan 3" |
| `pwm5` | J4003 fan pin | "BIOS fan 4" |
| `pwm6`–`pwm8` | not wired on this board | accept mode changes but don't hold a duty cycle |

All five wired channels were verified to accept and hold manual PWM values under Linux with the `nct6687` driver — the full J4003 header is usable for chassis fans. RPM feedback (`fanX_input`) only shows on channels with a fan connected. See [Pinouts](https://elektricm.github.io/amd-bc250-docs/hardware/pinouts/) for the physical pin map.

## How the fan curve works

The daemon reads the **GPU edge temperature** (the hottest and most load-sensitive sensor on the board — under LLM inference or gaming it tracks the silicon much better than the CPU socket sensor) and applies this curve to CPU_FAN1:

| GPU edge temp | PWM | ≈ Fan speed |
|---------------|-----|-------------|
| < 40 °C | 90 | ~35 % |
| 40–49 °C | 110 | ~43 % |
| 50–59 °C | 140 | ~55 % |
| 60–69 °C | 175 | ~69 % |
| 70–79 °C | 215 | ~84 % |
| ≥ 80 °C | 255 | 100 % |

A hard safety net forces 100 % above 95 °C regardless of the curve. J4003 channels are left at whatever you set manually — the daemon does not touch them.

### Tuning the curve

Edit `curve()` in `/usr/local/bin/bc250-fan-curve` (or `scripts/bc250-fan-curve` in this repo) — left side is the temperature threshold, right side the PWM duty (0–255). Then restart:

```sh
sudo rc-service bc250-fan-curve restart   # Alpine/OpenRC
sudo systemctl restart bc250-fan-curve    # systemd distros
```

Keep the `else` branch (the ≥ 80 °C ramp) at 255 — it is the safety path.

## Verified behavior

Tested on an ASRock Rack BC-250, Alpine Linux, kernel 7.0.10, with a 4-wire PWM fan on CPU_FAN1:

| PWM | Measured RPM |
|-----|--------------|
| 255 | ~4300 |
| 128 | ~2600 |
| 64 | ~1640 |

PWM duty does **not** survive a reboot by itself — that is what the daemon service is for. The BIOS fan mode is bypassed entirely once `nct6687` takes the channel; if you later want BIOS control back, unload the module (`rmmod nct6687`).

## Troubleshooting

- **`error: nct6686 hwmon not found`** — the `nct6687` module is not loaded. Check `lsmod | grep nct6687` and `dmesg | tail`. Remember it needs `force=true`.
- **`nct6683` and `nct6687` must never be loaded together** — they fight over the same chip. `install.sh` blacklists `nct6683`.
- **Fedora: "kernel headers not found"** — the running kernel and `kernel-devel` must match: `sudo dnf install kernel-devel-$(uname -r)`. After a kernel update, rebuild the module (rerun `install.sh`).
- **Fan ignores manual PWM** — make sure the curve daemon is stopped (`fan 60` does this for you) and `pwmX_enable` is `1`.
- **PWM resets after suspend/resume** — restart the service, or add it to your resume hooks.
- More board-specific issues: [AMD BC250 Documentation — Troubleshooting](https://elektricm.github.io/amd-bc250-docs/troubleshooting/boot/).

## License

MIT. The `nct6687` driver itself is licensed by its author ([Fred78290/nct6687d](https://github.com/Fred78290/nct6687d)).
