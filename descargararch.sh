#!/usr/bin/env bash
set -e

########################################
# 🎛️ PANEL
########################################

clear
echo "======================================"
echo "           KM RoBoTa"
echo "======================================"
echo "   Arch Linux Installation Script"
echo "======================================"
echo ""

########################################
# 💽 DETECCIÓN DEL SCRIPT (DIRECTORIO → DISPOSITIVO)
########################################

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

SCRIPT_DEV="$(findmnt -n -o SOURCE --target "$SCRIPT_DIR")"
SCRIPT_TRAN="$(lsblk -no TRAN "$SCRIPT_DEV")"
SCRIPT_DISK="/dev/$(lsblk -no pkname "$SCRIPT_DEV" 2>/dev/null || true)"

GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

echo ""

echo "📍 Script: $SCRIPT_PATH"
printf "📁 Script directory: %b%s%b\n" "$BLUE" "$SCRIPT_DIR" "$RESET"
printf "💽 Script device: %b%s%b\n" "$GREEN" "$SCRIPT_DEV" "$RESET"

if [[ "$SCRIPT_TRAN" == "usb" ]]; then
    printf "🔌 Transport type: %bUSB%b\n" "$YELLOW" "$RESET"
elif [[ "$SCRIPT_TRAN" == "nvme" ]]; then
    printf "🔌 Transport type: %bNVMe%b\n" "$BLUE" "$RESET"
elif [[ -n "$SCRIPT_TRAN" ]]; then
    printf "🔌 Transport type: %b%s%b\n" "$GREEN" "$SCRIPT_TRAN" "$RESET"
else
    printf "🔌 Transport type: %bunknown%b\n" "$RED" "$RESET"
fi

echo ""

########################################
# 💽 LISTADO COMPLETO DE DISCOS
########################################

echo "======================================"
echo "        DETECTED STORAGE DEVICES"
echo "======================================"

DISKS_PREVIEW=()
i=1

while read -r name size tran model; do
    DEV="/dev/$name"
    LABEL="$DEV - $size - $model"

    if [[ "$tran" == "usb" ]]; then
        if [[ "$DEV" == "$SCRIPT_DISK" ]]; then
            echo -e "${GREEN}[$i] $LABEL (SCRIPT USB - PROTECTED)${RESET}"
        else
            echo -e "${YELLOW}[$i] $LABEL (USB)${RESET}"
        fi
    elif [[ "$tran" == "nvme" ]]; then
        echo -e "${BLUE}[$i] $LABEL (NVME)${RESET}"
    else
        echo "[$i] $LABEL"
    fi

    DISKS_PREVIEW+=("$DEV")
    ((i++))

done < <(lsblk -dn -o NAME,SIZE,TRAN,MODEL)

echo "======================================"
echo ""

########################################
# 📁 DOWNLOAD DIRECTORY
########################################

echo "======================================"
echo "     SELECT DOWNLOAD DIRECTORY"
echo "======================================"
echo ""

echo "1) Use script directory (default)"
echo "2) Enter custom path"
echo ""

read -p "Choose option [1-2]: " dir_choice

if [[ "$dir_choice" == "1" || -z "$dir_choice" ]]; then
    BASE_DOWNLOAD_DIR="$SCRIPT_DIR"
elif [[ "$dir_choice" == "2" ]]; then
    read -p "Enter path: " BASE_DOWNLOAD_DIR
else
    echo "❌ Invalid option"
    exit 1
fi

if [[ -z "$BASE_DOWNLOAD_DIR" ]]; then
    echo "❌ No directory selected"
    exit 1
fi

DOWNLOAD_DIR="$BASE_DOWNLOAD_DIR/temp_arch_download"

mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

echo ""
printf "📂 Download folder created: %b%s%b\n" "$GREEN" "$DOWNLOAD_DIR" "$RESET"
echo ""

########################################
# ❓ DOWNLOAD CONFIRM (DEFAULT YES)
########################################

read -p "Download and verify Arch Linux ISO? (default: YES / type 'no' to cancel): " start

if [[ "$start" == "no" || "$start" == "NO" ]]; then
    echo "❌ Cancelled."
    exit 0
fi

echo "✔ Proceeding with download..."

########################################
# 📥 DOWNLOAD FILES
########################################

BASE_URL="https://theswissbay.ch/archlinux/iso/latest"
ISO="archlinux-x86_64.iso"

FILES=(
  "$ISO"
  "sha256sums.txt"
  "b2sums.txt"
)

echo ""
echo "📥 Checking files..."

for file in "${FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo "✔ $file already exists → skipping"
        continue
    fi
    echo "⬇️ Downloading $file"
    curl -LO "$BASE_URL/$file"
done

########################################
# 🔐 VERIFY SHA256
########################################

if [[ -f "$ISO" && -f "sha256sums.txt" ]]; then
    echo ""
    echo "🔐 Verifying SHA256..."
    grep "$ISO" sha256sums.txt | sha256sum -c -
else
    echo "❌ Missing ISO or sha256sums.txt"
    exit 1
fi

########################################
# 🔐 VERIFY BLAKE2
########################################

if [[ -f "$ISO" && -f "b2sums.txt" ]]; then
    echo ""
    echo "🔐 Verifying BLAKE2..."
    grep "$ISO" b2sums.txt | b2sum -c -
else
    echo "❌ Missing b2sums.txt"
    exit 1
fi

echo ""
echo "✅ ISO ready and verified"
echo ""

########################################
# 💽 SELECT DISK
########################################

echo "======================================"
echo "         SELECT INSTALL DISK"
echo "======================================"

DISKS=()
i=1

while read -r name size tran model; do
    DEV="/dev/$name"
    LABEL="$DEV - $size - $model"

    if [[ "$DEV" == "$SCRIPT_DISK" ]]; then
        echo -e "${GREEN}[$i] $LABEL (SCRIPT USB - BLOCKED)${RESET}"
        continue
    fi

    if [[ "$tran" == "usb" ]]; then
        echo -e "${YELLOW}[$i] $LABEL (USB)${RESET}"
    elif [[ "$tran" == "nvme" ]]; then
        echo -e "${BLUE}[$i] $LABEL (NVME)${RESET}"
    else
        echo "[$i] $LABEL"
    fi

    DISKS+=("$DEV")
    ((i++))

done < <(lsblk -dn -o NAME,SIZE,TRAN,MODEL)

echo "======================================"

read -p "Select disk number to install Arch Linux: " choice

TARGET_DISK="${DISKS[$((choice-1))]}"

if [[ -z "$TARGET_DISK" ]]; then
    echo "❌ Invalid selection"
    exit 1
fi

echo ""
echo "⚠️ WARNING: Selected disk: $TARGET_DISK"
echo "⚠️ ALL DATA WILL BE DESTROYED!"
echo ""

########################################
# 🚨 FINAL CONFIRM (DD)
########################################

read -p "Type 'yes' to WRITE ISO to disk (default: NO): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "❌ Cancelled"
    exit 0
fi

ISO_FILE="archlinux-x86_64.iso"

if [[ ! -f "$ISO_FILE" ]]; then
    echo "❌ ISO not found"
    exit 1
fi

echo ""
echo "🚀 Writing ISO to disk..."
echo "📀 ISO: $ISO_FILE"
echo "💽 Target: $TARGET_DISK"
echo ""

sudo dd bs=4M if="$ISO_FILE" of="$TARGET_DISK" status=progress oflag=sync

sync

echo ""
echo "🎉 DONE!"
echo "USB bootable Arch Linux created successfully."

########################################
# 🧹 CLEANUP (DEFAULT = YES)
########################################

echo ""
read -p "Delete downloaded files folder? (default: YES / type 'no' to keep): " clean

if [[ "$clean" == "no" || "$clean" == "NO" ]]; then
    echo "📁 Keeping download folder: $DOWNLOAD_DIR"
else
    cd "$SCRIPT_DIR"
    rm -rf "$DOWNLOAD_DIR"
    echo "🧹 Download folder deleted."
fi
