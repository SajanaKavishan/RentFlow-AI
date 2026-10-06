# RentFlow AI — Azure Deployment & CD Architecture Guide

This document defines the deployment architecture, networking model, CI/CD pipeline, and operational procedures for RentFlow AI on Microsoft Azure.

---

## 1. Target Architecture & Component Topology

```text
┌────────────────────────────────────────────────────────────────────────┐
│ PUBLIC INTERNET (Browsers & Mobile Clients)                           │
└───────────────┬───────────────────────────────────────┬────────────────┘
                │ HTTPS (Port 443)                      │ HTTPS (Port 443)
                ▼                                       ▼
┌───────────────────────────────┐       ┌────────────────────────────────┐
│ Azure Static Web Apps         │       │ Azure App Service (Linux)      │
│ (React SPA Client)            │       │ (ASP.NET Core 8 Web API)       │
│                               │       │                                │
│ staticwebapp.config.json      │       │ - Exposes REST endpoints       │
│ Deep-linking / SPA routing    │       │ - Health: /liveness, /readiness│
└───────────────┬───────────────┘       └───────┬──────────────┬─────────┘
                │ API Requests                  │              │
                └───────────────────────────────┘              │
                                                               │ Private VNet Integration
                                                               │ (Port 80/443 + X-RentFlow-Service-Key)
                                                               ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│ AZURE VIRTUAL NETWORK (VNet) - PRIVATE BOUNDARY                                │
│                                                                                │
│  ┌──────────────────────────────────────┐  ┌─────────────────────────────────┐ │
│  │ Azure Container Apps                 │  │ Azure Database for PostgreSQL   │ │
│  │ (FastAPI AI Agent)                   │  │ Flexible Server                 │ │
│  │                                      │  │                                 │ │
│  │ - Internal Ingress Only              │  │ - No public access / private    │ │
│  │ - Inaccessible to public internet    │  │   endpoint or firewall-locked   │ │
│  │ - Authenticated via Service Key      │  │ - Automated backups & PITR      │ │
│  │ - Health: /health                    │  │ - Controlled migrations only    │ │
│  └──────────────────────────────────────┘  └─────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼ (Direct S3-compatible API over HTTPS)
                  ┌────────────────────────────────┐
                  │ Cloudflare R2 Object Storage   │
                  │ (Document & Image Vault)       │
                  └────────────────────────────────┘
```

---

## 2. Network Boundaries & Zero-Trust Isolation

1. **Browser to Backend Only**:
   - The React frontend runs in the browser and connects **strictly** to the ASP.NET Core API at `https://<backend-app-service>.azurewebsites.net`.
   - The frontend never connects to or even knows the URL of the Python AI Agent.

2. **Python AI Agent Inaccessibility**:
   - The FastAPI agent is deployed on **Azure Container Apps** with **Internal Ingress** (`ingress.external: false`).
   - It only listens within the Azure Virtual Network (VNet). Public DNS and public IP addresses are **never** provisioned for the agent.
   - External browsers, crawlers, and scrapers cannot route to or reach the agent.

3. **Backend-to-Agent Service Authentication**:
   - The ASP.NET Core backend is linked to the VNet via **App Service Regional VNet Integration**.
   - Outbound traffic from App Service to the internal Container App FQDN routes over private VNet IPs.
   - Every request from the backend to the agent includes the HTTP header `X-RentFlow-Service-Key: <AGENT_SERVICE_API_KEY>`.
   - The agent's FastAPI middleware enforces this header using constant-time comparison (`hmac.compare_digest`). If missing or mismatched, it responds `401 Unauthorized`.

---

## 3. Database Migration & Backup Procedures

### A. Controlled Pre-Rollout Migration Policy
- **No auto-migration on instance startup**: App Service instances scale out dynamically. If every instance ran `Migrate()` at startup, database deadlocks and migration history table corruption would occur.
- **Dedicated CI/CD Migration Step**: Migrations run exactly **once** in the deployment pipeline, before the new backend code is deployed to App Service:
  ```bash
  dotnet RentFlow.Api.dll --migrate
  ```
- **Pipeline Gate**: If the migration step fails, the deployment pipeline immediately aborts. The App Service and Frontend remain untouched on the previous stable release.

### B. PostgreSQL Backup & Point-in-Time Restore (PITR)
1. **Automated Daily Backups**:
   - Azure Database for PostgreSQL Flexible Server takes automated snapshot backups daily and archive logs continuously.
   - Retention is set to 7 days for staging and 35 days for production.
2. **Pre-Deployment On-Demand Backup**:
   - Prior to executing schema migrations with data changes, create an immediate manual backup:
     ```bash
     az postgres flexible-server backup create \
       --resource-group rg-rentflow-production \
       --name psql-rentflow-prod \
       --backup-name "pre-deploy-$(date +%Y%m%d%H%M%S)"
     ```
3. **Point-In-Time Restore (PITR)**:
   - If a migration introduces a breaking schema bug or unintended data modification:
     ```bash
     az postgres flexible-server restore \
       --resource-group rg-rentflow-production \
       --name psql-rentflow-prod-restored \
       --source-server psql-rentflow-prod \
       --restore-time "2026-10-06T08:00:00Z"
     ```

---

## 4. Branch Flow & CD Promotion

```text
feature/* ──► Push / PR ──► CI Only (Tests + Linters + Builds)
                               │
                               ▼ Merge
dev ────────► Push ───────► CI Passes ──► Staging CD (Auto-Deploy)
                                              │
                                              ▼ Promote
main ───────► Push ───────► CI Passes ──► Production CD (Requires Manual Reviewer Approval)
```

1. **`feature/*` Branches**:
   - Runs `backend-ci.yml` (RentFlow CI): runs backend tests against PostgreSQL, React linter/tests/build, Python pytest, and Flutter analyze/tests.
   - No deployments are triggered.

2. **`dev` Branch (Staging)**:
   - Merging or pushing to `dev` runs RentFlow CI.
   - Upon successful completion, `.github/workflows/deploy-staging.yml` triggers automatically.
   - Targets the `staging` GitHub Environment.

3. **`main` Branch (Production)**:
   - Merging or pushing to `main` runs RentFlow CI.
   - Upon successful completion, `.github/workflows/deploy-production.yml` triggers.
   - Targets the `production` GitHub Environment, which requires manual approval from designated leads in GitHub Settings before any migration or deployment steps run.

4. **Flutter Mobile**:
   - Handled separately via `.github/workflows/release-flutter.yml`.
   - Triggered manually (`workflow_dispatch`) or on Git version tag (`v*.*.*`).
   - Builds release APK and Google Play App Bundle (AAB).

---

## 5. Deployment Step Order

Every staging and production deployment strictly executes the following sequence:

1. **Gate: CI Passed**:
   - Verified via `workflow_run` status (`conclusion == 'success'`).
2. **Database Migration**:
   - Publishes backend binaries: `dotnet publish backend/RentFlow.Api/RentFlow.Api.csproj -c Release -o ./publish-backend`
   - Executes: `dotnet ./publish-backend/RentFlow.Api.dll --migrate`
3. **Deploy & Verify FastAPI Agent**:
   - Builds container image and pushes to Azure Container Registry (ACR).
   - Deploys image to Azure Container Apps with production configuration.
   - Verifies agent `/health` endpoint responds HTTP 200 with `{"status":"healthy"}`.
4. **Deploy & Verify ASP.NET Core Backend**:
   - Applies environment settings to App Service.
   - Deploys backend package to Azure App Service.
   - Polls `/liveness` (returns `{"status":"ok"}`) and `/readiness` (returns `{"status":"ready"}`).
5. **Deploy React Frontend**:
   - Builds React app with `VITE_API_BASE_URL` pointing to backend HTTPS URL.
   - Deploys dist bundle to Azure Static Web Apps with `staticwebapp.config.json` routing.
6. **Execute Smoke Tests**:
   - Runs `node scripts/smoke-test.mjs` checking agent health, backend liveness, backend readiness, frontend loading, and auth login / protected API.

---

## 6. Required Azure Resources to Create

Run the following Azure CLI commands to provision the required resources:

```bash
# Set variables
RESOURCE_GROUP="rg-rentflow-staging"
LOCATION="eastus2"
ACR_NAME="crrentflowstaging"
VNET_NAME="vnet-rentflow-staging"
POSTGRES_SERVER="psql-rentflow-staging"
APP_SERVICE_PLAN="asp-rentflow-staging"
BACKEND_APP="app-rentflow-api-staging"
ACA_ENV="cae-rentflow-staging"
AGENT_APP="ca-rentflow-agent-staging"
SWA_NAME="swa-rentflow-web-staging"

# 1. Resource Group
az group create --name $RESOURCE_GROUP --location $LOCATION

# 2. Virtual Network & Subnets
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name $VNET_NAME \
  --address-prefixes 10.0.0.0/16 \
  --subnet-name snet-appservice \
  --subnet-prefixes 10.0.1.0/24

az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name snet-containerapps \
  --address-prefixes 10.0.2.0/23

# Delegate subnet to App Service
az network vnet subnet update \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name snet-appservice \
  --delegations Microsoft.Web/serverFarms

# 3. Azure Container Registry
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Standard \
  --admin-enabled true

# 4. Azure Database for PostgreSQL Flexible Server
az postgres flexible-server create \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER \
  --location $LOCATION \
  --admin-user rentflowadmin \
  --admin-password "<STRONG_PASSWORD>" \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --version 16 \
  --storage-size 32

az postgres flexible-server db create \
  --resource-group $RESOURCE_GROUP \
  --server-name $POSTGRES_SERVER \
  --database-name rentflow

# 5. Azure Container Apps Managed Environment & Internal Agent
az containerapp env create \
  --name $ACA_ENV \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --infrastructure-subnet-resource-id $(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VNET_NAME --name snet-containerapps --query id -o tsv) \
  --internal-only true

az containerapp create \
  --name $AGENT_APP \
  --resource-group $RESOURCE_GROUP \
  --environment $ACA_ENV \
  --image mcr.microsoft.com/azuredocs/aci-helloworld:latest \
  --target-port 8000 \
  --ingress internal \
  --min-replicas 1 \
  --max-replicas 3

# 6. Azure App Service Plan & Web App (Backend)
az appservice plan create \
  --name $APP_SERVICE_PLAN \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --is-linux \
  --sku B1

az webapp create \
  --name $BACKEND_APP \
  --resource-group $RESOURCE_GROUP \
  --plan $APP_SERVICE_PLAN \
  --runtime "DOTNETCORE:8.0"

# Connect App Service to VNet
az webapp vnet-integration add \
  --resource-group $RESOURCE_GROUP \
  --name $BACKEND_APP \
  --vnet $VNET_NAME \
  --subnet snet-appservice

# 7. Azure Static Web Apps (Frontend)
az staticwebapp create \
  --name $SWA_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

---

## 7. Required GitHub Secrets and Variables Inventory

Configure these in **GitHub Repository Settings** ➔ **Environments** (create `staging` and `production` environments):

### A. Environment Secrets

| Secret Name | Description / Example |
|---|---|
| `AZURE_CREDENTIALS` | Azure Service Principal JSON (`{ "clientId": "...", "clientSecret": "...", "subscriptionId": "...", "tenantId": "..." }`) |
| `AZURE_STATIC_WEB_APPS_API_TOKEN` | Deployment token from Azure Static Web App (`az staticwebapp secrets list`) |
| `POSTGRES_CONNECTION_STRING` | `Host=psql-rentflow-staging.postgres.database.azure.com;Port=5432;Database=rentflow;Username=rentflowadmin;Password=...;Ssl Mode=Require;Trust Server Certificate=true` |
| `AGENT_SERVICE_API_KEY` | 64+ char random secret key. Must match between backend & agent. |
| `JWT_SIGNING_KEY` | 32+ char cryptographic random signing key for HMAC SHA256. |
| `AI_API_KEY` | API key for Gemini / primary AI model provider. |
| `VISION_API_KEY` | API key for vision provider (or same as AI_API_KEY). |
| `CLOUDFLARE_R2_ACCOUNT_ID` | Cloudflare account identifier. |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | Cloudflare R2 API token access key. |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | Cloudflare R2 API token secret access key. |
| `STRIPE_SECRET_KEY` | `sk_test_...` (staging) or `sk_live_...` (production). |
| `STRIPE_PUBLISHABLE_KEY` | `pk_test_...` (staging) or `pk_live_...` (production). |
| `STRIPE_WEBHOOK_SECRET` | `whsec_...` from Stripe dashboard webhook endpoint. |
| `EMAIL_PASSWORD` | SMTP password / API token for transactional email provider. |
| `SMOKE_TEST_PASSWORD` | Password for automated smoke test synthetic user account. |

### B. Environment Variables

| Variable Name | Staging Example | Production Example |
|---|---|---|
| `AZURE_RESOURCE_GROUP` | `rg-rentflow-staging` | `rg-rentflow-production` |
| `AZURE_POSTGRES_SERVER_NAME` | `psql-rentflow-staging` | `psql-rentflow-prod` |
| `AZURE_CONTAINER_REGISTRY_NAME` | `crrentflowstaging` | `crrentflowprod` |
| `AZURE_CONTAINER_REGISTRY_LOGIN_SERVER` | `crrentflowstaging.azurecr.io` | `crrentflowprod.azurecr.io` |
| `AZURE_APP_SERVICE_NAME` | `app-rentflow-api-staging` | `app-rentflow-api-prod` |
| `AZURE_CONTAINER_APP_NAME` | `ca-rentflow-agent-staging` | `ca-rentflow-agent-prod` |
| `AZURE_STATIC_WEB_APP_NAME` | `swa-rentflow-web-staging` | `swa-rentflow-web-prod` |
| `BACKEND_BASE_URL` | `https://app-rentflow-api-staging.azurewebsites.net` | `https://api.rentflow.ai` |
| `FRONTEND_BASE_URL` | `https://swa-rentflow-web-staging.azurestaticapps.net` | `https://app.rentflow.ai` |
| `AGENT_SERVICE_BASE_URL` | `https://ca-rentflow-agent-staging.internal....azurecontainerapps.io` | `https://ca-rentflow-agent-prod.internal....azurecontainerapps.io` |
| `JWT_ISSUER` | `RentFlow.Api` | `RentFlow.Api` |
| `JWT_AUDIENCE` | `RentFlow.Clients` | `RentFlow.Clients` |
| `JWT_EXPIRY_MINUTES` | `30` | `30` |
| `CLOUDFLARE_R2_BUCKET_NAME` | `rentflow-staging-media` | `rentflow-production-media` |
| `EMAIL_SMTP_HOST` | `smtp.sendgrid.net` | `smtp.sendgrid.net` |
| `EMAIL_SMTP_PORT` | `587` | `587` |
| `EMAIL_USERNAME` | `apikey` | `apikey` |
| `EMAIL_FROM_ADDRESS` | `no-reply@staging.rentflow.ai` | `no-reply@rentflow.ai` |
| `EMAIL_FROM_NAME` | `RentFlow Staging` | `RentFlow AI` |
| `EMAIL_USE_SSL` | `true` | `true` |
| `AI_PROVIDER` | `gemini` | `gemini` |
| `AI_MODEL` | `gemini-1.5-flash` | `gemini-1.5-flash` |
| `VISION_PROVIDER` | `gemini` | `gemini` |
| `VISION_MODEL` | `gemini-1.5-flash` | `gemini-1.5-flash` |
| `SMOKE_TEST_EMAIL` | `smoke-test@rentflow.ai` | `smoke-test@rentflow.ai` |
| `VITE_GOOGLE_MAPS_MAP_ID` | `DEMO_MAP_ID` | `<PROD_MAP_ID>` |
