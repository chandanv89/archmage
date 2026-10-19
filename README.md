# Archmage

Guided Arch Linux installer for the official live ISO. It walks through the
[ArchWiki installation guide](https://wiki.archlinux.org/title/Installation_guide):
network setup, disk partitioning, mirrors, `pacstrap`, `genfstab`, system
configuration in `arch-chroot`, boot loader, and optional desktop profiles.

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
git clone https://github.com/YOUR_USER/archmage.git
cd archmage
chmod +x archmage
./archmage
```

Non-interactive:

```bash
./archmage --config examples/answers.json
```

Log file: `/var/log/archmage.log`. Resume state: `/var/lib/archmage/state.env`.

## What it does

| Phase | Actions |
|-------|---------|
| Live session | Keymap, boot mode (UEFI/BIOS), network check, clock sync |
| Disk | Guided GPT (UEFI) or MBR (BIOS): ESP + root (ext4 or btrfs), optional swap; manual `fdisk` path available |
| Install | `reflector` mirrorlist, `pacstrap` with kernel, firmware, microcode, NetworkManager, and profile packages |
| Target system | Locale, timezone, hostname, users, sudo, initramfs if needed |
| Boot | `systemd-boot` (UEFI default) or GRUB; enable display manager for chosen desktop |

Desktop choices (via `config/profiles.yaml`): none, KDE, GNOME, XFCE, Hyprland.
Pipewire and Bluetooth are optional during package selection.

Destructive disk steps require confirming `YES /dev/yourdisk`.

## CLI options

| Flag | Description |
|------|-------------|
| `--resume` | Continue from saved state |
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

## License

MIT - see [LICENSE](LICENSE).
