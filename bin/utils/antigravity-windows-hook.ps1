# Windows Antigravity IDE bridge for the WSL-hosted dotfiles validator.
# The Windows and WSL ~/.gemini directories are different.
param(
    [ValidateSet('install', 'run')][string]$Mode = 'run',
    [string]$Distro = '',
    [string]$RepoLinux = '',
    [string]$DistroB64 = '',
    [string]$RepoLinuxB64 = '',
    [string]$ConfigPath = ''
)
$ErrorActionPreference = 'Stop'
if ($DistroB64) { $Distro = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($DistroB64)) }
if ($RepoLinuxB64) { $RepoLinux = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RepoLinuxB64)) }
if (-not $Distro -or -not $RepoLinux) { throw 'Distro and RepoLinux are required' }

function Respond([string]$Reason) {
    @{decision='continue'; reason=$Reason} | ConvertTo-Json -Compress
}

if ($Mode -eq 'install') {
    if (-not $ConfigPath) { $ConfigPath = Join-Path $env:USERPROFILE '.gemini\config\hooks.json' }
    $parent = Split-Path -Parent $ConfigPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $target = $ConfigPath
    if (Test-Path -LiteralPath $ConfigPath) {
        $item = Get-Item -LiteralPath $ConfigPath -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $target = $item.Target
            if ($target -is [array]) { $target = $target[0] }
            if (-not [IO.Path]::IsPathRooted($target)) {
                $target = [IO.Path]::GetFullPath((Join-Path $parent $target))
            }
        }
    }
    $original = if (Test-Path -LiteralPath $target) {
        [IO.File]::ReadAllText($target)
    } else { '{}' }
    $settings = $original | ConvertFrom-Json
    if ($null -eq $settings -or $settings -isnot [pscustomobject]) {
        throw 'Antigravity hooks.json must be a JSON object'
    }
    # This script's absolute Windows path is used only by the Windows IDE.
    # PowerShell -EncodedCommand uses UTF-16LE. This keeps the exact UNC
    # script path, WSL distro and checkout path out of cmd.exe metacharacter,
    # percent-expansion and quoted-string parsing.
    $scriptQuoted = $PSCommandPath.Replace("'", "''")
    $distroArg = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Distro))
    $repoArg = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($RepoLinux))
    $launch = "& '$scriptQuoted' -Mode run -DistroB64 '$distroArg' -RepoLinuxB64 '$repoArg'"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($launch))
    $command = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
    $property = $settings.PSObject.Properties['pre-flight-stop-gate']
    if ($null -eq $property) {
        $group = [pscustomobject]@{}
        $settings | Add-Member -NotePropertyName 'pre-flight-stop-gate' -NotePropertyValue $group
    } else {
        $group = $property.Value
        if ($null -eq $group -or $group -isnot [pscustomobject]) {
            throw 'Antigravity managed hook group is not a JSON object'
        }
    }
    $handlers = @($group.Stop | Where-Object { $null -ne $_ -and $_.command -ne $command })
    $handlers += [pscustomobject]@{type='command'; command=$command; timeout=60}
    if ($null -eq $group.PSObject.Properties['Stop']) {
        $group | Add-Member -NotePropertyName Stop -NotePropertyValue $handlers
    } else { $group.Stop = $handlers }
    $result = ConvertTo-Json -InputObject $settings -Depth 100
    # Semantic no-op: preserve original formatting, inode and modification time.
    if ($original -and (($original | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress) -eq
                        ($result | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress))) {
        return
    }
    $targetParent = Split-Path -Parent $target
    $temp = Join-Path $targetParent ('.hooks-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temp, $result + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $target) {
        $backup = $target + '.bak.' + [guid]::NewGuid().ToString('N')
        [IO.File]::Replace($temp, $target, $backup)
    } else {
        [IO.File]::Move($temp, $target)
    }
    Write-Output '[CHANGED] Windows Antigravity hook settings updated'
    return
}

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if ($null -eq $payload -or $payload -isnot [pscustomobject]) {
        throw 'Missing/invalid Stop payload'
    }
    $mapped = @()
    foreach ($path in @($payload.workspacePaths)) {
        if ($path -match '^\\\\wsl(?:\.localhost|\$)\\([^\\]+)\\(.+)$') {
            if ($Matches[1] -ne $Distro) { throw ('Different WSL distribution: ' + $Matches[1]) }
            $mapped += '/' + $Matches[2].Replace('\', '/')
        } elseif ($path -match '^([a-zA-Z]):\\(.+)$') {
            $mapped += '/mnt/' + $Matches[1].ToLowerInvariant() + '/' + $Matches[2].Replace('\', '/')
        } elseif ($path.StartsWith('/')) {
            $mapped += $path
        } else {
            throw ('Unsupported Windows workspace path: ' + $path)
        }
    }
    $payload.workspacePaths = $mapped
    $wire = ConvertTo-Json -InputObject $payload -Depth 100 -Compress
    # Windows PowerShell 5.1 defaults native-process stdin to US-ASCII; UTF-8
    # is required for Korean filenames and non-ASCII workspace paths.
    $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $response = $wire | & wsl.exe -d $Distro -- bash "$RepoLinux/bin/hooks/agent-stop-adapter.sh" antigravity
    if ($LASTEXITCODE -ne 0) { throw ('WSL adapter exited ' + $LASTEXITCODE) }
    if (-not $response) { throw 'WSL adapter returned no JSON' }
    $response | ConvertFrom-Json | Out-Null
    Write-Output $response
} catch {
    Respond ('Windows Antigravity Stop validation could not run: ' + $_.Exception.Message)
}
