#!/bin/bash

# Parse command line arguments
APPIMAGE_PATH=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --appimage)
            APPIMAGE_PATH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --appimage /path/to/cursor.AppImage"
            exit 1
            ;;
    esac
done

# Validate AppImage path
if [ -z "$APPIMAGE_PATH" ]; then
    echo "Error: AppImage path is required"
    echo "Usage: $0 --appimage /path/to/cursor.AppImage"
    exit 1
fi

if [ ! -f "$APPIMAGE_PATH" ]; then
    echo "Error: AppImage file not found at $APPIMAGE_PATH"
    exit 1
fi

# Get the real user
REAL_USER=$(whoami)
if [ -z "$REAL_USER" ]; then
    echo "Error: Unable to determine the user."
    exit 1
fi
REAL_HOME=$(eval echo "~$REAL_USER")

# Check for required commands
for cmd in uuidgen; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: Required command $cmd not found."
        exit 1
    fi
done

# Generate a macMachineId-like ID
generate_mac_machine_id() {
    # Generate a UUID and ensure 13th char is 4 and 17th is 8-b
    uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    # Ensure 13th char is 4
    uuid=$(echo $uuid | sed 's/.\{12\}\(.\)/4/')
    # Ensure 17th char is 8-b (via random)
    random_hex=$(echo $RANDOM | md5sum | cut -c1)
    random_num=$((16#$random_hex))
    new_char=$(printf '%x' $(( ($random_num & 0x3) | 0x8 )))
    uuid=$(echo $uuid | sed "s/.\{16\}\(.\)/$new_char/")
    echo $uuid
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
    
    # Use jq to update the JSON file if available
    if command -v jq &> /dev/null; then
        jq --arg mid "$NEW_MACHINE_ID" \
           --arg mmid "$NEW_MAC_MACHINE_ID" \
           --arg did "$NEW_DEV_DEVICE_ID" \
           --arg sid "$NEW_SQM_ID" \
           '.["telemetry.machineId"]=$mid | .["telemetry.macMachineId"]=$mmid | .["telemetry.devDeviceId"]=$did | .["telemetry.sqmId"]=$sid' \
           "$STORAGE_JSON" > "${STORAGE_JSON}.tmp" && \
        mv "${STORAGE_JSON}.tmp" "$STORAGE_JSON" || {
            echo "Error: Failed to update storage.json"
            exit 1
        }
    else
        echo "Warning: jq not found. Skipping storage.json update."
    fi
fi

echo "Successfully updated all IDs:"
echo "New telemetry.machineId: $NEW_MACHINE_ID"
echo "New telemetry.macMachineId: $NEW_MAC_MACHINE_ID"
echo "New telemetry.devDeviceId: $NEW_DEV_DEVICE_ID"
echo "New telemetry.sqmId: $NEW_SQM_ID"
echo ""

TEMP_DIR=$(mktemp -d)
# Create temporary directory for download
if [ -z "$TEMP_DIR" ] || [ ! -d "$TEMP_DIR" ]; then
    echo "Error: Failed to create temporary directory"
    exit 1
fi

# After updating PATH configuration, extract the AppImage
APPIMAGE_DIR="$(dirname "$APPIMAGE_PATH")"
cd "$APPIMAGE_DIR" || { echo "Error: Unable to change to AppImage directory"; exit 1; }

# Create squashfs-root in temporary directory
cd "$TEMP_DIR" || { echo "Error: Unable to change to temporary directory"; exit 1; }

echo "Extracting AppImage..."
if [ ! -d "squashfs-root" ]; then
    "$APPIMAGE_PATH" --appimage-extract >/dev/null || { 
        echo "Error: Extraction failed."
        rm -rf "$TEMP_DIR"
        exit 1
    }
fi
echo "Extracted AppImage to: $TEMP_DIR/squashfs-root"

# Modify the files inside the extracted AppImage
FILES=(
    "$TEMP_DIR/squashfs-root/resources/app/out/main.js"
    "$TEMP_DIR/squashfs-root/resources/app/out/vs/code/node/cliProcessMain.js"
)

# Process each file
for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "Warning: File $file not found"
        continue
    fi

    # Ensure we have write permissions 
    chmod -R u+w "$TEMP_DIR/squashfs-root" || { 
        echo "Error: Unable to set permissions"
        rm -rf "$TEMP_DIR"
        exit 1
    }
    
    # Replace machine-id related code using sed
    sed -i 's/"[^"]*\/etc\/machine-id[^"]*"/"uuidgen"/g' "$file" || {
        echo "Error: Failed to modify $file"
        rm -rf "$TEMP_DIR"
        exit 1
    }
    
    echo "Successfully modified $file"
done

# Export the temporary directory path for later use
APPIMAGETOOL_PATH="/tmp/appimagetool"

# Function to download and setup appimagetool
setup_appimagetool() {
    echo "appimagetool not found, attempting to download..."
    
    # Download latest continuous build
    if command -v curl &> /dev/null; then
        curl -sL -o "$APPIMAGETOOL_PATH" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$(uname -m).AppImage" || {
            echo "Error: Failed to download appimagetool"
            exit 1
        }
    elif command -v wget &> /dev/null; then
        wget -O "$APPIMAGETOOL_PATH" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$(uname -m).AppImage" || {
            echo "Error: Failed to download appimagetool"
            exit 1
        }
    else
        echo "Error: Neither curl nor wget is available"
        exit 1
    fi
    
    # Make it executable
    chmod +x "$APPIMAGETOOL_PATH" || {
        echo "Error: Failed to make appimagetool executable"
        exit 1
    }
    
    echo "Successfully downloaded appimagetool to $APPIMAGETOOL_PATH"
}

# Check and setup appimagetool if needed
if [ ! -f "$APPIMAGETOOL_PATH" ]; then
    setup_appimagetool || {
        echo "Error: Failed to setup appimagetool"
        rm -rf "$TEMP_DIR"
        exit 1
    }
fi

# Repack the AppImage in-place (replacing the original)
echo "Repacking AppImage..."
ARCH=x86_64 "$APPIMAGETOOL_PATH" -n ./squashfs-root >/dev/null 2>&1 || { 
    echo "Error: Repacking failed."
    rm -rf "$TEMP_DIR"
    exit 1
}

NEW_IMAGE=$(ls -t Cursor-*.AppImage 2>/dev/null | head -n1)
if [ -z "$NEW_IMAGE" ]; then
    echo "Error: No repacked AppImage found."
    rm -rf "$TEMP_DIR"
    exit 1
fi

mv -f "$NEW_IMAGE" "$APPIMAGE_PATH" || { 
    echo "Error: Overwriting failed."
    rm -rf "$TEMP_DIR"
    exit 1
}
echo "Repacked AppImage updated at $APPIMAGE_PATH"

# Cleanup temporary directory
rm -rf "$TEMP_DIR"

echo "Reset complete! Please launch Cursor using $APPIMAGE_PATH"


