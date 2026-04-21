# 🐧 Debian 13 Live USB Creator (with Persistence)

An interactive, automated bash script to create a highly compatible Debian 13 (or newer) Live USB drive with a persistent storage partition. 

Unlike simple tools like `dd` or BalenaEtcher that write a read-only ISO9660 filesystem, this script builds a proper GPT (GUID Partition Table) layout from scratch. This allows the remaining space on your USB drive (even up to 2TB) to act as persistent overlay storage, so files, packages, and settings survive reboots.

## ✨ Features

- **True Multi-Boot Support:** Installs GRUB for both modern UEFI systems and legacy BIOS systems automatically.
- **Dynamic Partitioning:** Automatically calculates exact partition boundaries based on user input, ensuring maximum use of available drive space.
- **Robust Pathing:** Detects partition naming schemes correctly across standard USBs (`/dev/sdb`), NVMe drives (`/dev/nvme0n1`), and SD cards (`/dev/mmcblk0`).
- **Fail-safe Design:** Utilizes `set -e` and bash traps to ensure all temporary mount points are cleanly unmounted and synced if the script is interrupted (e.g., via `Ctrl+C`).
- **No External Dependencies for Renaming:** Uses native bash string manipulation to rename bootloader configurations (isolinux -> syslinux) without relying on Perl-based `rename` tools.

## 🛠 Prerequisites

This script is designed to be run from an existing Linux environment (Debian/Ubuntu recommended). It requires `root` privileges.

Ensure the following standard system utilities are installed:
```bash
sudo apt update
sudo apt install parted e2fsprogs dosfstools grub-pc-bin grub-efi-amd64-bin rsync
```

You will also need a **Debian Live ISO**. You can download the latest Debian Cinnamon Live ISO (or your preferred desktop environment) from the [official Debian website](https://www.debian.org/CD/live/).

## 🚀 Usage Instructions

1. **Clone or download the script:**
   ```bash
   git clone https://github.com/yourusername/debian-live-usb-persistence.git
   cd debian-live-usb-persistence
   ```

2. **Make the script executable:**
   ```bash
   chmod +x make-debian-usb-live-with-persistence.sh
   ```

3. **Run the script as root:**
   ```bash
   sudo ./make-debian-usb-live-with-persistence.sh
   ```

4. **Follow the interactive prompts:**
   - Provide the exact file path to your `.iso`.
   - Select your target USB drive (e.g., `/dev/sdb`). **⚠️ Ensure this is correct, as all data will be destroyed.**
   - Confirm or adjust the sizes for the BIOS, EFI, and LIVE partitions. (The script defaults work perfectly for a standard Debian 13 Cinnamon ISO). 
   - Type `YES` to confirm formatting.

## 💽 Partition Layout Explained

The script converts your drive to GPT and creates the following 4-partition layout:

| # | Label | Type | Size (Default) | Flag | Purpose |
|---|---|---|---|---|---|
| **1** | `biosboot` | unformatted | 4 MiB | `bios_grub` | Embedded space for legacy BIOS GRUB (`core.img`). Fixes the "blocklists unreliable" error. |
| **2** | `EFI` | FAT32 | 500 MiB | `esp` | Stores the UEFI bootloader (`BOOTX64.EFI`) for modern motherboards. |
| **3** | `LIVE` | FAT32 | ~6.5 GiB | `legacy_boot` | Holds the extracted, read-only contents of the Debian Live ISO. |
| **4** | `persistence` | ext4 | 100% of rest | None | The overlay filesystem. Debian Live automatically detects the label `persistence` and uses the `persistence.conf` file to save state here. |

## ⚠️ Important Warnings

- **Drive Erase:** This script uses `wipefs -a` to completely obliterate existing partition tables and magic signatures. It *will* destroy all data on the target drive. Double-check your drive letter using `lsblk` before proceeding.
- **Progress Pauses:** The script uses `rsync --info=progress2` to copy the ISO contents, which provides a nice progress bar. However, the subsequent `sync` command may take a minute or two to flush the memory buffer to the physical USB drive. **Do not unplug the drive early.**

## 📄 License

MIT License. See `LICENSE` for more information. Contributions and pull requests are welcome!
