<#
.SYNOPSIS
  Install Foundry Local prerequisites on the AKS Arc cluster: cert-manager,
  trust-manager, and an NGINX ingress controller.

.DESCRIPTION
  Step 1 of the Foundry Local on Azure Local deployment. Installs the
  Microsoft.CertManagement extension (cert-manager + trust-manager) via Azure
  Arc, then deploys an NGINX ingress controller via Helm for external endpoint
  exposure.

.EXAMPLE
  ./02-install-foundry-prereqs.ps1
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

Write-Host "==> Installing cert-manager + trust-manager (Microsoft.CertManagement)" -ForegroundColor Cyan
az k8s-extension create `
  --cluster-name $cluster `
  --name "azure-cert-manager" `
  --resource-group $rg `
  --cluster-type connectedClusters `
  --extension-type Microsoft.CertManagement `
  --scope cluster `
  --release-train stable `
  --config config.enableGatewayAPI=true `
  --config cert-manager.crds.keep=true `
  --config trust-manager.defaultPackage.enabled=false `
  --config trust-manager.secretTargets.enabled=true `
  --config trust-manager.secretTargets.authorizedSecretsAll=true `
  --only-show-errors

Write-Host "==> Installing NGINX ingress controller via Helm" -ForegroundColor Cyan
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>$null | Out-Null
helm repo update | Out-Null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
  --namespace ingress-nginx --create-namespace `
  --set controller.service.type=LoadBalancer

Write-Host "==> Waiting for ingress controller to get an address..." -ForegroundColor Cyan
kubectl wait --namespace ingress-nginx `
  --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller `
  --timeout=300s

kubectl get svc -n ingress-nginx ingress-nginx-controller

Write-Host "`nNext: ./03-deploy-foundry-local.ps1 (requires preview access)" -ForegroundColor Green
