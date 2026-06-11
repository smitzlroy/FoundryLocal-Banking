# Project Plan & Progress Tracker

**Project:** Sovereign Banking Interest-Rate Forecasting on **Foundry Local on Azure Local**
**Repo:** `smitzlroy/FoundryLocal-Banking`
**Last updated:** 2026-06-09

---

## Legend
- ✅ **Done** — completed and verified
- 🟡 **In progress** — partially done / blocked
- ⬜ **Not started**
- 🔒 **Blocked** — waiting on an external dependency

---

## At-a-glance status

| Milestone | Status |
| --- | --- |
| M0 — Research & plan | ✅ Done |
| M1 — Repo scaffold & dev experience | ✅ Done |
| M2 — Model pipeline (data → ONNX) | ✅ Done & verified locally |
| M3 — Web app (edge dashboard) | ✅ Done & running locally |
| M4 — CI/CD pipelines | ✅ Authored (not yet run in GitHub) |
| M5 — Azure access & cluster inventory | ✅ Done (Arizona chosen) |
| M6 — Provision AKS Arc cluster | 🟡 Deploying |
| M7 — Deploy Foundry Local extension | 🔒 Blocked (preview access) |
| M8 — Deploy catalog model (smoke test) | ⬜ Not started |
| M9 — Deploy BYO banking model | ⬜ Not started |
| M10 — End-to-end demo & verification | ⬜ Not started |

---

## M0 — Research & plan ✅
- ✅ Researched Foundry Local vs **Foundry Local on Azure Local** (the Arc/K8s product — our target)
- ✅ Captured architecture: inference operator, `Model`/`ModelDeployment` CRDs, ONNX-GenAI/vLLM runtimes, auth, ingress
- ✅ Confirmed BYO flow: package ONNX → OCI artifact (ORAS) → ACR → pull into cluster
- ✅ Agreed decisions: predictive ONNX regression, HF+Olive path, Next.js UI, new AKS Arc cluster, GitHub-hosted runners + Arc proxy

## M1 — Repo scaffold & dev experience ✅
- ✅ `.gitignore`, `.env.example`, `config/environment.example.json`
- ✅ `.devcontainer/devcontainer.json` (Node 22, Python 3.11, az, kubectl, Copilot)
- ✅ `README.md` with Mermaid architecture diagram

## M2 — Model pipeline (data → ONNX) ✅ verified
- ✅ `model/generate_data.py` — synthetic rate curves — **ran OK** (1,200 rows)
- ✅ `model/train_export.py` — train + export ONNX — **ran OK** (MAE 9.62 bps, 1.4 MB ONNX)
- ✅ `model/validate_onnx.py` — ONNX Runtime validation — **ran OK** (Validation OK)
- ✅ `model/convert_hf_to_onnx.sh` — Hugging Face → Olive → ONNX (BYO alt path)
- ✅ `model/package_and_push.sh` — tar.gz + ORAS push to ACR
- ✅ `model/requirements.txt`

## M3 — Web app (edge dashboard) ✅ running
- ✅ Next.js 16 + React 19 + Recharts app under `app/`
- ✅ `api/forecast/route.ts` — calls edge endpoint, falls back to mock when offline
- ✅ Yield-curve chart, scenario sliders, edge/mock badge, latency + Δ table
- ✅ `Dockerfile` (standalone), patched Next.js security CVE
- ✅ **Builds clean** and **dev server runs** at http://localhost:3000

## M4 — CI/CD pipelines ✅ authored
- ✅ `.github/workflows/ci.yml` — PR gate (model smoke + app build, no Azure)
- ✅ `.github/workflows/model.yml` — train → ONNX → ORAS push to ACR
- ✅ `.github/workflows/app.yml` — `az acr build` dashboard image
- ✅ `.github/workflows/infra.yml` — cluster ops via Arc proxy
- ✅ `.github/actions/arc-proxy/action.yml` — composite action
- ⬜ Not yet pushed to GitHub / run (needs repo secrets + OIDC)

## M5 — Azure access & cluster inventory ✅
- ✅ Signed in (browser flow — device-code blocked by Conditional Access)
- ✅ Confirmed subscription `fbaf508b-...` (AdaptiveCloudLab), RG `sovereign-ai-daz`
- ✅ Inventoried 20 Azure Local clusters via Resource Graph
- ✅ **Chosen: Arizona** — 4 nodes / 80 cores / 1 TB RAM, lightly loaded, no existing AKS Arc
- ✅ Storage warning assessed as non-blocking (containers have 2.5–3.8 TB free each)
- ✅ Logical network: `az-lnet-vlan27` (231 free IPs, gw 172.25.119.1, DNS 10.254.0.196/.197)
- ✅ Custom location: `Arizona`

## M6 — Provision AKS Arc cluster 🟡
- ✅ Filled `config/environment.json` with real IDs
- ✅ K8s versions confirmed (1.31/1.32/1.33) → using **1.32**
- ✅ VM sizes confirmed (CPU + GPU available) → control plane `D4s_v3`, workers 2× `D8s_v3`
- 🟡 Running `infra/01-create-aksarc.ps1` (cluster `fl-banking-aks`, ~15–30 min)
- ⬜ `infra/02-install-foundry-prereqs.ps1` (cert-manager, NGINX ingress)

### Chosen configuration
| Setting | Value |
| --- | --- |
| Cluster name | `fl-banking-aks` |
| Resource group | `sovereign-ai-daz` |
| Region | `southcentralus` |
| Azure Local | Arizona |
| Custom location | Arizona |
| Logical network | `az-lnet-vlan27` |
| Kubernetes | 1.32 |
| Control plane | 1× Standard_D4s_v3 |
| Worker pool | 2× Standard_D8s_v3 |

## M7 — Deploy Foundry Local extension 🔒
- 🔒 **Preview access required:** https://aka.ms/FoundryLocalAzure_PreviewRequest
- ⬜ `infra/10-create-entra-app.ps1`, `infra/11-create-acr.ps1`
- ⬜ `infra/03-deploy-foundry-local.ps1` (`Microsoft.Foundry` extension)

## M8 — Deploy catalog model (smoke test) ⬜
- ⬜ `scripts/list-catalog.ps1`
- ⬜ `kubectl apply k8s/modeldeployment-catalog-smoke.yaml`
- ⬜ Inference test via `scripts/invoke-inference.ps1`

## M9 — Deploy BYO banking model ⬜
- ⬜ `infra/11` ACR + push model with `package_and_push.sh`
- ⬜ Registry secret + `kubectl apply k8s/modeldeployment-rate-forecast.yaml`
- ⬜ Verify predictive inference

## M10 — End-to-end demo & verification ⬜
- ⬜ Point app `FOUNDRY_ENDPOINT` at live cluster
- ⬜ Dashboard slider → live edge forecast
- ⬜ Prove no cloud inference egress (sovereignty)
- ⬜ Latency table + final walkthrough

---

## Current blockers
1. **Azure sign-in** — device-code blocked by Conditional Access; completing browser login now.
2. **Preview access** — `Microsoft.Foundry` extension (M7) gated on access request. Everything up to M6 can proceed without it.

## Next action
Complete browser sign-in → run `infra/00-inventory.ps1` to discover the Azure Local custom location and pick the target cluster.
