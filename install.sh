#!/usr/bin/env bash

kernel_params="rw loglevel=3 quiet"

kernels=(
    linux
    linux-lts
)

packages=(
    dracut
    base
    linux-firmware
    sof-firmware
    networkmanager
)

packages+=("${kernels[@]}")

boot_partition=$1
root_partition=$2
home_partition=$3

disk_of_partition () {
    partition=$1
    disk=$(lsblk -n -o PKNAME "$partition")
    echo "/dev/$disk"
}

partition_num () {
    partition=$1
    echo $(lsblk -n -o MIN "$partition")
}

partition_fs_type () {
    partition=$1
    echo $(lsblk -n -o FSTYPE "$partition")
}

partition_fs_uuid () {
    partition=$1
    echo $(lsblk -n -o UUID "$partition")
}

root="/archinstall"

boot_partition_num=$(partition_num $boot_partition)
boot_disk=$(disk_of_partition $boot_partition)

mkfs -F -t ext4 "$root_partition"
mkfs.fat -F 32 "$boot_partition"

if [[ -z "$(partition_fs_type $home_partition)" ]]; then
    mkfs -F -t ext4 "$home_partition"
fi

parted "$boot_disk" "set $boot_partition_num boot on"

root_uuid=$(partition_fs_uuid $root_partition)

mkdir -p "$root"
mount "$root_partition" "$root"

mkdir -p "$root/boot"
mkdir -p "$root/home"

mount "$boot_partition" "$root/boot"
mount "$home_partition" "$root/home"

pacstrap $root ${packages[@]}

arch-chroot "$root" bash -c "systemctl enable NetworkManager"

genfstab -U "$root" > "$root/etc/fstab"

echo "archlinux" > "$root/etc/hostname"

# Loopback entries
echo "127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4" >> "$root/etc/hosts"
echo "::1         localhost localhost.localdomain localhost6 localhost6.localdomain6" >> "$root/etc/hosts"

echo "Type your new username: "
read username
arch-chroot "$root" bash -c "useradd -G wheel -s /bin/bash -m '$username'"
while ! arch-chroot "$root" bash -c "passwd '$username'"; do
    echo ""
done

kernels_reversed=( $(printf '%s\n' "${kernels[@]}" | tac) )
for kernel in "${kernels_reversed[@]}"
do
    efibootmgr --create \
    --disk "$boot_disk" --part $boot_partition_num \
    --label "Arch Linux$( [[ "$kernel" != "linux" ]] && echo " ($kernel)" )" \
    --loader "/vmlinuz-$kernel" \
    --unicode "root=UUID=$root_uuid $kernel_params initrd=\initramfs-$kernel.img"
done

umount "$root/boot"
umount "$root/home"
umount "$root"
