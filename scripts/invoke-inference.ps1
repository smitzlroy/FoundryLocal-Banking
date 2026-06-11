<#
.SYNOPSIS
  Retrieve a deployment's API key and send a test inference request.

.DESCRIPTION
  Convenience wrapper for the catalog/BYO smoke tests. Pulls the primary API
  key from the per-deployment Kubernetes Secret and POSTs to the
  OpenAI-compatible chat completions endpoint (generative) or the predict
  endpoint (predictive).

.EXAMPLE
  ./invoke-inference.ps1 -DeploymentName phi-4-cpu -ModelId "Phi-4-generic-cpu:1" -IngressHost 10.0.0.50
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $DeploymentName,
  [Parameter(Mandatory)] [string] $ModelId,
  [Parameter(Mandatory)] [string] $IngressHost,
  [string] $Namespace = "foundry-local-operator",
  [string] $Prompt = "Summarise today's rate outlook in one sentence."
)

$ErrorActionPreference = "Stop"

$keyB64 = kubectl get secret "$DeploymentName-api-keys" -n $Namespace `
  -o jsonpath='{.data.primary-key}'
$apiKey = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($keyB64))

$uri = "https://$IngressHost/$DeploymentName/v1/chat/completions"
$body = @{
  model    = $ModelId
  messages = @(
    @{ role = "system"; content = "You are a banking rate assistant." },
    @{ role = "user";   content = $Prompt }
  )
  max_tokens = 80
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Method Post -Uri $uri `
  -Headers @{ Authorization = "Bearer $apiKey"; "Content-Type" = "application/json" } `
  -Body $body -SkipCertificateCheck |
  ConvertTo-Json -Depth 8
