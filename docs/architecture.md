# Architecture — DHG CareTrack

## Data flow (as actually built)

```
[Synthetic Data Generator]  Cloud Run Job, scheduled every 15 min
 (generator/)                 via Cloud Scheduler
          |
          v
      [Pub/Sub]  --topic: patient-telemetry-raw--  (+ dead-letter topic)
          |
          v
     [Dataflow]  (custom Apache Beam pipeline, streaming)
 (pipeline/dataflow-beam/)
   parse -> DE-IDENTIFY (Cloud DLP, inline DoFn) -> route
          |
          |-------------------------+-------------------------|
          v                                                   v
[Cloud Healthcare API]                                   [BigQuery]
 FHIR Store: Patient,                          observations, diagnostic_reports
 Observation, DiagnosticReport                  (written directly by Dataflow,
 resources                                       not via FHIR export)
                                                          |
                                    - Dataplex/Data Catalog column-level
                                      security tags on report_text_redacted
                                      and gemini_explanation
                                    - Cloud Audit Logs (Data Access) enabled
                                      for BigQuery, Healthcare API, DLP
                                          |
                                          v
                          [risk-insight-processor]  (run manually/on demand,
                          (pipeline/risk-insight-processor/)  not yet scheduled)
                             BigQuery ML  --> numeric ml_risk_score
                             Gemini (Vertex AI) --> plain-language explanation
                                          |
                                          v
                                 [risk_assessments table]
                                          |
                                          |---> [alerting/] run manually,
                                          |      emails clinician on high risk
                                          |      via Gmail API (OAuth), HTML,
                                          |      color-coded by risk level
                                          v
   +-------------------------+-------------------------+
   |                                                     |
[Clinician Portal]                              [Partner-Clinic API]
 (portal/backend/)                               (partner-api/backend/)
 Cloud Run, real IAP + external HTTPS             Cloud Run, API-key auth
 Load Balancer + Cloud Armor + managed             (Secret Manager) *and*
 SSL cert on dhg-caretrack.gcpcloudhub.in           IAM-restricted (see note)
 - patient list, vitals chart (Chart.js),         - GET /patients/{id}/telemetry
   Gemini risk insight                            - OpenAPI spec auto-published
                                                     at /docs, /openapi.json
```

**Note on Partner-Clinic API auth:** the architecture calls for API-key auth
only, matching a real external-partner integration with no Google identity.
This project's organization has a Domain Restricted Sharing policy that
blocks making the Cloud Run service itself fully public (`allUsers`
invoker), so today it needs *both* an IAM-authenticated caller *and* a valid
API key. The API-key check itself is fully implemented and enforced at the
application layer exactly as designed — see
[known-deviations.md](known-deviations.md).

## Supporting infrastructure (cross-cutting)

| Concern | Service | Status |
|---|---|---|
| Secrets (API keys, OAuth) | Secret Manager | ✅ built (partner API key) |
| Portal auth | Identity-Aware Proxy (IAP) | ✅ built, real domain + managed SSL cert |
| API/network protection | Cloud Armor (rate limiting) | ✅ built, on the portal's backend service |
| Networking | Custom VPC + subnets (asia-south1, us-central1) | ✅ built, used by Dataflow |
| Column-level security | Dataplex / Data Catalog policy tags | ✅ built, on 2 sensitive columns |
| Data Access audit logging | Cloud Audit Logs | ✅ built, BigQuery/Healthcare API/DLP |
| Cost tracking | Resource labels (`environment`, `managed_by`, `project`) | ✅ built |
| Encryption at rest | Cloud KMS (CMEK) | ⏳ not built - relies on Google-managed encryption |
| Data exfiltration boundary | VPC Service Controls | ⏳ not built |
| CI/CD | GitHub Actions | ⏳ not built - all deploys are manual `terraform apply` / `gcloud builds submit` |
| Observability | Cloud Monitoring dashboards + alert policies | ⏳ not built - default Cloud Logging only |
| Reporting | Looker Studio dashboard | ⏳ not built |
| Alerting schedule | Cloud Scheduler for alerting/risk-insight-processor | ⏳ not built - both run manually; only the generator is scheduled |

## Why FHIR instead of raw BigQuery ingestion

Real healthcare systems exchange data using the FHIR standard, not arbitrary
JSON/CSV schemas. Routing synthetic data through Cloud Healthcare API before
it lands in BigQuery demonstrates the actual interoperability pattern a real
hospital integration would use, rather than a generic data pipeline with a
healthcare label on it.

## Why DLP + Dataplex + Audit Logs

These three controls mirror what a real healthcare compliance review asks
for first:
- **DLP** — is sensitive text (names, identifiers, conditions) detected and
  redacted/tokenized before storage? (Runs inline in the Dataflow pipeline,
  not as a separate service — see known-deviations.md.)
- **Dataplex column tagging** — are sensitive columns access-restricted, not
  just relying on table-level permissions?
- **Audit Logs** — is there a record of who accessed which patient data, and
  when?

See [compliance-controls.md](compliance-controls.md) for details on each.

## Why BigQuery ML *and* Gemini

BigQuery ML produces a quantitative risk score (a trained model's numeric
output). Gemini produces a qualitative, human-readable explanation of that
score, grounded in the patient's actual readings and report text. Using both
demonstrates knowing when to reach for a trained ML model versus an LLM,
rather than using Gemini for everything.

## Repository layout (as actually built)

```
dhg-clinical-insights-demo/
├── README.md
├── docs/
│   ├── architecture.md         This file
│   ├── known-deviations.md     Where the build differs from the original
│   │                           plan, and why (TODO - not yet written)
│   ├── compliance-controls.md  DLP/Dataplex/Audit Logs breakdown
│   │                           (TODO - not yet written)
│   └── snapshots/              GCP Console screenshots proving each piece
│                                is real, organized by area
├── terraform/
│   ├── environments/prod/      main.tf, variables.tf, terraform.tfvars,
│   │                           secrets.auto.tfvars (gitignored)
│   └── modules/
│       ├── pubsub/
│       ├── networking/         VPC + 2 subnets (asia-south1, us-central1)
│       ├── healthcare-api/     FHIR dataset + store
│       ├── bigquery/           dataset + 4 tables (schemas as .json/.tpl)
│       ├── dataflow/           Flex Template job
│       ├── data-governance/    Data Catalog taxonomy + policy tag
│       │                       (this is where Dataplex tagging + BQML
│       │                       actually live - no separate bigquery-ml,
│       │                       dlp, or dataplex-tagging modules exist)
│       ├── audit-logging/      Data Access audit config, 3 services
│       ├── cloud-run-generator/  Cloud Run Job + Cloud Scheduler
│       ├── clinician-portal/   Cloud Run service (the portal itself)
│       ├── portal-edge/        DNS + Load Balancer + IAP + Cloud Armor +
│       │                       managed SSL cert in front of the portal
│       └── partner-api/        Cloud Run service + Secret Manager
│                               (no vertex-ai-gemini or alerting-email
│                               modules - Gemini and alerting are plain
│                               Python apps, not Terraform-managed infra;
│                               no iam-security module - IAM lives inline
│                               in each module that needs it; no
│                               monitoring, looker-studio, or cost-labels
│                               modules - not built yet)
├── generator/                  Synthetic patient generator + patient pool
│                               (patient_profiles.py)
├── pipeline/
│   ├── dataflow-beam/          The actual streaming pipeline: parse, DLP
│   │                           de-identify, write to FHIR store AND
│   │                           BigQuery directly (no separate
│   │                           fhir-ingestion or dlp-deidentifier
│   │                           components - this one pipeline does both)
│   └── risk-insight-processor/ BigQuery ML score + Gemini explanation,
│                               run manually today
├── alerting/                   Email alert on high-risk flag (Gmail API,
│                               OAuth, HTML/color-coded), run manually
├── portal/backend/             Clinician portal - FastAPI + Jinja2 +
│                               Chart.js, no separate frontend/ dir
├── partner-api/backend/        Partner-clinic API - FastAPI, API-key
│                               auth via Secret Manager
├── sql/
│   ├── schema_*.sql            Original table schema references
│   ├── bqml_model_risk_score.sql
│   └── views/                  observations_wide, observations_wide_labeled,
│                               latest_risk_scores, clinician_dashboard_view
└── .github/workflows/          ⏳ not built - no CI/CD yet, all deploys
                               are manual terraform apply / gcloud builds
```
