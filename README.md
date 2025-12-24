# Arch Linux Clean Install Script (Noctalia Edition)

This is a **one-liner** automated installation script for Arch Linux, designed specifically for my **ThinkPad T480s** but compatible with most modern UEFI systems. 

It installs a fully riced **Hyprland** environment with **Noctalia Shell**, Full Disk Encryption (LUKS), and all my essential apps.

## ✨ Features

- **Full Disk Encryption** (LUKS on Btrfs)
- **Hyprland** + **Noctalia Shell** (Wayland)
- **Dotfiles Sync** (Auto-clones my configs)
- **Rice**: Custom `.bashrc`, Ghostty shaders, Twemoji, CJK Fonts
- **Apps**: Vesktop, Cursor, Mullvad, Thunar, Imv, etc.
- **Aesthetic Installer**: Uses `gum` for a pretty TUI.

## 🚀 How to Use

1. Boot into the Arch Linux Live ISO.
2. Connect to Wi-Fi (`iwctl` -> `station wlan0 connect SSID`).
3. Run the following command:

```bash
bash <(curl -s https://raw.githubusercontent.com/r3dg0d/arch-installer/main/install.sh)
```

## ⚠️ Requirements

- UEFI System
- Internet Connection
- Secure Boot Disabled (recommended for initial setup)

## 📦 What's Included?

- **Base**: Arch Linux, Linux Kernel, Base Devel
- **Desktop**: Hyprland, Noctalia Shell, Waybar, Wofi
- **Terminal**: Ghostty + Zsh/Bash Rice
- **Browser**: Firefox / Chromium
- **Dev**: Cursor, Git, Vim
- **Social**: Vesktop (Discord)
- **Utils**: Thunar, Imv, Mpv, Qbittorrent, Mullvad VPN

---
*Made for my personal setup, use at your own risk.*

