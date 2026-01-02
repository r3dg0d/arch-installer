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
YELLOW='\033[1;33m'
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
    echo -e "${RED}No disk selected.${NC}"
    exit 1
fi

echo -e "${YELLOW}WARNING: THIS WILL WIPE $DISK COMPLETELY!${NC}"
gum confirm "Are you absolutely sure you want to continue?" || exit 1

# ==============================================================================
# 2. DISK PARTITIONING & ENCRYPTION
# ==============================================================================

echo -e "\n${GREEN}Step 2: Wiping and Partitioning $DISK...${NC}"

# Validate disk exists
if [ ! -b "$DISK" ]; then
    echo -e "${RED}ERROR: Disk $DISK does not exist!${NC}"
    exit 1
fi

# Wipe disk completely
echo -e "${BLUE}Wiping disk...${NC}"
wipefs -a "$DISK" || echo "Warning: wipefs failed, continuing..."

# Create GPT partition table
echo -e "${BLUE}Creating partition table...${NC}"
parted -s "$DISK" mklabel gpt

# Create EFI partition (512MB)
echo -e "${BLUE}Creating EFI partition...${NC}"
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on

# Create root partition (rest of disk)
echo -e "${BLUE}Creating root partition...${NC}"
parted -s "$DISK" mkpart primary 513MiB 100%

# Set partition variables based on disk type
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

# Validate partitions exist
if [ ! -b "$EFI_PART" ] || [ ! -b "$ROOT_PART" ]; then
    echo -e "${RED}ERROR: Failed to create partitions!${NC}"
    exit 1
fi

# Encrypt root partition
echo -e "\n${BLUE}Encrypting root partition...${NC}"
echo -n "$ENC_PASSWORD" | cryptsetup -q luksFormat "$ROOT_PART"
echo -n "$ENC_PASSWORD" | cryptsetup open "$ROOT_PART" cryptroot

# Format filesystems
echo -e "${BLUE}Formatting filesystems...${NC}"
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 /dev/mapper/cryptroot

# Mount filesystems
echo -e "${BLUE}Mounting filesystems...${NC}"
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# ==============================================================================
# 3. BASE INSTALL
# ==============================================================================

echo -e "\n${GREEN}Step 3: Installing Base System...${NC}"
pacstrap /mnt base linux linux-firmware base-devel git vim networkmanager curl intel-ucode amd-ucode gum bluez bluez-utils

# Generate fstab
echo -e "${BLUE}Generating fstab...${NC}"
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
echo "KEYMAP=us" > /etc/vconsole.conf
echo "FONT=Lat2-Terminus16" >> /etc/vconsole.conf
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Create user and set passwords
echo "Creating user $USERNAME..."
useradd -m -G wheel,storage,power -s /bin/bash $USERNAME

echo "Setting passwords..."
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$ROOT_PASSWORD" | chpasswd

# Verify user was created successfully
if ! id "$USERNAME" &>/dev/null; then
    echo "ERROR: Failed to create user $USERNAME!"
    exit 1
fi

if ! groups "$USERNAME" | grep -q "wheel"; then
    echo "ERROR: User $USERNAME is not in wheel group!"
    exit 1
fi

echo "User $USERNAME created successfully with sudo access."
echo ""
echo "Installation Summary:"
echo "====================="
echo "Username: $USERNAME"
echo "Encryption Password: [SET] (will be required on boot to unlock disk)"
echo "Root Password: [SET]"
echo "User Password: [SET]"
echo ""
echo "On first boot:"
echo "1. Enter encryption password to unlock the disk"
echo "2. Login with username: $USERNAME and your user password"
echo "3. Hyprland will start automatically"

echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Install and configure bootloader (GRUB)
echo "Installing GRUB bootloader..."
pacman -S --noconfirm grub efibootmgr os-prober

# Configure GRUB for LUKS encryption
echo "Configuring GRUB for LUKS..."
ROOT_UUID=\$(blkid -s UUID -o value $ROOT_PART)
echo "Root partition UUID: \$ROOT_UUID"
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=\${ROOT_UUID}:cryptroot root=\/dev\/mapper\/cryptroot\"/g" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Configure initramfs for LUKS
echo "Configuring initramfs for encryption..."
sed -i 's/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/g' /etc/mkinitcpio.conf

echo "Building initramfs..."
if ! mkinitcpio -P; then
    echo "ERROR: Failed to build initramfs!"
    exit 1
fi

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
    nsxiv mpv vlc yt-dlp audacity kdenlive easyeffects obs-studio \
    firefox chromium tor-browser-bin \
    helium-browser-bin \
    telegram-desktop thunderbird \
    spotify-launcher \
    prismlauncher \
    cursor-bin \
    qbittorrent \
    keepassxc onionshare metadata-cleaner \
    flatseal mission-center peazip-qt-bin czkawka-gui-bin \
    timeshift virt-manager qemu-desktop switcheroo-control \
    dino senpai simplex-chat-bin \
    cups system-config-printer \
    wonderwall \
    waydroid \
    breezy \
    noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-twemoji-git ttf-jetbrains-mono ttf-font-awesome \
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

# Link Fastfetch config
ln -s /home/$USERNAME/dotfiles/.config/fastfetch /home/$USERNAME/.config/fastfetch

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

