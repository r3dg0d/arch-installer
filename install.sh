#!/bin/bash
#
# Arch Linux Post-Installation Setup Script
# Hyprland + Noctalia Shell Desktop Environment
# Run after minimal Arch Linux installation
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

   ARCH LINUX POST-INSTALL - HYPRLAND + NOCTALIA
${NC}"

echo -e "${YELLOW}This script assumes you already have a minimal Arch Linux installation.${NC}"
echo -e "${YELLOW}It will install and configure Hyprland + Noctalia Shell desktop environment.${NC}"

# ==============================================================================
# 1. USER CONFIGURATION
# ==============================================================================

echo -e "\n${GREEN}Step 1: User Configuration${NC}"

# Get current username if not specified
if [ -z "$1" ]; then
    CURRENT_USER=$(logname 2>/dev/null || whoami)
    USERNAME=$(gum input --placeholder "Username" --value "$CURRENT_USER")
else
    USERNAME="$1"
fi

# Verify user exists
if ! id "$USERNAME" &>/dev/null; then
    echo -e "${RED}User $USERNAME does not exist!${NC}"
    exit 1
fi

echo -e "${BLUE}Setting up desktop environment for user: $USERNAME${NC}"

# ==============================================================================
# 2. SYSTEM UPDATES & DEPENDENCIES
# ==============================================================================

echo -e "\n${GREEN}Step 2: System Updates & Dependencies${NC}"

# Update system
echo -e "${BLUE}Updating system packages...${NC}"
pacman -Syu --noconfirm

# Install essential dependencies
echo -e "${BLUE}Installing essential dependencies...${NC}"
pacman -S --noconfirm --needed \
    base-devel \
    git \
    intel-ucode \
    bluez \
    bluez-utils \
    gum

# ==============================================================================
# 3. DESKTOP ENVIRONMENT SETUP
# ==============================================================================

echo -e "\n${GREEN}Step 3: Desktop Environment Setup${NC}"

# Enable Services
echo -e "${BLUE}Enabling system services...${NC}"
systemctl enable NetworkManager
systemctl enable bluetooth

# ------------------------------------------------------------------------------
# AUR & PACKAGES
# ------------------------------------------------------------------------------

# Install Yay
echo -e "${BLUE}Installing Yay AUR helper...${NC}"
cd /home/$USERNAME
sudo -u $USERNAME git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
sudo -u $USERNAME makepkg -si --noconfirm
cd ..
rm -rf yay-bin

# Install Packages
echo -e "${BLUE}Installing Hyprland and Noctalia Shell...${NC}"
sudo -u $USERNAME yay -S --noconfirm \
    hyprland xdg-desktop-portal-hyprland \
    noctalia-shell \
    kitty \
    noto-fonts noto-fonts-cjk noto-fonts-emoji \
    polkit-gnome \
    qt5-wayland qt6-wayland

# Noctalia Setup
echo -e "${BLUE}Enabling Noctalia service for automatic startup...${NC}"
sudo -u $USERNAME systemctl --user enable noctalia.service

# Create basic Hyprland configuration for auto-startup
echo -e "${BLUE}Creating basic Hyprland configuration...${NC}"
mkdir -p /home/$USERNAME/.config/hypr
cat > /home/$USERNAME/.config/hypr/hyprland.conf << 'EOF'
# Basic Hyprland configuration for Noctalia
exec-once = noctalia-shell

# Environment variables
env = XCURSOR_SIZE,24

# Basic monitor and input settings
monitor=,preferred,auto,auto

# Basic window rules
windowrulev2 = float,class:(.*)

# Basic keybindings
$mainMod = SUPER

bind = $mainMod, Q, exec, kitty
bind = $mainMod, M, exit,
bind = $mainMod, C, killactive,
bind = $ALT, F4, killactive,

# Switch workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5

# Move active window to workspace
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5

# Scroll through workspaces
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1

# Move/resize windows
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow
EOF

# Set up environment for Hyprland/Wayland
echo -e "${BLUE}Setting up Wayland environment...${NC}"
cat >> /home/$USERNAME/.bashrc << 'EOF'

# Wayland/Hyprland environment
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export MOZ_ENABLE_WAYLAND=1
export SDL_VIDEODRIVER=wayland
export _JAVA_AWT_WM_NONREPARENTING=1
EOF

# Create .xinitrc for manual startup if needed
cat > /home/$USERNAME/.xinitrc << 'EOF'
#!/bin/sh
# Start Hyprland with Noctalia
exec Hyprland
EOF
chmod +x /home/$USERNAME/.xinitrc

# Create a systemd user service to start Hyprland automatically
mkdir -p /home/$USERNAME/.config/systemd/user
cat > /home/$USERNAME/.config/systemd/user/hyprland-session.service << 'EOF'
[Unit]
Description=Hyprland session with Noctalia
Wants=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/Hyprland
Restart=no
EOF

# Enable the Hyprland session service
sudo -u $USERNAME systemctl --user enable hyprland-session.service

# ------------------------------------------------------------------------------
# 4. OPTIONAL DOTFILES & TOOLS
# ------------------------------------------------------------------------------

echo -e "\n${GREEN}Step 4: Optional Dotfiles & Tools${NC}"

# Clone dotfiles (optional)
if gum confirm "Clone your dotfiles from GitHub?"; then
    echo -e "${BLUE}Cloning dotfiles...${NC}"
    sudo -u $USERNAME git clone https://github.com/r3dg0d/dotfiles.git /home/$USERNAME/dotfiles

    # Link .bashrc
    rm /home/$USERNAME/.bashrc
    ln -s /home/$USERNAME/dotfiles/.bashrc /home/$USERNAME/.bashrc

    # Link configs if they exist
    if [ -d "/home/$USERNAME/dotfiles/.config/ghostty" ]; then
        ln -s /home/$USERNAME/dotfiles/.config/ghostty /home/$USERNAME/.config/ghostty
    fi
    if [ -d "/home/$USERNAME/dotfiles/.config/fastfetch" ]; then
        ln -s /home/$USERNAME/dotfiles/.config/fastfetch /home/$USERNAME/.config/fastfetch
    fi
fi

# Clone System Update Script (optional)
if gum confirm "Install system update script?"; then
    echo -e "${BLUE}Installing System Update Script...${NC}"
    sudo -u $USERNAME git clone https://github.com/r3dg0d/arch-system-update.git /home/$USERNAME/arch-system-update
    chmod +x /home/$USERNAME/arch-system-update/system-update
    ln -s /home/$USERNAME/arch-system-update/system-update /usr/local/bin/system-update
fi

# Ensure permissions
chown -R $USERNAME:$USERNAME /home/$USERNAME

# ==============================================================================
# INSTALLATION COMPLETE
# ==============================================================================

echo -e "\n${GREEN}Installation Complete!${NC}"
echo -e "${BLUE}"
echo "Desktop Environment Setup Summary:"
echo "=================================="
echo "• Hyprland window manager installed and configured"
echo "• Noctalia Shell installed and set to autostart"
echo "• Bluetooth and NetworkManager enabled"
echo "• Intel microcode updates installed"
echo "• Kitty terminal installed"
echo "• Basic fonts and Qt Wayland support"
echo ""
echo "Next Steps:"
echo "1. Reboot your system"
echo "2. Login as: $USERNAME"
echo "3. Hyprland with Noctalia Shell will start automatically"
echo ""
echo "Manual Start (if needed):"
echo "• Run 'startx' from tty"
echo "• Or use 'systemctl --user start hyprland-session'"
echo ""
echo "Keybindings:"
echo "• Super+Q: Open terminal (Kitty)"
echo "• Super+1-5: Switch workspaces"
echo "• Super+Shift+1-5: Move windows to workspaces"
echo "• Super+C: Close window"
echo "• Super+M: Exit Hyprland"
echo -e "${NC}"