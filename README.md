# Cursor ID Manager

一个用于管理 Cursor IDE 设备标识的图形界面工具。支持重置设备标识和恢复到原始系统标识。

在https://github.com/hamflx/cursor-reset项目上进行进一步完善

⚠️ win+R输入regedit,搜索HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography即是修改的系统注册表

## ⚠️ 免责声明

本工具仅供学习和研究使用，旨在研究 Cursor IDE 的设备标识机制。**强烈建议购买 [Cursor](https://cursor.sh/) 的正版授权**以支持开发者。

使用本工具可能违反 Cursor 的使用条款。作者不对使用本工具导致的任何问题负责，包括但不限于：
- 软件授权失效
- 账号封禁
- 其他未知风险

## 功能特点

- 图形界面操作，简单直观
- 自动备份原始系统标识
- 支持一键重置和恢复
- 显示详细的操作结果
- 需要管理员权限运行

## 系统要求

- Windows 操作系统
- PowerShell
- 管理员权限
- Cursor IDE 0.46.11 版本（最新版本0.46.11已经成功，因为修改的是系统注册表的MachineGuid，而不是Cursor记录的机器码。故应该所有版本都适用。）

## 使用方法

### 首次使用前的准备

1. 在 Cursor IDE 中退出当前登录的账号（原项目使用命令行的方法需要退出账号、此项目使用程序文件进行操作不需要此过程）
2. 完全关闭 Cursor IDE（使用程序文件时也是不需要关闭的，但是由于Cursor运行读取的是未修改前的系统注册表，故哪怕修改成功，也需要重启才能够正常使用。因此还是建议完全关闭 Cursor IDE）
3. 以管理员身份运行 `CursorIDManager.exe`

### 重置设备标识

1. 点击 "Reset ID" 按钮
2. 等待操作完成
3. 查看结果信息
4. 重新启动 Cursor IDE

### 恢复原始标识

1. 点击 "Restore ID" 按钮
2. 等待操作完成
3. 查看恢复结果
4. 重新启动 Cursor IDE

### 命令行使用

#### 重置设备标识
```powershell
powershell -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iwr -Uri 'https://raw.githubusercontent.com/hamflx/cursor-reset/main/reset.ps1' -UseBasicParsing | iex"
```

#### 恢复原始标识
```powershell
powershell -ExecutionPolicy Bypass -File restore_machineGuid.ps1
```

### 生成可执行文件

如果您想自己生成可执行文件，请按照以下步骤操作：

1. **安装 PS2EXE 模块**
```powershell
Install-Module -Name ps2exe -Scope CurrentUser
```
安装过程中的提示：
- 提示是否信任 PSGallery，输入 `Y` 确认
- 提示是否安装 NuGet，输入 `Y` 确认

2. **生成 EXE 文件**
```powershell
Invoke-ps2exe .\cursor_manager.ps1 .\CursorIDManager.exe -noConsole -requireAdmin
```

参数说明：
- `-noConsole`: 不显示控制台窗口
- `-requireAdmin`: 要求管理员权限运行

生成的 `CursorIDManager.exe` 文件具有以下特点：
- 需要管理员权限运行
- 提供图形界面操作
- 包含完整的重置和恢复功能

## 工作原理

### 重置操作

重置操作会：
1. 备份当前的 MachineGuid 到 `%USERPROFILE%\MachineGuid_Backups` 目录
2. 生成新的随机标识符
3. 更新以下内容：
   - Windows 注册表中的 MachineGuid
   - Cursor 的 storage.json 文件中的设备标识信息

### 恢复操作

恢复操作会：
1. 读取最早创建的备份文件（原始系统标识）
2. 将 Windows 注册表中的 MachineGuid 恢复为原始值
3. 验证恢复结果

## 备份文件

### 位置
备份文件存储在：`%USERPROFILE%\MachineGuid_Backups` 目录

### 命名规则
- 格式：`MachineGuid_yyyyMMdd_HHmmss.txt`
- 示例：`MachineGuid_20240311_192059.txt`

### 恢复机制
- 恢复操作始终使用最早创建的备份文件 ⚠️ （建议自己再备份一下）
- 这确保了总是恢复到原始的系统标识

## 注意事项

1. **备份保护**
   - 请勿删除或修改 MachineGuid_Backups 目录中的文件
   - 建议定期备份该目录

2. **其他软件影响**
   - 修改 MachineGuid 可能影响其他使用此标识的软件
   - 如果其他软件出现问题，可以使用恢复功能


## 故障排除

1. **程序无法启动**
   - 确保以管理员身份运行
   - 检查是否被杀毒软件拦截 ⚠️ （程序文件本身是没有问题的，但是功能是修改系统注册表内容，故会被识别为危险文件）

2. **重置失败**
   - 确保 Cursor IDE 已完全关闭
   - 检查是否有足够的磁盘空间
   - 验证对注册表的访问权限

3. **恢复失败**
   - 检查备份文件是否存在且未损坏
   - 确认有修改注册表的权限

4. **Cursor 无法启动**
   - 尝试恢复到原始标识
   - 重新安装 Cursor IDE

## 技术支持

如果遇到问题：
1. 检查是否完全按照使用说明操作
2. 查看操作系统的事件日志
3. 确保系统满足所有要求
4. 如果问题持续，可以使用恢复功能回到原始状态

## 更新历史

### v1.0.0 (2024-03-11)
- 初始版本发布
- 支持图形界面操作
- 实现重置和恢复功能
- 添加详细的操作反馈

## 文件说明

### 主要文件
- `CursorIDManager.exe`: 图形界面程序
- `cursor_manager.ps1`: 源代码文件
- `reset.ps1`: 重置功能脚本
- `restore_machineGuid.ps1`: 恢复功能脚本

