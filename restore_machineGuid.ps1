# Check administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Requesting admin privileges..."
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Get backup directory path
$backupDir = Join-Path $HOME "MachineGuid_Backups"

if (-not (Test-Path $backupDir)) {
    Write-Host "Error: Backup folder not found" -ForegroundColor Red
    exit 1
}

# Get the first backup file (sorted by creation time)
$firstBackup = Get-ChildItem $backupDir -Filter "MachineGuid_*.txt" | Sort-Object CreationTime | Select-Object -First 1

if ($null -eq $firstBackup) {
    Write-Host "Error: No backup files found" -ForegroundColor Red
    exit 1
}

# Read original GUID
$originalGuid = Get-Content $firstBackup.FullName | Where-Object { $_ -match '[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}' } | Select-Object -First 1

if (-not $originalGuid) {
    Write-Host "Error: Invalid GUID in backup file" -ForegroundColor Red
    exit 1
}

# Get current MachineGuid
$currentGuid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid).MachineGuid

Write-Host "Current MachineGuid: $currentGuid"
Write-Host "System MachineGuid: $originalGuid"
Write-Host "Backup file: $($firstBackup.FullName)"

# Restore registry value
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -Value $originalGuid

# Verify the change
$newGuid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid).MachineGuid
if ($newGuid -eq $originalGuid) {
    Write-Host "Success: Registry restored" -ForegroundColor Green
} else {
    Write-Host "Warning: Verification failed" -ForegroundColor Yellow
}

Write-Host "`n按任意键退出..." -NoNewline
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") 