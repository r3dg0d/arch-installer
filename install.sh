#!/bin/bash
#
# Arch Linux Clean Install Script
# For ThinkPad T480s (and others)
# Includes Hyprland, Noctalia Shell, FDE, and Rice
#

# Stop on error
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Check if run as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

# Install Gum for UI if not present
if ! command -v gum &> /dev/null; then
    echo -e "${BLUE}Installing gum for UI...${NC}"
    pacman -Sy --noconfirm gum
fi

clear
echo -e "${BLUE}
   _    ____   ____ _   _ 
  / \  |  _ \ / ___| | | |
 / _ \ | |_) | |   | |_| |
/ ___ \|  _ <| |___|  _  |
/_/   \_\_| \_\\____|_| |_|

   ARCH LINUX INSTALLER - NOCTALIA EDITION
${NC}"

# ==============================================================================
# 1. USER INPUTS
# ==============================================================================

echo -e "\n${GREEN}Step 1: Configuration${NC}"

HOSTNAME=$(gum input --placeholder "Hostname" --value "archlinux")
USERNAME=$(gum input --placeholder "Username" --value "user")
PASSWORD=$(gum input --password --placeholder "User Password")
ROOT_PASSWORD=$(gum input --password --placeholder "Root Password")
ENC_PASSWORD=$(gum input --password --placeholder "Disk Encryption Password")

# Select Disk
DISK=$(gum choose $(lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop" | awk '{print "/dev/"$1" ("$2" "$3")"}') | awk '{print $1}')

if [ -z "$DISK" ]; then
    echo "No disk selected."
    exit 1
fi

gum confirm "WARNING: THIS WILL WIPE $DISK. CONTINUE?" || exit 1

# ==============================================================================
# 2. DISK PARTITIONING & ENCRYPTION
# ==============================================================================

echo -e "\n${GREEN}Step 2: Wiping and Partitioning $DISK...${NC}"

# Wipe
wipefs -a "$DISK"

# Partition layout:
# 1. EFI (512M)
# 2. Swap (Optional, using swapfile or partition? Let's go simple partition for hibernate support on laptop)
#    Actually, swapfile on Btrfs is fine, but let's stick to standard layout.
#    Let's do: EFI (512M), Root (Rest) -> LUKS -> LVM/Btrfs
#    We'll do a simple LUKS on Partition 2.

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary 513MiB 100%

EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"

# NVMe drives use p1/p2, SATA uses 1/2. Adjust if needed.
if [[ "$DISK" != *"nvme"* ]] && [[ "$DISK" != *"mmcblk"* ]]; then
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

# Encrypt Root
echo -e "\n${BLUE}Encrypting Root Partition...${NC}"
echo -n "$ENC_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" -
echo -n "$ENC_PASSWORD" | cryptsetup open "$ROOT_PART" cryptroot -

# Format
echo -e "\n${BLUE}Formatting filesystems...${NC}"
mkfs.fat -F32 "$EFI_PART"
mkfs.btrfs -L arch /dev/mapper/cryptroot

# Mount
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
umount /mnt

mount -o subvol=@,compress=zstd /dev/mapper/cryptroot /mnt
mkdir -p /mnt/home
mount -o subvol=@home,compress=zstd /dev/mapper/cryptroot /mnt/home
mkdir -p /mnt/var
mount -o subvol=@var,compress=zstd /dev/mapper/cryptroot /mnt/var

mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# ==============================================================================
# 3. BASE INSTALL
# ==============================================================================

echo -e "\n${GREEN}Step 3: Installing Base System...${NC}"
pacstrap /mnt base linux linux-firmware base-devel git vim networkmanager intel-ucode amd-ucode gum bluez bluez-utils

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# ==============================================================================
# 4. CHROOT SCRIPT
# ==============================================================================

cat <<EOF > /mnt/install_chroot.sh
#!/bin/bash
set -e

# Setup Time & Locale
ln -sf /usr/share/zoneinfo/US/Pacific /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Users
useradd -m -G wheel,storage,power -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$ROOT_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Bootloader (GRUB)
pacman -S --noconfirm grub efibootmgr
# Edit /etc/default/grub for LUKS
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet cryptdevice=UUID=$(blkid -s UUID -o value $ROOT_PART):cryptroot root=\/dev\/mapper\/cryptroot"/g' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# MKINITCPIO
sed -i 's/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/g' /etc/mkinitcpio.conf
mkinitcpio -P

# Enable Services
systemctl enable NetworkManager
systemctl enable bluetooth

# ------------------------------------------------------------------------------
# AUR & PACKAGES
# ------------------------------------------------------------------------------

# Install Yay
cd /home/$USERNAME
sudo -u $USERNAME git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
sudo -u $USERNAME makepkg -si --noconfirm
cd ..
rm -rf yay-bin

# Install Packages
# Using yay for everything to handle AUR dependencies easily
sudo -u $USERNAME yay -S --noconfirm \
    hyprland hyprpaper hyprlock hypridle xdg-desktop-portal-hyprland \
    flatpak \
    kitty thunar tumbler thunar-archive-plugin file-roller \
    imv mpv vlc audacity kdenlive easyeffects obs-studio \
    firefox chromium tor-browser-bin \
    helium-browser-bin \
    vesktop-bin telegram-desktop discord thunderbird \
    spotify \
    prismlauncher pcsx2 \
    cursor-bin \
    mullvad-vpn-bin \
    qbittorrent \
    keepassxc onionshare metadata-cleaner \
    flatseal mission-center-bin peazip-qt-bin czkawka-gui-bin \
    timeshift virt-manager qemu-desktop switcheroo-bin \
    dino senpai simplex-chat-desktop-bin \
    cups system-config-printer \
    wonderwall \
    waydroid \
    bazarr \
    constrict \
    localsend-bin \
    noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-twemoji ttf-jetbrains-mono ttf-font-awesome \
    noctalia-shell \
    fastfetch \
    polkit-gnome \
    qt5-wayland qt6-wayland

# Noctalia Setup
# Assuming noctalia-shell is in AUR or installed above.

# ------------------------------------------------------------------------------
# 5. SYSTEM UPDATE & DOTFILES
# ------------------------------------------------------------------------------

echo "Cloning dotfiles..."
sudo -u $USERNAME git clone https://github.com/r3dg0d/dotfiles.git /home/$USERNAME/dotfiles

# Link .bashrc
rm /home/$USERNAME/.bashrc
ln -s /home/$USERNAME/dotfiles/.bashrc /home/$USERNAME/.bashrc

# Link Ghostty
mkdir -p /home/$USERNAME/.config
ln -s /home/$USERNAME/dotfiles/.config/ghostty /home/$USERNAME/.config/ghostty

# Clone System Update Script
echo "Installing System Update Script..."
sudo -u $USERNAME git clone https://github.com/r3dg0d/arch-system-update.git /home/$USERNAME/arch-system-update
chmod +x /home/$USERNAME/arch-system-update/system-update
ln -s /home/$USERNAME/arch-system-update/system-update /usr/local/bin/system-update

# Ensure permissions
chown -R $USERNAME:$USERNAME /home/$USERNAME

EOF

chmod +x /mnt/install_chroot.sh

echo -e "\n${GREEN}Step 4: Entering Chroot...${NC}"
arch-chroot /mnt ./install_chroot.sh

# Cleanup
rm /mnt/install_chroot.sh
umount -R /mnt
swapoff -a

echo -e "\n${GREEN}Installation Complete! Rebooting in 5 seconds...${NC}"
sleep 5
reboot

