<div align="center">

# 🏥 DHG CareTrack — Clinical Insights on GCP

### Synthetic Patients · Real Pipeline · FHIR · Dataflow · BigQuery ML · Gemini 2.5 Flash

[![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)](https://python.org)
[![Dataflow](https://img.shields.io/badge/Dataflow-Apache_Beam-FF6F00?logo=apache&logoColor=white)](https://beam.apache.org)
[![Healthcare API](https://img.shields.io/badge/Cloud_Healthcare_API-FHIR_R4-34A853?logo=googlecloud&logoColor=white)](https://cloud.google.com/healthcare-api)
[![BigQuery](https://img.shields.io/badge/BigQuery-ML_%2B_Analytics-4285F4?logo=googlebigquery&logoColor=white)](https://cloud.google.com/bigquery)
[![Vertex AI](https://img.shields.io/badge/Vertex_AI-Gemini_2.5_Flash-8E44AD?logo=googlecloud&logoColor=white)](https://cloud.google.com/vertex-ai)
[![Terraform](https://img.shields.io/badge/Terraform-%E2%89%A51.5-844FBA?logo=terraform&logoColor=white)](https://www.terraform.io)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub_Actions_%2B_WIF-2088FF?logo=githubactions&logoColor=white)](.github/workflows/terraform.yml)
[![Security](https://img.shields.io/badge/Security-IAP_%7C_Cloud_Armor_%7C_DLP_%7C_Policy_Tags-1E8449)](#-security-and-governance)
[![Data](https://img.shields.io/badge/Data-100%25_Synthetic-C0392B)](#-overview)

---

*A working healthcare telemetry pipeline on Google Cloud, run end to end on
**synthetic patient data**. Wearable-style readings stream through Pub/Sub and
Dataflow, are de-identified with Cloud DLP, land in a FHIR store and BigQuery,
are risk-scored by BigQuery ML, explained in plain language by Gemini 2.5
Flash, and surfaced through an IAP-protected clinician portal, an analytics
dashboard, an API-key partner API, and email alerts. It is fully
Terraform-managed and delivered through GitHub Actions with keyless Workload
Identity Federation — real infrastructure, not a slide deck.*

</div>

---

## 🔗 Quick Links

- 🏛️ [Architecture](https://github.com/bikram-singh/dhg-clinical-insights-demo/blob/main/docs/architecture.md)
- 📈 [Dashboard](https://github.com/bikram-singh/dhg-clinical-insights-demo/blob/main/docs/dashboard.md)
- 🛡️ [Compliance controls](https://github.com/bikram-singh/dhg-clinical-insights-demo/blob/main/docs/compliance-controls.md)
- 🧾 [Known deviations](https://github.com/bikram-singh/dhg-clinical-insights-demo/blob/main/docs/known-deviations.md)
- 📸 [All snapshots](https://github.com/bikram-singh/dhg-clinical-insights-demo/tree/main/docs/snapshots)

---

## 📋 Table of Contents

- [Overview](#-overview)
- [The Problem, In Plain Terms](#-the-problem-in-plain-terms)
- [Architecture](#-architecture)
- [What It Does](#-what-it-does)
- [Repository Structure](#-repository-structure)
- [Prerequisites](#-prerequisites)
- [Setup](#-setup)
- [Testing and Verification](#-testing-and-verification)
- [Live Verification](#-live-verification)
- [Real Deployment Gotchas](#-real-deployment-gotchas)
- [Security and Governance](#-security-and-governance)
- [Analytics Dashboard](#-analytics-dashboard)
- [Snapshots](#-snapshots)
- [Known Limitations](#-known-limitations)
- [Documentation](#-documentation)
- [Repository](#-repository)

---

## 🌐 Overview

DHG CareTrack is a demonstration platform showing how a healthcare telemetry
and clinical-insights system can be built and run end to end on Google Cloud —
with **synthetic patient data**, but a **real, working pipeline**.

Everything here — the infrastructure, the data flow, and the AI-generated
insights — is real and running; only the patients are dummies.

> ⚠️ **A note on honesty.** No real patient, wearable device, or hospital
> system is involved anywhere. Every record, vital sign and report note is
> synthetically generated. The risk score and the Gemini explanation are
> demonstration outputs — **not a medical diagnosis**, and not validated by any
> clinician. Every infrastructure component is real, deployed, and verified
> against live GCP. This repo also records where the build falls short — see
> [Known Limitations](#-known-limitations) and
> [`docs/known-deviations.md`](docs/known-deviations.md).

### 🔑 Key Facts

| Property | Value |
|---|---|
| ☁️ **Cloud Platform** | Google Cloud Platform |
| 🌊 **Stream Processing** | Dataflow — Apache Beam, Flex Template, private workers |
| 🏥 **Clinical Data Store** | Cloud Healthcare API — FHIR R4 (`Patient`, `Observation`, `DiagnosticReport`) |
| 📊 **Analytics Store** | BigQuery — `observations`, `diagnostic_reports`, `risk_assessments`, `patients` |
| 🔒 **De-identification** | Cloud DLP, inline in the pipeline |
| 🧠 **AI** | BigQuery ML risk score + Gemini 2.5 Flash explanation via Vertex AI (`google-genai` SDK) |
| 📬 **Messaging** | Pub/Sub with a dead-letter topic |
| ⚙️ **Compute** | Cloud Run — portal, partner API, and three scheduled jobs (generator, risk scoring, alerting) |
| 🌐 **Edge** | HTTPS load balancer + Identity-Aware Proxy + Cloud Armor + managed SSL certificate |
| 🏗️ **IaC** | Terraform, 15 modules, GCS remote state |
| 🔁 **CI/CD** | GitHub Actions, Workload Identity Federation (keyless) |
| 🛡️ **Governance** | Data Catalog policy tags, Data Access audit logs, Secret Manager, Cloud KMS (CMEK on the BigQuery dataset) |
| 📈 **Dashboard** | The portal's `/analytics` page, defined in code |
| 🐍 **Language** | Python 3.12 |

---

## 🩺 The Problem, In Plain Terms

Wearables and home monitors produce a constant stream of vital signs. Two
problems follow:

- 👀 **Nobody can watch every reading.** A bare flag like "risk score 1.00"
  doesn't tell a clinician what to look at first. Pairing the score with a
  plain-language explanation — high blood pressure, low oxygen saturation,
  elevated heart rate — turns a number into a next step.
- 🔐 **Clinical data is sensitive.** Free-text notes can carry identifiers, and
  access has to be limited, logged, and encrypted, at column level, not just
  table level.

This project shows one way to do both on GCP: stream the data, de-identify it,
store it in a clinical standard (FHIR) *and* an analytics engine, score and
explain risk automatically, alert a clinician, and expose the results through
a portal and an API — with the controls that make it defensible built in from
the start.

---

## 🏛️ Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│ INGESTION                                                                                    │
├──────────────────────────────────────────────────────────────────────────────────────────────┤
│ Synthetic generator   Cloud Run Job, every 15 min via Cloud Scheduler                        │
│ Publishes patient readings (vitals + free-text report notes) to Pub/Sub                      │
│ Pub/Sub: patient-telemetry-raw   +   dead-letter topic (5 delivery attempts)                 │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
                                                │
                                                ▼
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│ STREAM PROCESSING   Dataflow Flex Template, Apache Beam, private workers                     │
├──────────────────────────────────────────────────────────────────────────────────────────────┤
│ parse / validate   ->   DE-IDENTIFY free text (Cloud DLP, inline)   ->   route               │
│ writes every event to BOTH stores below, independently (no export step)                      │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
                                                │
                       ┌────────────────────────┴───────────────────────┐
                       ▼                                                ▼
┌─────────────────────────────────────────────┐  ┌─────────────────────────────────────────────┐
│ CLINICAL STORE                              │  │ ANALYTICS STORE                             │
├─────────────────────────────────────────────┤  ├─────────────────────────────────────────────┤
│ Cloud Healthcare API - FHIR R4 store        │  │ BigQuery                                    │
│   Patient                                   │  │   observations, diagnostic_reports          │
│   Observation                               │  │   risk_assessments, patients                │
│   DiagnosticReport                          │  │   dashboard_* views (no tagged columns)     │
│                                             │  │ Policy tags | Audit Logs | CMEK default key │
└─────────────────────────────────────────────┘  └─────────────────────────────────────────────┘
                                                                        │
                                                                        ▼
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│ INTELLIGENCE   risk-insight-processor, Cloud Run Job, every 15 min                           │
├──────────────────────────────────────────────────────────────────────────────────────────────┤
│ BigQuery ML logistic regression   ->   ml_risk_score (0.0 - 1.0) per patient                 │
│ Gemini 2.5 Flash (Vertex AI, google-genai)   ->   plain-language explanation                 │
│ writes risk_assessments;  risk_level from the score:  high >= 0.7,  medium >= 0.4            │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
                                                 │
               ┌─────────────────────────────────┼────────────────────────────────┐
               ▼                                 ▼                                ▼
┌────────────────────────────┐  ┌────────────────────────────────┐  ┌──────────────────────────┐
│ ALERTING                   │  │ CLINICIAN PORTAL               │  │ PARTNER-CLINIC API       │
├────────────────────────────┤  ├────────────────────────────────┤  ├──────────────────────────┤
│ Cloud Run Job, 15 min      │  │ Cloud Run, ingress: LB only    │  │ Cloud Run                │
│ high-risk assessments      │  │ HTTPS LB + IAP + Cloud Armor   │  │ API key (Secret Manager) │
│ -> HTML email via          │  │ managed cert, custom domain    │  │ + IAM-restricted         │
│    Gmail API (OAuth)       │  │ /            patient list      │  │ GET /patients/{id}/      │
│    token: Secret Manager   │  │ /patient/{id}  vitals + AI     │  │     telemetry            │
│                            │  │ /analytics    dashboard        │  │ OpenAPI at /docs         │
└────────────────────────────┘  └────────────────────────────────┘  └──────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│ PLATFORM & DELIVERY   (spans everything above)                                               │
├──────────────────────────────────────────────────────────────────────────────────────────────┤
│ Terraform (15 modules, GCS state)  |  GitHub Actions + Workload Identity Fed. (keyless)      │
│ plan on push, guarded manual apply  |  Secret Manager  |  Cloud KMS  |  Cloud Monitoring     │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

The full annotated diagram and component-by-component breakdown live in
[`docs/architecture.md`](docs/architecture.md).

### 🔄 Layer Breakdown

| Layer | Components |
|---|---|
| 📥 **Ingestion** | Cloud Run Job generator (every 15 min) → Pub/Sub topic, with a dead-letter topic |
| 🌊 **Stream Processing** | Dataflow Flex Template (Apache Beam): parse → DLP de-identify → dual write |
| 🏥 **Clinical Store** | Cloud Healthcare API, FHIR R4 — written directly by Dataflow |
| 📊 **Analytics Store** | BigQuery — four tables plus three `dashboard_*` views; policy-tagged columns; audit logs |
| 🧠 **Intelligence** | BigQuery ML risk score + Gemini 2.5 Flash explanation, in a scheduled Cloud Run Job |
| 🚨 **Alerting** | Scheduled Cloud Run Job → HTML email through the Gmail API |
| 🖥️ **Serving** | Clinician Portal behind IAP (including `/analytics`); Partner-Clinic API behind an API key and IAM |
| 🔁 **Delivery** | Terraform + GitHub Actions + Workload Identity Federation |

The three scheduled jobs are staggered five minutes apart so each stage has
fresh upstream data: generator at `:00/:15/:30/:45`, risk scoring at
`:05/:20/:35/:50`, alerting at `:10/:25/:40/:55`.

---

## ✨ What It Does

| Capability | Description |
|---|---|
| 📡 **Continuous ingestion** | A scheduled generator publishes synthetic readings (BMI, blood pressure, weight, height, heart rate, SpO2, temperature, steps, battery, plus free-text report notes) for a pool of dummy patients |
| ☠️ **Bad-data isolation** | Messages that fail delivery repeatedly move to a dead-letter topic instead of blocking the pipeline |
| 🔒 **De-identification** | Free-text report notes pass through Cloud DLP before storage; if DLP fails, the text is replaced rather than stored raw |
| 🏥 **Dual write** | The same event lands in a FHIR R4 store and in BigQuery |
| 🧠 **Risk scoring** | A BigQuery ML logistic regression produces a 0–1 score per patient; scores map to `low` / `medium` / `high` |
| 💬 **Plain-language insight** | Gemini 2.5 Flash explains what drove each score in a sentence or two |
| 🚨 **Email alerts** | High-risk assessments trigger a colour-coded HTML email through the Gmail API |
| 🖥️ **Clinician portal** | Patient list, per-patient vitals chart, latest report note and risk insight — behind IAP |
| 📈 **Analytics dashboard** | Population-level KPIs, risk mix, vitals trends, ingestion cadence, and a patient table that highlights out-of-range values |
| 🔌 **Partner API** | `GET /patients/{id}/telemetry` behind an API key held in Secret Manager, with an auto-generated OpenAPI spec |
| 🛡️ **Column-level security** | Sensitive free-text columns carry a Data Catalog policy tag; only services that need them can read them |
| 🏗️ **Everything as code** | Networking, IAM, data, compute, edge and CI/CD are Terraform-managed; state is shared in a versioned GCS bucket |
| 🔐 **Keyless CI/CD** | GitHub Actions authenticates to GCP through Workload Identity Federation, locked to this repo — no stored keys |
| 🧯 **Safe by default** | Pushes only run `terraform plan`; applying is a manual step that refuses any plan containing deletes unless explicitly allowed |

---

## 📁 Repository Structure

```
dhg-clinical-insights-demo/
│
├── 📄 README.md
├── 📁 docs/
│   ├── 📄 architecture.md                  # data-flow diagram, service status table, repo layout
│   ├── 📄 known-deviations.md              # where the build differs from the plan, and the incidents behind it
│   ├── 📄 compliance-controls.md           # DLP, column-level security, audit logging
│   ├── 📄 dashboard.md                     # the /analytics dashboard, its views, colour rules
│   └── 📁 snapshots/                       # console evidence, organised by area
│
├── 📁 terraform/
│   ├── 📁 environments/prod/
│   │   ├── 📄 main.tf                      # module wiring + GCS remote state backend
│   │   ├── 📄 variables.tf, outputs.tf, terraform.tfvars
│   │   └── 📄 secrets.auto.tfvars.example  # IAP OAuth client (the real file is git-ignored)
│   └── 📁 modules/                         # 15 modules
│       ├── 📁 pubsub/                      # telemetry topic, dead-letter topic, subscriptions
│       ├── 📁 networking/                  # VPC + subnets (asia-south1, us-central1)
│       ├── 📁 healthcare-api/              # FHIR R4 dataset + store
│       ├── 📁 bigquery/                    # dataset, 4 tables, 3 dashboard_* views, optional CMEK default
│       ├── 📁 dataflow/                    # Flex Template streaming job
│       ├── 📁 data-governance/             # Data Catalog taxonomy + policy tag
│       ├── 📁 audit-logging/               # Data Access audit config (BigQuery, Healthcare API, DLP)
│       ├── 📁 security-kms/                # key ring + key, grants for BigQuery / Pub/Sub agents
│       ├── 📁 monitoring/                  # email channel, log-based error metric, alert policy
│       ├── 📁 cloud-run-generator/         # generator job + Cloud Scheduler + Artifact Registry
│       ├── 📁 pipeline-jobs/               # risk-scoring + alerting jobs, schedulers, token secret
│       ├── 📁 clinician-portal/            # portal Cloud Run service
│       ├── 📁 portal-edge/                 # DNS, HTTPS load balancer, IAP, Cloud Armor, managed cert
│       ├── 📁 partner-api/                 # partner API Cloud Run service + Secret Manager
│       └── 📁 github-actions-wif/          # Workload Identity Federation + CI deployer identity
│
├── 📁 generator/                           # synthetic patient generator (Cloud Run Job)
├── 📁 pipeline/
│   ├── 📁 dataflow-beam/                   # streaming pipeline: parse, DLP, FHIR + BigQuery writes
│   └── 📁 risk-insight-processor/          # BigQuery ML score + Gemini explanation (Cloud Run Job)
├── 📁 alerting/                            # Gmail API alert job (Cloud Run Job)
├── 📁 portal/backend/                      # clinician portal: FastAPI + Jinja2 + Chart.js
│   └── 📁 templates/                       # index, patient, analytics
├── 📁 partner-api/backend/                 # partner-clinic API: FastAPI, API key via Secret Manager
├── 📁 sql/                                 # table schemas, BQML model, base views (run by hand)
│   └── 📁 views/                           # observations_wide, latest_risk_scores, ...
│
└── 📁 .github/workflows/
    ├── 📄 terraform.yml                    # plan on push/PR; manual, destroy-guarded apply
    └── 📄 build-and-deploy.yml             # rebuilds and rolls out the five app images
```

Each app folder (`generator/`, `alerting/`, the two under `pipeline/`, `portal/backend/`
and `partner-api/backend/`) holds a `main.py` (or `pipeline.py`), a `Dockerfile` and a
`requirements.txt`.

---

## ✅ Prerequisites

| Requirement | Details |
|---|---|
| ☁️ **GCP project** | Billing enabled; you need permission to create IAM, networking, Cloud Run, Dataflow, Healthcare API and KMS resources |
| 🏗️ **Terraform** | 1.5 or newer, plus the `hashicorp/google`, `google-beta` and `random` providers |
| 🔐 **Credentials** | `gcloud auth login` and `gcloud auth application-default login` |
| 🌐 **A domain you control** | For the IAP-protected portal: the managed SSL certificate needs a real hostname whose DNS you can edit |
| 🔑 **OAuth clients** | A Web-application client for IAP (its ID and secret go in a git-ignored tfvars file) and, optionally, a Desktop client for Gmail alerts |
| 🐍 **Python** | 3.12 (matches the container images) |
| 🧠 **Vertex AI** | Gemini 2.5 Flash available in your region |

> The project was built inside an organisation with policies that block external
> IPs and restrict which identities can be granted access. It works within
> those constraints, and the [gotchas](#-real-deployment-gotchas) below record
> what that meant in practice.

---

## ⚙️ Setup

This is a reference build, not a one-click installer: it involves a domain, OAuth
clients and a few manual steps. The order below is the one that works.

**1. Create the shared Terraform state bucket** (once), then point the backend
block in `terraform/environments/prod/main.tf` at it:

```powershell
gcloud storage buckets create gs://<your-state-bucket> --project=<project> --location=<region> --uniform-bucket-level-access
gcloud storage buckets update gs://<your-state-bucket> --versioning
```

**2. Configure** — edit `terraform/environments/prod/terraform.tfvars` (project,
regions, image paths, emails, `github_repo`) and create the git-ignored secrets file:

```powershell
cd terraform\environments\prod
copy secrets.auto.tfvars.example secrets.auto.tfvars   # IAP OAuth client ID and secret
terraform init
```

**3. Create the container registry first**, so images have somewhere to go:

```powershell
terraform apply -target=module.cloud_run_generator.google_artifact_registry_repository.apps
```

**4. Build and push the five app images and the Dataflow template:**

```powershell
gcloud builds submit --tag <region>-docker.pkg.dev/<project>/apps/generator:latest        generator
gcloud builds submit --tag <region>-docker.pkg.dev/<project>/apps/portal:latest           portal/backend
gcloud builds submit --tag <region>-docker.pkg.dev/<project>/apps/partner-api:latest      partner-api/backend
gcloud builds submit --tag <region>-docker.pkg.dev/<project>/apps/risk-processor:latest   pipeline/risk-insight-processor
gcloud builds submit --tag <region>-docker.pkg.dev/<project>/apps/alerting:latest         alerting

# Dataflow: build the image, then register the Flex Template spec at template_gcs_path
gcloud dataflow flex-template build <template_gcs_path> --image <dataflow-image> --sdk-language PYTHON --metadata-file pipeline/dataflow-beam/metadata.json
```

**5. Review, then apply everything:**

```powershell
terraform plan -out=tfplan
terraform apply "tfplan"
```

**6. One-time manual steps after the first apply:**

| Step | What |
|---|---|
| 🧮 **Base views and model** | In BigQuery, run `sql/views/observations_wide.sql`, `observations_wide_labeled.sql`, `sql/bqml_model_risk_score.sql` and `sql/views/latest_risk_scores.sql` (replace `${project_id}` / `${dataset_id}`). Train the model once data has accumulated |
| 📧 **Alert token** | Run `alerting/main.py` locally once to complete the Gmail consent, then store the result: `gcloud secrets versions add alerting-oauth-token --data-file=alerting/token.json` |
| 🌐 **DNS** | Point an `A` record for your hostname at the load balancer's reserved IP and wait for the managed certificate to turn `ACTIVE` |
| 🔑 **IAP client** | Add the IAP redirect URI (`https://iap.googleapis.com/v1/oauth/clientIds/<client-id>:handleRedirect`) to the OAuth client |
| 🔁 **CI** | Add GitHub repo secrets `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT_EMAIL`, `TF_VAR_IAP_OAUTH_CLIENT_ID`, `TF_VAR_IAP_OAUTH_CLIENT_SECRET` |

> The Dataflow job's name carries a version (`...-v7`). Rolling out a pipeline
> change means bumping that version deliberately in Terraform, which is why
> Dataflow is excluded from the automated app-deploy workflow.

---

## 🧪 Testing and Verification

There is **no automated unit-test suite in this repo yet** (see
[Known Limitations](#-known-limitations)). Verification is done against live
GCP instead. These are the checks used throughout the build:

```powershell
# Infrastructure matches the code
cd terraform\environments\prod
terraform plan                                      # expect: No changes

# All three scheduled jobs are enabled and running
gcloud scheduler jobs list --location=us-central1 --format="table(name.basename(),schedule,state,lastAttemptTime)"
gcloud run jobs executions list --job=dhg-caretrack-risk-processor --region=us-central1 --limit=3

# The direct Cloud Run URL is locked out (expect 404; only the load balancer path works)
$t = gcloud auth print-identity-token
try { (Invoke-WebRequest -Uri "<portal-run-app-url>/healthz" -Headers @{Authorization="Bearer $t"} -UseBasicParsing).StatusCode } catch { $_.Exception.Response.StatusCode.value__ }
```

The analytics page's rendering logic was additionally exercised against faked
BigQuery data; that script is not part of the repo.

---

## 🔍 Live Verification

Every component below was checked against real GCP state, not just a green CI
run. Screenshots are in [Snapshots](#-snapshots).

| Component | Verified Via |
|---|---|
| 📬 Ingestion | Cloud Scheduler firing the generator every 15 minutes; Cloud Run Job executions succeeding |
| 🌊 Dataflow | Job `dhg-caretrack-telemetry-pipeline-v7` running in `us-central1` |
| 🏥 FHIR store | Healthcare API dataset and R4 store present, populated by the pipeline |
| 📊 BigQuery | Direct queries returning real readings, assessments and the three dashboard views |
| 🔒 DLP | Runs inline on every event; the synthetic report templates rarely contain anything to redact, so redacted output is uncommon |
| 🧠 Risk scoring | BigQuery ML model trained; scheduled scoring runs writing `risk_assessments` with Gemini explanations |
| 🛡️ Column-level security | Policy tag applied; enforcement observed — the scoring job received `403 ... fine-grained reader` until its service account was granted the tag |
| 🚨 Alerting | A real HTML alert email generated by the alerting job and delivered through the Gmail API |
| 🖥️ Portal | IAP sign-in on the custom domain; the direct Cloud Run URL returns 404 |
| 🔌 Partner API | `200` with a valid `X-API-Key`, `401` without one |
| 🔁 CI/CD | Both GitHub Actions workflows green; `terraform plan` reports "No changes" after each apply |
| 📈 Analytics | `/analytics` serving live data behind IAP |

**A real explanation generated during the build — not a curated example:**

> *"The elevated systolic and diastolic blood pressure, along with an increased
> heart rate, are notable. Additionally, the oxygen saturation is low and the
> BMI is in the overweight range, collectively contributing to the high risk
> assessment."*

---

## 🔧 Real Deployment Gotchas

Most write-ups skip this part. This project recorded it — the full story,
including how each was diagnosed, is in
[`docs/known-deviations.md`](docs/known-deviations.md).

| Gotcha | Symptom | Fix |
|---|---|---|
| 🗺️ Regional capacity | Dataflow fails with `ZONE_RESOURCE_POOL_EXHAUSTED` in `asia-south1` | Run Dataflow compute in `us-central1` on its own subnet; everything else stays in `asia-south1` |
| 🌐 Org policy blocks external IPs | Workers can't reach the internet; runtime `pip install` fails | Private workers; dependencies baked into the image at build time |
| 🐍 Beam serialization | `NameError` on a module-level dict inside a `DoFn` | Keep lookup tables as `DoFn` instance state |
| 🤖 Model retired | `gemini-2.0-flash-001` stopped working | `gemini-2.5-flash` through the current `google-genai` SDK |
| 📧 SMTP blocked | Gmail app passwords auto-revoked by an account security flag | Gmail API with OAuth; token cached in Secret Manager |
| 🌍 Broken domain DNS | `SERVFAIL`, certificate stuck at `FAILED_CAA_CHECKING` | Restored the registrar's own nameservers and pointed an `A` record at the load balancer |
| 🔒 Certificate replacement | GCP won't delete a certificate still attached to the HTTPS proxy | `create_before_destroy` plus a `random_id` suffix in the name |
| 🗄️ No shared Terraform state | The first CI run tried to create all 87 existing resources (`409`) | GCS backend and `terraform init -migrate-state` |
| 🔑 `roles/editor` isn't enough | `403` reading a secret's value; KMS and Monitoring admin also excluded | Grant `secretmanager.admin`, `cloudkms.admin`, `monitoring.admin`, `logging.admin` to the CI identity |
| 💥 Partial push | CI planned to delete live resources that were missing from the pushed code | Plan-only on push; manual apply that refuses any delete unless explicitly allowed |
| 🚫 Column security really blocks | The scoring job itself got `403` on a tagged column | Granted its service account the policy-tag reader role |
| 📭 Alerts to a non-mailbox | `550 5.1.1 NoSuchUser` bounce on the alert address | A dedicated `notification_email`, separate from IAM identities |
| 📊 Looker Studio can't be code | No Terraform resource; its Linking API only copies an existing report | `/analytics` page served from the portal, defined in code |

---

## 🛡️ Security and Governance

| Control | Implementation |
|---|---|
| 🔒 **Column-level security** | Data Catalog policy tag on `report_text_redacted` and `gemini_explanation`; the reader role is granted only to identities that need those columns |
| 🧼 **De-identification** | Cloud DLP inline in Dataflow (names, phones, emails, locations, dates of birth, ages); fails safe — text is replaced, never stored raw |
| 📜 **Audit trail** | Data Access logs (read and write) for BigQuery, the Healthcare API and DLP |
| 🌐 **Edge protection** | HTTPS load balancer, IAP, Cloud Armor rate limiting (100 requests/min/IP), and Cloud Run ingress locked to the load balancer |
| 🔐 **Keyless CI** | Workload Identity Federation limited to this repository — no downloaded service account keys anywhere |
| 🗝️ **Secrets** | Partner API key and the alert OAuth token live in Secret Manager |
| 🔏 **Encryption** | Customer-managed key (90-day rotation) as the BigQuery dataset's default; applies to new tables only |
| 🧯 **Change safety** | Plan on every push; apply is manual and refuses deletes unless `allow_destroy` is set |
| 📟 **Monitoring** | A log-based alert emails on any error from the scheduled jobs |

Details and honest limits are in
[`docs/compliance-controls.md`](docs/compliance-controls.md).

---

## 📈 Analytics Dashboard

The portal serves a population-level dashboard at `/analytics`, defined entirely
in code and deployed by the same pipeline as the rest of the portal.

![Analytics dashboard](docs/snapshots/analytics/analytics-dashboard.png)

- **KPI cards** — patients monitored, high risk now, high-risk assessments in 24 h, average heart rate and SpO2, and the age of the newest reading (which doubles as a pipeline health light)
- **Charts** — risk split, vitals by hour, assessments per hour by risk level, readings ingested per 15 minutes
- **Patient table** — highest risk first; values that cross the synthetic risk rule are marked in red, and a risk that predates a patient's newest reading is faded with an "updating" pill
- **Governance by construction** — it reads only three `dashboard_*` BigQuery views that never select the policy-tagged columns

It is private (behind IAP), so it has no public link. A Looker Studio report was
planned and dropped because it can't be defined in code — see
[`docs/dashboard.md`](docs/dashboard.md).

---

## 📸 Snapshots

Real console and browser captures from the actual build — nothing simulated.
The full set, organised by area, is in [`docs/snapshots/`](docs/snapshots/).

<details>
<summary><b>🗂️ Folder index — what each snapshot folder contains</b></summary>

- [`analytics/`](docs/snapshots/analytics/) — the `/analytics` dashboard and the patient detail page it links to
- [`data-pipeline/`](docs/snapshots/data-pipeline/) — Dataflow job, Pub/Sub, BigQuery, Healthcare API / FHIR store
- [`ai-ml/`](docs/snapshots/ai-ml/) — BigQuery ML model training and scoring, Gemini-generated risk explanations
- [`alerting/`](docs/snapshots/alerting/) — a real high-risk alert email sent by the alerting service
- [`compute/`](docs/snapshots/compute/) — Cloud Run services and jobs, Cloud Scheduler, Artifact Registry, and the portal's ingress locked to the load balancer
- [`networking/`](docs/snapshots/networking/) — VPC, load balancer, Cloud DNS, managed SSL certificate
- [`security-governance/`](docs/snapshots/security-governance/) — IAM, policy tags, audit logs, Cloud Armor, IAP, Secret Manager, the KMS key and its use as the BigQuery default, and the Monitoring alert
- [`cicd/`](docs/snapshots/cicd/) — Workload Identity Federation, GitHub Actions runs, and the versioned Terraform state bucket
- [`portal-access-demo/`](docs/snapshots/portal-access-demo/) — the portal's patient list, the IAP sign-in flow, and the DNS fix that unblocked the custom domain
- [`oauth-setup/`](docs/snapshots/oauth-setup/) — OAuth consent screen and client configuration for the alerting service and IAP
- [`billing-and-registry/`](docs/snapshots/billing-and-registry/) — billing account linkage and GCS bucket setup

Where the same resource was captured more than once, only the most current screenshot is kept.

</details>

### 🖥️ Portal and Analytics

![Patient detail with Gemini risk insight](docs/snapshots/analytics/patient-detail-uhid-0006.png)

### 🔁 CI/CD — GitHub Actions and Keyless Auth

![Terraform workflow runs](docs/snapshots/cicd/github-actions-terraform-runs.png)
![Build and deploy workflow](docs/snapshots/cicd/github-actions-build-and-deploy.png)

<details>
<summary><b>🔐 Workload Identity Federation and shared state</b></summary>

![Workload Identity pool](docs/snapshots/cicd/workload-identity-pool.png)
![Provider condition locked to this repo](docs/snapshots/cicd/workload-identity-provider-condition.png)
![Versioned Terraform state bucket](docs/snapshots/cicd/terraform-state-bucket.png)

</details>

<details>
<summary><b>🌊 Data pipeline</b></summary>

![Dataflow job](docs/snapshots/data-pipeline/dataflow-job-v7.png)
![Pub/Sub topics](docs/snapshots/data-pipeline/pubsub-topics.png)
![BigQuery schema](docs/snapshots/data-pipeline/bigquery-observations-wide-schema.png)
![FHIR store](docs/snapshots/data-pipeline/healthcare-fhir-store.png)

</details>

<details>
<summary><b>🧠 AI, scoring and alerting</b></summary>

![BigQuery ML model](docs/snapshots/ai-ml/bqml-model-schema-final.png)
![Gemini explanations in risk_assessments](docs/snapshots/ai-ml/gemini-risk-assessments-schema-final.png)
![High-risk alert email](docs/snapshots/alerting/high-risk-alert-email.png)

</details>

<details>
<summary><b>⚙️ Compute and scheduling</b></summary>

![Cloud Run services](docs/snapshots/compute/cloud-run-services-overview.png)
![Schedules, portal ingress and alerting runs](docs/snapshots/compute/scheduler-portal-ingress-alerting-runs.png)
![Artifact Registry](docs/snapshots/compute/artifact-registry-repos.png)

</details>

<details>
<summary><b>🌐 Networking and edge</b></summary>

![Load balancer backend](docs/snapshots/networking/load-balancer-backend-service.png)
![Managed SSL certificate active](docs/snapshots/networking/ssl-certificate-active.png)
![Cloud DNS zone](docs/snapshots/networking/cloud-dns-zone.png)
![VPC](docs/snapshots/networking/vpc-networks.png)

</details>

<details>
<summary><b>🛡️ Security and governance</b></summary>

![Data Catalog policy tag](docs/snapshots/security-governance/data-catalog-policy-tag.png)
![Audit logs configuration](docs/snapshots/security-governance/audit-logs-data-access-config.png)
![Cloud Armor policy](docs/snapshots/security-governance/cloud-armor-security-policy.png)
![Identity-Aware Proxy](docs/snapshots/security-governance/iap-identity-aware-proxy.png)
![IAM](docs/snapshots/security-governance/iam-permissions.png)
![Cloud KMS key](docs/snapshots/security-governance/kms-key-overview.png)
![Key permissions and the dataset's default key](docs/snapshots/security-governance/kms-key-permissions-and-dataset-cmek.png)
![Monitoring alert](docs/snapshots/security-governance/monitoring-channel-alert-policy-log-metric.png)
![Secret Manager](docs/snapshots/security-governance/secret-manager-partner-api-key.png)

</details>

---

## 🚧 Known Limitations

Recorded here so nobody has to discover them:

- **Risk scores are effectively binary.** The model is trained on a label derived from a simple rule over the same inputs, so scores come out as 0.00 or 1.00 and the `medium` band never appears. It is a demonstration, not a validated clinical model.
- **No automated unit-test suite** yet.
- **Not everything is in code.** The base BigQuery views and the BQML model are created by running SQL files by hand, and the Dataflow workers' IAM grants were applied with `gcloud` rather than Terraform — a fresh project needs those added.
- **Partial encryption and perimeter controls.** CMEK covers new BigQuery tables only (existing tables and Pub/Sub topics keep Google-managed encryption), and VPC Service Controls was deliberately not attempted.
- **Dataflow is excluded from CI/CD.** Rolling out a pipeline change is a deliberate, manual version bump.
- **The Partner API is IAM-restricted as well as key-protected**, because the organisation policy blocks public access; a truly anonymous external caller cannot reach it.
- **The analytics dashboard is private** and can only be shown through screenshots.
- **Alert volume isn't yet controlled** — a one-hour lookback every 15 minutes re-sends the same assessments.
- **The `patients` table is empty**; the pipeline writes patient records to the FHIR store only.

---

## 📚 Documentation

### 📖 Docs

| Document | Contents |
|---|---|
| 🏛️ [`docs/architecture.md`](docs/architecture.md) | The data-flow diagram; the built / partial / not-built status of every supporting service; the repository layout; and why FHIR, DLP with policy tags and audit logs, and BigQuery ML alongside Gemini |
| 🧾 [`docs/known-deviations.md`](docs/known-deviations.md) | Every place the build differs from the plan, and why: regions, the pipeline, AI/ML, alerting (including the mailbox bounce), the Looker Studio decision, domain and DNS, the Partner API, security and governance, and the CI/CD failures in the order they happened |
| 🛡️ [`docs/compliance-controls.md`](docs/compliance-controls.md) | DLP, column-level security and audit logging: what each does, where to see it, and its limits |
| 📈 [`docs/dashboard.md`](docs/dashboard.md) | The `/analytics` dashboard: what it shows, the three views behind it, governance decisions, colour rules, why not Looker Studio, and limitations |
| 📸 [`docs/snapshots/`](docs/snapshots/) | Console evidence, organised by area |

### 🧭 Where to Look in the Code

| Topic | Location |
|---|---|
| 🏗️ Infrastructure wiring | [`terraform/environments/prod/main.tf`](terraform/environments/prod/main.tf) |
| 📈 Dashboard views | [`terraform/modules/bigquery/views.tf`](terraform/modules/bigquery/views.tf) |
| 🔒 Column-level security | [`terraform/modules/data-governance/`](terraform/modules/data-governance/) and the schema templates in [`terraform/modules/bigquery/schemas/`](terraform/modules/bigquery/schemas/) |
| 🔁 CI/CD | [`.github/workflows/terraform.yml`](.github/workflows/terraform.yml), [`build-and-deploy.yml`](.github/workflows/build-and-deploy.yml), and [`terraform/modules/github-actions-wif/`](terraform/modules/github-actions-wif/) |
| 🌊 Streaming pipeline | [`pipeline/dataflow-beam/pipeline.py`](pipeline/dataflow-beam/pipeline.py) |
| 🧠 Risk scoring | [`pipeline/risk-insight-processor/main.py`](pipeline/risk-insight-processor/main.py) and [`sql/bqml_model_risk_score.sql`](sql/bqml_model_risk_score.sql) |
| 🖥️ Portal and analytics | [`portal/backend/main.py`](portal/backend/main.py) and [`portal/backend/templates/`](portal/backend/templates/) |
| 🔌 Partner API | [`partner-api/backend/main.py`](partner-api/backend/main.py) |

---

## 🔗 Repository

| Repository | Purpose |
|---|---|
| [`dhg-clinical-insights-demo`](https://github.com/bikram-singh/dhg-clinical-insights-demo) | A working healthcare telemetry pipeline on GCP, run end to end on synthetic data |

---

<div align="center">

**Maintained by Bikram Singh**

*Built with Dataflow · Cloud Healthcare API · BigQuery ML · Vertex AI · Terraform · GitHub Actions*

</div>
