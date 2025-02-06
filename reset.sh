#!/bin/bash

# 获取实际用户信息
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
elif [ -n "$DOAS_USER" ]; then
    REAL_USER="$DOAS_USER"
else
    REAL_USER=$(who am i | awk '{print $1}')
    if [ -z "$REAL_USER" ]; then
        REAL_USER=$(logname)
    fi
fi

if [ -z "$REAL_USER" ]; then
    echo "错误: 无法确定实际用户"
    exit 1
fi

REAL_HOME=$(eval echo ~$REAL_USER)

# 检查必要的命令
for cmd in uuidgen ioreg; do
    if ! command -v $cmd &> /dev/null; then
        echo "错误: 需要 $cmd 但未找到"
        exit 1
    fi
done

# 生成类似 macMachineId 的格式
generate_mac_machine_id() {
    # 使用 uuidgen 生成基础 UUID，然后确保第 13 位是 4，第 17 位是 8-b
    uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    # 确保第 13 位是 4
    uuid=$(echo $uuid | sed 's/.\{12\}\(.\)/4/')
    # 确保第 17 位是 8-b (通过随机数)
    random_hex=$(echo $RANDOM | md5 | cut -c1)
    random_num=$((16#$random_hex))
    new_char=$(printf '%x' $(( ($random_num & 0x3) | 0x8 )))
    uuid=$(echo $uuid | sed "s/.\{16\}\(.\)/$new_char/")
    echo $uuid
}

# 生成64位随机ID
generate_random_id() {
    uuid1=$(uuidgen | tr -d '-')
    uuid2=$(uuidgen | tr -d '-')
    echo "${uuid1}${uuid2}"
}

# 检查 Cursor 进程
if pgrep -x "Cursor" > /dev/null || pgrep -f "Cursor.app" > /dev/null; then
    echo "检测到 Cursor 正在运行。请关闭 Cursor 后继续..."
    echo "正在等待 Cursor 进程退出..."
    while pgrep -x "Cursor" > /dev/null || pgrep -f "Cursor.app" > /dev/null; do
        sleep 1
    done
fi

echo "Cursor 已关闭，继续执行..."

# 定义文件路径
STORAGE_JSON="$REAL_HOME/Library/Application Support/Cursor/User/globalStorage/storage.json"
FILES=(
    "/Applications/Cursor.app/Contents/Resources/app/out/main.js"
    "/Applications/Cursor.app/Contents/Resources/app/out/vs/code/node/cliProcessMain.js"
)

# 恢复功能
restore_files() {
    # 恢复 storage.json
    if [ -f "${STORAGE_JSON}.bak" ]; then
        cp "${STORAGE_JSON}.bak" "$STORAGE_JSON" && {
            echo "已恢复 storage.json"
            # 确保恢复后的文件权限正确
            chown $REAL_USER:staff "$STORAGE_JSON"
            chmod 644 "$STORAGE_JSON"
        } || echo "错误: 恢复 storage.json 失败"
    else
        echo "警告: storage.json 的备份文件不存在"
    fi

    # 恢复应用程序
    if [ -d "/Applications/Cursor.backup.app" ]; then
        echo "正在恢复 Cursor.app..."
        # 关闭应用
        osascript -e 'tell application "Cursor" to quit' || true
        sleep 2
        
        # 删除当前应用并恢复备份
        rm -rf "/Applications/Cursor.app"
        mv "/Applications/Cursor.backup.app" "/Applications/Cursor.app" && {
            echo "已恢复 Cursor.app"
            # 确保恢复后的应用权限正确
            chown -R $REAL_USER:staff "/Applications/Cursor.app"
            chmod -R 755 "/Applications/Cursor.app"
        } || echo "错误: 恢复 Cursor.app 失败"
    else
        echo "警告: Cursor.app 的备份不存在"
    fi

    echo "恢复操作完成"
    exit 0
}

# 检查是否为恢复模式
if [ "$1" = "--restore" ]; then
    restore_files
fi

# 更新 storage.json
NEW_MACHINE_ID=$(generate_random_id)
NEW_MAC_MACHINE_ID=$(generate_mac_machine_id)
NEW_DEV_DEVICE_ID=$(uuidgen)
NEW_SQM_ID="{$(uuidgen | tr '[:lower:]' '[:upper:]')}"

if [ -f "$STORAGE_JSON" ]; then
    # 备份原始文件
    cp "$STORAGE_JSON" "${STORAGE_JSON}.bak" || {
        echo "错误: 无法备份 storage.json"
        exit 1
    }
    
    # 确保备份文件的所有权正确
    chown $REAL_USER:staff "${STORAGE_JSON}.bak"
    chmod 644 "${STORAGE_JSON}.bak"
    
    # 使用 osascript 更新 JSON 文件
    osascript -l JavaScript << EOF
        function run() {
            const fs = $.NSFileManager.defaultManager;
            const path = '$STORAGE_JSON';
            const nsdata = fs.contentsAtPath(path);
            const nsstr = $.NSString.alloc.initWithDataEncoding(nsdata, $.NSUTF8StringEncoding);
            const content = nsstr.js;
            const data = JSON.parse(content);
            
            data['telemetry.machineId'] = '$NEW_MACHINE_ID';
            data['telemetry.macMachineId'] = '$NEW_MAC_MACHINE_ID';
            data['telemetry.devDeviceId'] = '$NEW_DEV_DEVICE_ID';
            data['telemetry.sqmId'] = '$NEW_SQM_ID';
            
            const newContent = JSON.stringify(data, null, 2);
            const newData = $.NSString.alloc.initWithUTF8String(newContent);
            newData.writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
            
            return "success";
        }
EOF
    
    if [ $? -ne 0 ]; then
        echo "错误: 更新 storage.json 失败"
        exit 1
    fi

    # 确保修改后的文件所有权正确
    chown $REAL_USER:staff "$STORAGE_JSON"
    chmod 644 "$STORAGE_JSON"
fi

echo "Successfully updated all IDs:"
echo "Backup file created at: $BACKUP_FILE"
echo "New telemetry.machineId: $NEW_MACHINE_ID"
echo "New telemetry.macMachineId: $NEW_MAC_MACHINE_ID"
echo "New telemetry.devDeviceId: $NEW_DEV_DEVICE_ID"
echo "New telemetry.sqmId: $NEW_SQM_ID"
echo ""

# 在处理文件之前，先复制整个应用到临时目录
echo "正在复制 Cursor.app 到临时目录..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEMP_DIR="/tmp/cursor_reset_${TIMESTAMP}"
TEMP_APP="$TEMP_DIR/Cursor.app"

# 确保临时目录不存在
if [ -d "$TEMP_DIR" ]; then
    echo "清理已存在的临时目录..."
    rm -rf "$TEMP_DIR"
fi

# 创建临时目录
mkdir -p "$TEMP_DIR" || {
    echo "错误: 无法创建临时目录"
    exit 1
}

# 复制应用到临时目录
cp -R "/Applications/Cursor.app" "$TEMP_DIR" || {
    echo "错误: 无法复制应用到临时目录"
    rm -rf "$TEMP_DIR"
    exit 1
}

# 确保临时目录的权限正确
chown -R $REAL_USER "$TEMP_DIR"
chmod -R 755 "$TEMP_DIR"

echo "正在移除临时应用的签名..."
codesign --remove-signature "$TEMP_APP" || {
    echo "警告: 移除应用签名失败"
}

# 移除所有相关组件的签名
components=(
    "$TEMP_APP/Contents/Frameworks/Cursor Helper.app"
    "$TEMP_APP/Contents/Frameworks/Cursor Helper (GPU).app"
    "$TEMP_APP/Contents/Frameworks/Cursor Helper (Plugin).app"
    "$TEMP_APP/Contents/Frameworks/Cursor Helper (Renderer).app"
)

for component in "${components[@]}"; do
    if [ -e "$component" ]; then
        echo "正在移除签名: $component"
        codesign --remove-signature "$component" || {
            echo "警告: 移除组件签名失败: $component"
        }
    fi
done

# 修改临时应用中的文件
FILES=(
    "$TEMP_APP/Contents/Resources/app/out/main.js"
    "$TEMP_APP/Contents/Resources/app/out/vs/code/node/cliProcessMain.js"
)

# 处理每个文件
for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "警告: 文件 $file 不存在"
        continue
    fi

    # 创建备份
    backup_file="${file}.bak"
    cp "$file" "$backup_file" || {
        echo "错误: 无法备份文件 $file"
        continue
    }

    # 读取文件内容
    content=$(cat "$file")
    
    # 查找 IOPlatformUUID 的位置
    uuid_pos=$(printf "%s" "$content" | grep -b -o "IOPlatformUUID" | cut -d: -f1)
    if [ -z "$uuid_pos" ]; then
        echo "警告: 在 $file 中未找到 IOPlatformUUID"
        continue
    fi

    # 从 UUID 位置向前查找 switch
    before_uuid=${content:0:$uuid_pos}
    switch_pos=$(printf "%s" "$before_uuid" | grep -b -o "switch" | tail -n1 | cut -d: -f1)
    if [ -z "$switch_pos" ]; then
        echo "警告: 在 $file 中未找到 switch 关键字"
        continue
    fi

    # 构建新的文件内容
    printf "%sreturn crypto.randomUUID();\n%s" "${content:0:$switch_pos}" "${content:$switch_pos}" > "$file" || {
        echo "错误: 无法写入文件 $file"
        continue
    }

    echo "成功修改文件: $file"
done

# 重新签名临时应用
echo "正在重新签名临时应用..."
codesign --sign - "$TEMP_APP" --force --deep || {
    echo "警告: 重新签名失败"
}

# 关闭原应用
echo "正在关闭 Cursor..."
osascript -e 'tell application "Cursor" to quit' || true
sleep 2

# 备份原应用
echo "备份原应用..."
if [ -d "/Applications/Cursor.backup.app" ]; then
    rm -rf "/Applications/Cursor.backup.app"
fi
mv "/Applications/Cursor.app" "/Applications/Cursor.backup.app" || {
    echo "错误: 无法备份原应用"
    rm -rf "$TEMP_DIR"
    exit 1
}
# 设置备份应用的所有权为实际用户
chown -R $REAL_USER:staff "/Applications/Cursor.backup.app"

# 移动修改后的应用到应用程序文件夹
echo "安装修改后的应用..."
mv "$TEMP_APP" "/Applications/" || {
    echo "错误: 无法安装修改后的应用"
    mv "/Applications/Cursor.backup.app" "/Applications/Cursor.app"
    rm -rf "$TEMP_DIR"
    exit 1
}

# 设置新应用的权限
chown -R $REAL_USER:staff "/Applications/Cursor.app"
chmod -R 755 "/Applications/Cursor.app"

# 清理临时目录
rm -rf "$TEMP_DIR"

echo "应用修改完成！原应用已备份为 /Applications/Cursor.backup.app"
echo "所有操作完成"
