[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Write-TerminalMessage {
    param(
        [string]$Prefix,
        [string]$Message,
        [ValidateSet('Blue', 'Yellow', 'Red')]
        [string]$Color = 'Blue',
        [switch]$BoldMessage,
        [switch]$StandardError
    )

    $redirected = if ($StandardError) { [Console]::IsErrorRedirected } else { [Console]::IsOutputRedirected }
    $forceColor = -not [string]::IsNullOrEmpty($env:DOTFILES_COLOR)
    $disableColor = $null -ne $env:NO_COLOR -or -not [string]::IsNullOrEmpty($env:DOTFILES_NO_COLOR)
    $useColor = -not $disableColor -and ($forceColor -or (-not $redirected -and $env:TERM -ne 'dumb'))
    $stream = if ($StandardError) { [Console]::Error } else { [Console]::Out }
    if ($useColor -and ($Host.UI.SupportsVirtualTerminal -or $forceColor)) {
        $escape = [char]27
        $colorCode = @{ Blue = 34; Yellow = 33; Red = 31 }[$Color]
        $reset = "${escape}[0m"
        $body = if ($BoldMessage) { "${escape}[1m$Message$reset" } else { $Message }
        $stream.WriteLine("${escape}[${colorCode}m$Prefix$reset $body")
    } elseif ($useColor) {
        $originalColor = [Console]::ForegroundColor
        try {
            [Console]::ForegroundColor = [ConsoleColor]$Color
            $stream.Write($Prefix)
        } finally {
            [Console]::ForegroundColor = $originalColor
        }
        $stream.WriteLine(" $Message")
    } else {
        $stream.WriteLine("$Prefix $Message")
    }
}

function Write-Step {
    param([string]$Message)
    Write-TerminalMessage -Prefix '==>' -Message $Message -BoldMessage
}

function Write-Detail {
    param([string]$Message)
    [Console]::Out.WriteLine($Message)
}

function Write-Summary {
    param(
        [string]$Message,
        [ValidateSet('Installed', 'Configured', 'Restored', 'Unchanged')]
        [string]$Outcome = 'Configured'
    )

    Write-Step 'Summary'
    if ($null -ne $env:DOTFILES_NO_EMOJI) {
        Write-Detail $Message
        return
    }
    $badge = if ($null -ne $env:DOTFILES_SUMMARY_BADGE) {
        $env:DOTFILES_SUMMARY_BADGE
    } else {
        $codePoint = @{
            Installed = 0x1F4E6
            Configured = 0x1F527
            Restored = 0x1F504
            Unchanged = 0x2705
        }[$Outcome]
        [char]::ConvertFromUtf32($codePoint)
    }
    Write-Detail "$badge  $Message"
}

function Write-Caution {
    param([string]$Message)
    Write-TerminalMessage -Prefix 'Warning:' -Message $Message -Color Yellow -StandardError
}

function Write-Failure {
    param([string]$Message)
    Write-TerminalMessage -Prefix 'Error:' -Message $Message -Color Red -StandardError
}

function Assert-PowerShellVersion {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw 'PowerShell 7 or newer is required. Run this script using pwsh.'
    }
}

function Resolve-FilePath {
    param([string]$Path)
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Resolve-TerminalSettingsPath {
    param([string]$Path, [switch]$Optional)

    if ($Path) { return Resolve-FilePath -Path $Path }
    foreach ($relativePath in @(
        'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json',
        'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json',
        'Microsoft\Windows Terminal\settings.json'
    )) {
        $candidate = Join-Path $env:LOCALAPPDATA $relativePath
        if ((Test-Path -LiteralPath $candidate) -or (Test-Path -LiteralPath "$candidate.dotfiles.bak")) {
            return $candidate
        }
    }
    if (-not $Optional) {
        throw 'Windows Terminal settings were not found. Open Windows Terminal once, or supply -SettingsPath.'
    }
}

function Read-Settings {
    param([string]$Path)

    $settings = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    if ($settings -isnot [System.Collections.IDictionary]) { throw "Expected a JSON object in $Path." }
    return $settings
}

function Get-SettingsObject {
    param([System.Collections.IDictionary]$Object, [string]$Name)

    if ($null -eq $Object) { throw "Cannot set '$Name' on an invalid settings object." }
    if ($null -eq $Object[$Name]) { $Object[$Name] = @{} }
    if ($Object[$Name] -isnot [System.Collections.IDictionary]) { throw "Settings property '$Name' must be an object." }
    return $Object[$Name]
}

function Write-AtomicFile {
    param([string]$Path, [AllowEmptyCollection()][byte[]]$Bytes)

    $absolutePath = Resolve-FilePath -Path $Path
    $directory = [System.IO.Path]::GetDirectoryName($absolutePath)
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporaryPath = Join-Path $directory ([System.IO.Path]::GetRandomFileName())
    try {
        [System.IO.File]::WriteAllBytes($temporaryPath, $Bytes)
        if ([System.IO.File]::Exists($absolutePath)) {
            [System.IO.File]::Replace($temporaryPath, $absolutePath, [System.Management.Automation.Language.NullString]::Value)
        } else {
            [System.IO.File]::Move($temporaryPath, $absolutePath)
        }
    } finally {
        if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) }
    }
}

function Write-AtomicText {
    param([string]$Path, [AllowEmptyString()][string]$Content)
    Write-AtomicFile -Path $Path -Bytes ([System.Text.UTF8Encoding]::new($false).GetBytes($Content))
}

function Save-OriginalFile {
    param([string]$Path, [switch]$AllowMissing)

    $Path = Resolve-FilePath -Path $Path
    $backupPath = "$Path.dotfiles.bak"
    $missingPath = "$Path.dotfiles.absent"
    foreach ($snapshotPath in @($backupPath, $missingPath)) {
        if ((Test-Path -LiteralPath $snapshotPath) -and -not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
            throw "Snapshot path is not a file: $snapshotPath"
        }
    }
    if ((Test-Path -LiteralPath $backupPath) -or (Test-Path -LiteralPath $missingPath)) {
        Write-Detail 'Keeping the original configuration snapshot'
        return
    }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        [System.IO.File]::Copy([System.IO.Path]::GetFullPath($Path), [System.IO.Path]::GetFullPath($backupPath), $false)
        Write-Detail "Saved original configuration: $backupPath"
    } elseif ($AllowMissing) {
        Write-AtomicText -Path $missingPath -Content ''
    } else {
        throw "Cannot back up missing file: $Path"
    }
}

function Restore-OriginalFile {
    param([string]$Path)

    $Path = Resolve-FilePath -Path $Path
    $backupPath = "$Path.dotfiles.bak"
    $missingPath = "$Path.dotfiles.absent"
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        Write-AtomicFile -Path $Path -Bytes ([System.IO.File]::ReadAllBytes([System.IO.Path]::GetFullPath($backupPath)))
    } elseif (Test-Path -LiteralPath $missingPath -PathType Leaf) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { Remove-Item -LiteralPath $Path }
    } else {
        throw "No original configuration snapshot exists for $Path."
    }
    Write-Detail "Restored $Path"
}

function Invoke-CheckedCommand {
    param([string]$Command, [string[]]$Arguments)

    $global:LASTEXITCODE = 0
    & $Command @Arguments
    if ($global:LASTEXITCODE -ne 0) { throw "$Command failed with exit code $global:LASTEXITCODE." }
}
