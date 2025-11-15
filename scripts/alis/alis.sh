#!/usr/bin/env bash

set -euo pipefail

DISK="DISCO"

LUKS_PASSWORD="SENHA"
ROOT_PASSWORD="SENHA"

HOSTNAME="archlinux"
TIMEZONE="America/Sao_Paulo"

LOCALE="pt_BR.UTF-8"

CONSOLE_KEYMAP="us-acentos"
CONSOLE_FONT="eurlatgr"

sgdisk -Z "${DISK}"
sgdisk -o "${DISK}"
sgdisk -n 1:0:+1G -t 1:EF00 "${DISK}"
sgdisk -n 2:0:0 -t 2:8309 "${DISK}"

BOOT_PART=${DISK}1
ROOT_PART=${DISK}2

LUKS_MAPPER="cryptroot"

echo "${LUKS_PASSWORD}" | cryptsetup --batch-mode --hash sha512 --use-random --sector-size 4096 luksFormat ${ROOT_PART}
echo "${LUKS_PASSWORD}" | cryptsetup --batch-mode open ${ROOT_PART} ${LUKS_MAPPER}

LUKS_CONTAINER="/dev/mapper/${LUKS_MAPPER}"
TARGET="/mnt"

# Format partitions
mkfs.fat -F 32 ${BOOT_PART}
mkfs.btrfs ${LUKS_CONTAINER}

# Mount $TARGET to create subvolumes
mount ${LUKS_CONTAINER} $TARGET

# Create the subvolumes
for SUBVOL in @ @home @pkg @flatpak @machines @portables @log @.snapshots; do
    btrfs su cr ${TARGET}/${SUBVOL}
done

# Umount $TARGET to mount the subvolumes itself
umount ${TARGET}

BTRFS_MOUNT_OPTIONS_COMPRESS="rw,relatime,compress=zstd:7,space_cache=v2"
BTRFS_MOUNT_OPTIONS_NODATACOW="rw,relatime,compress=zstd:7,space_cache=v2"
BOOT_MOUNT_OPTIONS="rw,relatime,umask=0077,utf8,errors=remount-ro"

mount ${LUKS_CONTAINER} -o "${BTRFS_MOUNT_OPTIONS_COMPRESS}",subvol=@ ${TARGET}
mount ${LUKS_CONTAINER} -m -o "${BTRFS_MOUNT_OPTIONS_COMPRESS}",subvol=@home ${TARGET}/home
mount ${LUKS_CONTAINER} -m -o "${BTRFS_MOUNT_OPTIONS_NODATACOW}",subvol=@pkg ${TARGET}/var/cache/pacman/pkg
mount ${LUKS_CONTAINER} -m -o "${BTRFS_MOUNT_OPTIONS_NODATACOW}",subvol=@flatpak ${TARGET}/var/lib/flatpak
mount ${LUKS_CONTAINER} -m -o "${BTRFS_MOUNT_OPTIONS_COMPRESS}",subvol=@machines ${TARGET}/var/lib/machines
mount ${LUKS_CONTAINER} -m -o "${BTRFS_MOUNT_OPTIONS_COMPRESS}",subvol=@portables ${TARGET}/var/lib/portables
mount ${LUKS_CONTAINER} -m -o "${BTRFS_MOUNT_OPTIONS_NODATACOW}",subvol=@log ${TARGET}/var/log
mount ${LUKS_CONTAINER} -m -o "${BTRFS_MOUNT_OPTIONS_COMPRESS}",subvol=@.snapshots ${TARGET}/.snapshots
mount ${BOOT_PART} -m -o ${BOOT_MOUNT_OPTIONS} ${TARGET}/efi

# Setting the Pacman configurations
cat > /etc/pacman.conf << EOF
[options]
HoldPkg = pacman glibc
Architecture = auto

UseSyslog
Color
CheckSpace
VerbosePkgLists
ParallelDownloads = 5
DownloadUser = alpm
DisableDownloadTimeout

SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

# Create a custom mirrorlist for Pacman
cat > /etc/pacman.d/mirrorlist << EOF
# UFPR
Server = https://archlinux.c3sl.ufpr.br/\$repo/os/\$arch

# UFSCAR
Server = https://mirror.ufscar.br/archlinux/\$repo/os/\$arch

# UNICAMP
Server = https://mirrors.ic.unicamp.br/archlinux/\$repo/os/\$arch

# Kernel.org
Server = https://mirrors.edge.kernel.org/archlinux/\$repo/os/\$arch

# Rackspace
Server = https://iad.mirror.rackspace.com/archlinux/\$repo/os/\$arch
Server = https://ord.mirror.rackspace.com/archlinux/\$repo/os/\$arch
Server = https://dfw.mirror.rackspace.com/archlinux/\$repo/os/\$arch
Server = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch

# Leaseweb
Server = https://mirror.wdc1.us.leaseweb.net/archlinux/\$repo/os/\$arch
Server = https://mirror.sfo12.us.leaseweb.net/archlinux/\$repo/os/\$arch

# PKGBUILD
Server = https://fastly.mirror.pkgbuild.com/\$repo/os/\$arch
Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch
EOF

# The list of packages to be installed
PACKAGES=(
    base
    linux
    linux-firmware
    intel-ucode
    btrfs-progs
    neovim
    sudo
    man-db
    man-pages
)

# Install the system with Pacstrap
pacstrap -KP ${TARGET} "${PACKAGES[@]}"

# Getting the UUID for partitions
BOOT_PART_UUID=$(blkid -s UUID -o value ${BOOT_PART})
ROOT_PART_UUID=$(blkid -s UUID -o value ${ROOT_PART})
LUKS_CONTAINER_UUID=$(blkid -s UUID -o value ${LUKS_CONTAINER})

# Create the custom FSTAB file
cat > ${TARGET}/etc/fstab << EOF
# FILESYSTEM PATH TYPE OPTIONS DUMP PASS
UUID=${LUKS_CONTAINER_UUID} / btrfs ${BTRFS_MOUNT_OPTIONS_COMPRESS},subvol=@ 0 0
UUID=${LUKS_CONTAINER_UUID} /home btrfs ${BTRFS_MOUNT_OPTIONS_COMPRESS},subvol=@home 0 0
UUID=${LUKS_CONTAINER_UUID} /var/cache/pacman/pkg btrfs ${BTRFS_MOUNT_OPTIONS_NODATACOW},subvol=@pkg 0 0
UUID=${LUKS_CONTAINER_UUID} /var/lib/flatpak btrfs ${BTRFS_MOUNT_OPTIONS_NODATACOW},subvol=@flatpak 0 0
UUID=${LUKS_CONTAINER_UUID} /var/lib/machines btrfs ${BTRFS_MOUNT_OPTIONS_COMPRESS},subvol=@machines 0 0
UUID=${LUKS_CONTAINER_UUID} /var/lib/portables btrfs ${BTRFS_MOUNT_OPTIONS_COMPRESS},subvol=@portables 0 0
UUID=${LUKS_CONTAINER_UUID} /var/log btrfs ${BTRFS_MOUNT_OPTIONS_NODATACOW},subvol=@log 0 0
UUID=${LUKS_CONTAINER_UUID} /.snapshots btrfs ${BTRFS_MOUNT_OPTIONS_COMPRESS},subvol=@.snapshots 0 0
UUID=${BOOT_PART_UUID} /efi vfat ${BOOT_MOUNT_OPTIONS} 0 2
EOF

# Set the NTP pool servers
NTP=(
    "0.pool.ntp.org"
    "1.pool.ntp.org"
    "2.pool.ntp.org"
    "3.pool.ntp.org"
)

# Configure the systemd-timesyncd
cat > ${TARGET}/etc/systemd/timesyncd.conf << EOF
[Time]
NTP=${NTP[@]}
EOF

# Link $TIMEZONE to localtime and sincronize it with hardware clock
arch-chroot ${TARGET} ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
arch-chroot ${TARGET} hwclock --systohc

# Set the locale
echo "${LOCALE} UTF-8" > ${TARGET}/etc/locale.gen
echo "LANG=${LOCALE}" > ${TARGET}/etc/locale.conf

# Generate the locales
arch-chroot ${TARGET} locale-gen

# Set the configurations for the console
cat > ${TARGET}/etc/vconsole.conf << EOF
KEYMAP=${CONSOLE_KEYMAP}
FONT=${CONSOLE_FONT}
EOF

# Set the hostname
echo ${HOSTNAME} > ${TARGET}/etc/hostname

# Configure the hosts file
cat > ${TARGET}/etc/hosts << EOF
# IPv4
127.0.0.1 localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}

# IPv6
::1 localhost ip6-localhost ip6-loopback
fa02::1 ip6-allnodes
fa02::2 ip6-allrouters
EOF

# Configure sudo
echo "%wheel ALL=(ALL:ALL) ALL" | EDITOR="tee" visudo -f ${TARGET}/etc/sudoers.d/00-wheel

# Root password set
echo ${ROOT_PASSWORD} | arch-chroot ${TARGET} passwd --stdin root

# Systemd services
SYSTEMD_SERVICES=(
    "systemd-timesyncd.service"
    "systemd-oomd.service"
    "systemd-resolved.service"
)

# Enable systemd services
systemctl enable --root=${TARGET} "${SYSTEMD_SERVICES[@]}"

# Systemd timers
SYSTEMD_TIMERS=(
    "btrfs-scrub@-.timer"
    "btrfs-scrub@home.timer"
    "btrfs-scrub@pkg.timer"
    "btrfs-scrub@flatpak.timer"
    "btrfs-scrub@machines.timer"
    "btrfs-scrub@portables.timer"
    "btrfs-scrub@log.timer"
    "btrfs-scrub@\\x2esnapshots.timer"
)

# Enable systemd timers
systemctl enable --root=${TARGET} "${SYSTEMD_TIMERS[@]}"

# Install the bootloader
bootctl --esp-path=${TARGET}/efi install

# Create the cmdline.d folder
mkdir -p ${TARGET}/etc/cmdline.d

# Configure cmdline
echo "rd.luks.name=${ROOT_PART_UUID}=${LUKS_MAPPER}" > ${TARGET}/etc/cmdline.d/00-luks.conf
echo "root=${LUKS_CONTAINER}" > ${TARGET}/etc/cmdline.d/10-root.conf
echo "rootflags=subvol=@" > ${TARGET}/etc/cmdline.d/20-btrfs.conf
echo "rw loglevel=3" > ${TARGET}/etc/cmdline.d/30-parameters.conf

# Remove old reminecences from old mkinitcpio configuration
rm /boot/initramfs-linux.img

# Configure mkinitcpio
cat > ${TARGET}/etc/mkinitcpio.conf << EOF
MODULES=()
BINARIES=()
FILES=()
HOOKS=(systemd autodetect microcode modconf kms keyboard sd-vconsole sd-encrypt block filesystems)
EOF

# Configure linux kernel generation for mkinitcpio
cat > ${TARGET}/etc/mkinitcpio.d/linux.preset << EOF
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_uki="/efi/EFI/Linux/arch-linux.efi"
EOF

# Generate initramfs image
arch-chroot ${TARGET} mkinitcpio -P

# Exiting
umount -R /mnt
cryptsetup close ${LUKS_MAPPER}
#systemctl reboot

echo "==== O SCRIPT TERMINOU SEM ERROS ==="
