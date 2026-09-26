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
5. FHIR data is exported to **BigQuery** for analytics, with column-level
   security tags (**Dataplex**) on sensitive fields and **Cloud Audit Logs**
   enabled on all data access.
6. A **BigQuery ML** model produces a numeric risk score per patient; **Gemini**
   (via Vertex AI) produces a plain-language explanation of that risk.
7. High-risk flags trigger an **email alert** to the clinician.
8. A **Clinician Portal** (Cloud Run, behind IAP) shows each dummy patient's
   vitals history and risk insight.
9. A **Partner-Clinic API** (Cloud Run, API-key secured) exposes patient data
   to simulate an external clinic integration.
10. Everything is deployed via **Terraform** and **GitHub Actions**, monitored
    via **Cloud Monitoring**, and protected by **Cloud Armor**, **VPC Service
    Controls**, **Secret Manager**, and **Cloud KMS**.

## Architecture

See [docs/architecture.md](docs/architecture.md) for the full diagram and
component-by-component breakdown.

## Repository structure

See [docs/architecture.md](docs/architecture.md) for the annotated folder
layout.

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
