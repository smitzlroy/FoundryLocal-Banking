<#
.SYNOPSIS
  List models available in the synced Foundry Local catalog.

.EXAMPLE
  ./list-catalog.ps1
#>
[CmdletBinding()]
param(
  [string] $Namespace = "foundry-local-operator"
)

$ErrorActionPreference = "Stop"

$json = kubectl get configmap foundry-local-catalog -n $Namespace `
  -o jsonpath="{.data['catalog\.json']}"

if (-not $json) {
  throw "Catalog configmap not found. Is the inference operator installed and catalog synced?"
}

$json | ConvertFrom-Json |
  Select-Object -ExpandProperty models |
  Format-Table alias, displayName, task, framework -AutoSize
