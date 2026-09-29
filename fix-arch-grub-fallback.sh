#!/usr/bin/env bash
#
# Arch Linux UEFI/GRUB fallback recovery helper
#
# Purpose:
#   - Verify the system is booted in UEFI mode
#   - Verify /boot is mounted
#   - Show current UEFI boot entries
#   - Find an existing GRUB EFI executable
#   - Create the standard EFI fallback loader:
#       /boot/EFI/Boot/bootx64.efi
#   - Regenerate GRUB configuration
#
# This script DOES NOT:
#   - format or repartition disks
#   - reinstall Arch
#   - delete existing EFI files
#   - change Secure Boot settings
#   - create/delete NVRAM boot entries
#
# Run from the installed Arch system, not from a random live environment.
#
# Usage:
#   chmod +x fix-arch-grub-fallback.sh
#   sudo ./fix-arch-grub-fallback.sh

set -u

if [[ $EUID -ne 0 ]]; then
    echo "Please run this script with sudo:"
    echo "  sudo $0"
    exit 1
fi

echo " Arch Linux UEFI/GRUB Fallback Recovery"

# 1. Verify UEFI mode
if [[ ! -d /sys/firmware/efi ]]; then
    echo "ERROR: This system is not currently booted in UEFI mode."
    echo "Boot the installed system in UEFI mode and run the script again."
    exit 1
fi

echo "[OK] System is booted in UEFI mode."
echo

# 2. Verify /boot
if ! mountpoint -q /boot; then
    echo "ERROR: /boot is not a separate mounted filesystem."
    echo "This script will not guess which partition should be mounted."
    echo
    echo "Run:"
    echo "  lsblk -f"
    echo
    echo "and verify your EFI System Partition before proceeding."
    exit 1
fi

BOOT_SOURCE="$(findmnt -no SOURCE /boot 2>/dev/null || true)"
BOOT_FSTYPE="$(findmnt -no FSTYPE /boot 2>/dev/null || true)"

echo "[OK] /boot is mounted."
echo "     Device:  ${BOOT_SOURCE:-unknown}"
echo "     Type:    ${BOOT_FSTYPE:-unknown}"
echo

if [[ "$BOOT_FSTYPE" != "vfat" && "$BOOT_FSTYPE" != "fat" && "$BOOT_FSTYPE" != "msdos" ]]; then
    echo "WARNING: /boot does not appear to be a FAT EFI System Partition."
    echo "The script will not modify it automatically."
    exit 1
fi

# 3. Show current boot entries
echo "Current UEFI boot entries:"
echo "----------------------------------------------"
if command -v efibootmgr >/dev/null 2>&1; then
    efibootmgr -v || true
else
    echo "efibootmgr is not installed."
fi
echo

# 4. Find existing EFI GRUB executable
GRUB_SOURCE=""

CANDIDATES=(
    "/boot/EFI/GRUB/grubx64.efi"
    "/boot/EFI/grub/grubx64.efi"
    "/boot/EFI/Arch/grubx64.efi"
    "/boot/EFI/arch/grubx64.efi"
)

for candidate in "${CANDIDATES[@]}"; do
    if [[ -f "$candidate" ]]; then
        GRUB_SOURCE="$candidate"
        break
    fi
done

# If not found in common locations, search /boot/EFI.
if [[ -z "$GRUB_SOURCE" ]]; then
    while IFS= read -r candidate; do
        GRUB_SOURCE="$candidate"
        break
    done < <(find /boot/EFI -type f \( -iname 'grubx64.efi' -o -iname 'grub.efi' \) 2>/dev/null)
fi

if [[ -z "$GRUB_SOURCE" ]]; then
    echo "ERROR: No existing GRUB EFI executable was found under /boot/EFI."
    echo
    echo "The script will not install or guess a bootloader."
    echo "Inspect your installation with:"
    echo "  sudo find /boot -type f \\( -name 'grub*.efi' -o -name 'bootx64.efi' \\) -print"
    exit 1
fi

echo "[OK] Found GRUB EFI executable:"
echo "     $GRUB_SOURCE"
echo

# 5. Check architecture/type if file command exists
if command -v file >/dev/null 2>&1; then
    echo "EFI executable type:"
    file "$GRUB_SOURCE"
    echo
fi

# 6. Create fallback directory
FALLBACK_DIR="/boot/EFI/Boot"
FALLBACK_FILE="$FALLBACK_DIR/bootx64.efi"

mkdir -p "$FALLBACK_DIR"

# 7. If fallback exists, preserve it and ask before replacing
if [[ -e "$FALLBACK_FILE" ]]; then
    echo "A fallback loader already exists:"
    echo "  $FALLBACK_FILE"
    echo
    read -r -p "Replace it with the detected GRUB loader? [y/N]: " answer
    case "$answer" in
        y|Y)
            BACKUP="${FALLBACK_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
            cp -a "$FALLBACK_FILE" "$BACKUP"
            echo "[OK] Existing fallback backed up to:"
            echo "     $BACKUP"
            cp -a "$GRUB_SOURCE" "$FALLBACK_FILE"
            ;;
        *)
            echo "Leaving existing fallback loader unchanged."
            ;;
    esac
else
    cp -a "$GRUB_SOURCE" "$FALLBACK_FILE"
    echo "[OK] Created:"
    echo "     $FALLBACK_FILE"
fi

echo

# 8. Verify fallback
if [[ -f "$FALLBACK_FILE" ]]; then
    echo "Fallback loader:"
    ls -lh "$FALLBACK_FILE"
else
    echo "ERROR: Fallback loader was not created."
    exit 1
fi

echo

# 9. Regenerate GRUB configuration if grub-mkconfig exists
if command -v grub-mkconfig >/dev/null 2>&1; then
    echo "Regenerating GRUB configuration..."
    if grub-mkconfig -o /boot/grub/grub.cfg; then
        echo "[OK] GRUB configuration regenerated."
    else
        echo "ERROR: grub-mkconfig failed."
        exit 1
    fi
else
    echo "WARNING: grub-mkconfig was not found."
    echo "GRUB configuration was not regenerated."
fi

echo
echo " Recovery preparation completed"
echo
echo "Fallback loader:"
echo "  $FALLBACK_FILE"
echo
echo "Check UEFI entries with:"
echo "  sudo efibootmgr -v"
echo
echo "IMPORTANT:"
echo "  - Keep Secure Boot settings appropriate for your bootloader."
echo "  - Do not delete the existing GRUB EFI files."
echo "  - Reboot only after verifying the output above."
echo
echo "If the machine still reports 'No bootable device',"
echo "save the output of:"
echo "  sudo efibootmgr -v"
echo "  lsblk -f"
echo "  sudo find /boot -maxdepth 3 -type f \\( -name 'grub*.efi' -o -name 'bootx64.efi' \\) -print"
echo
