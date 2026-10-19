# Archmage

Opinionated, menu-driven helper for a **typical** Arch Linux install from the
official live ISO. It automates a subset of steps described on the
[ArchWiki installation guide](https://wiki.archlinux.org/title/Installation_guide)
so you do not have to type every command by hand.

**Archmage is not a general-purpose or official installer.** It encodes fixed
choices that work for many laptops, VMs, and simple desktops. If you need
encryption, RAID, Btrfs subvolumes, dual-boot, custom partitioning, a window
manager not listed here, corporate policies, or anything non-standard, use the
[installation guide](https://wiki.archlinux.org/title/Installation_guide) and
related ArchWiki articles and install manually.

## What Archmage does (exactly)

Archmage runs **only** on the live environment as root. It does **not** replace
reading the wiki; it runs a fixed pipeline with prompts and writes state under
`/var/lib/archmage`.

| Area | What Archmage implements |
|------|---------------------------|
| Firmware | Detects UEFI vs BIOS; UEFI gets a 1 GiB ESP + root; BIOS gets MBR + root |
| Filesystems | **ext4** or **btrfs** on a single root partition; optional **4 GiB swap** partition |
| Disk layout | One target disk, guided `sfdisk` (or optional manual `fdisk` path); wipes after `YES /dev/disk` |
| Packages | Fixed `base` set in `config/profiles.yaml` plus one kernel (`linux` / `linux-lts` / `linux-zen`), Intel/AMD microcode when detected, **GRUB** (BIOS or UEFI) or **systemd-boot** (UEFI only), NetworkManager, sudo, reflector mirror refresh |
| Users | Root + one normal user (passwords), `wheel` in sudoers, hostname, locale/timezone/keymap from menus |
| Desktop (optional) | Preset package lists only: **none**, **KDE**, **GNOME**, **XFCE**, **Hyprland**; optional Pipewire and Bluetooth |
| Boot | Installs bootloader to the disk you selected; enables display manager only when the profile defines one (Hyprland uses seatd, no DM by default) |

What it **does not** do: disk encryption (LUKS), LVM, ZFS, dual-boot with Windows,
custom mkinitcpio hooks, secure boot, arbitrary package lists, full disk
inventory beyond a numbered `lsblk` menu, or validation of every possible
keymap/locale (menus cover common values; "Other" is best-effort).

For anything outside this table, follow the
[ArchWiki](https://wiki.archlinux.org/) and treat Archmage as a reference or
starting point (`--dry-run`, logs, `exported-answers.json`), not the final word.

## Prerequisites

| | |
|--|--|
| **Required** | Official [Arch Linux live ISO](https://archlinux.org/download/), root shell, working network before `pacstrap` (and before installing extra packages below). Secure Boot disabled. |
| **On the ISO (checked at start)** | `pacstrap`, `arch-chroot`, `genfstab`, `lsblk`, `sfdisk`, `mkfs.ext4`, `mount`, `ping` |
| **Installed when needed** | `reflector` (mirror step), `jq` (`--config` JSON). On the live ISO, Archmage runs `pacman -Sy --needed` for these if they are missing. With `--config`, `jq` is installed automatically when possible. Otherwise you are prompted; decline and you must install manually, then re-run. |
| **Wi-Fi setup** | `iwctl` from package `iwd` (usually on the ISO; same install prompt if missing) |
| **Optional** | `dialog` (nicer menus; text menus work without it), `jq` (also used to write `state.json` when resuming) |

Manual install (live shell):

```bash
pacman -Sy --needed reflector jq dialog
```

`--config` needs network up first so `pacman` can fetch `jq`.

## Usage

```bash
git clone https://github.com/chandanv89/archmage.git
cd archmage
chmod +x archmage
./archmage
```

Non-interactive:

```bash
./archmage --config examples/answers.json
```

Log file: `/var/log/archmage.log`. Resume state: `/var/lib/archmage/state.env`.

### Logs and config files

| What | Path |
|------|------|
| Install log (every run appends here) | `/var/log/archmage.log` |
| Saved wizard state | `/var/lib/archmage/state.env` |
| Same state as JSON (when `jq` is installed) | `/var/lib/archmage/state.json` |
| Answers template after a run or dry-run | `/var/lib/archmage/exported-answers.json` |
| Desktop/package profiles (shipped with Archmage) | `config/profiles.yaml` in the repo |
| Input for `--config` | `examples/answers.json` (or your own JSON) |

Dry-run does **not** create a separate config file by itself; it still updates state and the log. At the end of a full run (including `--dry-run`), Archmage writes `exported-answers.json` from your choices (passwords are **not** stored; add `root_password` / `user_password` before reusing as `--config`).

```bash
./archmage --show-paths
./archmage --export-config /root/my-answers.json   # from current state only, no install steps
tail -f /var/log/archmage.log
```

From another machine (SSH), copy artifacts off the live ISO:

```bash
scp root@VM_IP:/var/log/archmage.log .
scp root@VM_IP:/var/lib/archmage/state.json .
scp root@VM_IP:/var/lib/archmage/exported-answers.json .
```

If a step failed and you want a clean run (not `--resume` / `--from-step`), clear state first:

```bash
./archmage --reset
```

## Install steps (wizard order)

| Step | Actions |
|------|---------|
| Live session | Keymap and console font menus, boot mode detection, network check, NTP |
| Disk | Numbered disk list; guided partition + format; confirm with `YES /dev/yourdisk` |
| Install | Mirror country menu + `reflector`; `pacstrap` from `profiles.yaml` |
| Target system | Locale/timezone menus, hostname, users, `genfstab`, `arch-chroot` setup |
| Boot / desktop | Bootloader install; enable DM or Hyprland seatd when applicable |

Package and desktop presets are defined in `config/profiles.yaml` only; edit that
file if you need to tweak the **opinionated** package set (advanced).

## CLI options

| Flag | Description |
|------|-------------|
| `--resume` | Continue from saved state |
| `--reset` | Delete saved state and run from the first step (use after a failed run) |
| `--show-paths` | Print paths to log, state, profiles, and examples |
| `--export-config [FILE]` | Write `exported-answers.json` from saved state and exit |
| `--dry-run` | Print planned commands; skip format, pacstrap, and chroot changes |
| `--config FILE` | Load answers from JSON (see `examples/answers.json`) |
| `--from-step ID` | Start at a given step |
| `--only-step ID` | Run a single step |
| `-h`, `--help` | Show help |

**Step IDs:** `preflight`, `live_keyboard`, `network`, `clock`, `disk`, `mount`,
`mirrors`, `pacstrap`, `fstab`, `chroot_configure`, `bootloader`, `desktop`, `finish`.

## Environment variables

| Variable | Description |
|----------|-------------|
| `ARCHMAGE_STATE_DIR` | State directory (default `/var/lib/archmage`) |
| `ARCHMAGE_LOG` | Log path (default `/var/log/archmage.log`) |
| `ARCHMAGE_MNT` | Install mount point (default `/mnt`) |
| `ARCHMAGE_NO_BANNER` | Short header instead of the full logo |
| `ARCHMAGE_NO_CLEAR` | Do not clear the screen before the banner |
| `NO_COLOR` | Disable ANSI colors |
| `ARCHMAGE_VERBOSE` | Set to `1` to show INFO logs and command output on the terminal (default: log file only) |

## License

MIT - see [LICENSE](LICENSE).
