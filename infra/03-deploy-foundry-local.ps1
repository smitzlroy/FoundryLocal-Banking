<#
.SYNOPSIS
  Deploy the Foundry Local inference operator as an Azure Arc extension.

.DESCRIPTION
  Step 2 of the Foundry Local on Azure Local deployment. Installs the
  Microsoft.Foundry extension into the foundry-local-operator namespace with
  Entra ID authentication configured. Requires preview access granted via
  https://aka.ms/FoundryLocalAzure_PreviewRequest.

.EXAMPLE
  ./03-deploy-foundry-local.ps1
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = "$PSScriptRoot/../config/environment.json"
)

$ErrorActionPreference = "Stop"
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
az account set --subscription $cfg.azure.subscriptionId | Out-Null

$rg = $cfg.azure.resourceGroup
$cluster = $cfg.aksArc.clusterName
$ns = $cfg.foundryLocal.operatorNamespace

if ([string]::IsNullOrWhiteSpace($cfg.entra.clientId)) {
  throw "entra.clientId is empty. Run infra/10-create-entra-app.ps1 first."
}

Write-Host "==> Installing Foundry Local inference operator (Microsoft.Foundry)" -ForegroundColor Cyan
az k8s-extension create `
  --resource-group $rg `
  --cluster-name $cluster `
  --name "inference-operator" `
  --extension-type Microsoft.Foundry `
  --scope cluster `
  --release-namespace $ns `
  --cluster-type connectedClusters `
  --auto-upgrade-minor-version true `
  --release-train $cfg.foundryLocal.releaseTrain `
  --config entraAuth.tenantId="$($cfg.entra.tenantId)" `
  --config entraAuth.clientId="$($cfg.entra.clientId)" `
  --only-show-errors

Write-Host "==> Waiting for operator pods to be Running" -ForegroundColor Cyan
kubectl wait --namespace $ns --for=condition=ready pod --all --timeout=300s 2>$null

kubectl get pods -n $ns
Write-Host "`n==> Foundry CRDs:" -ForegroundColor Cyan
kubectl get crd | Select-String foundry

Write-Host "`nNext: scripts/list-catalog.ps1 then deploy k8s/modeldeployment-catalog-smoke.yaml" -ForegroundColor Green
