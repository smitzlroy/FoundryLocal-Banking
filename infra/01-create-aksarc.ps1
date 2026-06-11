<#
.SYNOPSIS
  Create a new AKS cluster enabled by Azure Arc on Azure Local.

.DESCRIPTION
  Provisions an AKS Arc cluster with a CPU node pool sized for the sovereign
  banking edge-inference demo. Reads parameters from config/environment.json.
  Kubernetes >= 1.29 is required by Foundry Local on Azure Local.

.NOTES
  Requires the connectedk8s, k8s-extension, customlocation and aksarc CLI
  extensions. The script installs them if missing.

.EXAMPLE
  ./01-create-aksarc.ps1
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = "$PSScriptRoot/../config/environment.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) {
  throw "Missing $ConfigPath. Copy config/environment.example.json and fill it in."
}
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

az account set --subscription $cfg.azure.subscriptionId | Out-Null

Write-Host "==> Ensuring required CLI extensions" -ForegroundColor Cyan
foreach ($ext in @("connectedk8s", "k8s-extension", "customlocation", "aksarc")) {
  az extension add --name $ext --upgrade --only-show-errors 2>$null | Out-Null
}

$cl = $cfg.azureLocal.customLocationId
if ([string]::IsNullOrWhiteSpace($cl)) {
  throw "azureLocal.customLocationId is empty. Run 00-inventory.ps1 and update config."
}

$cpVmSize = if ($cfg.aksArc.controlPlaneVmSize) { $cfg.aksArc.controlPlaneVmSize } else { "Standard_D4s_v3" }

# Build args dynamically. --kubernetes-version is intentionally OMITTED so the
# cluster defaults to the latest supported version: the aksarc extension has a
# validation bug that rejects explicit versions during create ("Supported
# values are '{}'"). Set aksArc.kubernetesVersion in config to force a version.
$createArgs = @(
  "--resource-group", $cfg.azure.resourceGroup
  "--name", $cfg.aksArc.clusterName
  "--location", $cfg.azure.location
  "--custom-location", $cl
  "--vnet-ids", $cfg.azureLocal.logicalNetworkId
  "--control-plane-count", $cfg.aksArc.controlPlaneCount
  "--control-plane-vm-size", $cpVmSize
  "--node-count", $cfg.aksArc.nodePool.count
  "--node-vm-size", $cfg.aksArc.nodePool.vmSize
  "--generate-ssh-keys"
)
if (-not [string]::IsNullOrWhiteSpace($cfg.aksArc.kubernetesVersion)) {
  $createArgs += @("--kubernetes-version", $cfg.aksArc.kubernetesVersion)
}
if (-not [string]::IsNullOrWhiteSpace($cfg.aksArc.controlPlaneIp)) {
  $createArgs += @("--control-plane-ip", $cfg.aksArc.controlPlaneIp)
}

Write-Host "==> Validating cluster input parameters" -ForegroundColor Cyan
az aksarc create @createArgs --validate
if ($LASTEXITCODE -ne 0) { throw "Validation failed. See errors above." }

Write-Host "==> Creating AKS Arc cluster '$($cfg.aksArc.clusterName)' (15-30 min)" -ForegroundColor Cyan
az aksarc create @createArgs --only-show-errors
if ($LASTEXITCODE -ne 0) { throw "Cluster creation failed. See errors above." }

Write-Host "==> Fetching admin kubeconfig" -ForegroundColor Cyan
az aksarc get-credentials `
  --resource-group $cfg.azure.resourceGroup `
  --name $cfg.aksArc.clusterName `
  --admin --overwrite-existing

Write-Host "==> Cluster nodes:" -ForegroundColor Cyan
kubectl get nodes -o wide

Write-Host "`nNext: ./02-install-foundry-prereqs.ps1" -ForegroundColor Green
