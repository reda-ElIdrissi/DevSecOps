. "$PSScriptRoot/common.ps1"
if (Test-Path "$Pki/password") { throw 'PKI already exists.' }
$javaHome = Get-JavaHome
New-Item -ItemType Directory -Force $Pki | Out-Null
$env:EAZYBANK_PKI_PASS = New-LocalSecret
Push-Location $Pki
try {
    Invoke-Native openssl @('req','-x509','-newkey','rsa:3072','-nodes','-sha256','-days','365',
        '-subj','/CN=EazyBank Local CA','-addext','basicConstraints=critical,CA:TRUE',
        '-addext','keyUsage=critical,keyCertSign,cRLSign','-out','ca.pem','-keyout','ca.key')
    @('basicConstraints=critical,CA:FALSE','keyUsage=critical,digitalSignature,keyEncipherment',
        'extendedKeyUsage=serverAuth','subjectAltName=DNS:localhost,IP:127.0.0.1') | Set-Content -Encoding ASCII server.ext
    foreach ($name in $Ports.Keys) {
        Invoke-Native openssl @('req','-newkey','rsa:2048','-nodes','-sha256','-subj','/CN=localhost',
            '-out',"$name.csr",'-keyout',"$name.key")
        Invoke-Native openssl @('x509','-req','-sha256','-days','90','-CA','ca.pem','-CAkey','ca.key',
            '-CAcreateserial','-extfile','server.ext','-in',"$name.csr",'-out',"$name.pem")
        Invoke-Native openssl @('verify','-CAfile','ca.pem','-verify_hostname','localhost',"$name.pem")
        if ($name -ne 'keycloak') {
            Invoke-Native openssl @('pkcs12','-export','-inkey',"$name.key",'-in',"$name.pem",'-certfile','ca.pem',
                '-name',$name,'-out',"$name.p12",'-passout','env:EAZYBANK_PKI_PASS')
            Remove-Item -LiteralPath "$name.key"
        }
        Remove-Item -LiteralPath "$name.csr"
    }
    Invoke-Native "$javaHome/bin/keytool.exe" @('-importcert','-noprompt','-alias','eazybank-local-ca',
        '-file','ca.pem','-keystore','truststore.p12','-storetype','PKCS12','-storepass:env','EAZYBANK_PKI_PASS')
    [IO.File]::WriteAllText((Join-Path $Pki 'password'), $env:EAZYBANK_PKI_PASS)
} finally {
    Pop-Location
    Remove-Item Env:EAZYBANK_PKI_PASS
}
