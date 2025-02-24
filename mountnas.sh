#!/bin/bash

# Script with logging, unmount option, and SELinux support

# Configuration
SHARE_PATH="//ip_address_to_server/share_folder_name"
MOUNT_POINT="/mnt/windows_share"
BACKUP_MOUNT_POINT="/mnt/backup_share"
USERNAME="windows_user_name"
PASSWORD="windows_password"
CREDENTIALS_FILE="/root/.smbcredentials"
BACKUP_CREDS="/tmp/.smbcredentials"
MOUNT_SERVICE="mount-windows-share.service"
UMOUNT_SERVICE="umount-windows-share.service"
SHUTDOWN_SCRIPT="/etc/rc6.d/K01umount-share.sh"
NETWORK_TIMEOUT=60
LOG_FILE="/var/log/mount_share.log"

# Simple error function with logging
show_error() {
    echo "PROBLEM: $1" | tee -a "$LOG_FILE"
    echo "WHAT TO DO:" | tee -a "$LOG_FILE"
    echo -e "$2\n" | tee -a "$LOG_FILE"
}

# Log regular messages
log_message() {
    echo "$1" | tee -a "$LOG_FILE"
}

# Check if log directory exists
mkdir -p /var/log 2>/dev/null
touch "$LOG_FILE" 2>/dev/null && chmod 644 "$LOG_FILE" || log_message "Warning: Can’t write logs, proceeding anyway."

# Handle unmount option
if [ "$1" = "--unmount" ]; then
    log_message "Trying to disconnect the files..."
    if mountpoint -q "$MOUNT_POINT"; then
        umount "$MOUNT_POINT" 2>/dev/null || umount -f "$MOUNT_POINT" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "Disconnected successfully from $MOUNT_POINT!"
            exit 0
        else
            show_error "Couldn’t disconnect" "Try typing this: sudo umount $MOUNT_POINT"
            exit 1
        fi
    else
        log_message "Nothing to disconnect—files aren’t connected at $MOUNT_POINT."
        exit 0
    fi
fi

# Check if running as root
log_message "Checking if I have permission to run..."
if [ "$EUID" -ne 0 ]; then
    show_error "I need special permission" "Type this in the terminal and press Enter:\nsudo bash $0"
    exit 1
fi

# Check cifs-utils
log_message "Checking if I have the right tools..."
CIFS_OK=1
if ! command -v mount.cifs >/dev/null 2>&1; then
    show_error "Missing a tool called 'cifs-utils'" "For Debian: Put a USB with 'cifs-utils' into the computer, then type: sudo apt install ./cifs-utils*.deb\nFor Arch: Use a USB and type: sudo pacman -U cifs-utils*.pkg.tar.zst\nFor Fedora: Use a USB and type: sudo dnf install cifs-utils*.rpm\nI’ll keep going, but it might not work until you do this.\nOR try this later: sudo mount -t cifs $SHARE_PATH $MOUNT_POINT -o username=$USERNAME,password=$PASSWORD"
    CIFS_OK=0
fi

# Prepare mount point
log_message "Making a spot for the files..."
if [ -d "$MOUNT_POINT" ]; then
    umount "$MOUNT_POINT" 2>/dev/null
    rm -rf "$MOUNT_POINT" 2>/dev/null
fi
mkdir -p "$MOUNT_POINT" || {
    show_error "Can’t make the main folder" "I’ll try a backup spot instead..."
    mkdir -p "$BACKUP_MOUNT_POINT" || {
        show_error "Can’t make any folder" "Check if the computer’s storage is full or locked."
        exit 1
    }
    MOUNT_POINT="$BACKUP_MOUNT_POINT"
    log_message "Switched to backup folder: $MOUNT_POINT"
}
chmod 755 "$MOUNT_POINT"
if [ $(stat -c %a "$MOUNT_POINT") -ne 755 ]; then
    show_error "Folder setup didn’t work right" "I’ll fix it..."
    chmod 755 "$MOUNT_POINT" 2>/dev/null || log_message "Still not perfect, but should work."
fi
# SELinux context for Fedora
if command -v chcon >/dev/null 2>&1; then
    chcon -t samba_share_t "$MOUNT_POINT" 2>/dev/null || log_message "Note: Couldn’t set special Fedora permissions, might still work."
fi

# Set up credentials
log_message "Storing the login info..."
echo -e "username=$USERNAME\npassword=$PASSWORD" > "$CREDENTIALS_FILE" 2>/dev/null
if [ $? -ne 0 ]; then
    show_error "Can’t save login info in the usual spot" "Trying a backup spot..."
    if ! echo -e "username=$USERNAME\npassword=$PASSWORD" > "$BACKUP_CREDS" 2>/dev/null; then
        show_error "Can’t save login anywhere" "Check if the computer’s storage is full."
        exit 1
    fi
    CREDENTIALS_FILE="$BACKUP_CREDS"
    log_message "Using backup login file: $CREDENTIALS_FILE"
fi
chmod 600 "$CREDENTIALS_FILE"
if [ $(stat -c %a "$CREDENTIALS_FILE") -ne 600 ]; then
    chmod 600 "$CREDENTIALS_FILE" 2>/dev/null || log_message "Login file setup might be off, but I’ll proceed."
fi

# Wait for network
log_message "Looking for the network..."
SECONDS_WAITED=0
INTERVAL=5
while ! ping -c 2 192.168.1.119 >/dev/null 2>&1 && [ $SECONDS_WAITED -lt $NETWORK_TIMEOUT ]; do
    log_message "No network yet, waiting $INTERVAL seconds... ($SECONDS_WAITED/$NETWORK_TIMEOUT)"
    sleep $INTERVAL
    SECONDS_WAITED=$((SECONDS_WAITED + INTERVAL))
done
if [ $SECONDS_WAITED -ge $NETWORK_TIMEOUT ]; then
    show_error "Can’t find the Windows computer" "1. Make sure the Windows computer is on\n2. Check its address is 192.168.1.119\n3. Make sure cables are plugged in\nI’ll keep trying in the background.\nOR type this to test: ping 192.168.1.119"
fi

# Get user info
CURRENT_UID=$(id -u "$(whoami)")
CURRENT_GID=$(id -g "$(whoami)")

# Create mount service
log_message "Setting up the automatic connection..."
cat > "/etc/systemd/system/$MOUNT_SERVICE" << EOF
[Unit]
Description=Mount Windows Share
After=network-online.target
Wants=network-online.target
Before=$UMOUNT_SERVICE

[Service]
Type=oneshot
ExecStart=/bin/sh -c "until mount -t cifs $SHARE_PATH $MOUNT_POINT -o credentials=$CREDENTIALS_FILE,vers=3.0,uid=$CURRENT_UID,gid=$CURRENT_GID,file_mode=0666,dir_mode=0777 || mount -t cifs $SHARE_PATH $MOUNT_POINT -o credentials=$CREDENTIALS_FILE,vers=2.1,uid=$CURRENT_UID,gid=$CURRENT_GID,file_mode=0666,dir_mode=0777 || mount -t cifs $SHARE_PATH $MOUNT_POINT -o credentials=$CREDENTIALS_FILE,vers=1.0,uid=$CURRENT_UID,gid=$CURRENT_GID,file_mode=0666,dir_mode=0777; do echo 'Retrying in 5s...'; sleep 5; done"
RemainAfterExit=yes
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF
if [ $? -ne 0 ]; then
    show_error "Can’t set up the connection" "Check if the computer’s storage is full."
    rm -f "$CREDENTIALS_FILE"
    exit 1
fi

# Create primary unmount service
log_message "Setting up the disconnect for shutdown..."
cat > "/etc/systemd/system/$UMOUNT_SERVICE" << EOF
[Unit]
Description=Unmount Windows Share (Primary)
Before=shutdown.target reboot.target halt.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/bin/sh -c "if mountpoint -q $MOUNT_POINT; then umount $MOUNT_POINT || umount -f $MOUNT_POINT; fi"
RemainAfterExit=yes
TimeoutSec=10

[Install]
WantedBy=shutdown.target reboot.target
EOF
if [ $? -ne 0 ]; then
    show_error "Can’t set up disconnect" "Check if storage is full."
    rm -f "$CREDENTIALS_FILE"
    rm -f "/etc/systemd/system/$MOUNT_SERVICE"
    exit 1
fi

# Prompt for SysV backup
log_message "I can add an extra way to disconnect the files when you shut down."
log_message "It’s not needed on Arch or Fedora, but helps on Debian."
echo "Do you want this extra step? Type 'yes' or 'no' and press Enter (or just press Enter to skip):"
read -r SYSV_CHOICE
if [ "$SYSV_CHOICE" = "yes" ]; then
    log_message "Adding a backup disconnect method..."
    cat > "$SHUTDOWN_SCRIPT" << EOF
#!/bin/bash
# Backup to unmount share during shutdown/reboot
if mountpoint -q $MOUNT_POINT; then
    umount $MOUNT_POINT 2>/dev/null || umount -f $MOUNT_POINT 2>/dev/null
fi
exit 0
EOF
    if [ $? -ne 0 ]; then
        show_error "Backup disconnect failed" "Check if storage is full."
        rm -f "$CREDENTIALS_FILE"
        rm -f "/etc/systemd/system/$MOUNT_SERVICE"
        rm -f "/etc/systemd/system/$UMOUNT_SERVICE"
        exit 1
    fi
    chmod 755 "$SHUTDOWN_SCRIPT"
    if [ $(stat -c %a "$SHUTDOWN_SCRIPT") -ne 755 ]; then
        chmod 755 "$SHUTDOWN_SCRIPT" 2>/dev/null || log_message "Backup script setup might be off, but should work."
    fi
    ln -sf "$SHUTDOWN_SCRIPT" "/etc/rc0.d/K01umount-share.sh" 2>/dev/null || log_message "This extra step might not work on Arch or Fedora, but the main disconnect will."
    SYSV_ENABLED=1
else
    log_message "Skipping the extra disconnect step—main method will still work."
    SYSV_ENABLED=0
fi

# Activate services
systemctl daemon-reload
systemctl enable "$MOUNT_SERVICE" 2>/dev/null || show_error "Connection setup didn’t stick" "Restart the computer and try again."
systemctl enable "$UMOUNT_SERVICE" 2>/dev/null || show_error "Disconnect setup didn’t stick" "Restart the computer and try again."

# Try initial mount
if [ $CIFS_OK -eq 1 ]; then
    log_message "Trying to connect now..."
    for VERSION in "3.0" "2.1" "1.0"; do
        mount -t cifs "$SHARE_PATH" "$MOUNT_POINT" -o credentials="$CREDENTIALS_FILE",vers="$VERSION",uid="$CURRENT_UID",gid="$CURRENT_GID",file_mode=0666,dir_mode=0777 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "SUCCESS: Connected with version $VERSION at $MOUNT_POINT"
            break
        fi
        log_message "Version $VERSION didn’t work, trying next..."
    done
    if ! mountpoint -q "$MOUNT_POINT"; then
        show_error "Couldn’t connect right away" "It’ll keep trying. Wait a minute, or check the Windows computer."
    fi
fi

# Test write access
if mountpoint -q "$MOUNT_POINT"; then
    log_message "Making sure you can add files..."
    TEST_FILE="$MOUNT_POINT/test_$(date +%s).txt"
    echo "Write test" > "$TEST_FILE" 2>/dev/null
    if [ $? -eq 0 ]; then
        log_message "You can add files—great!"
        rm -f "$TEST_FILE"
    else
        show_error "Can’t add files" "The Windows computer might be blocking this. Check its sharing settings."
    fi
fi

# Double-check everything
log_message "Making sure all pieces are ready..."
if [ -f "/etc/systemd/system/$UMOUNT_SERVICE" ] && systemctl is-enabled "$UMOUNT_SERVICE" >/dev/null 2>&1; then
    log_message "Main disconnect is ready."
else
    show_error "Main disconnect isn’t perfect" "Restart the computer to fix it."
fi
if [ "$SYSV_ENABLED" -eq 1 ] && [ -x "$SHUTDOWN_SCRIPT" ] && [ -L "/etc/rc0.d/K01umount-share.sh" ]; then
    log_message "Backup disconnect is ready (works best on Debian, optional on Arch/Fedora)."
else
    if [ "$SYSV_ENABLED" -eq 1 ]; then
        show_error "Backup disconnect isn’t perfect" "Still safe, but you can type: sudo umount $MOUNT_POINT before shutting down if needed.\nNote: This backup is mainly for Debian."
    fi
fi

# Final message
log_message "ALL DONE!"
log_message "Your files should be at: $MOUNT_POINT"
log_message "If not there yet, wait a minute—it’s still trying!"
log_message "To see what’s happening: Type: systemctl status $MOUNT_SERVICE"
log_message "To disconnect manually: Type: sudo bash $0 --unmount"
log_message "Check what happened: Look at $LOG_FILE"
log_message "Shutting down should be smooth now."
log_message "If anything goes wrong, restart and run this again."
