#!/bin/bash
# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script using sudo."
    exit 1
fi

# Get the real user
REAL_USER=${SUDO_USER}
if [ -z "$REAL_USER" ]; then
    REAL_USER=$(logname)
fi
if [ -z "$REAL_USER" ]; then
    echo "Error: Unable to determine the real user."
    exit 1
fi
REAL_HOME=$(eval echo "~$REAL_USER")

# Check for required commands
for cmd in python3 uuidgen; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: Required command $cmd not found."
        exit 1
    fi
done

# Generate a macMachineId-like ID using Python
generate_mac_machine_id() {
    python3 -c '
import uuid, random
def generate():
    template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    result = ""
    for c in template:
        if c == "x":
            result += hex(random.randint(0, 15))[2:]
        elif c == "y":
            r = random.randint(0, 15)
            result += hex((r & 0x3) | 0x8)[2:]
        else:
            result += c
    return result
print(generate())
' 2>/dev/null || {
    echo "Error: Failed to execute Python script for macMachineId."
    exit 1
}
}

# Generate a 64-bit random ID
generate_random_id() {
    uuid1=$(uuidgen | tr -d '-')
    uuid2=$(uuidgen | tr -d '-')
    echo "${uuid1}${uuid2}"
}

# Check if Cursor process is running (case-insensitive match)
while pgrep -i -x "Cursor" > /dev/null || pgrep -i -f "Cursor.app" > /dev/null; do
    echo "Detected that Cursor is running. Please close Cursor to continue..."
    echo "Waiting for Cursor to exit..."
    sleep 1
done

echo "Cursor is not running. Continuing execution..."

# Backup the original UUID from system
BACKUP_DIR="$REAL_HOME/IOPlatformUUID_Backups"
mkdir -p "$BACKUP_DIR" || {
    echo "Error: Unable to create backup directory."
    exit 1
}

ORIGINAL_UUID=""
if [ -f /sys/class/dmi/id/product_uuid ]; then
    ORIGINAL_UUID=$(cat /sys/class/dmi/id/product_uuid)
fi
if [ -z "$ORIGINAL_UUID" ]; then
    echo "Warning: Unable to retrieve the original UUID."
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/IOPlatformUUID_${TIMESTAMP}.txt"
COUNTER=0
while [ -f "$BACKUP_FILE" ]; do
    COUNTER=$((COUNTER + 1))
    BACKUP_FILE="$BACKUP_DIR/IOPlatformUUID_${TIMESTAMP}_$COUNTER.txt"
done

echo "$ORIGINAL_UUID" > "$BACKUP_FILE" || {
    echo "Error: Unable to create backup file."
    exit 1
}

# Update storage.json with new telemetry IDs
STORAGE_JSON="$REAL_HOME/.config/Cursor/User/globalStorage/storage.json"
NEW_MACHINE_ID=$(generate_random_id)
NEW_MAC_MACHINE_ID=$(generate_mac_machine_id)
NEW_DEV_DEVICE_ID=$(uuidgen)
NEW_SQM_ID="{$(uuidgen | tr '[:lower:]' '[:upper:]')}"

if [ -f "$STORAGE_JSON" ]; then
    cp "$STORAGE_JSON" "${STORAGE_JSON}.bak" || {
        echo "Error: Unable to backup storage.json."
        exit 1
    }
    python3 -c "
import json
try:
    with open('$STORAGE_JSON', 'r') as f:
        data = json.load(f)
    data['telemetry.machineId'] = '$NEW_MACHINE_ID'
    data['telemetry.macMachineId'] = '$NEW_MAC_MACHINE_ID'
    data['telemetry.devDeviceId'] = '$NEW_DEV_DEVICE_ID'
    data['telemetry.sqmId'] = '$NEW_SQM_ID'
    with open('$STORAGE_JSON', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print('Error: Failed to update storage.json -', str(e))
    exit(1)
" || {
    echo "Error: Python script execution failed while updating storage.json."
    exit 1
}
fi

# Change ownership of backup directory
chown -R $REAL_USER:$(id -gn $REAL_USER) "$BACKUP_DIR" || {
    echo "Warning: Unable to change ownership of the backup directory."
}

echo "Successfully updated all IDs:"
echo "Backup file created at: $BACKUP_FILE"
echo "New telemetry.machineId: $NEW_MACHINE_ID"
echo "New telemetry.macMachineId: $NEW_MAC_MACHINE_ID"
echo "New telemetry.devDeviceId: $NEW_DEV_DEVICE_ID"
echo "New telemetry.sqmId: $NEW_SQM_ID"
echo ""

# Automatically update PATH
SHELL_CONFIG=""
PATH_EXPORT="export PATH=\"$FAKE_COMMANDS_DIR:\$PATH\""

# Detect user's default shell
USER_SHELL=$(basename "$SHELL")
if [ -z "$USER_SHELL" ]; then
    USER_SHELL=$(basename $(grep "^$REAL_USER:" /etc/passwd | cut -d: -f7))
fi

# 根据不同的 shell 选择配置文件
case "$USER_SHELL" in
    "zsh")
        SHELL_CONFIG="$REAL_HOME/.zshrc"
        ;;
    "bash")
        if [ -f "$REAL_HOME/.bash_profile" ]; then
            SHELL_CONFIG="$REAL_HOME/.bash_profile"
        elif [ -f "$REAL_HOME/.bashrc" ]; then
            SHELL_CONFIG="$REAL_HOME/.bashrc"
        else
            SHELL_CONFIG="$REAL_HOME/.profile"
        fi
        ;;
    *)
        SHELL_CONFIG="$REAL_HOME/.profile"
        ;;
esac

# Check configuration existence
if ! grep -q "$FAKE_COMMANDS_DIR" "$SHELL_CONFIG" 2>/dev/null; then
    sudo -u $REAL_USER bash -c "echo '' >> \"$SHELL_CONFIG\"" || {
        echo "Warning: Unable to update shell configuration file"
    }
    sudo -u $REAL_USER bash -c "echo '# Added by Cursor Reset Script' >> \"$SHELL_CONFIG\"" || {
        echo "Warning: Unable to update shell configuration file"
    }
    sudo -u $REAL_USER bash -c "echo '$PATH_EXPORT' >> \"$SHELL_CONFIG\"" || true
    
    # Apply configuration immediately
    sudo -u $REAL_USER bash -c "export PATH=\"$FAKE_COMMANDS_DIR:\$PATH\""
    
    echo "PATH configuration has been automatically added to $SHELL_CONFIG"
    echo "Configuration is now active, no manual action required"
else
    echo "PATH configuration already exists in $SHELL_CONFIG, no need to add again"
fi

# After updating PATH configuration, extract the AppImage in /opt/cursor-bin
cd /opt/cursor-bin || { echo "Error: Unable to change to /opt/cursor-bin"; exit 1; }
APPIMAGE_PATH="./cursor-bin.AppImage"
if [ ! -d "squashfs-root" ]; then
    $APPIMAGE_PATH --appimage-extract || { echo "Error: Extraction failed."; exit 1; }
fi
echo "Extracted AppImage to: ./squashfs-root"

# Modify the main.js file inside the extracted AppImage
MAIN_JS="./squashfs-root/resources/app/out/main.js"
if [ -f "$MAIN_JS" ]; then
    # Ensure we have write permissions 
    sudo chown -R root:root ./squashfs-root || { echo "Error: Unable to set permissions"; exit 1; }
    
    python3 - "$MAIN_JS" "$NEW_MACHINE_ID" <<'EOF'
import re, sys, pathlib

def replace_patterns(content, machine_id):
    # Replace machine ID patterns
    pattern1 = r'return\s*.*?\?\?\s*(this\.[a-z]+\.(?:mac)?[mM]achineId);'
    content, count1 = re.subn(
        pattern1,
        r'return \1;',
        content,
        flags=re.MULTILINE
    )
    
    # Replace timeout pattern
    pattern2 = r'=\s*r\$\(t\$\(y5\[mm\],\s*{\s*timeout:\s*5e3\s*}\)\.toString\(\)\)'
    content, count2 = re.subn(
        pattern2,
        f'="{machine_id}"',
        content
    )
    
    if count1 > 0:
        print(f"[√] Replaced {count1} machine ID patterns")
    else:
        print("[!] No machine ID patterns found")
        
    if count2 > 0:
        print(f"[√] Replaced {count2} timeout patterns")
    else:
        print("[!] No timeout patterns found")
    
    return content

file_path = pathlib.Path(sys.argv[1])
machine_id = sys.argv[2]

# Read, modify and write the file
with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

modified_content = replace_patterns(content, machine_id)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(modified_content)

print("[√] Modifications complete")
EOF
    [ $? -eq 0 ] || { echo "Error: Failed to modify main.js."; exit 1; }
    echo "Modified main.js to force machineId from configuration."
else
    echo "Error: main.js not found at $MAIN_JS"
    exit 1
fi

# Repack the AppImage in-place (replacing the original)
if command -v appimagetool &> /dev/null; then
    echo "Repacking AppImage..."
    ARCH=x86_64 appimagetool -n ./squashfs-root || { echo "Error: Repacking failed."; exit 1; }
    NEW_IMAGE=$(ls -t Cursor-*.AppImage 2>/dev/null | head -n1)
    if [ -z "$NEW_IMAGE" ]; then
        echo "Error: No repacked AppImage found."
        exit 1
    fi
    mv -f "$NEW_IMAGE" "$APPIMAGE_PATH" || { echo "Error: Overwriting failed."; exit 1; }
    echo "Repacked AppImage updated at $APPIMAGE_PATH"
    
    # Cleanup extracted files
    rm -rf ./squashfs-root || echo "Warning: Failed to cleanup extracted files"
else
    echo "Error: appimagetool not found. Cannot repack AppImage."
    exit 1
fi

echo "Reset complete! Please launch Cursor using $APPIMAGE_PATH"


