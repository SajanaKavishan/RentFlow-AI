# RentFlow-AI 🏢⚡

[![CI Workflow](https://github.com/SajanaKavishan/RentFlow-AI/actions/workflows/ci.yml/badge.svg)](https://github.com/SajanaKavishan/RentFlow-AI/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![.NET](https://img.shields.io/badge/.NET-8.0-purple.svg)](https://dotnet.microsoft.com/)
[![React](https://img.shields.io/badge/React-19.2-61dafb.svg)](https://react.dev/)
[![Python](https://img.shields.io/badge/Python-3.11+-yellow.svg)](https://www.python.org/)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B.svg)](https://flutter.dev/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791.svg)](https://www.postgresql.org/)

An **Agentic AI-powered Property Rental and Lifecycle Management Platform** developed for the **SE3090 Software Engineering Project**. RentFlow-AI modernizes property discovery, viewing scheduling, tenant verification, digital lease signing, rent collection, and AI-automated maintenance coordination across Web and Mobile ecosystems.

---

## 📑 Table of Contents

- [System Architecture](#-system-architecture)
- [Key Features](#-key-features)
  - [🏢 Property Management & Discovery](#-property-management--discovery)
  - [📅 Viewing Scheduling & Reviews](#-viewing-scheduling--reviews)
  - [🤖 AI Application Validation Agent](#-ai-application-validation-agent)
  - [📄 Offers & Digital Lease Agreements](#-offers--digital-lease-agreements)
  - [💳 Rent Schedules & Stripe Payments](#-rent-schedules--stripe-payments)
  - [🔧 AI Maintenance Coordination](#-ai-maintenance-coordination)
  - [🛡️ Admin, Staff Provisioning & Support](#️-admin-staff-provisioning--support)
- [Tech Stack](#-tech-stack)
- [Repository Structure](#-repository-structure)
- [Getting Started](#-getting-started)
  - [Prerequisites](#prerequisites)
  - [1. Backend Setup (ASP.NET Core)](#1-backend-setup-aspnet-core)
  - [2. AI Agent Setup (Python FastAPI)](#2-ai-agent-setup-python-fastapi)
  - [3. Web Client Setup (React 19 + Vite)](#3-web-client-setup-react-19--vite)
  - [4. Mobile App Setup (Flutter)](#4-mobile-app-setup-flutter)
- [Running Tests & CI Validation](#-running-tests--ci-validation)
- [CI/CD & Deployment](#-cicd--deployment)
- [Security & Zero-Trust Model](#-security--zero-trust-model)
- [License](#-license)

---

## 🏛 System Architecture

RentFlow-AI operates under a **Zero-Trust Network Boundary**. Public web and mobile clients communicate exclusively with the ASP.NET Core API. The AI Agent and PostgreSQL Database reside entirely within an isolated private network, ensuring sensitive documents and tenant data are strictly shielded.

```text
┌────────────────────────────────────────────────────────────────────────┐
│ PUBLIC INTERNET (Web Browser / Flutter Mobile App)                     │
└───────────────┬───────────────────────────────────────┬────────────────┘
                │ HTTPS (Port 443)                      │ HTTPS (Port 443)
                ▼                                       ▼
┌───────────────────────────────┐       ┌────────────────────────────────┐
│ Azure Static Web Apps         │       │ Azure App Service (Linux)      │
│ (React 19 SPA Client)         │       │ (ASP.NET Core 8 Web API)       │
│                               │       │                                │
│ - Interactive Map & Portals   │       │ - Single Public Gateway        │
│ - Multi-role Web Dashboard    │       │ - Auth & RBAC (JWT)            │
└───────────────┬───────────────┘       │ - Business Rules & Workflows   │
                │ API Requests          └───────┬──────────────┬─────────┘
                └───────────────────────────────┘              │
                                                               │ Private VNet Integration
                                                               │ (X-RentFlow-Service-Key)
                                                               ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│ AZURE VIRTUAL NETWORK (VNet) — PRIVATE ISOLATION BOUNDARY                      │
│                                                                                │
│  ┌──────────────────────────────────────┐  ┌─────────────────────────────────┐ │
│  │ Azure Container Apps                 │  │ Azure Database for PostgreSQL   │ │
│  │ (FastAPI AI Agent — LangGraph)       │  │ Flexible Server                 │ │
│  │                                      │  │                                 │ │
│  │ - 7-Step Verification Workflow       │  │ - Multi-tenant Relational DB    │ │
│  │ - Bounded OCR & Vision Analysis      │  │ - Entity Framework Core 8       │ │
│  │ - Inaccessible to Public Internet    │  │ - Automated Backups & PITR      │ │
│  └──────────────────────────────────────┘  └─────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼ (Direct S3-Compatible API over HTTPS)
                  ┌────────────────────────────────┐
                  │ Cloudflare R2 Object Storage   │
                  │ (Document & Image Vault)       │
                  └────────────────────────────────┘
```

---

## ✨ Key Features

### 🏢 Property Management & Discovery
- **Rich Property Listings**: Detailed property attributes, dynamic pricing, amenity tags, and high-resolution photo galleries stored in Cloudflare R2.
- **Interactive Map Search**: Google Maps integration with custom Advanced Markers, geocoded locations, and distance filters.
- **Role-Based Portals**: Tailored views for Landlords, Tenants, Technicians, and System Administrators.

### 📅 Viewing Scheduling & Reviews
- **Availability Windows**: Landlords define recurring or ad-hoc viewing slots.
- **Seamless Booking**: Prospective tenants book viewings with instant confirmation.
- **Post-Viewing Feedback & Reviews**: Automated follow-ups allow tenants to rate properties and leave structured reviews.

### 🤖 AI Application Validation Agent
- **7-Stage LangGraph Pipeline**:
  1. `plan`: Schema and policy verification.
  2. `analyze_application_data`: Completeness and cross-attribute validation.
  3. `analyze_document_metadata`: Checks file types, metadata freshness, and duplicates.
  4. `verify_supporting_documents`: In-memory OCR (`pypdf`) and vision extraction (Google Gemini / Groq) for identity and paystubs.
  5. `analyze_cross_document_consistency`: Conservative consistency checks (name, declared income vs. paystub).
  6. `analyze_consistency`: Comparison between stated facts and authoritative findings.
  7. `summarize_findings`: Generates concise landlord review summaries.
- **Human-in-the-Loop Guarantee**: The AI agent **never** makes autonomous rental approval/rejection decisions (`requiresHumanApproval: true` enforced at all times).

### 📄 Offers & Digital Lease Agreements
- **Rental Offers**: Tenants submit offers; landlords accept, counter, or decline with real-time status transitions.
- **Digital Leases**: Dynamic generation of binding lease agreements with defined security deposits, terms, and digital sign-off tracking.

### 💳 Rent Schedules & Stripe Payments
- **Automated Rent Schedules**: Automatically creates monthly payment schedules upon lease activation.
- **Secure Stripe Integration**: Powered by `Stripe.net` and `flutter_stripe` for card transactions, recurring rent collections, and digital payment receipts.

### 🔧 AI Maintenance Coordination
- **Tenant Incident Reporting**: Upload fault descriptions and up to 5 photos.
- **AI Triage & Classification**: Multimodal analysis automatically assesses urgency, categorizes trade requirements (plumbing, electrical, HVAC), and estimates repair scope.
- **Technician Dispatch**: Recommends and assigns certified technicians, tracks repair progress, and handles technician activation/sign-off.

### 🛡️ Admin, Staff Provisioning & Support
- **Comprehensive Admin Dashboard**: Platform metrics, user audit logs, support ticket management, and staff account onboarding.
- **Transactional Communications**: In-app notifications and email dispatch via MailKit.

---

## 💻 Tech Stack

| Domain | Technology / Library | Purpose |
| :--- | :--- | :--- |
| **Backend API** | ASP.NET Core 8 Web API | Central business logic, REST API, Auth, and Orchestrator |
| **Database** | PostgreSQL 16 + EF Core 8 | Relational data persistence with strict schema migrations |
| **AI Agent** | Python 3.11+, FastAPI, LangGraph | Autonomous multi-step verification agent & maintenance triage |
| **LLMs & Vision** | Groq (Llama / OSS), Google Gemini Vision | Document OCR, structured extraction, and repair diagnostics |
| **Web Frontend** | React 19, Vite 8, React Router v7 | Responsive desktop & tablet web application |
| **Mobile App** | Flutter 3.x, Dart | Cross-platform mobile app (Android & iOS) |
| **Payments** | Stripe (`Stripe.net`, `flutter_stripe`) | Card processing and rent schedule reconciliation |
| **Object Storage**| Cloudflare R2 (AWS S3 SDK) | Encrypted storage for property photos and verification documents |
| **Email Service** | MailKit / MimeKit | Automated email alerts and onboarding invitations |
| **CI / CD** | GitHub Actions & Azure | Automated container builds, test suites, and deployments |

---

## 📁 Repository Structure

```text
RentFlow-AI/
├── .github/
│   └── workflows/              # GitHub Actions CI & Production CD pipelines
├── agent/                      # Private Python AI Agent (FastAPI + LangGraph)
│   ├── app/
│   │   ├── chains/             # LangGraph nodes & deterministic rules
│   │   ├── models/             # Strict Pydantic input/output schemas
│   │   └── services/           # Vision adapters (Groq / Gemini) & text extractors
│   ├── tests/                  # Pytest test suite
│   ├── Dockerfile              # Container image definition for Azure Container Apps
│   └── requirements.txt        # Python package dependencies
├── backend/                    # Core ASP.NET Core 8 Web API
│   ├── RentFlow.Api/
│   │   ├── Controllers/        # REST endpoints (Properties, Leases, Payments, etc.)
│   │   ├── Data/               # EF Core DbContext, PostgreSQL migrations & seed data
│   │   ├── DTOs/               # Data Transfer Objects
│   │   ├── Models/             # Entity models
│   │   └── Services/           # Stripe, Storage, Email, and Agent integration services
│   ├── RentFlow.Api.Tests/     # Unit and PostgreSQL integration tests
│   └── RentFlow.DevTools/      # Database seeding & administrative CLI tools
├── docs/                       # Architecture diagrams, reports, and deployment guides
├── mobile/
│   └── rentflow_mobile/        # Flutter Cross-Platform Mobile Client
│       ├── lib/                # Flutter screens, widgets, and state providers
│       ├── test/               # Flutter unit and widget tests
│       └── pubspec.yaml        # Flutter dependencies
├── scripts/                    # Deployment scripts & smoke test suites
└── web/
    └── rentflow-web/           # React 19 + Vite Web Application
        ├── src/                # Components, Pages, Contexts, Hooks, and CSS Design System
        ├── package.json        # Node.js dependencies
        └── vite.config.js      # Vite build configuration
```

---

## 🚀 Getting Started

### Prerequisites

Ensure you have the following installed locally:
- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Node.js 20+ & npm](https://nodejs.org/)
- [Python 3.11+](https://www.python.org/)
- [Flutter SDK (3.x)](https://docs.flutter.dev/get-started/install)
- [PostgreSQL 16](https://www.postgresql.org/download/)

---

### 1. Backend Setup (ASP.NET Core)

1. Navigate to the backend directory:
   ```bash
   cd backend/RentFlow.Api
   ```

2. Configure `appsettings.Development.json` or user-secrets with your local credentials:
   ```json
   {
     "ConnectionStrings": {
       "DefaultConnection": "Host=localhost;Port=5432;Database=rentflow;Username=postgres;Password=your_password"
     },
     "AgentService": {
       "ServiceApiKey": "your-agent-shared-key",
       "BaseUrl": "http://127.0.0.1:8001"
     },
     "Jwt": {
       "SigningKey": "your-at-least-32-character-secret-key-here"
     }
   }
   ```

3. Run migrations and launch the API:
   ```bash
   dotnet restore
   dotnet ef database update
   dotnet run
   ```
   *The backend will be accessible at `http://localhost:5277` (Swagger UI at `/swagger`).*

---

### 2. AI Agent Setup (Python FastAPI)

1. Navigate to the agent directory:
   ```bash
   cd agent
   ```

2. Create and activate a Python virtual environment:
   ```powershell
   # Windows PowerShell
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   ```
   ```bash
   # macOS / Linux
   python3 -m venv .venv
   source .venv/bin/activate
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

4. Configure your `.env` file (copy from `.env.example`):
   ```env
   AI_PROVIDER=groq
   GROQ_API_KEY=your_groq_api_key
   VISION_PROVIDER=gemini
   VISION_API_KEY=your_gemini_api_key
   AGENT_SERVICE_API_KEY=your-agent-shared-key
   ```

5. Run the FastAPI development server:
   ```bash
   python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8001
   ```
   *Health check endpoint:* `http://127.0.0.1:8001/health`

---

### 3. Web Client Setup (React 19 + Vite)

1. Navigate to the web project:
   ```bash
   cd web/rentflow-web
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Configure `.env`:
   ```env
   VITE_API_BASE_URL=http://localhost:5277
   VITE_GOOGLE_MAPS_API_KEY=your_optional_maps_key
   ```

4. Launch the development server:
   ```bash
   npm run dev
   ```
   *The web client will run at `http://localhost:5173`.*

---

### 4. Mobile App Setup (Flutter)

1. Navigate to the mobile project:
   ```bash
   cd mobile/rentflow_mobile
   ```

2. Fetch Flutter packages:
   ```bash
   flutter pub get
   ```

3. Run on your connected emulator or device:
   ```bash
   flutter run
   ```

---

## 🧪 Running Tests & CI Validation

Run all test suites locally to mirror the GitHub Actions CI pipeline:

```powershell
# 1. Backend Unit & Integration Tests
dotnet test backend/RentFlow.Api.Tests/RentFlow.Api.Tests.csproj --configuration Release

# 2. Web Lint, Tests & Production Build
Set-Location web/rentflow-web
npm run lint
npm run test
npm run build

# 3. AI Agent Pytest Suite
Set-Location ../../agent
python -m pytest

# 4. Flutter Static Analysis & Widget Tests
Set-Location ../mobile/rentflow_mobile
flutter analyze
flutter test
```

> **Note on PostgreSQL Integration Tests**: To execute backend database integration tests locally, set the environment variable `RENTFLOW_TEST_POSTGRES_CONNECTION_STRING` pointing to a disposable database named with the prefix `rentflow_component3_test`.

---

## 🌐 CI/CD & Deployment

- **Continuous Integration (`ci.yml`)**: On every push and PR to `main` and `dev`, builds and validates the ASP.NET Core backend against a live disposable PostgreSQL 16 container, runs React Vitest tests & production builds, executes Pytest for the AI Agent, and runs Flutter static analysis.
- **Production Pipeline (`deploy-production.yml`)**: Builds Docker containers for the backend and agent, deploys to **Azure App Service** and **Azure Container Apps** behind private VNets, and updates the **Azure Static Web App** for the frontend.
- **Mobile Release (`release-flutter.yml`)**: Compiles optimized APK and App Bundle artifacts for mobile releases.

For comprehensive cloud setup and environment variables, consult the [Azure Deployment Guide](docs/azure-deployment-guide.md).

---

## 🔒 Security & Zero-Trust Model

1. **Private AI Ingress**: The Python AI Agent has no public IP or public ingress. It can only be invoked by the ASP.NET Core backend inside the virtual network using shared service keys (`X-RentFlow-Service-Key`).
2. **Encrypted Storage**: Documents (passports, paystubs, utility bills) uploaded by tenants are encrypted and stored in Cloudflare R2 with expiring pre-signed URLs.
3. **Stateless Processing**: The AI agent decodes documents in-memory for OCR text extraction and never persists extracted tenant documents to disk.
4. **Role-Based Access Control**: Strict JWT authentication with role authorization (`Tenant`, `Landlord`, `Technician`, `Admin`).

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
