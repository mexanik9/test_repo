#!/bin/sh
# MIT/zlib license
# Shell compatible installation script for concrete_arch
# BIOS/UEFI
# Modify SETTINGS SECTION according to your needs
# Requires ArchISO modification

#sed -i '/HOOKS=(/c\HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems resume fsck)' /etc/mkinitcpio.conf
# sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=${PART_LUKS_UUID}:luks_partition resume=/dev/system_vg/swap\"" /etc/default/grub



####### [Settings section]
## Alternatively "intel-ucode" for Intel processors
MICROCODE="amd-ucode" 

## Specify drivers for your GPU
VIDEO_DRIVERS="mesa"

## Packages to be installed
#SYSTEM_PACKAGES="nano less doas iwd nftables openssh pipewire pipewire-pulseaudio"
#BASIC_PACKAGES="abduco dvtm bc pass oathtool paperkey zip unzip rsync newsboat neomutt tldr arch-wiki-lite"
#EXTRA_PACKAGES=""
SYSTEM_PACKAGES="nano less"
BASIC_PACKAGES="abduco dvtm"
EXTRA_PACKAGES="bc"

## User settings
HOST_NAME="mycomputer"
USER_NAME="user"
TIMEZONE_REGION="Europe"
TIMEZONE_CITY="Moscow"

## Extra options
# 'true' to enable option, anything else to disable it
DISABLE_LIDSWITCH="false"
DISABLE_POWER_KEY="false" # On some laptops it is usually better to disable power key altogether
DISABLE_SUSPEND="false" # On some laptops suspend can cause issues or does not work properly

## TTY settings
# select alternative keyboard layout and font
# leave empty if not required
# https://wiki.archlinux.org/title/Linux_console#Fonts
TTY_KEYMAP=""
TTY_FONT=""
####### [End of settings section]




####### [Internal]
delete_lines() {
    _N=$1
    while [ "${_N}" -ne 0 ]
    do
        printf "\x1b[A\x1b[2K"
        _N=$(("${_N}"-1))
    done
}

display_section() {
    printf "\x1b[1;7m::::::::[%s]\x1b[0m\n" "$1"
}

display_error() {
    printf "\x1b[1;31m:: %s\x1b[0m\n" "$1"
}

display_heading() {
    printf "\x1b[1;36m:: \x1b[37m%s\x1b[0m\n" "$1"
}

get_input() {
    printf "\x1b[1;35m==> \x1b[37m%s:\x1b[0m " "$1"
    read -r _INPUT_LINE
    delete_lines 1
}

get_confirmation() {
    printf "\x1b[1;36m:: \x1b[37m%s \x1b[0m\n" "$1"
    while true
    do    
        printf "\x1b[1;36m==> \x1b[37mEnter '\x1b[36mYESIAMSURE\x1b[37m' to continue or '\x1b[36mCtrl-C\x1b[37m' to terminate process: \x1b[0m"
        read -r _INPUT_LINE
        if [ "$_INPUT_LINE" = "YESIAMSURE" ]; then 
            delete_lines 1
            printf "\x1b[1;36m:: \x1b[37mConfirmed\x1b[0m\n"
            break; 
        else 
            delete_lines 1; 
            continue; 
        fi
    done
}

get_confirmation_or_retry() {
    while true
    do    
        printf "\x1b[1;36m:: \x1b[37m%s: \x1b[7m %s \x1b[0m\n" "$1" "$2"
        printf "\x1b[1;35m==> \x1b[37mEnter '\x1b[36mYESIAMSURE\x1b[37m' to continue or '\x1b[36mTRY\x1b[37m' to try again: \x1b[0m"
        read -r _INPUT_LINE
        if [ "$_INPUT_LINE" = "YESIAMSURE" ]; then 
            delete_lines 1
            printf "\x1b[1;36m:: \x1b[32mConfirmed\x1b[0m\n"
            return 0
        elif [ "$_INPUT_LINE" = "TRY" ]; then
            delete_lines 2
            return 1
        else
            delete_lines 2
            continue
        fi
    done
}

terminate_process() {
    # unmount
    # deactivate lvm
    # close luks
    display_heading "Installation process terminated!"
    exit
}

get_uefi() {
    if ls /sys/firmware/efi/fw_platform_size >/dev/null 2>&1; then BOOT_MODE=UEFI; else BOOT_MODE=BIOS; fi
    display_heading "Detected boot mode: \x1b[7m ${BOOT_MODE} \x1b[0m"
    printf "\n"
}

get_block_device() {
    display_heading "Select block device"
    printf "\x1b[1m::\x1b[0m\n"
    lsblk --scsi --noheadings --paths --output PATH,TYPE,MODEL,TRAN,SIZE && lsblk --nvme --noheadings --paths --output PATH,TYPE,MODEL,TRAN,SIZE
    printf "\x1b[1m::\x1b[0m\n"

    while true
    do
        get_input "Enter block device path"
        if [ -z "$_INPUT_LINE" ] || [ ! -b "$_INPUT_LINE" ]; then
            display_error "'${_INPUT_LINE}' is not a valid block device!"
            sleep 3
            delete_lines 3
            continue
        else
            BLOCK_DEVICE="$_INPUT_LINE"
            get_confirmation_or_retry "Confirm selected block device" "${BLOCK_DEVICE}"
            if [ $? -eq 0 ]; then break; else delete_lines 3; continue; fi
        fi
    done

    printf "\n"
}

get_part_sizes() {
    display_heading "Specify partition and volume sizes"

    # EFI
    if [ "$BOOT_MODE" = "UEFI" ]; then
        while true
        do
            get_input "Enter EFI partition size (GiB)"
            _SIZE="$_INPUT_LINE"
            if [ -n "$_SIZE" ]; then
                get_confirmation_or_retry "Confirm EFI partition size (GiB)" "${_SIZE}GiB"
                if [ $? -eq 0 ]; then PART_EFI_SIZE="$_PASSWORD"; break; else continue; fi
            else
                continue
            fi
        done
    fi

    #LVs
    while true
    do
        get_input "Enter ROOT logical volume(LV) size (GiB)";
        if [ -z "$_INPUT_LINE" ]; then continue; fi
        LV_ROOT_SIZE="$_INPUT_LINE"
        display_heading "ROOT LV set to ${LV_ROOT_SIZE}"
        get_input "Enter SWAP logical volume(LV) size (GiB)";
        if [ -z "$_INPUT_LINE" ]; then delete_lines 1; continue; fi
        LV_SWAP_SIZE="$_INPUT_LINE"
        display_heading "SWAP LV set to ${LV_SWAP_SIZE}"
        get_input "Enter HOME logical volume(LV) size (GiB)";
        if [ -z "$_INPUT_LINE" ]; then delete_lines 2; continue; fi
        LV_HOME_SIZE="$_INPUT_LINE"
        delete_lines 2

        get_confirmation_or_retry "Confirm LVs" "ROOT=${LV_ROOT_SIZE}GiB SWAP=${LV_SWAP_SIZE}GiB HOME=${LV_HOME_SIZE}GiB"
        if [ $? -eq 0 ]; then break; else continue; fi
    done

    printf "\n"
}

get_passwords() {
    display_heading "Entering system passwords. Make sure you remember them!"

    # luks
    while true
    do
        get_input "Enter LUKS encryption password"
        _PASSWORD="$_INPUT_LINE"
        if [ -n "$_PASSWORD" ]; then
            get_confirmation_or_retry "Confirm LUKS encryption password" "${_PASSWORD}"
            if [ $? -eq 0 ]; then PASSWORD_LUKS="$_PASSWORD"; break; else continue; fi
        else
            continue
        fi
    done

    # root
    while true
    do
        get_input "Enter root password"
        _PASSWORD="$_INPUT_LINE"
        if [ -n "$_PASSWORD" ]; then
            get_confirmation_or_retry "Confirm ROOT password" "${_PASSWORD}"
            if [ $? -eq 0 ]; then PASSWORD_ROOT="$_PASSWORD"; break; else continue; fi
        else
            continue
        fi
    done

    # # user
    while true
    do
        get_input "Enter password for user '${USER_NAME}'"
        _PASSWORD="$_INPUT_LINE"
        if [ -n "$_PASSWORD" ]; then
            get_confirmation_or_retry "Confirm password for user '${USER_NAME}'" "${_PASSWORD}"
            if [ $? -eq 0 ]; then PASSWORD_USER="$_PASSWORD"; break; else continue; fi
        else
            continue
        fi
    done

    printf "\n"
}

VERSION="0.1a"
####### [End of internal]




####### [Begin]
trap 'terminate_process "Received SIGINT!"' 2 # trap SIGINT
display_section "concrete_mixer v${VERSION}"
display_heading "This installation script will install <concrete_arch> on your machine"
display_heading "Make sure to BACKUP ALL YOUR DATA before starting installation process"
display_heading "This script will FORMAT YOUR HARD DRIVE!"
display_heading "Internet connection is required!"
display_heading "Check <wiki.archlinux.org> for additional info"

get_confirmation "Start installation process?"

get_uefi
get_block_device
get_part_sizes
get_passwords

get_confirmation "Continue installation process?"

# check connectivity
if ! ping -c 4 -w 5 archlinux.org; then display_error "Unable to reach 'archlinux.org'!"; terminate_process; fi
####### [End of begin]




####### [Disk formatting]
display_section "Block device formatting"

## Confirm selection
display_heading "Formatting ${BLOCK_DEVICE}"

## Set up EFI and LUKS partitions
display_heading "Partitioning block device"
if printf "label: gpt\n size=%sG, type=uefi, name=\"EFI System Partition\", bootable*\n size=+, name=\"LUKS Partition\"" "$PART_EFI_SIZE" | sfdisk "$BLOCK_DEVICE"; then
    PART_EFI=$(sfdisk --dump | grep "EFI System Partition" | cut --delimiter ' ' --fields 1)
    PART_LUKS=$(sfdisk --dump | grep "LUKS Container Partition" | cut --delimiter ' ' --fields 1)
else
    display_error "Error! Unable to partition block device!"
    terminate_process
fi
printf "\n"

## Initialize and open LUKS container
display_heading "Initializing LUKS on partition ${PART_LUKS}"
if ! echo "$PASSWORD_LUKS" | cryptsetup luksFormat --verify-passphrase --verbose --type luks2 "$PART_LUKS" -; then
    display_error "Error initializing LUKS partition!"
    terminate_process
fi
display_heading "Opening LUKS partition"
if ! echo "$PASSWORD_LUKS" | cryptsetup --allow-discards --persistent open "$PART_LUKS" luks_partition -; then
    display_error "Error opening LUKS partition!"
    terminate_process
fi
printf "\n"

## Initialize LVM within LUKS container
display_heading "Initializing LVM within LUKS container"
pvcreate /dev/mapper/luks_partition
vgcreate system_vg /dev/mapper/luks_partition
lvcreate --size "${LV_SWAP_SIZE}"G system_vg --name swap
lvcreate --size "${LV_ROOT_SIZE}"G system_vg --name root
lvcreate --size "${LV_HOME_SIZE}"G system_vg --name home
printf "\n"
mkfs.fat -F32 "$PART_EFI"
mkfs.ext4 /dev/system_vg/root
mkfs.ext4 /dev/system_vg/home
mkswap /dev/system_vg/swap
printf "\n"
####### [End of disk formatting]




####### [Basic system]
display_section "Basic system installation"

## Mount filesystems and enable swap
display_heading "Mounting file systems"
mount --mkdir "$PART_EFI" /mnt/boot
mount /dev/system_vg/root /mnt
mount --mkdir /dev/system_vg/home /mnt/home
swapon /dev/system_vg/swap
printf "\n"

## Install packages
display_heading "Installing packages"
pacstrap -K /mnt base linux linux-firmware lvm2 "$MICROCODE" "$VIDEO_DRIVERS" "$SYSTEM_PACKAGES" "$BASIC_PACKAGES" "$EXTRA_PACKAGES"
printf "\n"

## Generate fstab
display_heading "Generating fstab"
genfstab -t UUID /mnt >> /mnt/etc/fstab
printf "\n"

## Chroot into new system
display_heading "Chrooting into the system"
arch-chroot /mnt
printf "\n"

## Set time zone
display_heading "Setting timezone"
ln -sf /usr/share/zoneinfo/$TIMEZONE_REGION/$TIMEZONE_CITY /etc/localtime
printf "\n"

## Hardware clock setup
display_heading "Hardware clock setup"
hwclock --systohc
printf "\n"

## Generate locale
display_section "Generating locale"
sed -i '/#en_US.UTF UTF-8/c\en_US.UTF UTF-8' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
printf "\n"

## Network configuration
display_section "Network configuraion"
echo "$HOST_NAME" > /etc/hostname
printf "\n"

## Initramfs configuration
display_section "Configuring initramfs"
sed -i '/HOOKS=(/c\HOOKS=(systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt lvm2 filesystems fsck)' /etc/mkinitcpio.conf
mkinitcpio -P
printf "\n"

## Bootloader
display_section "Configuring bootloader"
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
PART_LUKS_UUID=$(lsblk --noheadings --nodeps --output=UUID /dev/mapper/luks_partition)
sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet rd.luks.name=${PART_LUKS_UUID}=luks_partition resume=/dev/system_vg/swap\"" /etc/default/grub
sed -i '/GRUB_DEFAULT=/c\GRUB_DEFAULT=saved' /etc/default/grub
sed -i '/GRUB_SAVEDEFAULT=/c\GRUB_SAVEDEFAULT=true' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
printf "\n"

## Root password
display_heading "Setting up root password"
echo "$PASSWORD_ROOT" | passwd -s
printf "\n"
####### [End of basic system]




####### [System configuration]
## Enable useful services
display_heading "Enabling services"
systemctl enable fstrim.timer
systemctl enable paccache.timer
printf "\n"

## Disable powerkey
if [ "$DISABLE_POWER_KEY" = "true" ]; then
    display_heading "Disabling power key"
    printf "[Login]\nHandlePowerKey=Ignore\n" > /etc/systemd/logind.conf.d/disable_power_key.conf
fi
printf "\n"

## Disable lid switch
if [ "$DISABLE_LIDSWITCH" = "true" ]; then
    display_heading "Disabling lid switch"
    printf "[Login]\nHandleLidSwitch=Ignore\nHandleLidSwitchDocked=ignore\n" > /etc/systemd/logind.conf.d/disable_lid_switch.conf
fi
printf "\n"

## Disable suspend
if [ "$DISABLE_SUSPEND" = "true" ]; then
    display_heading "Disabling suspend"
    printf "[Sleep]\nAllowSuspend=no\nAllowSuspendThenHibernate=no\n" > /etc/systemd/sleep.conf.d/disable_suspend.conf
fi
printf "\n"

## Set up user
display_heading "Creating user: '${USER_NAME}'"
useradd -m -G wheel "$USER_NAME"
passwd "$USER_NAME"
printf "\n"

## doas configuration


####### [End of system configuration]




####### [Additional configuration]
####### [End of additional configuration]





####### [Reboot]



####### [After]
# backlight
# power tools
