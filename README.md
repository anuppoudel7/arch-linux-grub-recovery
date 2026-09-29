# Fixing "No Bootable Device Found" on Arch Linux (UEFI/GRUB)

## Overview

This guide documents how to recover an Arch Linux system when the laptop
reports:

> **No bootable device found**

In the case documented here, the NVMe drive and EFI System Partition
were still present, and the GRUB EFI files existed on disk. The problem
was that the UEFI firmware did not have a usable GRUB boot entry. Secure
Boot also initially rejected the manually selected GRUB EFI file.

The fix was to:

1.  Confirm the NVMe drive and EFI partition were intact.
2.  Boot Arch successfully by adding the existing GRUB EFI file as a
    trusted UEFI file.
3.  Keep Secure Boot disabled because the existing GRUB EFI executable
    was rejected by Secure Boot.
4.  Add the standard UEFI fallback loader: `EFI/Boot/bootx64.efi`
5.  Regenerate the GRUB configuration.

The fallback loader provides an additional way for UEFI firmware to find
GRUB if the normal NVRAM boot entry disappears again.

------------------------------------------------------------------------

## Symptoms

Typical symptoms:

-   Laptop starts with **No bootable device found**.
-   BIOS/UEFI detects the SSD/NVMe drive.
-   The BIOS Boot list is empty or does not contain the Linux/GRUB
    entry.
-   The BIOS can browse the EFI partition and see GRUB EFI files.
-   Selecting the GRUB EFI file while Secure Boot is enabled may
    produce: `Prohibited by Secure Boot policy`.

------------------------------------------------------------------------

## Important Safety Notes

Before modifying anything:

-   **Do not format the SSD.**
-   **Do not delete or recreate partitions.**
-   **Do not reinstall Arch just because the boot entry is missing.**
-   Do not delete existing GRUB EFI files until the installation has
    been verified.
-   If possible, make a backup of important files before making
    bootloader changes.
-   BIOS menus differ between laptop manufacturers.

------------------------------------------------------------------------

# Part 1 --- Diagnose the Problem

After successfully entering Arch Linux, check whether the system is
booted in UEFI mode:

``` bash
test -d /sys/firmware/efi && echo "UEFI mode" || echo "Legacy mode"
```

Expected result:

``` text
UEFI mode
```

Check the UEFI boot entries:

``` bash
efibootmgr -v
```

A healthy setup may contain something similar to:

``` text
BootCurrent: 0000
BootOrder: 0000,...
Boot0000* GRUB    ...\grub\x86_64-efi\grub.efi
```

The important part is the `GRUB` entry and the EFI file it points to.

------------------------------------------------------------------------

## Check the partitions

Run:

``` bash
lsblk -f
```

A typical Arch UEFI installation may look like:

``` text
nvme0n1
├─nvme0n1p1   vfat   FAT32   /boot
├─nvme0n1p2   ext4           /
└─nvme0n1p3   ext4           /home
```

The FAT32 partition mounted at `/boot` is the EFI System Partition in
this setup.

**Do not assume these partition numbers are the same on another
computer. Always verify with `lsblk -f`.**

------------------------------------------------------------------------

## Check the GRUB EFI files

Run:

``` bash
sudo find /boot -maxdepth 3 -type f \( -name 'grub*.efi' -o -name 'bootx64.efi' \) -print
```

For the system documented here, the important files were:

``` text
/boot/grub/x86_64-efi/grub.efi
/boot/EFI/GRUB/grubx64.efi
```

Check an EFI executable:

``` bash
file /boot/EFI/GRUB/grubx64.efi
```

Expected type:

``` text
PE32+ executable for EFI (application), x86-64
```

------------------------------------------------------------------------

# Part 2 --- Recover When the BIOS Boot List Is Empty

If BIOS can browse the EFI files, look for a menu similar to:

``` text
Security
└── Select an UEFI file as trusted for executing
```

Then navigate to the EFI System Partition.

On the system documented here, the GRUB file was located at:

``` text
HDD/NVMe
└── grub
    └── EFI
        └── grub.efi
```

The exact path can differ between installations.

Select the appropriate GRUB EFI executable and add it as a trusted UEFI
file.

After saving the BIOS settings, the Boot menu should contain an entry
similar to:

``` text
EFI File Boot 0: GRUB
```

Set it as the first boot option if necessary.

------------------------------------------------------------------------

# Part 3 --- Secure Boot Issue

When attempting to boot the existing GRUB EFI file, this system
displayed:

``` text
Prohibited by Secure Boot policy
```

This means the firmware's Secure Boot policy rejected that EFI
executable.

For this recovery procedure, Secure Boot was disabled in BIOS:

``` text
BIOS
→ Security
→ Secure Boot
→ Disabled
```

Then the GRUB EFI file could be launched.

## Important

Disabling Secure Boot is a troubleshooting choice, not a requirement for
every Arch installation.

If you want Secure Boot enabled permanently, configure a properly signed
boot chain (for example, using a supported signed bootloader/kernel
configuration). Do not simply copy unsigned EFI files and expect Secure
Boot to accept them.

------------------------------------------------------------------------

# Part 4 --- Add the UEFI Fallback Loader

The normal GRUB entry can depend on a UEFI NVRAM entry such as:

``` text
Boot0000* GRUB
```

If firmware loses that entry, the EFI files can still exist on the disk
while the firmware has no Linux boot entry to launch.

UEFI provides a standard fallback path:

``` text
EFI/Boot/bootx64.efi
```

On this system, `/boot` is the EFI System Partition, so the fallback
path is:

``` text
/boot/EFI/Boot/bootx64.efi
```

## Create the directory

``` bash
sudo mkdir -p /boot/EFI/Boot
```

## Copy the existing GRUB EFI executable

For the installation documented here:

``` bash
sudo cp /boot/EFI/GRUB/grubx64.efi /boot/EFI/Boot/bootx64.efi
```

Verify:

``` bash
sudo ls -lah /boot/EFI/Boot/
```

Expected:

``` text
bootx64.efi
```

This does **not** delete or replace the existing GRUB files.

------------------------------------------------------------------------

# Part 5 --- Regenerate GRUB Configuration

Regenerate the GRUB configuration:

``` bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

A successful run should detect the installed Linux kernel and initramfs,
for example:

``` text
Found linux image: /boot/vmlinuz-linux
Found initrd image: /boot/intel-ucode.img /boot/initramfs-linux.img
Adding boot menu entry for UEFI Firmware Settings ...
done
```

Verify the configuration file:

``` bash
ls -lh /boot/grub/grub.cfg
```

------------------------------------------------------------------------

# Part 6 --- Verify the Final Setup

Check the UEFI entries:

``` bash
sudo efibootmgr -v
```

You should have a GRUB entry similar to:

``` text
Boot0000* GRUB
```

Check the fallback loader:

``` bash
sudo ls -lah /boot/EFI/Boot/
```

You should see:

``` text
bootx64.efi
```

Check the GRUB configuration:

``` bash
ls -lh /boot/grub/grub.cfg
```

------------------------------------------------------------------------

# Why the Fallback Loader Helps

A UEFI boot setup can be thought of as having two paths:

### Normal path

``` text
UEFI firmware
      ↓
UEFI NVRAM GRUB entry
      ↓
/EFI or /grub/.../grub.efi
      ↓
GRUB
      ↓
Arch Linux
```

### Fallback path

``` text
UEFI firmware
      ↓
EFI/Boot/bootx64.efi
      ↓
GRUB
      ↓
Arch Linux
```

If the firmware loses the NVRAM `GRUB` entry, the fallback path gives
the firmware a standard location from which it may find a bootloader.

This does not guarantee that every laptop firmware will use the fallback
path in every situation, but it makes the installation less dependent on
a single custom NVRAM entry.

------------------------------------------------------------------------

# What Was Found on the Example System

The system had:

``` text
NVMe SSD
├── nvme0n1p1  FAT32  /boot
├── nvme0n1p2  ext4   /
└── nvme0n1p3  ext4   /home
```

The existing EFI files included:

``` text
/boot/grub/x86_64-efi/grub.efi
/boot/EFI/GRUB/grubx64.efi
```

The UEFI entry was:

``` text
Boot0000* GRUB
```

pointing to:

``` text
\grub\x86_64-efi\grub.efi
```

There was initially no:

``` text
/boot/EFI/Boot/bootx64.efi
```

It was added using:

``` bash
sudo mkdir -p /boot/EFI/Boot
sudo cp /boot/EFI/GRUB/grubx64.efi /boot/EFI/Boot/bootx64.efi
```

------------------------------------------------------------------------

# If the Problem Happens Again

If BIOS again says:

> No bootable device found

check the following before reinstalling anything.

### 1. Check whether the SSD is detected

BIOS should still show the NVMe/SSD.

If the drive itself is missing from BIOS, this is a different problem
and may involve hardware, connection, or firmware issues.

### 2. Check the BIOS Boot menu

Look for:

``` text
GRUB
Linux Boot Manager
UEFI OS
```

If the entry disappeared but the drive and EFI partition are still
present, the UEFI NVRAM entry may have been lost or reset.

### 3. Check the fallback file from Arch

If you can boot using another method, run:

``` bash
sudo ls -lah /boot/EFI/Boot/bootx64.efi
```

### 4. Check UEFI entries

``` bash
sudo efibootmgr -v
```

### 5. Check Secure Boot

If you get:

``` text
Prohibited by Secure Boot policy
```

check the BIOS Secure Boot setting and your bootloader's signing
configuration.

------------------------------------------------------------------------

# Investigating Why the Boot Entry Keeps Disappearing

A missing NVRAM entry does not necessarily mean the SSD or Arch
installation is damaged.

Possible causes include:

-   BIOS/UEFI firmware resetting or modifying NVRAM.
-   BIOS/firmware updates.
-   Firmware-specific behavior with custom Linux boot entries.
-   Changes to bootloader configuration.
-   Other operating systems or bootloader tools modifying EFI/NVRAM
    entries.
-   Secure Boot configuration changes.
-   CMOS/RTC or firmware configuration problems in some systems.

The exact cause should be investigated rather than assumed.

If the problem repeats, compare:

``` bash
sudo efibootmgr -v
```

before and after the problem occurs.

Also check whether BIOS settings such as UEFI/Legacy mode and Secure
Boot have changed.

------------------------------------------------------------------------

# Useful Commands

## Show disks and filesystems

``` bash
lsblk -f
```

## Show UEFI boot entries

``` bash
sudo efibootmgr -v
```

## Check UEFI boot mode

``` bash
test -d /sys/firmware/efi && echo "UEFI mode" || echo "Legacy mode"
```

## Find GRUB EFI files

``` bash
sudo find /boot -maxdepth 3 -type f \( -name 'grub*.efi' -o -name 'bootx64.efi' \) -print
```

## Inspect EFI executable type

``` bash
file /boot/EFI/GRUB/grubx64.efi
```

## Regenerate GRUB configuration

``` bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

## Check fallback loader

``` bash
sudo ls -lah /boot/EFI/Boot/
```

------------------------------------------------------------------------

# Final Recovery Checklist

Use this checklist when sharing or following the guide:

-   [ ] SSD/NVMe is detected in BIOS.
-   [ ] EFI System Partition is detected.
-   [ ] Arch root partition is intact.
-   [ ] System boots in UEFI mode.
-   [ ] GRUB EFI executable exists.
-   [ ] A `GRUB` UEFI entry exists in `efibootmgr`.
-   [ ] `/boot/EFI/Boot/bootx64.efi` exists.
-   [ ] `grub.cfg` has been regenerated.
-   [ ] Secure Boot configuration is understood.
-   [ ] Important data is backed up.

------------------------------------------------------------------------

## Key Takeaway

A **"No bootable device"** message does not automatically mean the
operating system or SSD is gone.

If the EFI partition and GRUB files are still present, the problem can
be at the UEFI boot-entry/bootloader level.

For this particular recovery, the important addition was:

``` text
/boot/EFI/Boot/bootx64.efi
```

which provides the standard UEFI fallback path in addition to the
existing `GRUB` NVRAM boot entry.
