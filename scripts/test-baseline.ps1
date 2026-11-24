. "$PSScriptRoot/common.ps1"
$commit = 'd46a25ec486362562a3db2a4e7704a0639845f19'
$checkout = Join-Path $Runtime 'baseline-checkout'
$names = @('loans','cards','accounts')
$busy = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -in 8080,8090,9000
if ($busy) { throw 'Stop the local stack before running the baseline.' }
if (-not (Test-Path $checkout)) {
    Invoke-Native git @('-C',$Root,'worktree','add','--detach',$checkout,$commit)
}
$head = & git -C $checkout rev-parse HEAD
if ($LASTEXITCODE -or $head -ne $commit) { throw "Unexpected baseline checkout at $checkout." }
$env:JAVA_HOME = Get-JavaHome
Push-Location $checkout
try { Invoke-Native '.\mvnw.cmd' @('--batch-mode','clean','verify') } finally { Pop-Location }

$started = @()
try {
    foreach ($name in $names) {
        $jar = '"{0}/{1}/target/{1}-1.0.0.jar"' -f $checkout,$name
        Start-OwnedProcess "baseline-$name" "$env:JAVA_HOME/bin/java.exe" @('-jar',$jar) @{}
        $started += $name
    }
    foreach ($name in $names) {
        $deadline = [DateTime]::UtcNow.AddSeconds(60)
        do {
            if (-not (Get-OwnedProcess "baseline-$name")) { throw "Baseline $name exited." }
            & curl.exe --silent --fail --max-time 2 --noproxy '*' --output NUL "http://127.0.0.1:$($Ports[$name])/actuator/health"
            if (-not $LASTEXITCODE) { break }
            Start-Sleep -Seconds 1
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($LASTEXITCODE) { throw "Baseline $name did not become healthy." }
    }
    $summary = Invoke-Native curl.exe @('--silent','--fail','--noproxy','*',
        'http://127.0.0.1:8080/api/fetchCustomerDetails?mobileNumber=0600000001')
    $dto = $summary | ConvertFrom-Json
    if (-not ($dto.accountsDto -and $dto.loansDto -and $dto.cardsDto)) { throw 'B1 returned an incomplete dossier.' }
    Write-Host 'B1 HTTP 200 with account, loan and card'
    foreach ($name in 'loans','cards') {
        Invoke-Native curl.exe @('--silent','--fail','--noproxy','*','--output','NUL',
            "http://127.0.0.1:$($Ports[$name])/api/fetch?mobileNumber=0600000001")
        Write-Host "B2 $name HTTP 200"
    }
} finally {
    foreach ($name in $started) { Stop-OwnedProcess "baseline-$name" }
}
