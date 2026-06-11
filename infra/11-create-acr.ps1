<#
.SYNOPSIS
  Create an Azure Container Registry to host the bring-your-own model artifact.

.DESCRIPTION
  Creates an ACR in the existing resource group. The registry stores the ONNX
  model packaged as an OCI artifact (pushed with ORAS) that Foundry Local on
  Azure Local pulls during BYO deployment.

.EXAMPLE
  ./11-create-acr.ps1
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = "$PSScriptRoot/../config/environment.json"
)

$ErrorActionPreference = "Stop"
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
az account set --subscription $cfg.azure.subscriptionId | Out-Null

Write-Host "==> Creating ACR '$($cfg.acr.name)'" -ForegroundColor Cyan
az acr create `
  --resource-group $cfg.azure.resourceGroup `
  --name $cfg.acr.name `
  --sku $cfg.acr.sku `
  --location $cfg.azure.location `
  --only-show-errors

Write-Host "==> ACR login server:" -ForegroundColor Cyan
az acr show --name $cfg.acr.name --query loginServer -o tsv

Write-Host "`nNote: For pull from the cluster, create a scoped token or use the" -ForegroundColor Yellow
Write-Host "Entra workload identity. See k8s/secrets/registry-credentials.example.yaml" -ForegroundColor Yellow
