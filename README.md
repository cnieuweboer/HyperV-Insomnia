# HyperV-Insomnia

HyperV-Insomnia prevents a Windows host from going to sleep while one or more Hyper-V virtual machines are active.

It is intended for unattended VM workloads, such as development or automation tasks, where the host's normal sleep settings should remain unchanged when no VM is running.

## How it works

When Hyper-V reports that a VM has started, Task Scheduler launches `vm_insomnia.ps1` in the background.

The helper:

- requests that Windows keeps the system awake
- checks Hyper-V once per minute for active VMs
- resets its shutdown timer whenever an active VM is found
- exits after two consecutive checks find no active VMs

The sleep-prevention request only exists while the helper process is running. If Windows restarts or the process terminates, no persistent power setting is left behind.

A named mutex prevents multiple copies of the helper from running at the same time.

## Installation

Keep these files together in the same folder:

```text
install.ps1
vm_insomnia.ps1
vm_insomnia.vbs
```

The folder can be located anywhere.

1. Run `install.ps1` as Administrator.
2. When prompted, choose where the task should be created in Task Scheduler:
   - press **Enter** to use the Task Scheduler root
   - or enter a folder such as `\User`
3. The installer creates the scheduled task and automatically uses the current location of `vm_insomnia.vbs`.

After installation, no manual startup is required. Starting a Hyper-V VM will automatically start the sleep-prevention helper.

To verify that it is active, run:

```powershell
powercfg /requests
```

You should see a PowerShell process listed under `SYSTEM` while a VM is active.
