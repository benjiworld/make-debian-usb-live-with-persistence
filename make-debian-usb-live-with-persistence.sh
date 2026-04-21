#!/usr/bin/env bash
set -e

# ==========================================
# Debian 13 Live USB Persistence Setup Script
# ==========================================

# Colors for output
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Debian 13 Live USB Creator with Persistence ===${NC}\n"

# 1. Root Check
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (use sudo).${NC}" 
   exit 1
fi

# 2. Dependency Check
DEPENDENCIES=(parted mkfs.vfat mkfs.ext4 wipefs grub-install sed rsync)
for cmd in "${DEPENDENCIES[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}Error: Required command '$cmd' is not installed.${NC}"
        echo "Please run: apt install parted e2fsprogs dosfstools grub-pc-bin grub-efi-amd64-bin rsync"
        exit 1
    fi
done

# 3. Interactive Inputs
read -e -p "Enter path to the Debian Live ISO: " ISO_PATH
if [[ ! -f "$ISO_PATH" ]]; then
    echo -e "${RED}Error: ISO file not found!${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Available drives:${NC}"
lsblk -d -p -o NAME,SIZE,MODEL | grep -v "loop"

echo ""
read -p "Enter target USB drive path (e.g., /dev/sdb): " DRIVE
if [[ ! -b "$DRIVE" ]]; then
    echo -e "${RED}Error: Drive $DRIVE is not a valid block device!${NC}"
    exit 1
fi

# Partition Size Inputs (in MiB)
echo -e "\n${YELLOW}--- Partition Dimensions (in MiB) ---${NC}"
read -p "1. BIOS Boot partition size [Default: 4]: " BIOS_SIZE
BIOS_SIZE=${BIOS_SIZE:-4}

read -p "2. EFI partition size [Default: 500]: " EFI_SIZE
EFI_SIZE=${EFI_SIZE:-500}

read -p "3. LIVE OS partition size (needs ~6000 for Cinnamon) [Default: 6500]: " LIVE_SIZE
LIVE_SIZE=${LIVE_SIZE:-6500}

echo -e "4. Persistence partition will automatically use the ${GREEN}remaining 100%${NC} of the drive."

# Calculate start and end points
START_BIOS=1
END_BIOS=$((START_BIOS + BIOS_SIZE))
END_EFI=$((END_BIOS + EFI_SIZE))
END_LIVE=$((END_EFI + LIVE_SIZE))

# Drive Warning
echo -e "\n${RED}=================================================================${NC}"
echo -e "${RED}WARNING: ALL DATA ON ${DRIVE} WILL BE PERMANENTLY ERASED!${NC}"
echo -e "${RED}=================================================================${NC}"
lsblk "$DRIVE"
echo ""
read -p "Are you absolutely sure you want to format this drive? (Type YES to continue): " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
    echo "Operation aborted by user."
    exit 0
fi

# Handle partition naming format (e.g., /dev/nvme0n1p1 vs /dev/sdb1)
get_part() {
    if [[ $1 == *"nvme"* ]] || [[ $1 == *"mmcblk"* ]] || [[ $1 == *"loop"* ]]; then
        echo "${1}p${2}"
    else
        echo "${1}${2}"
    fi
}
PART1=$(get_part "$DRIVE" 1)
PART2=$(get_part "$DRIVE" 2)
PART3=$(get_part "$DRIVE" 3)
PART4=$(get_part "$DRIVE" 4)

# Setup mount point cleanup trap
cleanup() {
    echo -e "\n${YELLOW}Cleaning up mounts and syncing data...${NC}"
    sync
    umount /tmp/usb-efi /tmp/usb-live /tmp/usb-persistence /tmp/live-iso 2>/dev/null || true
    rm -rf /tmp/usb-efi /tmp/usb-live /tmp/usb-persistence /tmp/live-iso
}
trap cleanup EXIT

# ==========================================
# Execution Phase
# ==========================================

echo -e "\n${GREEN}[1/8] Unmounting and wiping drive...${NC}"
umount "${DRIVE}"* 2>/dev/null || true
wipefs -a "$DRIVE"

echo -e "\n${GREEN}[2/8] Creating GPT partitions...${NC}"
parted -s "$DRIVE" mktable gpt
parted -s "$DRIVE" mkpart biosboot ${START_BIOS}MiB ${END_BIOS}MiB
parted -s "$DRIVE" mkpart EFI fat32 ${END_BIOS}MiB ${END_EFI}MiB
parted -s "$DRIVE" mkpart LIVE fat32 ${END_EFI}MiB ${END_LIVE}MiB
parted -s "$DRIVE" mkpart persistence ext4 ${END_LIVE}MiB 100%

parted -s "$DRIVE" set 1 bios_grub on
parted -s "$DRIVE" set 2 esp on
parted -s "$DRIVE" set 3 legacy_boot on

echo -e "\n${GREEN}[3/8] Formatting partitions...${NC}"
mkfs.vfat -F32 -n EFI "$PART2"
mkfs.vfat -F32 -n LIVE "$PART3"
mkfs.ext4 -F -L persistence "$PART4"

echo -e "\n${GREEN}[4/8] Mounting partitions and ISO...${NC}"
mkdir -p /tmp/usb-efi /tmp/usb-live /tmp/usb-persistence /tmp/live-iso
mount "$PART2" /tmp/usb-efi
mount "$PART3" /tmp/usb-live
mount "$PART4" /tmp/usb-persistence
mount -o ro "$ISO_PATH" /tmp/live-iso

echo -e "\n${GREEN}[5/8] Copying ISO contents (this will take a few minutes)...${NC}"
rsync -a --info=progress2 /tmp/live-iso/ /tmp/usb-live/
sync

echo -e "\n${GREEN}[6/8] Configuring persistence...${NC}"
echo "/ union" > /tmp/usb-persistence/persistence.conf

echo -e "\n${GREEN}[7/8] Patching Bootloader configs...${NC}"
# Rename isolinux to syslinux safely without relying on external 'rename' tools
if [[ -d /tmp/usb-live/isolinux ]]; then
    mv /tmp/usb-live/isolinux /tmp/usb-live/syslinux
    for f in /tmp/usb-live/syslinux/isolinux*; do
        [ -e "$f" ] && mv "$f" "${f//isolinux/syslinux}"
    done
fi

# Inject persistence kernel parameter
sed -i 's/\(boot=live .*\)$/\1 persistence/' /tmp/usb-live/boot/grub/grub.cfg
if [[ -f /tmp/usb-live/syslinux/menu.cfg ]]; then
    sed -i 's/\(boot=live .*\)$/\1 persistence/' /tmp/usb-live/syslinux/menu.cfg
fi

echo -e "\n${GREEN}[8/8] Installing GRUB (BIOS & UEFI)...${NC}"
grub-install --target=i386-pc --boot-directory=/tmp/usb-live/boot --recheck "$DRIVE"
grub-install --target=x86_64-efi --boot-directory=/tmp/usb-live/boot --efi-directory=/tmp/usb-efi --removable --no-uefi-secure-boot --recheck "$DRIVE"

echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN}SUCCESS! Debian 13 Persistence USB is ready.${NC}"
echo -e "${GREEN}==============================================${NC}"
# Trap will automatically run cleanup() here upon exit.
