. "$PSScriptRoot/common.ps1"
if (-not (Test-Path "$Pki/password")) { throw 'Run generate-local-pki.ps1 first.' }
if (Get-OwnedProcess keycloak) { throw 'Keycloak is already running.' }
if (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -in 8443,9001) {
    throw 'Keycloak ports 8443 and 9001 must be available.'
}
$javaHome = Get-JavaHome
$keycloak = $env:KEYCLOAK_HOME
if (-not $keycloak) { $keycloak = Join-Path $Runtime "tools/keycloak-$KeycloakVersion" }
$launcher = Join-Path $keycloak 'bin/kc.bat'
if (-not (Test-Path $launcher) -or -not (Test-Path "$keycloak/lib/lib/main/org.keycloak.keycloak-core-$KeycloakVersion.jar")) {
    throw "Install Keycloak $KeycloakVersion and set KEYCLOAK_HOME."
}
$realm = Get-Content -Raw "$Root/infra/keycloak/realm-template.json" | ConvertFrom-Json
if (-not (Test-Path "$Runtime/secrets.json")) {
    $secrets = @{admin = New-LocalSecret}
    foreach ($client in $realm.clients) { $secrets[$client.clientId] = New-LocalSecret }
    Write-JsonFile "$Runtime/secrets.json" $secrets
}
$secrets = Get-Secrets
foreach ($client in $realm.clients) {
    $client | Add-Member -NotePropertyName secret -NotePropertyValue $secrets.($client.clientId)
}
$importDir = Join-Path $keycloak 'data/import'
New-Item -ItemType Directory -Force $importDir | Out-Null
$importFile = Join-Path $importDir 'eazybank-realm.json'
if (Test-Path $importFile) { throw "Import file already exists at $importFile." }
Write-JsonFile $importFile $realm
$environment = @{
    JAVA_HOME = $javaHome
    KC_HTTP_ENABLED = 'false'
    KC_HTTP_HOST = '127.0.0.1'
    KC_HTTP_MANAGEMENT_HOST = '127.0.0.1'
    KC_HTTP_MANAGEMENT_PORT = '9001'
    KC_HTTPS_PORT = '8443'
    KC_HTTPS_PROTOCOLS = 'TLSv1.3,TLSv1.2'
    KC_HOSTNAME = 'https://localhost:8443'
    KC_HTTPS_CERTIFICATE_FILE = (Join-Path $Pki 'keycloak.pem')
    KC_HTTPS_CERTIFICATE_KEY_FILE = (Join-Path $Pki 'keycloak.key')
    KC_HEALTH_ENABLED = 'true'
    KC_BOOTSTRAP_ADMIN_CLIENT_ID = 'local-admin'
    KC_BOOTSTRAP_ADMIN_CLIENT_SECRET = $secrets.admin
    KC_DB = 'dev-mem'
    KC_CACHE = 'local'
}
try {
    Start-OwnedProcess keycloak $env:ComSpec @('/d','/s','/c',('""{0}" start --import-realm"' -f $launcher)) $environment
    Wait-LocalHttps keycloak 'https://localhost:9001/health/ready'
    Wait-LocalHttps keycloak "$Issuer/.well-known/openid-configuration"
} catch {
    Stop-OwnedProcess keycloak
    throw
} finally {
    Remove-Item -LiteralPath $importFile
}
