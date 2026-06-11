<#
.SYNOPSIS
  Act 2 — deploy the rate-forecast model AND dashboard to the AKS Arc edge.

.DESCRIPTION
  Sovereign "everything at the edge" deployment onto fl-banking-portland:
    1. Package the ONNX model + metadata and push to ACR (ORAS).
    2. Build the dashboard image in ACR.
    3. Create the registry pull secret in both namespaces.
    4. Apply the predictive ModelDeployment (Foundry Local pulls + serves it as
       an in-cluster ClusterIP service rate-forecast-byo-cpu:5000, TLS).
    5. Read the per-deployment API key and deploy the dashboard pointed at the
       in-cluster model endpoint (no traffic leaves the appliance).
    6. Port-forward the dashboard so it is reachable from the workstation.

  This cluster has NO external LoadBalancer (ingress IP stays <pending>), so the
  UI is exposed via `kubectl port-forward` over the Arc proxy.

  Requires an active `az connectedk8s proxy` session and $env:KUBECONFIG set to
  the proxy kubeconfig (see config note). Only touches fl-banking-* resources in
  resource group sovereign-ai-daz.

.EXAMPLE
  # In a dedicated terminal, keep this running:
  #   az connectedk8s proxy -g sovereign-ai-daz -n fl-banking-portland --file "$env:USERPROFILE\.kube\config-portland-proxy"
  $env:KUBECONFIG = "$env:USERPROFILE\.kube\config-portland-proxy"
  ./21-deploy-edge.ps1
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = "$PSScriptRoot/../config/environment.json",
  [switch] $SkipModelPush,
  [switch] $SkipImageBuild,
  [int]    $LocalPort = 8080
)

$ErrorActionPreference = "Stop"
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$rg          = $cfg.azure.resourceGroup
$acrName     = $cfg.acr.name
$registry    = "$acrName.azurecr.io"
$modelRepo   = $cfg.model.acrRepository
$modelTag    = $cfg.model.modelTag
$deployName  = $cfg.model.deploymentName            # rate-forecast-byo-cpu
$opNs        = $cfg.foundryLocal.operatorNamespace  # foundry-local-operator
$repoRoot    = Resolve-Path "$PSScriptRoot/.."
$dashImage   = "$($cfg.dashboard.imageRepository):$($cfg.dashboard.imageTag)"

az account set --subscription $cfg.azure.subscriptionId | Out-Null

function Require-Kubeconfig {
  if (-not $env:KUBECONFIG) {
    throw "KUBECONFIG not set. Start 'az connectedk8s proxy -g $rg -n $($cfg.aksArc.clusterName) --file <path>' and set `$env:KUBECONFIG to that file."
  }
  kubectl get nodes --request-timeout=10s | Out-Null
}

# --- 1. Package + push the ONNX model to ACR (ORAS) ---
if (-not $SkipModelPush) {
  Write-Host "==> Packaging + pushing model to $registry/$modelRepo:$modelTag" -ForegroundColor Cyan
  bash "$repoRoot/model/package_and_push.sh" "$repoRoot/model/artifacts" $acrName $modelRepo $modelTag
}

# --- 2. Build the dashboard image in ACR (server-side) ---
if (-not $SkipImageBuild) {
  Write-Host "==> Building dashboard image $registry/$dashImage" -ForegroundColor Cyan
  az acr build --registry $acrName --resource-group $rg --image $dashImage `
    --file "$repoRoot/app/Dockerfile" "$repoRoot/app" --only-show-errors
}

Require-Kubeconfig

# --- 3. Registry pull secret (model namespace + dashboard namespace) ---
Write-Host "==> Creating registry pull secret" -ForegroundColor Cyan
az acr update --name $acrName --resource-group $rg --admin-enabled true --only-show-errors | Out-Null
$acrUser = az acr credential show --name $acrName --resource-group $rg --query username -o tsv
$acrPass = az acr credential show --name $acrName --resource-group $rg --query "passwords[0].value" -o tsv

kubectl create namespace fl-banking --dry-run=client -o yaml | kubectl apply -f -
foreach ($ns in @($opNs, "fl-banking")) {
  # docker-registry secret for image pulls (dashboard).
  kubectl create secret docker-registry registry-credentials `
    -n $ns `
    --docker-server=$registry `
    --docker-username=$acrUser `
    --docker-password=$acrPass `
    --dry-run=client -o yaml | kubectl apply -f -
}
# generic username/password secret for the Foundry operator's model pull.
kubectl create secret generic registry-credentials `
  -n $opNs --from-literal=username=$acrUser --from-literal=password=$acrPass `
  --dry-run=client -o yaml | kubectl apply -f - 2>$null

# --- 4. Apply the predictive ModelDeployment (in-cluster only) ---
Write-Host "==> Applying ModelDeployment '$deployName'" -ForegroundColor Cyan
kubectl apply -f "$repoRoot/k8s/modeldeployment-rate-forecast.yaml"

Write-Host "==> Waiting for model to become ready (up to 10 min)" -ForegroundColor Cyan
kubectl wait --for=condition=Ready "modeldeployment/$deployName" -n $opNs --timeout=600s 2>$null
kubectl rollout status "deployment/$deployName" -n $opNs --timeout=300s 2>$null

# --- 5. Read the per-deployment API key ---
Write-Host "==> Reading API key from '$deployName-api-keys'" -ForegroundColor Cyan
$keyB64 = kubectl get secret "$deployName-api-keys" -n $opNs -o jsonpath='{.data.primary-key}' 2>$null
if (-not $keyB64) { throw "API key secret '$deployName-api-keys' not found; model may not be ready." }
$apiKey = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($keyB64))

# --- 6. Deploy the dashboard pointed at the in-cluster model endpoint ---
$foundryEndpoint = "https://$deployName.$opNs.svc.cluster.local:5000"
Write-Host "==> Deploying dashboard -> $foundryEndpoint" -ForegroundColor Cyan
(Get-Content "$repoRoot/k8s/dashboard.yaml" -Raw).
  Replace('__IMAGE__', "$registry/$dashImage").
  Replace('__FOUNDRY_ENDPOINT__', $foundryEndpoint).
  Replace('__FOUNDRY_API_KEY__', $apiKey) |
  kubectl apply -f -

kubectl rollout status deployment/rate-dashboard -n fl-banking --timeout=180s

# --- 7. Expose the UI to the workstation via port-forward ---
Write-Host "`n==> Act 2 deployed (everything at the edge)" -ForegroundColor Green
Write-Host "    Model (in-cluster) : $foundryEndpoint/v1/predict" -ForegroundColor Green
Write-Host "    Dashboard pod      : rate-dashboard (ns fl-banking)" -ForegroundColor Green
Write-Host "`n==> Port-forwarding dashboard to http://localhost:$LocalPort (Ctrl+C to stop)" -ForegroundColor Cyan
Write-Host "    Open: http://localhost:$LocalPort" -ForegroundColor Yellow
kubectl port-forward -n fl-banking svc/rate-dashboard "${LocalPort}:80"
