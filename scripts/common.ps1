$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Runtime = Join-Path $Root 'runtime'
$Pki = Join-Path $Runtime 'pki'
$State = Join-Path $Runtime 'processes'
$KeycloakVersion = '26.8.2'
$Ports = @{keycloak = 8443; loans = 8090; cards = 9000; accounts = 8080}
$Issuer = 'https://localhost:8443/realms/eazybank'

function Write-JsonFile($Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
}
function Get-JavaHome {
    $candidate = $env:JAVA_HOME
    if (-not $candidate) {
        $jdk = Get-ChildItem "$Runtime/tools" -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($jdk) { $candidate = $jdk.FullName }
    }
    if (-not $candidate) { throw 'Set JAVA_HOME to a JDK 21 installation.' }
    $version = @(& "$candidate/bin/java.exe" --version)[0]
    if ($LASTEXITCODE -or $version -notmatch '^(?:openjdk|java) 21(?:\.|\s|$)') { throw "JDK 21 is required. Found $version" }
    (Resolve-Path $candidate).Path
}
function Get-Secrets {
    Get-Content -Raw "$Runtime/secrets.json" | ConvertFrom-Json
}
function New-LocalSecret {
    $bytes = New-Object byte[] 32
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($bytes) } finally { $random.Dispose() }
    [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}
function Invoke-Native([string]$Program, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    & $Program @Arguments
    if ($LASTEXITCODE) { throw "$Program failed (exit $LASTEXITCODE)." }
}
function Get-OwnedProcess($Name) {
    $path = Join-Path $State "$Name.json"
    if (-not (Test-Path $path)) { return }
    $record = Get-Content -Raw $path | ConvertFrom-Json
    $process = Get-Process -Id $record.id -ErrorAction SilentlyContinue
    if ($process -and $process.StartTime.ToUniversalTime().Ticks -eq [long]$record.startTicks) { $process }
}
function Start-OwnedProcess($Name, $Executable, [string[]]$Arguments, [hashtable]$Environment) {
    New-Item -ItemType Directory -Force $State | Out-Null
    if (Get-OwnedProcess $Name) { throw "$Name is already running." }
    $previous = @{}
    try {
        foreach ($key in $Environment.Keys) {
            $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
            [Environment]::SetEnvironmentVariable($key, $Environment[$key], 'Process')
        }
        $options = @{
            FilePath=$Executable; ArgumentList=$Arguments; WorkingDirectory=$Root; WindowStyle='Hidden'; PassThru=$true
            RedirectStandardOutput=(Join-Path $State "$Name.out.log"); RedirectStandardError=(Join-Path $State "$Name.err.log")
        }
        $process = Start-Process @options
        Write-JsonFile (Join-Path $State "$Name.json") @{id=$process.Id; startTicks=[string]($process.StartTime.ToUniversalTime().Ticks)}
    } finally {
        foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
    }
}
function Stop-OwnedProcess($Name) {
    $process = Get-OwnedProcess $Name
    if ($process) { Invoke-Native taskkill.exe @('/PID', [string]$process.Id, '/T', '/F') | Out-Null }
    $path = Join-Path $State "$Name.json"
    if (Test-Path $path) { Remove-Item -LiteralPath $path }
}
function Get-TlsCurl {
    $candidates = if ($env:EAZYBANK_CURL) { @($env:EAZYBANK_CURL) } else {
        @(Get-Command curl.exe -All -ErrorAction SilentlyContinue | ForEach-Object Source)
    }
    foreach ($candidate in $candidates) {
        $version = @(& $candidate --version)[0]
        if ($version -match '\bOpenSSL/') { return $candidate }
    }
    throw 'Install an OpenSSL-enabled curl.exe or set EAZYBANK_CURL to its full path.'
}
function Wait-LocalHttps($Name, $Url) {
    $curl = Get-TlsCurl
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    do {
        if (-not (Get-OwnedProcess $Name)) { throw "$Name exited. See runtime/processes/$Name.*.log." }
        & $curl --silent --fail --max-time 3 --noproxy '*' --cacert (Join-Path $Pki 'ca.pem') --output NUL $Url
        if (-not $LASTEXITCODE) { return }
        Start-Sleep -Seconds 1
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "$Name readiness timed out. See runtime/processes/$Name.*.log."
}
