[CmdletBinding()]
param(
    [string]$Flavor,
    [string]$SettingsPath,
    [switch]$Remove,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

try {
    if ($Help) {
        Write-Step 'Usage: ./Install-CatppuccinWindowsTerminal.ps1 [options]'
        Write-Detail '-Flavor <names>       Comma-separated frappe, latte, macchiato, mocha; default: all.'
        Write-Detail '-SettingsPath <path>  Use a specific Windows Terminal settings file.'
        Write-Detail '-Remove               Restore the original terminal settings snapshot.'
        Write-Detail '-Help                 Show usage.'
        return
    }

    Assert-PowerShellVersion
    $SettingsPath = Resolve-TerminalSettingsPath -Path $SettingsPath

    if ($Remove) {
        Write-Step 'Restoring Windows Terminal settings'
        Write-Caution 'Restoring the shared snapshot also reverts later terminal settings edits.'
        Restore-OriginalFile -Path $SettingsPath
        Write-Summary 'Windows Terminal settings restored'
        return
    }

    $availableFlavors = @('frappe', 'latte', 'macchiato', 'mocha')
    $selectedFlavors = if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $availableFlavors
    } else {
        @($Flavor -split '[,;]' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Select-Object -Unique)
    }
    $invalidFlavors = @($selectedFlavors | Where-Object { $_ -notin $availableFlavors })
    if ($invalidFlavors.Count -gt 0) {
        throw "Invalid flavor: $($invalidFlavors -join ', '). Choose frappe, latte, macchiato, or mocha."
    }

    Write-Step 'Installing Catppuccin for Windows Terminal'
    $settings = Read-Settings -Path $SettingsPath
    foreach ($property in @('themes', 'schemes')) {
        if ($null -eq $settings[$property]) { $settings[$property] = @() }
        if ($settings[$property] -isnot [array]) { throw "Settings property '$property' must be an array." }
    }

    $addedCount = 0
    foreach ($selectedFlavor in $selectedFlavors) {
        Write-Step "Fetching Catppuccin $selectedFlavor"
        $baseUrl = 'https://raw.githubusercontent.com/catppuccin/windows-terminal/refs/heads/main'
        foreach ($resource in @(
            @{ Property = 'themes'; File = "${selectedFlavor}Theme.json" },
            @{ Property = 'schemes'; File = "$selectedFlavor.json" }
        )) {
            $item = Invoke-RestMethod -Uri "$baseUrl/$($resource.File)" -TimeoutSec 60
            if ([string]::IsNullOrWhiteSpace($item.name)) {
                throw "Downloaded $($resource.File) has no name. Settings were not changed."
            }
            $property = $resource.Property
            if ($settings[$property] | Where-Object { $_.name -eq $item.name }) {
                Write-Detail "$($item.name) $property already present"
                continue
            }
            $settings[$property] += $item
            $addedCount++
        }
    }

    if ($addedCount -gt 0) {
        Save-OriginalFile -Path $SettingsPath
        Write-AtomicText -Path $SettingsPath -Content ($settings | ConvertTo-Json -Depth 100)
        $summary = "Installed $addedCount theme and color scheme entries"
    } else {
        $summary = 'All selected themes and color schemes are already installed'
    }
    Write-Step 'Caveats'
    Write-Detail 'Choose a Catppuccin color scheme in Windows Terminal Settings > Profiles > Appearance.'
    Write-Summary $summary
} catch {
    Write-Failure $_.Exception.Message
    exit 1
}
