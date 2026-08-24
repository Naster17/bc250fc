# bc250fc — Fan Control for the AMD BC-250

Ready-to-run software fan control for the [AMD BC-250](https://github.com/elektricM/amd-bc250-docs) board: a temperature-based fan curve daemon plus a small CLI for manual control. No GUI required, works over SSH, tested on Alpine Linux.

The board's only fan header (**CPU_FAN1**) is driven by a Nuvoton NCT6686D Super I/O chip. The in-kernel `nct6683` driver can only *read* sensors — to *write* PWM you need the out-of-tree [`nct6687`](https://github.com/Fred78290/nct6687d) driver. This repo wires the whole chain up for you: driver build → module loading → curve daemon → manual override CLI.

> Full documentation lives in the [Fan Control guide](https://elektricm.github.io/amd-bc250-docs/system/fan-control/) of the AMD BC250 Documentation project.

## What you get

| File | Purpose |
|------|---------|
| `scripts/bc250-fan-curve` | Daemon: maps GPU edge temperature → PWM duty every 2 s, with a 95 °C+ full-speed emergency override |
| `scripts/fan` | CLI: `fan 60` (60 % speed), `fan status`, `fan auto` (back to the curve) |
| `init/bc250-fan-curve.openrc` | OpenRC service (Alpine, Gentoo) |
| `init/bc250-fan-curve.service` | systemd unit (Fedora, Bazzite, Arch, ...) |
| `install.sh` | One-shot setup: builds/loads `nct6687`, makes it persistent, installs scripts + service |

## Requirements

- AMD BC-250 board running Linux, root access (`doas` or `sudo`)
- The `nct6687` driver — `install.sh` builds it automatically if the kernel does not ship it (needs `git`, `make`, `gcc` and kernel headers)
- `lm-sensors` recommended for a human-readable view: `apk add lm-sensors` / `dnf install lm_sensors` / `pacman -S lm_sensors`

## Install

```sh
git clone https://github.com/Naster17/bc250fc.git
cd bc250fc
doas sh install.sh
```

That's it. The daemon starts immediately and at boot. Verify:

```sh
fan status
# gpu edge : 48 C
# pwm      : 110/255 (43%)
# rpm      : 2357
# mode     : enable=1 (curve daemon running)
```

## Usage

```sh
doas fan 95      # 95% speed — automatically stops the curve daemon
doas fan 40      # quiet mode
doas fan status  # temperature / PWM / RPM / mode
doas fan auto    # hand control back to the curve daemon
```

Watch it live:

```sh
watch -n 1 'fan status'
```

## How the fan curve works

The daemon reads the **GPU edge temperature** (the hottest and most load-sensitive sensor on the board — under LLM inference or gaming it tracks the silicon much better than the CPU socket sensor) and applies this curve:

| GPU edge temp | PWM | ≈ Fan speed |
|---------------|-----|-------------|
| < 40 °C | 90 | ~35 % |
| 40–49 °C | 110 | ~43 % |
| 50–59 °C | 140 | ~55 % |
| 60–69 °C | 175 | ~69 % |
| 70–79 °C | 215 | ~84 % |
| ≥ 80 °C | 255 | 100 % |

A hard safety net forces 100 % above 95 °C regardless of the curve.

### Tuning the curve

Edit `curve()` in `/usr/local/bin/bc250-fan-curve` (or `scripts/bc250-fan-curve` in this repo) — left side is the temperature threshold, right side the PWM duty (0–255). Then restart:

```sh
doas rc-service bc250-fan-curve restart   # Alpine/OpenRC
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
- **Fan ignores manual PWM** — make sure the curve daemon is stopped (`fan 60` does this for you) and `pwm2_enable` is `1`.
- **PWM resets after suspend/resume** — restart the service, or add it to your resume hooks.
- More board-specific issues: [AMD BC250 Documentation — Troubleshooting](https://elektricm.github.io/amd-bc250-docs/troubleshooting/boot/).

## License

MIT. The `nct6687` driver itself is licensed by its author ([Fred78290/nct6687d](https://github.com/Fred78290/nct6687d)).
