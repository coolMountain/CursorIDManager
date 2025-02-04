#!/bin/bash

# 检查是否为 root 权限
if [ "$EUID" -ne 0 ]; then
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

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
        cp "${STORAGE_JSON}.bak" "$STORAGE_JSON" && echo "已恢复 storage.json" || echo "错误: 恢复 storage.json 失败"
    else
        echo "警告: storage.json 的备份文件不存在"
    fi

    # 恢复其他文件
    for file in "${FILES[@]}"; do
        if [ -f "${file}.bak" ]; then
            cp "${file}.bak" "$file" && echo "已恢复 $file" || echo "错误: 恢复 $file 失败"
        else
            echo "警告: ${file} 的备份文件不存在"
        fi
    done

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
fi

echo "Successfully updated all IDs:"
echo "Backup file created at: $BACKUP_FILE"
echo "New telemetry.machineId: $NEW_MACHINE_ID"
echo "New telemetry.macMachineId: $NEW_MAC_MACHINE_ID"
echo "New telemetry.devDeviceId: $NEW_DEV_DEVICE_ID"
echo "New telemetry.sqmId: $NEW_SQM_ID"
echo ""

# 处理每个文件
for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "警告: 文件 $file 不存在"
        continue
    fi

    # 创建备份（如果备份不存在）
    backup_file="${file}.bak"
    if [ ! -f "$backup_file" ]; then
        echo "正在备份 $file 到 $backup_file"
        cp "$file" "$backup_file" || {
            echo "错误: 无法备份文件 $file"
            continue
        }
    else
        echo "备份文件 $backup_file 已存在，跳过备份"
    fi

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

echo "所有操作完成"
