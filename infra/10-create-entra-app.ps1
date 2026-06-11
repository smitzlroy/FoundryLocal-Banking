<#
.SYNOPSIS
  Create the Microsoft Entra app registration used for Foundry Local inference
  authentication (Entra ID / JWT).

.DESCRIPTION
  Registers an application whose audience (api://<clientId>) is used when
  acquiring JWTs to call the inference endpoints. Writes the resulting clientId
  back into config/environment.json.

.EXAMPLE
  ./10-create-entra-app.ps1
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = "$PSScriptRoot/../config/environment.json"
)

$ErrorActionPreference = "Stop"
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
az account set --subscription $cfg.azure.subscriptionId | Out-Null

$appName = $cfg.entra.appRegistrationName
Write-Host "==> Creating Entra app registration '$appName'" -ForegroundColor Cyan

$existing = az ad app list --display-name $appName --query "[0].appId" -o tsv
if ($existing) {
  Write-Host "    App already exists: $existing" -ForegroundColor Yellow
  $appId = $existing
} else {
  $appId = az ad app create --display-name $appName --query appId -o tsv
  Write-Host "    Created appId: $appId" -ForegroundColor Green
}

# Set the Application ID URI so api://<appId> works as the token audience.
az ad app update --id $appId --identifier-uris "api://$appId" --only-show-errors

# Persist clientId back into config.
$cfg.entra.clientId = $appId
$cfg | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath
Write-Host "==> Wrote clientId to $ConfigPath" -ForegroundColor Green

Write-Host "`nAudience for inference JWTs: api://$appId" -ForegroundColor Cyan
