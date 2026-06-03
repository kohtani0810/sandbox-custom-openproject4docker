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

    if (Test-Path -LiteralPath $Path) {
        $content = Get-Content -LiteralPath $Path -Encoding UTF8
    } else {
        $content = @()
    }

    $pattern = '^\s*' + [regex]::Escape($Name) + '='
    $found = $false
    $updated = foreach ($item in $content) {
        if ($item -match $pattern) {
            $found = $true
            $line
        } else {
            $item
        }
    }

    if (-not $found) {
        $updated += $line
    }

    Set-Content -LiteralPath $Path -Value $updated -Encoding UTF8
}

function Invoke-Compose {
    param(
        [string]$Root,
        [string]$Distro
    )

    $wslRoot = & wsl.exe -d $Distro wslpath -a $Root
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($wslRoot)) {
        throw "Could not resolve the project path from WSL distro '$Distro': $Root"
    }

    & wsl.exe -d $Distro -- bash -lc "cd '$($wslRoot.Trim())' && docker compose up -d --force-recreate openproject web"
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed. Confirm Docker Engine is running in WSL distro '$Distro'."
    }
}

function Invoke-NetworkSetupAsAdmin {
    param(
        [string]$Address,
        [int]$ListenPort,
        [int]$TargetPort,
        [string]$Root,
        [switch]$RemoveRule
    )

    $argsList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-ListenAddress", "$Address",
        "-ExternalPort", "$ListenPort",
        "-InternalPort", "$TargetPort",
        "-WslDistro", "$WslDistro",
        "-ProjectRoot", "`"$Root`"",
        "-NetworkOnly"
    )

    if ($RemoveRule) { $argsList += "-Remove" }

    Start-Process -FilePath powershell.exe -Verb RunAs -Wait -ArgumentList $argsList
}

if (-not $ListenAddress) {
    $ListenAddress = Get-DefaultListenAddress
}

$ruleName = "OpenProject WSL $ExternalPort"
$envPath = Join-Path $ProjectRoot ".env"

if ($Remove) {
    if (-not (Test-Administrator)) {
        Invoke-NetworkSetupAsAdmin -Address $ListenAddress -ListenPort $ExternalPort -TargetPort $InternalPort -Root $ProjectRoot -RemoveRule
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

Invoke-NetworkSetupAsAdmin -Address $ListenAddress -ListenPort $ExternalPort -TargetPort $InternalPort -Root $ProjectRoot

if (-not $SkipComposeRestart) {
    Invoke-Compose -Root $ProjectRoot -Distro $WslDistro
}

Write-Host "OpenProject external URL: http://$ListenAddress`:$ExternalPort"
Write-Host "Port forwarding: $ListenAddress`:$ExternalPort -> 127.0.0.1:$InternalPort"
