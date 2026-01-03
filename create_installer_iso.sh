#!/bin/bash
#
# Create Custom Arch Linux INSTALLER ISO (like OMArchY)
# This creates an ISO that installs your Hyprland setup, not just a live environment
#

set -e

echo "🚀 Creating ULTRA-MINIMAL Hyprland Arch Linux INSTALLER ISO..."
echo "⚡ This version installs FAST (no Qt dependencies) - add packages later!"

# Create custom profile
echo "📁 Setting up minimal installer profile..."
sudo mkdir -p ~/arch-installer-iso
cd ~/arch-installer-iso

# Create basic profile structure
sudo mkdir -p {work,out}
sudo mkdir -p airootfs/root

# Create packages list - ULTRA MINIMAL (no Qt dependencies)
cat > packages.x86_64 << 'EOF'
# Base installer packages only
base
linux
linux-firmware
base-devel
vim
networkmanager
curl
intel-ucode
amd-ucode
gum
git

# Essential fonts (no emoji/fonts that pull Qt)
noto-fonts
ttf-dejavu
ttf-liberation

# Minimal terminal
kitty
EOF

# Create pacman config with multilib enabled
sudo cp /etc/pacman.conf airootfs/etc/

# Create installation script that runs automatically
sudo tee airootfs/root/autoinstall.sh > /dev/null << 'EOF'
#!/bin/bash
#
# Automatic Installation Script for Custom Hyprland ISO
#

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${BLUE}"
echo "   _    ____   ____ _   _  "
echo "  / \  |  _ \ / ___| | | | "
echo " / _ \ | |_) | |   | |_| | "
echo "/ ___ \|  _ <| |___|  _  | "
echo "/_/   \_\_| \_\\____|_| |_| "
echo ""
echo "   HYPRLAND ARCH INSTALLER"
echo "     Custom Edition"
echo "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Get user input
echo -e "\n${GREEN}Configuration${NC}"
HOSTNAME=$(gum input --placeholder "Hostname" --value "hyprland")
USERNAME=$(gum input --placeholder "Username" --value "user")
DISK=$(gum choose $(lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop" | awk '{print "/dev/"$1" ("$2" "$3")"}') | awk '{print $1}')

if [ -z "$DISK" ]; then
    echo -e "${RED}No disk selected!${NC}"
    exit 1
fi

echo -e "${YELLOW}WARNING: This will WIPE $DISK completely!${NC}"
gum confirm "Continue?" || exit 1

# Disk setup (similar to your installer)
echo -e "\n${GREEN}Setting up disk...${NC}"

# Wipe disk
wipefs -a "$DISK"

# Partition
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary 513MiB 100%

EFI_PART="${DISK}1"
ROOT_PART="${DISK}2"

# Encrypt and format
echo "Encrypting disk..."
cryptsetup luksFormat "$ROOT_PART"
cryptsetup open "$ROOT_PART" cryptroot

mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 /dev/mapper/cryptroot

# Mount
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# Install base system
echo -e "\n${GREEN}Installing base system...${NC}"
pacstrap /mnt base linux linux-firmware base-devel git vim networkmanager curl intel-ucode amd-ucode

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Copy chroot script and execute
cat > /mnt/install_chroot.sh << 'CHROOT_EOF'
#!/bin/bash
set -e

# Setup locale and timezone
ln -sf /usr/share/zoneinfo/US/Pacific /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
echo "FONT=Lat2-Terminus16" >> /etc/vconsole.conf

# Hostname
echo "hyprland" > /etc/hostname

# Create user
useradd -m -G wheel,storage,power -s /bin/bash user
echo "user:password" | chpasswd
echo "root:root" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Install Yay
cd /home/user
sudo -u user git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
sudo -u user makepkg -si --noconfirm
cd ..
rm -rf yay-bin

# Install minimal desktop environment (user can add more later)
sudo -u user yay -S --noconfirm \
    hyprland hyprpaper hyprlock hypridle xdg-desktop-portal-hyprland \
    kitty thunar nsxiv mpv yt-dlp \
    noctalia-shell fastfetch polkit-gnome qt5-wayland qt6-wayland

# Setup bootloader
pacman -S --noconfirm grub efibootmgr
ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot)
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=${ROOT_UUID}:cryptroot root=\/dev\/mapper\/cryptroot\"/g" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Configure initramfs
sed -i 's/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/g' /etc/mkinitcpio.conf
mkinitcpio -P

# Enable services
systemctl enable NetworkManager bluetooth

# Setup basic dotfiles (minimal)
cd /home/user
sudo -u user git clone https://github.com/r3dg0d/dotfiles.git .dotfiles
sudo -u user ln -s .dotfiles/.bashrc .bashrc
sudo -u user mkdir -p .config
sudo -u user ln -s ../.dotfiles/.config/fastfetch .config/fastfetch 2>/dev/null || true

chown -R user:user /home/user

echo "Installation complete! Remove installation media and reboot."
CHROOT_EOF

chmod +x /mnt/install_chroot.sh
arch-chroot /mnt ./install_chroot.sh
rm /mnt/install_chroot.sh

# Cleanup
umount -R /mnt
cryptsetup close cryptroot

echo -e "\n${GREEN}✅ Installation complete!${NC}"
echo "Remove the USB drive and reboot to start your Hyprland system!"
echo ""
echo "Default login:"
echo "Username: user"
echo "Password: password"
echo ""
echo "Root password: root"
EOF

# Make the script executable
sudo chmod +x airootfs/root/autoinstall.sh

# Create profile configuration
cat > profiledef.sh << 'EOF'
#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="hyprland-arch"
iso_label="HYPR_ARCH_$(date +%Y%m)"
iso_publisher="Custom Hyprland Arch Linux"
iso_application="Hyprland Arch Linux Installer"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito' 'uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' -Xdict-size '1M')
bootstrap_tarball_compression=('xz')
file_permissions=(
  ["/root/autoinstall.sh"]="0:0:755"
)
EOF

# Build the ISO
echo "🔨 Building the installer ISO (this will take 30-60 minutes)..."
sudo mkarchiso -v .

echo "✅ Custom Hyprland Arch Linux Installer ISO created!"
echo "📁 Location: ~/arch-installer-iso/out/"
ls -la ~/arch-installer-iso/out/