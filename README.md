# MountNAS Script

This script mounts a Windows NAS share on Linux, with auto-mounting on boot, unmounting on shutdown, and logging to `/var/log/mount_share.log`. It supports SELinux and multiple SMB versions.

## Purpose

Mounts a configurable Windows share (default: `//ip_address_to_server/share_folder_name`) to `/mnt/windows_share`. Designed for situations where mounting via `fstab` isn’t viable, such as:
- Unreliable network connections that need retries (e.g., Wi-Fi drops).
- Dynamic NAS setups where IP or credentials change (e.g., temporary shares).
  
## Requirements

- Linux (Debian, Arch, Fedora, etc.)
- Root access (`sudo`)
- `cifs-utils` installed (e.g., `sudo apt install cifs-utils` on Debian)

## Configuration

Edit these variables in `mountnas.sh`:
```bash
SHARE_PATH="//ip_address_to_server/share_folder_name"
MOUNT_POINT="/mnt/windows_share"
USERNAME="windows_user_name"
PASSWORD="windows_password"
```
Use a text editor (e.g., nano mountnas.sh), then save and exit.
Setup

    Download from GitHub: “Code” > “Download ZIP”, unzip it.
    Open terminal, cd to the folder.
    Make executable: chmod +x mountnas.sh
    Run: sudo bash mountnas.sh
    Optional: Answer “yes” or “no” to the backup shutdown prompt (useful for Debian).

Files appear at the configured MOUNT_POINT.
Troubleshooting

    Check log: cat /var/log/mount_share.log
    Check status: systemctl status mount-windows-share.service
    Unmount manually: sudo bash mountnas.sh --unmount

Features

    Logs to /var/log/mount_share.log
    Supports SMB versions 3.0, 2.1, 1.0
    Ensures clean unmount on shutdown

Report issues in the GitHub “Issues” tab.
