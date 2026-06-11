<#
.SYNOPSIS
  Inventory Azure Local custom locations and pick the best target for an AKS
  Arc cluster, based on available custom locations in the resource group.

.DESCRIPTION
  Read-only. Lists connected Kubernetes clusters, custom locations, and any
  existing provisioned cluster instances (AKS Arc) so you can choose where to
  deploy. Prints a ranked summary.

.EXAMPLE
  ./00-inventory.ps1 -ResourceGroup sovereign-ai-daz
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $ResourceGroup,
  [string] $SubscriptionId = "fbaf508b-cb61-4383-9cda-a42bfa0c7bc9"
)

$ErrorActionPreference = "Stop"
az account set --subscription $SubscriptionId | Out-Null

Write-Host "=== Custom Locations in $ResourceGroup ===" -ForegroundColor Cyan
az customlocation list -g $ResourceGroup `
  --query "[].{name:name, location:location, hostType:displayName}" -o table

Write-Host "`n=== Arc-connected Kubernetes clusters ===" -ForegroundColor Cyan
az connectedk8s list -g $ResourceGroup `
  --query "[].{name:name, location:location, version:agentVersion, status:connectivityStatus}" -o table

Write-Host "`n=== Existing AKS Arc (provisioned cluster instances) ===" -ForegroundColor Cyan
az aksarc list -g $ResourceGroup `
  --query "[].{name:name, location:location, state:provisioningState}" -o table 2>$null

Write-Host "`n=== Logical networks (for AKS Arc node networking) ===" -ForegroundColor Cyan
az stack-hci-vm network lnet list -g $ResourceGroup `
  --query "[].{name:name, location:location}" -o table 2>$null

Write-Host "`nTip: capture the custom location id and a logical network id into" -ForegroundColor Yellow
Write-Host "config/environment.json before running 01-create-aksarc.ps1." -ForegroundColor Yellow
