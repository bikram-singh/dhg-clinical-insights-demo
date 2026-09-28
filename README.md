# DHG CareTrack — Live GCP Demo

**Synthetic Patients, Real Pipeline: Building DHG CareTrack on GCP with FHIR, Gemini, and DLP**

## What this is

DHG CareTrack is a demonstration platform showing how a healthcare telemetry
and clinical-insights system can be built and run end-to-end on Google Cloud —
using **synthetic patient data**, but a **real, working pipeline**.

This repo is the companion build to the
[gcp-solutions-architecture-blueprint](https://github.com/bikram-singh/gcp-solutions-architecture-blueprint)
capstone project (MedSecure case study). That repo defines the architecture
on paper across 10 solution pillars. This repo proves a working slice of it
actually runs — real infrastructure, real data flow, real AI-generated
insights — against dummy patients instead of real ones.

## A note on honesty

Every infrastructure component in this repo is real, deployed, and tested.
**No real patient, wearable device, or hospital system is involved anywhere.**
All patient records, vitals, and test reports are synthetically generated.
Where the pipeline produces a "risk suggestion," that output is an AI-generated
suggestion for demonstration purposes only — **not a medical diagnosis**, and
not validated by any clinician.

## What it does

1. A generator creates synthetic daily patient readings (BMI, blood pressure,
   weight, height, heart rate, and free-text test report notes) for a pool of
   dummy patients.
2. Readings are published to **Pub/Sub** and processed by **Dataflow**.
3. Patient and observation data is written to **Cloud Healthcare API** as FHIR
   resources (Patient, Observation, DiagnosticReport).
4. Free-text report notes pass through **Cloud DLP** for de-identification
   before storage.
5. The same Dataflow job also writes the data to **BigQuery** for analytics,
   with column-level security tags (**Dataplex**) on sensitive fields and
   **Cloud Audit Logs** enabled on data access. The dataset's default
   encryption uses a customer-managed **Cloud KMS** key (new tables only —
   see [known-deviations.md](docs/known-deviations.md)).
6. A **BigQuery ML** model produces a numeric risk score per patient; **Gemini**
   (via Vertex AI) produces a plain-language explanation of that risk.
7. High-risk assessments trigger an **email alert** to the clinician. Scoring
   and alerting run as scheduled Cloud Run Jobs, staggered after each
   generator run.
8. A **Clinician Portal** (Cloud Run, behind IAP) shows each dummy patient's
   vitals history and risk insight.
9. A **Partner-Clinic API** (Cloud Run, API-key secured) exposes patient data
   to simulate an external clinic integration.
10. Deployed via **Terraform** with a shared GCS state backend. **GitHub
    Actions** authenticates through Workload Identity Federation (no stored
    keys): pushes run `terraform plan`, and applying is a deliberate manual
    run that refuses any plan containing deletes unless explicitly allowed.
    Protected by **Cloud Armor**, **IAP**, and **Secret Manager**; a
    **Cloud Monitoring** alert emails on scheduled-job errors. **VPC Service
    Controls** was deliberately not attempted, and the Dataflow pipeline is
    excluded from automated deploys — see
    [known-deviations.md](docs/known-deviations.md) for why.

## Architecture

See [docs/architecture.md](docs/architecture.md) for the full diagram and
component-by-component breakdown.

## Repository structure

See [docs/architecture.md](docs/architecture.md) for the annotated folder
layout.

## GCP Console verification (screenshots)

[`docs/snapshots/`](docs/snapshots/) holds console screenshots proving each
piece of the architecture above is real and deployed, organized by area:

- [`data-pipeline/`](docs/snapshots/data-pipeline/) — Dataflow job, Pub/Sub,
  BigQuery, Healthcare API/FHIR store
- [`ai-ml/`](docs/snapshots/ai-ml/) — BigQuery ML model training and
  scoring, Gemini-generated risk explanations
- [`alerting/`](docs/snapshots/alerting/) — a real high-risk alert email
  sent by the alerting service
- [`compute/`](docs/snapshots/compute/) — Cloud Run services/jobs, Cloud
  Scheduler, Artifact Registry
- [`networking/`](docs/snapshots/networking/) — VPC, Load Balancer, Cloud
  DNS, managed SSL certificate
- [`security-governance/`](docs/snapshots/security-governance/) — IAM,
  Dataplex/Data Catalog policy tags, Cloud Audit Logs, Cloud Armor, IAP,
  Secret Manager
- [`portal-access-demo/`](docs/snapshots/portal-access-demo/) — the
  Clinician Portal's patient list/detail pages and the real IAP sign-in flow
- [`oauth-setup/`](docs/snapshots/oauth-setup/) — the OAuth consent screen
  and client configuration steps needed for the alerting service and IAP
- [`billing-and-registry/`](docs/snapshots/billing-and-registry/) — billing
  account linkage and GCS bucket setup

Where the same resource was captured more than once across the build (e.g.
an earlier Dataflow job version, superseded once the pipeline was fixed and
redeployed), only the most current/complete screenshot is kept.

**A note on what's deliberately excluded:** a couple of screenshots from the
original build session showed live OAuth client secrets in plaintext (Google
only displays a client secret once, at creation) — these are excluded from
this folder and were never committed, since publishing a real credential in
a public repo would be a genuine security exposure regardless of the fact
that it's a demo project. If you're the one who ran this build, treat any
OAuth client secret that appeared on-screen during setup as compromised and
rotate it in the Google Cloud Console (APIs & Services → Credentials).

## Known deviations

See [docs/known-deviations.md](docs/known-deviations.md) for anything built
differently than originally planned, and why.

## Compliance controls

See [docs/compliance-controls.md](docs/compliance-controls.md) for a
breakdown of the DLP, audit logging, and column-level tagging controls and
what they demonstrate.

## Status

🚧 Under active development. See commit history and
[known-deviations.md](docs/known-deviations.md) for current build status.
