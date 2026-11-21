param([ValidateSet('all','accounts','loans','cards','keycloak')][string]$Service = 'all')
. "$PSScriptRoot/common.ps1"
$names = if ($Service -eq 'all') { @('accounts','cards','loans','keycloak') } else { @($Service) }
foreach ($name in $names) { Stop-OwnedProcess $name }
