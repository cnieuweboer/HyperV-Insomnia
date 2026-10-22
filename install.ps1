# install.ps1
#
# Installs the VM Insomnia scheduled task.
# Keep this file in the same folder as:
#   vm_insomnia.vbs
#   vm_insomnia.ps1
#
# Run this script as Administrator.

$ErrorActionPreference = 'Stop'

$TaskName = 'VM insomnia'

# ---------------------------------------------------------------------------
# Require Administrator
# ---------------------------------------------------------------------------

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Error 'This installer must be run as Administrator.'
    exit 1
}

# ---------------------------------------------------------------------------
# Ask where to place the task
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host 'Task Scheduler folder'
Write-Host 'Leave empty to install the task in the Task Scheduler root.'
Write-Host 'Example: \User'
Write-Host ''

$TaskFolder = Read-Host 'Folder'

$TaskFolder = $TaskFolder.Trim()

if ([string]::IsNullOrWhiteSpace($TaskFolder)) {
    $TaskPath = "\$TaskName"
}
else {
    $TaskFolder = '\' + $TaskFolder.Trim('\')
    $TaskPath = "$TaskFolder\$TaskName"
}

# ---------------------------------------------------------------------------
# Resolve files
# ---------------------------------------------------------------------------

$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbsPath = Join-Path $scriptFolder 'vm_insomnia.vbs'
$ps1Path = Join-Path $scriptFolder 'vm_insomnia.ps1'

if (-not (Test-Path -LiteralPath $vbsPath)) {
    Write-Error "Missing file: $vbsPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $ps1Path)) {
    Write-Error "Missing file: $ps1Path"
    exit 1
}

$escapedVbsPath = [System.Security.SecurityElement]::Escape($vbsPath)

# ---------------------------------------------------------------------------
# Build Task Scheduler XML
# ---------------------------------------------------------------------------

$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Prevents the host from sleeping while a Hyper-V virtual machine is active.</Description>
  </RegistrationInfo>

  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-Hyper-V-Worker-Admin"&gt;&lt;Select Path="Microsoft-Windows-Hyper-V-Worker-Admin"&gt;*[System[Provider[@Name='Microsoft-Windows-Hyper-V-Worker'] and EventID=18500]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>

  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>

  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>

    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>

    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>

  <Actions Context="Author">
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>&quot;$escapedVbsPath&quot;</Arguments>
    </Exec>
  </Actions>
</Task>
"@

# ---------------------------------------------------------------------------
# Register task
# ---------------------------------------------------------------------------

$tempXml = Join-Path $env:TEMP 'vm-insomnia-task.xml'

try {
    Set-Content `
        -LiteralPath $tempXml `
        -Value $taskXml `
        -Encoding Unicode

    & schtasks.exe /Create `
        /TN $TaskPath `
        /XML $tempXml `
        /F

    if ($LASTEXITCODE -ne 0) {
        throw "schtasks.exe failed with exit code $LASTEXITCODE."
    }
}
finally {
    Remove-Item -LiteralPath $tempXml -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "Installed scheduled task: $TaskPath"
Write-Host "Helper path: $vbsPath"
Write-Host ''
Write-Host 'VM Insomnia is ready.'