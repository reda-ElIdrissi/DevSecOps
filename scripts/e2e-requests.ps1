$Curl = Get-TlsCurl
function Invoke-LocalRequest {
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Method = 'GET',
        [string]$Token,
        [string]$Basic,
        [string]$Form,
        [string]$Json,
        [string[]]$Headers = @()
    )
    if ($Url -notmatch '^https://localhost:(8080|8090|8443|9000|9001)/') { throw 'Expected a local HTTPS fixture URL.' }
    $config = @()
    if ($Token) { $config += 'header = "Authorization: Bearer ' + $Token + '"' }
    if ($Basic) { $config += 'user = "' + $Basic + '"' }
    if ($Form) { $config += 'data = "' + $Form + '"' }
    if ($Json) {
        $config += 'header = "Content-Type: application/json"'
        $config += 'data = "' + $Json.Replace('\','\\').Replace('"','\"') + '"'
    }
    foreach ($header in $Headers) { $config += 'header = "' + $header + '"' }
    if (-not $config) { $config = @('# no credentials') }
    $reply = @($config | & $Curl --config - --silent --max-time 20 --noproxy '*' --cacert "$Pki/ca.pem" `
        --request $Method --write-out '\nEAZYBANK_HTTP:%{http_code}\n%{header_json}' $Url)
    if ($LASTEXITCODE) { throw "Local HTTPS request failed (curl $LASTEXITCODE)." }
    $raw = $reply -join "`n"
    $framing = [regex]::Match($raw, '(?s)^(.*)\nEAZYBANK_HTTP:(\d{3})\n(.*)$')
    if (-not $framing.Success) { throw 'Missing HTTP status in curl response.' }
    [pscustomobject]@{
        Status = [int]$framing.Groups[2].Value
        Headers = $framing.Groups[3].Value | ConvertFrom-Json
        Body = $framing.Groups[1].Value
    }
}
function Assert-Status($Case, $Expected, $Response) {
    if ($Response.Status -ne $Expected) { throw "$Case expected HTTP $Expected, received $($Response.Status)." }
    Write-Host "$Case HTTP $Expected"
}
function Get-TestToken($Client, $Realm = 'eazybank') {
    $secrets = Get-Secrets
    $secret = if ($Client -eq 'local-admin') { $secrets.admin } else { $secrets.$Client }
    $response = Invoke-LocalRequest -Method POST -Url "https://localhost:8443/realms/$Realm/protocol/openid-connect/token" `
        -Basic ("${Client}:$secret") -Form 'grant_type=client_credentials'
    if ($response.Status -ne 200) { throw "Token issuance for $Client failed ($($response.Status))." }
    ($response.Body | ConvertFrom-Json).access_token
}
function Get-JwtClaims($Token) {
    $payload = $Token.Split('.')[1].Replace('-','+').Replace('_','/')
    $payload = $payload.PadRight([int]([Math]::Ceiling($payload.Length / 4) * 4), '=')
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
}
function Restart-Accounts {
    param([string]$LoansBaseUrl = 'https://localhost:8090', [switch]$InvalidLoansSecret)
    & "$PSScriptRoot/stop-local.ps1" accounts
    & "$PSScriptRoot/start-local.ps1" accounts -LoansBaseUrl $LoansBaseUrl -InvalidLoansSecret:$InvalidLoansSecret
}
