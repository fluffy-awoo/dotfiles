[CmdletBinding()]
param(
    [string]$SettingsPath,
    [string]$VSCodeSettingsPath,
    [switch]$SkipInstall,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } finally {
        $identity.Dispose()
    }
}

function Find-InlineSudo {
    $executable = Join-Path $env:WINDIR 'System32\sudo.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { return }

    try {
        $settings = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' -ErrorAction Stop
        if ($null -eq $settings.Enabled -or [uint32]$settings.Enabled -lt 3) { return }
        $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Sudo'
        if (Test-Path -LiteralPath $policyPath -ErrorAction Stop) {
            $policy = Get-ItemProperty -LiteralPath $policyPath -ErrorAction Stop
            if ($null -ne $policy.Enabled -and [uint32]$policy.Enabled -lt 3) { return }
        }
    } catch {
        return
    }
    return $executable
}

function Restart-AsAdministrator {
    param([string]$ScriptPath, [string]$TerminalPath, [string]$EditorPath, [switch]$SkipPowerShellInstall)

    $invocation = "& '$($ScriptPath.Replace("'", "''"))'"
    if ($TerminalPath) { $invocation += " -SettingsPath '$((Resolve-FilePath $TerminalPath).Replace("'", "''"))'" }
    if ($EditorPath) { $invocation += " -VSCodeSettingsPath '$((Resolve-FilePath $EditorPath).Replace("'", "''"))'" }
    if ($SkipPowerShellInstall) { $invocation += ' -SkipInstall' }
    $workingDirectory = Resolve-FilePath '.'
    $invocation = "Set-Location -LiteralPath '$($workingDirectory.Replace("'", "''"))'`n" + $invocation
    $command = @'
$global:LASTEXITCODE = 0
__INVOCATION__
exit $global:LASTEXITCODE
'@
    $command = $command.Replace('__INVOCATION__', $invocation)
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $sudo = Find-InlineSudo
    if ($sudo) {
        Write-Step 'Requesting administrator privileges with sudo'
        Invoke-CheckedCommand -Command $sudo -Arguments @(
            '--inline', $windowsPowerShell, '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand
        )
        return
    }
    Write-Step 'Requesting administrator privileges'
    Write-Detail 'Inline sudo is unavailable; opening an administrator window.'
    Write-Detail 'Continue in the administrator setup window.'
    try {
        $process = Start-Process -FilePath $windowsPowerShell -Verb RunAs -WindowStyle Normal -WorkingDirectory $workingDirectory -Wait -PassThru -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
    } catch {
        throw "Administrator approval is required to continue. $($_.Exception.Message)"
    }
    if ($process.ExitCode -ne 0) { throw "Administrator setup failed with exit code $($process.ExitCode)." }
}

function Install-PowerShell7 {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'WinGet was not found. Install App Installer from Microsoft Store, then rerun this script.'
    }

    Write-Step 'Checking PowerShell 7'
    $global:LASTEXITCODE = 0
    & winget.exe install --id Microsoft.PowerShell --exact --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
    $noUpgradeAvailable = -1978335189
    if ($global:LASTEXITCODE -eq $noUpgradeAvailable) {
        Write-Detail 'PowerShell 7 is already up to date'
    } elseif ($global:LASTEXITCODE -ne 0) {
        throw "PowerShell installation failed with exit code $global:LASTEXITCODE."
    }
}

function Find-PowerShell7 {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\PowerShell\7\pwsh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe')
    )
    $candidates += @(Get-Command pwsh.exe -All -CommandType Application -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    $installations = foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try {
            $global:LASTEXITCODE = 0
            $versionText = & $candidate -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
            if ($global:LASTEXITCODE -eq 0 -and "$versionText" -match '^7\.\d+\.\d+$') {
                [pscustomobject]@{ Path = $candidate; Version = [version]"$versionText" }
            }
        } catch {
            continue
        }
    }
    $installation = $installations | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $installation) {
        throw 'A stable PowerShell 7 installation was not found. Open a new terminal and rerun this script.'
    }
    Write-Detail "Using PowerShell $($installation.Version): $($installation.Path)"
    return $installation.Path
}

function Get-ShellSettingsTargets {
    param([string]$TerminalPath, [string]$EditorPath)

    if ($TerminalPath) {
        [pscustomobject]@{ Kind = 'Terminal'; Path = (Resolve-FilePath $TerminalPath) }
    } else {
        foreach ($relativePath in @(
            'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json',
            'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json',
            'Microsoft\Windows Terminal\settings.json'
        )) {
            $path = Join-Path $env:LOCALAPPDATA $relativePath
            if (Test-Path -LiteralPath (Split-Path $path -Parent) -PathType Container) {
                [pscustomobject]@{ Kind = 'Terminal'; Path = $path }
            }
        }
    }

    if ($EditorPath) {
        [pscustomobject]@{ Kind = 'Editor'; Path = (Resolve-FilePath $EditorPath) }
    } else {
        foreach ($editorName in @('Code', 'Code - Insiders', 'VSCodium')) {
            $userDirectory = Join-Path $env:APPDATA "$editorName\User"
            if (-not (Test-Path -LiteralPath $userDirectory -PathType Container)) { continue }
            [pscustomobject]@{ Kind = 'Editor'; Path = (Join-Path $userDirectory 'settings.json') }
            $profilesDirectory = Join-Path $userDirectory 'profiles'
            if (Test-Path -LiteralPath $profilesDirectory -PathType Container) {
                foreach ($profileDirectory in Get-ChildItem -LiteralPath $profilesDirectory -Directory) {
                    [pscustomobject]@{ Kind = 'Editor'; Path = (Join-Path $profileDirectory.FullName 'settings.json') }
                }
            }
        }
    }
}

function Set-TerminalPowerShellDefault {
    param([System.Collections.IDictionary]$Settings, [string]$Executable)

    $profiles = Get-SettingsObject -Object $Settings -Name 'profiles'
    $defaults = Get-SettingsObject -Object $profiles -Name 'defaults'
    $defaults['startingDirectory'] = '%USERPROFILE%'
    if ($null -eq $profiles['list']) { $profiles['list'] = @() }
    if ($profiles['list'] -isnot [array]) { throw "Settings property 'profiles.list' must be an array." }
    foreach ($profile in $profiles['list']) {
        if ($profile -isnot [System.Collections.IDictionary]) { throw 'Each terminal profile must be an object.' }
    }

    $profileId = '{d92cc4ba-b07c-4905-9fde-62ecec492131}'
    $matchingProfiles = @($profiles['list'] | Where-Object { $_['guid'] -eq $profileId })
    if ($matchingProfiles.Count -gt 1) { throw 'Multiple PowerShell profiles have the same identifier.' }
    if ($matchingProfiles.Count -eq 1) {
        $profile = $matchingProfiles[0]
    } else {
        $profile = @{ guid = $profileId; name = 'PowerShell 7' }
        $profiles['list'] += $profile
    }
    $profile.Remove('source') | Out-Null
    $profile['commandline'] = '"' + $Executable + '" -NoLogo'
    $profile['startingDirectory'] = '%USERPROFILE%'
    $profile['hidden'] = $false
    $Settings['defaultProfile'] = $profileId
    $Settings['firstWindowPreference'] = 'defaultProfile'
    $Settings.Remove('startupActions') | Out-Null
}

function Set-EditorPowerShellDefault {
    param([System.Collections.IDictionary]$Settings, [string]$Executable)

    $profiles = Get-SettingsObject -Object $Settings -Name 'terminal.integrated.profiles.windows'
    $profile = Get-SettingsObject -Object $profiles -Name 'PowerShell 7'
    $profile.Remove('source') | Out-Null
    $profile['path'] = $Executable
    $profile['args'] = @('-NoLogo')
    $Settings['terminal.integrated.defaultProfile.windows'] = 'PowerShell 7'
    $automationProfile = Get-SettingsObject -Object $Settings -Name 'terminal.integrated.automationProfile.windows'
    $automationProfile['path'] = $Executable
    $automationProfile['args'] = @('-NoLogo', '-NoProfile')
    $Settings.Remove('terminal.integrated.shell.windows') | Out-Null
    $Settings.Remove('terminal.integrated.shellArgs.windows') | Out-Null
    $extensionExecutables = Get-SettingsObject -Object $Settings -Name 'powershell.powerShellAdditionalExePaths'
    $extensionExecutables['PowerShell 7'] = $Executable
    $Settings['powershell.powerShellDefaultVersion'] = 'PowerShell 7'
}

function Set-PowerShellUserPolicy {
    foreach ($scope in @('MachinePolicy', 'UserPolicy')) {
        $policy = Get-ExecutionPolicy -Scope $scope
        if ($policy -in @('Restricted', 'AllSigned')) {
            throw "The $scope execution policy is $policy. An administrator must allow your local profile scripts."
        }
    }
    if ((Get-ExecutionPolicy -Scope CurrentUser) -in @('RemoteSigned', 'Unrestricted', 'Bypass')) {
        Write-Detail 'PowerShell execution policy is already set'
        return
    }
    Write-Step 'Allowing local PowerShell profiles for your user account'
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    } catch {
        if ((Get-ExecutionPolicy -Scope CurrentUser) -ne 'RemoteSigned') {
            throw "Could not save the current-user execution policy, even with administrator privileges. $($_.Exception.Message)"
        }
    }
    if ((Get-ExecutionPolicy -Scope CurrentUser) -ne 'RemoteSigned') {
        throw 'PowerShell did not save the RemoteSigned execution policy for your user account.'
    }
}

function Test-SettingsEquivalent {
    param($Left, $Right)

    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    if ($Left -is [System.Collections.IDictionary] -and $Right -is [System.Collections.IDictionary]) {
        if ($Left.Count -ne $Right.Count) { return $false }
        foreach ($key in $Left.Keys) {
            if (-not $Right.Contains($key) -or -not (Test-SettingsEquivalent $Left[$key] $Right[$key])) { return $false }
        }
        return $true
    }
    if ($Left -is [array] -and $Right -is [array]) {
        if ($Left.Count -ne $Right.Count) { return $false }
        for ($index = 0; $index -lt $Left.Count; $index++) {
            if (-not (Test-SettingsEquivalent $Left[$index] $Right[$index])) { return $false }
        }
        return $true
    }
    return $Left.GetType() -eq $Right.GetType() -and $Left -ceq $Right
}

try {
    if ($Help) {
        Write-Step 'Usage: ./Install-PowerShell7.ps1 [options]'
        Write-Detail 'Install or upgrade stable PowerShell 7 and configure shell defaults for your user.'
        Write-Detail 'Starts in Windows PowerShell 5.1; switches to PowerShell 7 for configuration.'
        Write-Detail 'Requests administrator privileges before making changes.'
        Write-Detail 'Prefers Windows sudo in inline mode; otherwise opens an administrator window.'
        Write-Detail 'Configures Windows Terminal, VS Code, VS Code Insiders, and VSCodium when detected.'
        Write-Detail 'Includes editor profiles, task shells, and the PowerShell extension.'
        Write-Detail '-SettingsPath <path>        Target a specific Windows Terminal settings file.'
        Write-Detail '-VSCodeSettingsPath <path>  Target a specific editor settings file.'
        Write-Detail '-SkipInstall                Configure an existing PowerShell 7 installation.'
        Write-Detail '-Help                       Show usage.'
        Write-Detail 'Explicit powershell.exe calls and project or remote shell overrides remain independent.'
        return
    }

    if (-not (Test-Administrator)) {
        Restart-AsAdministrator -ScriptPath $PSCommandPath -TerminalPath $SettingsPath -EditorPath $VSCodeSettingsPath -SkipPowerShellInstall:$SkipInstall
        return
    }
    if (-not $SkipInstall) { Install-PowerShell7 }
    $executable = Find-PowerShell7
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Step 'Continuing setup in PowerShell 7'
        $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-SkipInstall')
        if ($SettingsPath) { $arguments += @('-SettingsPath', (Resolve-FilePath $SettingsPath)) }
        if ($VSCodeSettingsPath) { $arguments += @('-VSCodeSettingsPath', (Resolve-FilePath $VSCodeSettingsPath)) }
        Invoke-CheckedCommand -Command $executable -Arguments $arguments
        return
    }

    $targets = @(Get-ShellSettingsTargets -TerminalPath $SettingsPath -EditorPath $VSCodeSettingsPath)
    if ($targets.Count -eq 0) {
        throw 'No terminal or editor settings were found. Open Windows Terminal or VS Code once, or supply a settings path.'
    }
    Write-Step 'Checking shell profiles'
    $changes = @(foreach ($target in $targets) {
        $settings = if (Test-Path -LiteralPath $target.Path) { Read-Settings $target.Path } else { @{} }
        $originalSettings = $settings | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100
        if ($target.Kind -eq 'Terminal') {
            Set-TerminalPowerShellDefault -Settings $settings -Executable $executable
        } else {
            Set-EditorPowerShellDefault -Settings $settings -Executable $executable
        }
        if (Test-SettingsEquivalent $originalSettings $settings) {
            Write-Detail "Already set: $($target.Path)"
            continue
        }
        [pscustomobject]@{ Kind = $target.Kind; Path = $target.Path; Content = ($settings | ConvertTo-Json -Depth 100) }
    })
    foreach ($change in $changes) { Save-OriginalFile -Path $change.Path -AllowMissing }
    Set-PowerShellUserPolicy
    foreach ($change in $changes) {
        $application = if ($change.Kind -eq 'Terminal') { 'Windows Terminal' } else { 'editor shells' }
        Write-Step "Configuring $application"
        Write-AtomicText -Path $change.Path -Content $change.Content
        Write-Detail $change.Path
    }
    Write-Step 'Caveats'
    Write-Detail 'Restart Windows Terminal and VS Code, then open a new terminal.'
    Write-Detail 'Project settings and explicit powershell.exe calls can still select another shell.'
    if ($changes.Count -eq 0) {
        Write-Summary 'PowerShell 7 is already the default. No profile changes needed.'
    } else {
        Write-Summary "PowerShell 7 defaults updated in $($changes.Count) terminal and editor settings files."
    }
} catch {
    Write-Failure $_.Exception.Message
    exit 1
}
