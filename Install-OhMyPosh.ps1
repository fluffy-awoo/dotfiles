[CmdletBinding()]
param(
    [ValidateSet('catppuccin', 'frappe', 'latte', 'macchiato', 'mocha')]
    [string]$Flavor = 'catppuccin',
    [string]$SettingsPath,
    [string]$ProfilePath = $PROFILE,
    [string]$ThemeDirectory = (Join-Path $HOME '.poshthemes'),
    [switch]$InstallFont,
    [switch]$Remove,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Terminal.Common.ps1')

try {
    if ($Help) {
        Write-Step 'Usage: ./Install-OhMyPosh.ps1 [options]'
        Write-Detail '-Flavor <name>         catppuccin, frappe, latte, macchiato, mocha; default: catppuccin.'
        Write-Detail '-InstallFont           Install the latest Cascadia Mono Nerd Font and configure Windows Terminal.'
        Write-Detail '-SettingsPath <path>   Use a specific Windows Terminal settings file.'
        Write-Detail '-ProfilePath <path>    Use a specific PowerShell profile.'
        Write-Detail '-ThemeDirectory <dir>  Store downloaded themes in this directory.'
        Write-Detail '-Remove                Restore the original profile and any terminal settings snapshot.'
        Write-Detail '-Help                  Show usage.'
        return
    }

    Assert-PowerShellVersion
    $ProfilePath = Resolve-FilePath -Path $ProfilePath
    $ThemeDirectory = Resolve-FilePath -Path $ThemeDirectory

    if ($Remove) {
        Write-Step 'Restoring PowerShell profile'
        Write-Caution 'Restoring snapshots also reverts edits made after the initial setup.'
        Restore-OriginalFile -Path $ProfilePath
        $terminalPath = Resolve-TerminalSettingsPath -Path $SettingsPath -Optional
        if ($terminalPath -and (Test-Path -LiteralPath "$terminalPath.dotfiles.bak")) {
            Write-Step 'Restoring Windows Terminal settings'
            Restore-OriginalFile -Path $terminalPath
        }
        Write-Step 'Caveats'
        Write-Detail 'Oh My Posh, installed fonts, and downloaded themes remain available.'
        Write-Summary 'Original configuration restored' -Outcome Restored
        return
    }

    $settings = $null
    $fontFace = 'CaskaydiaMono Nerd Font Mono'
    if ($InstallFont) {
        $SettingsPath = Resolve-TerminalSettingsPath -Path $SettingsPath
        $settings = Read-Settings -Path $SettingsPath
        $profiles = Get-SettingsObject -Object $settings -Name 'profiles'
        $defaults = Get-SettingsObject -Object $profiles -Name 'defaults'
        $font = Get-SettingsObject -Object $defaults -Name 'font'
        $font['face'] = $fontFace
        if ($null -ne $profiles['list'] -and $profiles['list'] -isnot [array]) {
            throw "Settings property 'profiles.list' must be an array."
        }
        foreach ($terminalProfile in $profiles['list']) {
            $font = Get-SettingsObject -Object $terminalProfile -Name 'font'
            $font['face'] = $fontFace
        }
    }

    Write-Step 'Checking Oh My Posh'
    if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw 'WinGet was not found. Install Oh My Posh, then rerun this script.'
        }
        Write-Step 'Installing Oh My Posh'
        Invoke-CheckedCommand -Command 'winget' -Arguments @(
            'install', '--id', 'JanDeDobbeleer.OhMyPosh', '--exact', '--source', 'winget', '--scope', 'user'
        )
        $env:Path += ";$(Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin')"
        if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
            throw 'Oh My Posh is not on PATH after installation. Open a new PowerShell session and rerun this script.'
        }
    } else {
        Write-Detail 'Oh My Posh is already installed'
    }

    $themeName = if ($Flavor -eq 'catppuccin') { 'catppuccin.omp.json' } else { "catppuccin_$Flavor.omp.json" }
    $themePath = [System.IO.Path]::GetFullPath((Join-Path $ThemeDirectory $themeName))
    Write-Step "Fetching Catppuccin $Flavor prompt"
    $theme = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/$themeName" -TimeoutSec 60
    if (-not $theme.blocks) { throw 'The downloaded prompt theme has no blocks.' }

    if ($InstallFont) {
        Write-Step "Installing $fontFace"
        Invoke-CheckedCommand -Command 'oh-my-posh' -Arguments @('font', 'install', 'CascadiaMono')
        Save-OriginalFile -Path $SettingsPath
        Write-AtomicText -Path $SettingsPath -Content ($settings | ConvertTo-Json -Depth 100)
        Write-Detail "Windows Terminal font set to $fontFace"
    }

    Write-AtomicText -Path $themePath -Content ($theme | ConvertTo-Json -Depth 100)
    $profileContent = if (Test-Path -LiteralPath $ProfilePath) {
        [System.IO.File]::ReadAllText($ProfilePath)
    } else { '' }
    $escapedThemePath = $themePath.Replace("'", "''")
    $loaderLine = "oh-my-posh init pwsh --config '$escapedThemePath' | Invoke-Expression"
    $pattern = [regex]::new('(?m)^[\t ]*oh-my-posh[\t ]+init\b[^\r\n]*')
    $updatedContent = if ($pattern.IsMatch($profileContent)) {
        $pattern.Replace($profileContent, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $loaderLine }, 1)
    } elseif ($profileContent.Length -gt 0) {
        $profileContent.TrimEnd("`r", "`n") + [Environment]::NewLine + $loaderLine + [Environment]::NewLine
    } else {
        $loaderLine + [Environment]::NewLine
    }

    Save-OriginalFile -Path $ProfilePath -AllowMissing
    if ($updatedContent -cne $profileContent) {
        Write-AtomicText -Path $ProfilePath -Content $updatedContent
    }
    Write-Step 'Caveats'
    Write-Detail 'Open a new PowerShell session to load your prompt.'
    Write-Summary 'Oh My Posh configured' -Outcome Configured
} catch {
    Write-Failure $_.Exception.Message
    exit 1
}
