param(
    [string]$ListenAddress,
    [int]$ExternalPort = 18080,
    [int]$InternalPort = 8080,
    [string]$WslDistro = "Ubuntu",
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Remove,
    [switch]$SkipComposeRestart,
    [switch]$NetworkOnly
)

$ErrorActionPreference = "Stop"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-PowerShellLiteral {
    param([string]$Value)

    return "'" + ($Value -replace "'", "''") + "'"
}

function ConvertTo-BashLiteral {
    param([string]$Value)

    return "'" + ($Value -replace "'", "'`"`"'`"`"'") + "'"
}

function ConvertTo-WslPath {
    param([string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path).Path

    if ($resolved -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2] -replace '\\', '/'
        return "/mnt/$drive/$rest"
    }

    if ($resolved -match '^\\\\') {
        throw "UNC paths are not supported by this script: $resolved"
    }

    return $resolved -replace '\\', '/'
}

function Get-DefaultListenAddress {
    $addresses = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.InterfaceAlias -notlike "vEthernet*" -and
            $_.InterfaceAlias -notlike "*WSL*" -and
            $_.InterfaceAlias -notlike "*Loopback*" -and
            $_.AddressState -eq "Preferred"
        } |
        Sort-Object @{
            Expression = {
                if ($_.InterfaceAlias -like "*Ethernet*" -or $_.InterfaceAlias -like "*Wi-Fi*") { 0 } else { 1 }
            }
        }, InterfaceMetric

    if (-not $addresses) {
        throw "Could not auto-detect a LAN IPv4 address. Specify -ListenAddress."
    }

    return $addresses[0].IPAddress
}

function Set-EnvValue {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )

    $line = "${Name}=${Value}"

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $content = if (Test-Path -LiteralPath $Path) {
        [string[]][System.IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)
    } else {
        [string[]]@()
    }
    $pattern = '^\s*' + [regex]::Escape($Name) + '='
    $found = $false
    $updated = @(
      foreach ($item in $content) {
        if ($item -match $pattern) {
            $found = $true
            $line
        } else {
            $item
        }
      }
    )

    if (-not $found) {
        $updated = @($updated) + $line
    }

    [System.IO.File]::WriteAllLines($Path, [string[]]$updated, $utf8NoBom)
}

function New-SecretKey {
    $bytes = New-Object byte[] 64
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }

    return (($bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Initialize-EnvFile {
    param([string]$Root)

    $envPath = Join-Path $Root ".env"
    if (Test-Path -LiteralPath $envPath -PathType Leaf) {
        return
    }

    $examplePath = Join-Path $Root ".env.example"
    if (-not (Test-Path -LiteralPath $examplePath -PathType Leaf)) {
        throw ".env was not found and .env.example is missing."
    }

    $secret = New-SecretKey
    $content = [System.IO.File]::ReadAllText($examplePath, [Text.Encoding]::UTF8)
    $content = $content.Replace("replace-with-a-random-secret", $secret)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($envPath, $content, $utf8NoBom)
    Write-Host "Created .env with a random SECRET_KEY_BASE."
}

function Test-ProjectRoot {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "ProjectRoot does not exist: $Root"
    }

    $composePath = Join-Path $Root "compose.yaml"
    if (-not (Test-Path -LiteralPath $composePath -PathType Leaf)) {
        throw "compose.yaml was not found in ProjectRoot. Run this script from the repository root, or specify -ProjectRoot."
    }

    $probePath = Join-Path $Root ".codex-write-test"
    try {
        Set-Content -LiteralPath $probePath -Value "ok" -Encoding ASCII
        Remove-Item -LiteralPath $probePath -Force
    } catch {
        throw "ProjectRoot is not writable: $Root. Move the repository under your user folder, for example C:\Users\<user>\Documents, or fix the folder permissions."
    }
}

function Invoke-Compose {
    param(
        [string]$Root,
        [string]$Distro
    )

    $wslRoot = ConvertTo-WslPath -Path $Root
    $quotedWslRoot = ConvertTo-BashLiteral -Value $wslRoot
    & wsl.exe -d $Distro -- bash -lc "cd $quotedWslRoot && docker compose up -d --force-recreate openproject web"
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed. Confirm Docker Engine is running in WSL distro '$Distro'."
    }
}

function Invoke-NetworkSetupAsAdmin {
    param(
        [string]$Address,
        [int]$ListenPort,
        [int]$TargetPort,
        [switch]$RemoveRule
    )

    $scriptPath = ConvertTo-PowerShellLiteral -Value $PSCommandPath
    $addressArg = ConvertTo-PowerShellLiteral -Value $Address
    $distroArg = ConvertTo-PowerShellLiteral -Value $WslDistro

    $command = "& $scriptPath -ListenAddress $addressArg -ExternalPort $ListenPort -InternalPort $TargetPort -WslDistro $distroArg -NetworkOnly"
    if ($RemoveRule) {
        $command += " -Remove"
    }

    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $argsList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-EncodedCommand", $encodedCommand
    )

    Start-Process -FilePath powershell.exe -Verb RunAs -Wait -ArgumentList $argsList
}

if (-not $ListenAddress) {
    $ListenAddress = Get-DefaultListenAddress
}

if (-not $NetworkOnly -and -not $Remove) {
    Test-ProjectRoot -Root $ProjectRoot
    Initialize-EnvFile -Root $ProjectRoot
}

$ruleName = "OpenProject WSL $ExternalPort"
$envPath = Join-Path $ProjectRoot ".env"

if ($Remove) {
    if (-not (Test-Administrator)) {
        Invoke-NetworkSetupAsAdmin -Address $ListenAddress -ListenPort $ExternalPort -TargetPort $InternalPort -RemoveRule
        exit
    }

    netsh interface portproxy delete v4tov4 listenaddress=$ListenAddress listenport=$ExternalPort | Out-Null
    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Host "Removed port forwarding and firewall rule for $ListenAddress`:$ExternalPort."
    exit
}

if ($NetworkOnly) {
    if (-not (Test-Administrator)) {
        throw "NetworkOnly mode must run as administrator."
    }

    netsh interface portproxy delete v4tov4 listenaddress=$ListenAddress listenport=$ExternalPort | Out-Null
    netsh interface portproxy add v4tov4 listenaddress=$ListenAddress listenport=$ExternalPort connectaddress=127.0.0.1 connectport=$InternalPort | Out-Null

    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalAddress $ListenAddress `
        -LocalPort $ExternalPort `
        -Profile Private | Out-Null

    Write-Host "Configured port forwarding: $ListenAddress`:$ExternalPort -> 127.0.0.1:$InternalPort"
    exit
}

Set-EnvValue -Path $envPath -Name "OPENPROJECT_HOST_NAME" -Value "$ListenAddress`:$ExternalPort"
Set-EnvValue -Path $envPath -Name "PORT" -Value "$InternalPort"

Invoke-NetworkSetupAsAdmin -Address $ListenAddress -ListenPort $ExternalPort -TargetPort $InternalPort

if (-not $SkipComposeRestart) {
    Invoke-Compose -Root $ProjectRoot -Distro $WslDistro
}

Write-Host "OpenProject external URL: http://$ListenAddress`:$ExternalPort"
Write-Host "Port forwarding: $ListenAddress`:$ExternalPort -> 127.0.0.1:$InternalPort"
