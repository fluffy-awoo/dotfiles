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
        Write-Detail '-Flavor <names>       Comma-separated frappe, latte, macchiato, mocha, or all.'
        Write-Detail '-SettingsPath <path>  Use a specific Windows Terminal settings file.'
        Write-Detail '-Remove               Restore the original terminal settings snapshot.'
        Write-Detail '-Help                 Show usage.'
        Write-Detail 'Examples: ./Install-CatppuccinWindowsTerminal.ps1 -Flavor frappe'
        Write-Detail '          ./Install-CatppuccinWindowsTerminal.ps1 -Flavor all'
        return
    }

    Assert-PowerShellVersion
    if ($Remove) {
        $SettingsPath = Resolve-TerminalSettingsPath -Path $SettingsPath
        Write-Step 'Restoring Windows Terminal settings'
        Write-Caution 'Restoring the shared snapshot also reverts later terminal settings edits.'
        Restore-OriginalFile -Path $SettingsPath
        Write-Summary 'Windows Terminal settings restored'
        return
    }

    $flavorLabels = [ordered]@{
        frappe = 'Frappé'
        latte = 'Latte'
        macchiato = 'Macchiato'
        mocha = 'Mocha'
    }
    $availableFlavors = @($flavorLabels.Keys)
    if (-not $PSBoundParameters.ContainsKey('Flavor')) {
        $options = @($availableFlavors) + 'all'
        $labels = @($flavorLabels.Values) + 'All presets'
        $selection = Read-MenuChoice -Title 'Choose a Catppuccin color preset' -Options $labels -DefaultIndex 4
        if ($null -eq $selection) { return }
        $Flavor = $options[$selection]
    }
    $selectedFlavors = if ($Flavor.Trim() -ieq 'all') {
        $availableFlavors
    } else {
        @($Flavor -split '[,;]' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Select-Object -Unique)
    }
    $invalidFlavors = @($selectedFlavors | Where-Object { $_ -notin $availableFlavors })
    if ($invalidFlavors.Count -gt 0) {
        throw "Invalid flavor: $($invalidFlavors -join ', '). Choose frappe, latte, macchiato, mocha, or all."
    }

    $SettingsPath = Resolve-TerminalSettingsPath -Path $SettingsPath
    Write-Step 'Installing Catppuccin for Windows Terminal'
    $settings = Read-Settings -Path $SettingsPath
    foreach ($property in @('themes', 'schemes')) {
        if ($null -eq $settings[$property]) { $settings[$property] = @() }
        if ($settings[$property] -isnot [array]) { throw "Settings property '$property' must be an array." }
    }

    $addedCount = 0
    foreach ($selectedFlavor in $selectedFlavors) {
        Write-Step "Fetching Catppuccin $($flavorLabels[$selectedFlavor])"
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
