Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Check administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Create form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Cursor ID Manager'
$form.Size = New-Object System.Drawing.Size(400,200)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

# Create reset button
$resetButton = New-Object System.Windows.Forms.Button
$resetButton.Location = New-Object System.Drawing.Point(50,50)
$resetButton.Size = New-Object System.Drawing.Size(120,40)
$resetButton.Text = 'Reset ID'
$resetButton.Add_Click({
    try {
        # 生成新的 ID
        function New-MacMachineId {
            $template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
            $result = ""
            $random = [Random]::new()
            foreach ($char in $template.ToCharArray()) {
                if ($char -eq 'x' -or $char -eq 'y') {
                    $r = $random.Next(16)
                    $v = if ($char -eq "x") { $r } else { ($r -band 0x3) -bor 0x8 }
                    $result += $v.ToString("x")
                } else {
                    $result += $char
                }
            }
            return $result
        }

        function New-RandomId {
            $uuid1 = [guid]::NewGuid().ToString("N")
            $uuid2 = [guid]::NewGuid().ToString("N")
            return $uuid1 + $uuid2
        }

        # 备份当前 MachineGuid
        $backupDir = Join-Path $HOME "MachineGuid_Backups"
        if (-not (Test-Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir | Out-Null
        }

        $currentValue = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFile = Join-Path $backupDir "MachineGuid_$timestamp.txt"
        $counter = 0

        while (Test-Path $backupFile) {
            $counter++
            $backupFile = Join-Path $backupDir "MachineGuid_${timestamp}_$counter.txt"
        }

        $currentValue.MachineGuid | Out-File $backupFile

        # 生成新的 ID
        $newMachineId = New-RandomId
        $newMacMachineId = New-MacMachineId
        $newDevDeviceId = [guid]::NewGuid().ToString()
        $newSqmId = "{$([guid]::NewGuid().ToString().ToUpper())}"
        $newMachineGuid = [guid]::NewGuid().ToString()

        # 更新 storage.json
        $storageJsonPath = Join-Path $env:APPDATA "Cursor\User\globalStorage\storage.json"
        if (Test-Path $storageJsonPath) {
            $originalAttributes = (Get-ItemProperty $storageJsonPath).Attributes
            Set-ItemProperty $storageJsonPath -Name IsReadOnly -Value $false
            
            $jsonContent = Get-Content $storageJsonPath -Raw -Encoding UTF8
            $data = $jsonContent | ConvertFrom-Json
            
            # 更新或添加属性
            $properties = @{
                "telemetry.machineId" = $newMachineId
                "telemetry.macMachineId" = $newMacMachineId
                "telemetry.devDeviceId" = $newDevDeviceId
                "telemetry.sqmId" = $newSqmId
            }

            foreach ($prop in $properties.Keys) {
                if (-not (Get-Member -InputObject $data -Name $prop -MemberType Properties)) {
                    $data | Add-Member -NotePropertyName $prop -NotePropertyValue $properties[$prop]
                } else {
                    $data.$prop = $properties[$prop]
                }
            }
            
            $newJson = $data | ConvertTo-Json -Depth 100
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($storageJsonPath, $newJson.Replace("`r`n", "`n"), $utf8NoBom)
            
            Set-ItemProperty $storageJsonPath -Name Attributes -Value $originalAttributes
        }

        # 更新注册表
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -Value $newMachineGuid

        # 创建结果消息
        $resultMessage = "Successfully updated all IDs:`n"
        $resultMessage += "Backup file created at: $backupFile`n"
        $resultMessage += "New MachineGuid: $newMachineGuid`n"
        $resultMessage += "New telemetry.machineId: $newMachineId`n"
        $resultMessage += "New telemetry.macMachineId: $newMacMachineId`n"
        $resultMessage += "New telemetry.devDeviceId: $newDevDeviceId`n"
        $resultMessage += "New telemetry.sqmId: $newSqmId"

        [System.Windows.Forms.MessageBox]::Show($resultMessage, "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Reset failed: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# Create restore button
$restoreButton = New-Object System.Windows.Forms.Button
$restoreButton.Location = New-Object System.Drawing.Point(230,50)
$restoreButton.Size = New-Object System.Drawing.Size(120,40)
$restoreButton.Text = 'Restore ID'
$restoreButton.Add_Click({
    try {
        # Get backup directory path
        $backupDir = Join-Path $HOME "MachineGuid_Backups"
        if (-not (Test-Path $backupDir)) {
            throw "Backup folder not found"
        }

        # Get the first backup file
        $firstBackup = Get-ChildItem $backupDir -Filter "MachineGuid_*.txt" | Sort-Object CreationTime | Select-Object -First 1
        if ($null -eq $firstBackup) {
            throw "No backup files found"
        }

        # Read original GUID
        $originalGuid = Get-Content $firstBackup.FullName | Where-Object { $_ -match '[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}' } | Select-Object -First 1
        if (-not $originalGuid) {
            throw "Invalid GUID in backup file"
        }

        # Get current MachineGuid
        $currentGuid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid).MachineGuid

        # Create result message
        $resultMessage = "Current MachineGuid: $currentGuid`nSystem MachineGuid: $originalGuid`nBackup file: $($firstBackup.FullName)"

        # Restore registry value
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -Value $originalGuid

        # Verify the change
        $newGuid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid).MachineGuid
        if ($newGuid -eq $originalGuid) {
            $resultMessage += "`n`nSuccess: Registry restored"
            [System.Windows.Forms.MessageBox]::Show($resultMessage, "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            throw "Verification failed"
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Restore failed: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# Add buttons to form
$form.Controls.Add($resetButton)
$form.Controls.Add($restoreButton)

# Show form
$form.ShowDialog()
