. "$PSScriptRoot/common.ps1"
. "$PSScriptRoot/e2e-requests.ps1"
$accounts = 'https://localhost:8080/api/fetchCustomerDetails'
$loans = 'https://localhost:8090/api/fetch'
$cards = 'https://localhost:9000/api/fetch'
$fixture = 'mobileNumber=0600000001'
$operations = @(
    @{Client='bank-client'; Audience='accounts-api'; Role='SUMMARY_READ'},
    @{Client='accounts-to-loans'; Audience='loans-api'; Role='LOANS_READ'},
    @{Client='accounts-to-cards'; Audience='cards-api'; Role='CARDS_READ'},
    @{Client='cards-operator'; Audience='cards-api'; Role='CARDS_WRITE'},
    @{Client='probe-cards'; Audience='cards-api'; Role=$null}
)
$tokens = @{}
foreach ($operation in $operations) {
    $token = Get-TestToken $operation.Client
    $claims = Get-JwtClaims $token
    $roles = @($claims.realm_access.roles | Where-Object { $_ })
    if ($claims.iss -cne $Issuer -or $claims.azp -cne $operation.Client -or -not $claims.sub -or
        @($claims.aud).Count -ne 1 -or $claims.aud -cne $operation.Audience -or
        $claims.exp - $claims.iat -ne 120 -or
        ($operation.Role -and ($roles.Count -ne 1 -or $roles[0] -cne $operation.Role)) -or
        (-not $operation.Role -and $roles.Count -ne 0)) {
        throw "Unexpected token claims for $($operation.Client)."
    }
    $tokens[$operation.Client] = $token
}
$bank = $tokens['bank-client']
$reader = $tokens['accounts-to-cards']
$summaryUrl = "${accounts}?$fixture"
$cardsUrl = "${cards}?$fixture"
$nominal = Invoke-LocalRequest $summaryUrl -Token $bank
Assert-Status T1 200 $nominal
$body = $nominal.Body | ConvertFrom-Json
if (-not ($body.accountsDto -and $body.loansDto -and $body.cardsDto)) { throw 'T1 partial response.' }
$correlation = $nominal.Headers.'x-correlation-id'[0]
foreach ($name in 'loans','cards') {
    if (-not (Select-String -Path "$State/$name.out.log" -SimpleMatch "correlationId=$correlation client=accounts-to-$name decision=allowed status=200")) {
        throw "T1 missing correlated decision in $name."
    }
}
foreach ($url in $summaryUrl,"${loans}?$fixture",$cardsUrl) {
    Assert-Status T2 401 (Invoke-LocalRequest $url)
}
Assert-Status T4 401 (Invoke-LocalRequest $cardsUrl -Token $bank)
Assert-Status T4 401 (Invoke-LocalRequest $cardsUrl -Token $tokens['accounts-to-loans'])
Assert-Status T5 403 (Invoke-LocalRequest $cardsUrl -Token $tokens['probe-cards'])
Assert-Status T6 200 (Invoke-LocalRequest $cardsUrl -Token $reader)
$create = 'https://localhost:9000/api/create?mobileNumber=0600000003'
$delete = 'https://localhost:9000/api/delete?mobileNumber=0600000003'
$created = "${cards}?mobileNumber=0600000003"
Assert-Status T6 403 (Invoke-LocalRequest $create -Method POST -Token $reader)
Assert-Status T6 403 (Invoke-LocalRequest $delete -Method DELETE -Token $reader)
Assert-Status T6 404 (Invoke-LocalRequest $created -Token $reader)
Assert-Status T7 401 (Invoke-LocalRequest $summaryUrl -Headers @('X-Role: SUMMARY_READ','X-Service: bank-client'))
Assert-Status T11 404 (Invoke-LocalRequest "${accounts}?mobileNumber=0600000099" -Token $bank)
Assert-Status T11 400 (Invoke-LocalRequest "${accounts}?mobileNumber=invalid" -Token $bank)
foreach ($route in '/h2-console/','/actuator/shutdown','/api/update') {
    Assert-Status T12 403 (Invoke-LocalRequest "https://localhost:9000$route" -Token $reader)
}
$admin = Get-TestToken local-admin master
$adminApi = 'https://localhost:8443/admin/realms/eazybank'
$operator = Invoke-LocalRequest "$adminApi/users?username=service-account-cards-operator&exact=true" -Token $admin
Assert-Status 'T13 operator lookup' 200 $operator
$operatorId = ($operator.Body | ConvertFrom-Json).id
$role = Invoke-LocalRequest "$adminApi/roles/CARDS_WRITE" -Token $admin
Assert-Status 'T13 role lookup' 200 $role
$mapping = "$adminApi/users/$operatorId/role-mappings/realm"
$roleBody = '[' + $role.Body + ']'
Assert-Status 'T13 remove role' 204 (Invoke-LocalRequest $mapping -Method DELETE -Token $admin -Json $roleBody)
try {
    Assert-Status T13 403 (Invoke-LocalRequest $create -Method POST -Token (Get-TestToken cards-operator))
    Assert-Status T13 404 (Invoke-LocalRequest $created -Token $reader)
} finally {
    Assert-Status 'T13 restore role' 204 (Invoke-LocalRequest $mapping -Method POST -Token (Get-TestToken local-admin master) -Json $roleBody)
}
$writer = Get-TestToken cards-operator
try {
    Assert-Status T13 201 (Invoke-LocalRequest $create -Method POST -Token $writer)
    Assert-Status T13 200 (Invoke-LocalRequest $created -Token $reader)
    Assert-Status T13 403 (Invoke-LocalRequest $delete -Method DELETE -Token $writer)
} finally {
    & "$PSScriptRoot/stop-local.ps1" cards
    & "$PSScriptRoot/start-local.ps1" cards
}
Assert-Status T13 404 (Invoke-LocalRequest $created -Token (Get-TestToken accounts-to-cards))
Assert-Status T14 200 (Invoke-LocalRequest 'https://localhost:9001/health/ready')
$sockets = @(Get-NetTCPConnection -State Listen | Where-Object LocalPort -in 8080,8090,9000,8443,9001)
if (@($sockets.LocalPort | Sort-Object -Unique).Count -ne 5 -or @($sockets | Where-Object LocalAddress -ne '127.0.0.1').Count) {
    throw 'T14 expected five loopback-only listeners.'
}
foreach ($port in 8080,8090,9000,8443,9001) {
    $null = & curl.exe --silent --fail --noproxy '*' --max-time 2 --output NUL "http://localhost:$port/"
    if (-not $LASTEXITCODE) { throw "T14 unexpected plaintext response on $port." }
}
Write-Host 'T14 loopback and HTTPS listeners verified.'
$baselineCount = @(Select-String -Path "$State/accounts.out.log" -SimpleMatch 'issuedTokenFor=').Count
Assert-Status T10 200 (Invoke-LocalRequest $summaryUrl -Token (Get-TestToken bank-client))
if (@(Select-String -Path "$State/accounts.out.log" -SimpleMatch 'issuedTokenFor=').Count -ne $baselineCount) {
    throw 'T10 an unexpired service token was not reused. Run this suite on a fresh stack.'
}
Write-Host 'Waiting for JWT expiration and clock tolerance.'
$until = [DateTimeOffset]::FromUnixTimeSeconds((Get-JwtClaims $bank).exp + 32)
while ([DateTimeOffset]::UtcNow -lt $until) { Start-Sleep -Seconds 2 }
Assert-Status T3 401 (Invoke-LocalRequest $summaryUrl -Token $bank)
$fresh = Get-TestToken bank-client
$pieces = $fresh.Split('.')
$replacement = if ($pieces[2][0] -eq 'A') { 'B' } else { 'A' }
$pieces[2] = $replacement + $pieces[2].Substring(1)
Assert-Status T3 401 (Invoke-LocalRequest $summaryUrl -Token ($pieces -join '.'))
Assert-Status T10 200 (Invoke-LocalRequest $summaryUrl -Token $fresh)
if (@(Select-String -Path "$State/accounts.out.log" -SimpleMatch 'issuedTokenFor=').Count -ne ($baselineCount + 2)) {
    throw 'T10 expected one new token for each outbound registration.'
}
try {
    Restart-Accounts -InvalidLoansSecret
    Assert-Status T9 502 (Invoke-LocalRequest $summaryUrl -Token (Get-TestToken bank-client))
} finally { Restart-Accounts }
try {
    & "$PSScriptRoot/stop-local.ps1" loans
    Assert-Status 'T9/T11' 503 (Invoke-LocalRequest $summaryUrl -Token (Get-TestToken bank-client))
} finally { & "$PSScriptRoot/start-local.ps1" loans }

$tlsPort = 8091
if (Get-NetTCPConnection -State Listen -LocalPort $tlsPort -ErrorAction SilentlyContinue) { throw "T8 port $tlsPort is busy." }
$tlsFixture = Join-Path $Runtime 'tls-test'
New-Item -ItemType Directory -Force $tlsFixture | Out-Null
Invoke-Native openssl @('req','-x509','-newkey','rsa:2048','-nodes','-sha256','-days','1',
    '-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost',
    '-keyout',"$tlsFixture/server.key",'-out',"$tlsFixture/server.pem") | Out-Null
$openssl = (Get-Command openssl).Source
try {
    Start-OwnedProcess tls-test $openssl @('s_server','-accept',"127.0.0.1:$tlsPort",'-quiet','-www',
        '-key',('"{0}/server.key"' -f $tlsFixture),'-cert',('"{0}/server.pem"' -f $tlsFixture)) @{}
    Restart-Accounts -LoansBaseUrl "https://localhost:$tlsPort"
    if (-not (Get-OwnedProcess tls-test) -or -not (Get-NetTCPConnection -State Listen -LocalPort $tlsPort -ErrorAction SilentlyContinue)) {
        throw 'T8 TLS fixture failed to bind.'
    }
    Assert-Status T8 503 (Invoke-LocalRequest $summaryUrl -Token (Get-TestToken bank-client))
} finally {
    Stop-OwnedProcess tls-test
    Restart-Accounts
}
Assert-Status 'Final T1' 200 (Invoke-LocalRequest $summaryUrl -Token (Get-TestToken bank-client))
Write-Host 'E2E scenarios passed.'
