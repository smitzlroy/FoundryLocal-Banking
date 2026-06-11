<#
.SYNOPSIS
  Act 1 — deploy the rate-forecast model API AND dashboard UI to Azure (cloud).

.DESCRIPTION
  Runs the SAME model and the SAME UI as the Act 2 edge deployment, but in
  Azure Container Apps so the demo opens a real public *.azurecontainerapps.io
  URL with the badge "Running in Azure (Cloud)".

  Topology (all in resource group sovereign-ai-daz, only fl-banking-* resources):
    fl-banking-rate-api   (internal ingress, :8000)  -- the ONNX model service,
                          speaks the Foundry Local predictive contract.
    fl-banking-dashboard  (external ingress, :3000)  -- the Next.js UI, public,
                          DEPLOYMENT_TARGET=cloud, points at the internal API.

  Both images are built server-side in ACR (no local Docker). The dashboard
  image (shared/rate-dashboard) is the IDENTICAL artifact reused at the edge,
  so Act 1 and Act 2 differ only by URL + DEPLOYMENT_TARGET + FOUNDRY_ENDPOINT.

.EXAMPLE
  ./20-deploy-aca.ps1
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = "$PSScriptRoot/../config/environment.json"
)

$ErrorActionPreference = "Stop"
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$rg        = $cfg.azure.resourceGroup
$location  = $cfg.azure.location
$acrName   = $cfg.acr.name
$envName   = $cfg.act1.environmentName
$apiApp    = $cfg.act1.appName
$apiImage  = "$($cfg.act1.imageRepository):$($cfg.act1.imageTag)"
$apiPort   = $cfg.act1.targetPort
$dashApp   = $cfg.act1.dashboardAppName
$dashPort  = $cfg.act1.dashboardPort
$dashImage = "$($cfg.dashboard.imageRepository):$($cfg.dashboard.imageTag)"
$modelId   = "$($cfg.model.deploymentName):$($cfg.model.modelTag)"
$apiCtx    = Resolve-Path "$PSScriptRoot/../azure-api"
$appCtx    = Resolve-Path "$PSScriptRoot/../app"

az account set --subscription $cfg.azure.subscriptionId | Out-Null

# --- 1. Ensure the containerapp CLI extension + providers ---
Write-Host "==> Ensuring containerapp extension + providers" -ForegroundColor Cyan
az extension add --name containerapp --upgrade --only-show-errors 2>$null
az provider register --namespace Microsoft.App --wait | Out-Null
az provider register --namespace Microsoft.OperationalInsights --wait | Out-Null

# --- 2. Build both images in ACR (server-side) ---
Write-Host "==> Building API image '$apiImage' in ACR '$acrName'" -ForegroundColor Cyan
az acr build --registry $acrName --resource-group $rg --image $apiImage `
  --file "$apiCtx/Dockerfile" $apiCtx.Path --only-show-errors

Write-Host "==> Building dashboard image '$dashImage' in ACR '$acrName'" -ForegroundColor Cyan
az acr build --registry $acrName --resource-group $rg --image $dashImage `
  --file "$appCtx/Dockerfile" $appCtx.Path --only-show-errors

$loginServer  = az acr show --name $acrName --resource-group $rg --query loginServer -o tsv
$fullApiImage = "$loginServer/$apiImage"
$fullDashImg  = "$loginServer/$dashImage"

# --- 3. ACR pull credentials + shared inference API key ---
az acr update --name $acrName --resource-group $rg --admin-enabled true --only-show-errors | Out-Null
$acrUser = az acr credential show --name $acrName --resource-group $rg --query username -o tsv
$acrPass = az acr credential show --name $acrName --resource-group $rg --query "passwords[0].value" -o tsv
$apiKey  = [Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Maximum 256 }))

# --- 4. Ensure the managed environment exists ---
Write-Host "==> Ensuring Container Apps environment '$envName'" -ForegroundColor Cyan
$envExists = az containerapp env show --name $envName --resource-group $rg --query name -o tsv 2>$null
if (-not $envExists) {
  az containerapp env create --name $envName --resource-group $rg `
    --location $location --only-show-errors
}

# --- 5. Deploy the model API (INTERNAL ingress; only the dashboard calls it) ---
Write-Host "==> Deploying model API '$apiApp' (internal)" -ForegroundColor Cyan
az containerapp create `
  --name $apiApp `
  --resource-group $rg `
  --environment $envName `
  --image $fullApiImage `
  --registry-server $loginServer `
  --registry-username $acrUser `
  --registry-password $acrPass `
  --target-port $apiPort `
  --ingress internal `
  --min-replicas 1 `
  --max-replicas 2 `
  --cpu 1.0 `
  --memory 2.0Gi `
  --secrets "api-key=$apiKey" `
  --env-vars "MODEL_PATH=/models/rate_forecast.onnx" "META_PATH=/models/model_metadata.json" "MODEL_ID=$modelId" "API_KEY=secretref:api-key" `
  --only-show-errors

$apiFqdn = az containerapp show --name $apiApp --resource-group $rg --query "properties.configuration.ingress.fqdn" -o tsv
$apiEndpoint = "https://$apiFqdn"

# --- 6. Deploy the dashboard UI (EXTERNAL ingress; public demo URL) ---
Write-Host "==> Deploying dashboard '$dashApp' (public) -> $apiEndpoint" -ForegroundColor Cyan
az containerapp create `
  --name $dashApp `
  --resource-group $rg `
  --environment $envName `
  --image $fullDashImg `
  --registry-server $loginServer `
  --registry-username $acrUser `
  --registry-password $acrPass `
  --target-port $dashPort `
  --ingress external `
  --min-replicas 1 `
  --max-replicas 2 `
  --cpu 0.5 `
  --memory 1.0Gi `
  --secrets "api-key=$apiKey" `
  --env-vars "DEPLOYMENT_TARGET=cloud" "FOUNDRY_ENDPOINT=$apiEndpoint" "FOUNDRY_MODEL_ID=$modelId" "FOUNDRY_API_KEY=secretref:api-key" `
  --only-show-errors

$dashFqdn = az containerapp show --name $dashApp --resource-group $rg --query "properties.configuration.ingress.fqdn" -o tsv

Write-Host "`n==> Act 1 deployed to Azure (Cloud)" -ForegroundColor Green
Write-Host "    Dashboard (OPEN THIS) : https://$dashFqdn" -ForegroundColor Green
Write-Host "    Model API (internal)  : $apiEndpoint" -ForegroundColor Green
Write-Host "    Model ID              : $modelId" -ForegroundColor Green
Write-Host "    Inference API key     : $apiKey" -ForegroundColor Yellow
Write-Host "`nSmoke test (UI):" -ForegroundColor Cyan
Write-Host "    Open https://$dashFqdn  -> badge should read 'Running in Azure (Cloud)'"
