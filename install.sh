#!/bin/bash

# Drive to install to.
DRIVE='/dev/sda'

# Hostname of the installed machine.
HOSTNAME='arch'

# Main user to create (by default, added to wheel group, and others).
USER_NAME='morgan'

# System timezone.
TIMEZONE='Africa/Johannesburg'

# Have /tmp on a tmpfs or not.  Leave blank to disable.
# Only leave this blank on systems with very little RAM.
TMP_ON_TMPFS='TRUE'

KEYMAP='us'
# KEYMAP='dvorak'

# Choose your video driver
# For Intel
#VIDEO_DRIVER="i915"
# For nVidia
VIDEO_DRIVER="nouveau"
# For ATI
#VIDEO_DRIVER="radeon"
# For generic stuff
#VIDEO_DRIVER="vesa"

setup() {
    local boot_dev="$DRIVE"1
    local data_dev="$DRIVE"2

    echo 'Creating partitions'
    partition_drive "$DRIVE"

    echo 'Formatting filesystems'
    format_filesystems "$DRIVE"

    echo 'Mounting filesystems'
    mount_filesystems "$DRIVE"

    return

    echo 'Installing base system'
    install_base

    echo 'Chrooting into installed system to continue setup...'
    cp $0 /mnt/setup.sh
    arch-chroot /mnt ./setup.sh chroot

    if [ -f /mnt/setup.sh ]
    then
        echo 'ERROR: Something failed inside the chroot, not unmounting filesystems so you can investigate.'
        echo 'Make sure you unmount everything before you try to run this script again.'
    else
        echo 'Unmounting filesystems'
        unmount_filesystems
        echo 'Done! Reboot system.'
    fi
}

configure() {
    local boot_dev="$DRIVE"1

    # echo 'Installing additional packages'
    # install_packages

    # echo 'Clearing package tarballs'
    # clean_packages

    echo 'Setting hostname'
    set_hostname "$HOSTNAME"

    echo 'Setting timezone'
    set_timezone "$TIMEZONE"

    echo 'Setting locale'
    set_locale

    echo 'Setting console keymap'
    set_keymap

    echo 'Setting hosts file'
    set_hosts "$HOSTNAME"

    echo 'Setting fstab'
    set_fstab "$TMP_ON_TMPFS" "$boot_dev"

    echo 'Configuring sudo'
    set_sudoers

    echo 'Setting root password'
    set_root_password

    echo 'Creating initial user'
    create_user "$USER_NAME"

    rm /setup.sh
}

partition_drive() {
    local drive="$1"; shift

    parted -s "$drive" \
        mklabel gpt \
        mkpart primary ext2 1MiB 513MiB \
        mkpart primary linux-swap 538M 3G \
        mkpart primary ext4 3G 100% \
        set 1 boot on \
        quit
}

format_filesystems() {
    local drive="$1"; shift

    mkfs.ext2 -L boot "$drive"1
    mkfs.ext4 -L root "$drive"3

    mkswap "$drive"2
    swapon "$drive"2
}

mount_filesystems() {
    local drive="$1"; shift

    mount "$drive"3 /mnt
    mkdir /mnt/boot
    mount "$drive"1 /mnt/boot
}

install_base() {
    echo 'Server = http://mirrors.kernel.org/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist

    pacstrap /mnt base base-devel
}

unmount_filesystems() {
    umount /mnt/boot
    umount /mnt
    swapoff /dev/vg00/swap
    vgchange -an
}

install_packages() {
    local packages=''

    # General utilities/libraries
    packages+=' alsa-utils snapd sudo'

    # Development packages
    packages+=' git'

    # Xserver
    packages+=' xorg-apps xorg-server xorg-xinit xterm'

    # On Intel processors
    packages+=' intel-ucode'

    if [ "$VIDEO_DRIVER" = "i915" ]
    then
        packages+=' xf86-video-intel libva-intel-driver'
    elif [ "$VIDEO_DRIVER" = "nouveau" ]
    then
        packages+=' xf86-video-nouveau'
    elif [ "$VIDEO_DRIVER" = "radeon" ]
    then
        packages+=' xf86-video-ati'
    elif [ "$VIDEO_DRIVER" = "vesa" ]
    then
        packages+=' xf86-video-vesa'
    fi

    pacman -Sy --noconfirm $packages
}

clean_packages() {
    yes | pacman -Scc
}

set_hostname() {
    local hostname="$1"; shift

    echo "$hostname" > /etc/hostname
}

set_timezone() {
    local timezone="$1"; shift

    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
}

set_locale() {
    echo 'LANG="en_US.UTF-8"' >> /etc/locale.conf
    echo 'LC_COLLATE="C"' >> /etc/locale.conf
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
}

set_keymap() {
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
}

set_hosts() {
    local hostname="$1"; shift

    cat <<EOT >> /etc/hosts
127.0.0.1 localhost.localdomain localhost $hostname
::1       localhost.localdomain localhost $hostname
EOT
}

set_fstab() {
    local tmp_on_tmpfs="$1"; shift
    local boot_dev="$1"; shift

    local boot_uuid=$(get_uuid "$boot_dev")

    cat <<EOT >> /etc/fstab
#
# /etc/fstab: static file system information
#
# <file system> <dir>    <type> <options>    <dump> <pass>

/dev/vg00/swap none swap  sw                0 0
/dev/vg00/root /    ext4  defaults,relatime 0 1

UUID=$boot_uuid /boot ext2 defaults,relatime 0 2
EOT
}

set_sudoers() {
    cat  <<EOT >> /etc/sudoers
##
## User privilege specification
##
root ALL=(ALL) ALL

## Uncomment to allow members of group wheel to execute any command
%wheel ALL=(ALL) ALL

## Read drop-in files from /etc/sudoers.d
## (the '#' here does not indicate a comment)
#includedir /etc/sudoers.d
EOT

    chmod 440 /etc/sudoers
}

set_root_password() {
    passwd
}

create_user() {
    local name="$1"; shift

    useradd -m -g users -G wheel -s /bin/bash "$name"
    passwd "$name"
}

get_uuid() {
    blkid -o export "$1" | grep UUID | awk -F= '{print $2}'
}

set -ex

if [ "$1" == "chroot" ]
then
    configure
else
    setup
fi
