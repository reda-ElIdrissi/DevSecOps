param(
    [ValidateSet('all','accounts','loans','cards')][string]$Service = 'all',
    [string]$LoansBaseUrl = 'https://localhost:8090',
    [switch]$InvalidLoansSecret
)
. "$PSScriptRoot/common.ps1"
$javaHome = Get-JavaHome
$java = Join-Path $javaHome 'bin/java.exe'
$names = if ($Service -eq 'all') { @('loans','cards','accounts') } else { @($Service) }
$neededPorts = @($names | ForEach-Object { $Ports[$_] })
if ($Service -eq 'all') { $neededPorts += 8443,9001 }
$occupied = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -in $neededPorts
if ($occupied) { throw "Required ports are busy: $($occupied.LocalPort | Sort-Object -Unique)." }
foreach ($name in $names) {
    if (-not (Test-Path "$Root/$name/target/$name-1.0.0.jar")) {
        throw "Build the project with .\mvnw.cmd clean verify first."
    }
}
$started = @()
try {
    if ($Service -eq 'all') {
        if (-not (Test-Path "$Pki/password")) { & "$PSScriptRoot/generate-local-pki.ps1" }
        & "$PSScriptRoot/init-keycloak.ps1"
        $started += 'keycloak'
    } elseif (-not (Get-OwnedProcess keycloak)) {
        throw 'Start Keycloak first with init-keycloak.ps1.'
    }
    $password = Get-Content -Raw "$Pki/password"
    foreach ($name in $names) {
        $environment = @{
            TLS_KEYSTORE = ([Uri]::new((Join-Path $Pki "$name.p12"))).AbsoluteUri
            TLS_KEYSTORE_PASSWORD = $password
            TLS_TRUSTSTORE = ([Uri]::new((Join-Path $Pki 'truststore.p12'))).AbsoluteUri
            TLS_TRUSTSTORE_PASSWORD = $password
            ISSUER_URI = $Issuer
        }
        if ($name -eq 'accounts') {
            $secrets = Get-Secrets
            $environment.ACCOUNTS_LOANS_CLIENT_SECRET = if ($InvalidLoansSecret) { New-LocalSecret } else { $secrets.'accounts-to-loans' }
            $environment.ACCOUNTS_CARDS_CLIENT_SECRET = $secrets.'accounts-to-cards'
            $environment.LOANS_BASE_URL = $LoansBaseUrl
            $environment.CARDS_BASE_URL = 'https://localhost:9000'
        }
        Start-OwnedProcess $name $java @('-jar',"$name/target/$name-1.0.0.jar") $environment
        $started += $name
    }
    foreach ($name in $names) { Wait-LocalHttps $name "https://localhost:$($Ports[$name])/actuator/health" }
    Write-Host "Ready: $($started -join ', ')"
} catch {
    foreach ($name in $started) { Stop-OwnedProcess $name }
    throw
}
