# vm_insomnia.ps1
#
# Prevents Windows from sleeping while any Hyper-V VM is active.
#
# Intended to be launched by Task Scheduler when Hyper-V activity occurs.
# Only one instance can run at a time.
#
# The helper exits after two consecutive checks find no active VMs.
# Checks are performed once per minute by default.

Import-Module Hyper-V -ErrorAction Stop

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$PollIntervalSeconds = 60
$NoVmChecksRequired  = 2

# States considered safely inactive.
$InactiveStates = @(
    'Off'
    'Saved'
    'OffCritical'
    'SavedCritical'
)

# ---------------------------------------------------------------------------
# Single instance
# ---------------------------------------------------------------------------

$mutexName = 'Global\HyperV-SleepBlocker'
$createdNew = $false
$mutex = $null
$ownsMutex = $false

try {
    $mutex = New-Object System.Threading.Mutex(
        $true,
        $mutexName,
        [ref]$createdNew
    )

    if (-not $createdNew) {
        # Another instance is already running.
        exit 0
    }

    $ownsMutex = $true

    # -----------------------------------------------------------------------
    # Windows sleep-prevention API
    # -----------------------------------------------------------------------

    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class SleepBlocker
{
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
"@

    # PowerShell 5.1 interprets 0x80000000 as signed Int32 first,
    # so use the decimal UInt32 value instead.
    $ES_CONTINUOUS      = [uint32]2147483648
    $ES_SYSTEM_REQUIRED = [uint32]1

    $result = [SleepBlocker]::SetThreadExecutionState(
        $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED
    )

    if ($result -eq 0) {
        throw 'SetThreadExecutionState failed.'
    }

    # -----------------------------------------------------------------------
    # Monitor Hyper-V
    # -----------------------------------------------------------------------

    $noVmCount = 0

    while ($true) {
        try {
            $activeVMs = @(
                Get-VM -ErrorAction Stop |
                    Where-Object {
                        $_.State.ToString() -notin $InactiveStates
                    }
            )

            if ($activeVMs.Count -gt 0) {
                # At least one VM is active.
                $noVmCount = 0
            }
            else {
                $noVmCount++

                if ($noVmCount -ge $NoVmChecksRequired) {
                    break
                }
            }
        }
        catch {
            # If Hyper-V cannot be queried, do not risk allowing the
            # machine to sleep. Treat the result as inconclusive.
            $noVmCount = 0
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }
}
finally {
    # Clear this thread's sleep-prevention request.
    if ('SleepBlocker' -as [type]) {
        [SleepBlocker]::SetThreadExecutionState(
            [uint32]2147483648
        ) | Out-Null
    }

    if ($mutex) {
        if ($ownsMutex) {
            try {
                $mutex.ReleaseMutex()
            }
            catch {
                # Process is exiting anyway.
            }
        }

        $mutex.Dispose()
    }
}