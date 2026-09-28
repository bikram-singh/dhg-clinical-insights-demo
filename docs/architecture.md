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
                          [risk-insight-processor]  (Cloud Run Job, scheduled
                          (pipeline/risk-insight-processor/)  :05/:20/:35/:50)
                             BigQuery ML  --> numeric ml_risk_score
                             Gemini (Vertex AI) --> plain-language explanation
                                          |
                                          v
                                 [risk_assessments table]
                                          |
                                          |---> [alerting/] Cloud Run Job,
                                          |      scheduled :10/:25/:40/:55;
                                          |      emails clinician on high risk
                                          |      via Gmail API (OAuth), HTML,
                                          |      color-coded by risk level
                                          v
   +-------------------------+-------------------------+
   |                                                     |
[Clinician Portal]                              [Partner-Clinic API]
 (portal/backend/)                               (partner-api/backend/)
 Cloud Run, ingress locked to the load           Cloud Run, API-key auth
 balancer: real IAP + external HTTPS LB +          (Secret Manager) *and*
 Cloud Armor + managed SSL cert on                  IAM-restricted (see note)
 dhg-caretrack.gcpcloudhub.in
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
| Encryption at rest | Cloud KMS (CMEK) | ◑ partial - key + BigQuery dataset default only (new tables; the 4 existing tables and the Pub/Sub topics keep Google-managed encryption) |
| Data exfiltration boundary | VPC Service Controls | ⏳ not built - deliberately not attempted (org-level, can lock out live services) |
| CI/CD | GitHub Actions + Workload Identity Federation | ✅ built - plan on every push/PR, guarded manual apply, per-app image build/deploy (Dataflow excluded) |
| Observability | Cloud Monitoring alert policy (log-based) | ◑ partial - email on any scheduled-job error; no dashboards, no Dataflow-specific alerts |
| Reporting | Looker Studio dashboard | ⏳ not built |
| Pipeline scheduling | Cloud Scheduler | ✅ built - generator, risk-insight-processor and alerting all scheduled, cron-staggered 5 minutes apart |
| Terraform state | GCS backend (versioned bucket) | ✅ built - shared by local runs and CI |

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
│   │                           plan, why, and what went wrong along the way
│   ├── compliance-controls.md  DLP / Dataplex / Audit Logs breakdown
│   └── snapshots/              GCP Console screenshots proving each piece
│                               is real, organized by area
├── terraform/
│   ├── environments/prod/      main.tf, variables.tf, terraform.tfvars,
│   │                           secrets.auto.tfvars (gitignored); state
│   │                           lives in a versioned GCS bucket
│   └── modules/
│       ├── pubsub/
│       ├── networking/         VPC + 2 subnets (asia-south1, us-central1)
│       ├── healthcare-api/     FHIR dataset + store
│       ├── bigquery/           dataset + 4 tables (schemas as .json/.tpl);
│       │                       optional CMEK default key on the dataset
│       ├── dataflow/           Flex Template job
│       ├── data-governance/    Data Catalog taxonomy + policy tag
│       ├── audit-logging/      Data Access audit config, 3 services
│       ├── security-kms/       Key ring + key (90-day rotation), grants
│       │                       for BigQuery and Pub/Sub service agents
│       ├── monitoring/         Email channel, log-based error metric,
│       │                       alert policy for the scheduled jobs
│       ├── cloud-run-generator/  Generator Cloud Run Job + Scheduler
│       ├── pipeline-jobs/      risk-insight-processor + alerting Cloud
│       │                       Run Jobs + Schedulers + OAuth-token secret
│       ├── clinician-portal/   Cloud Run service (the portal itself)
│       ├── portal-edge/        DNS + Load Balancer + IAP + Cloud Armor +
│       │                       managed SSL cert in front of the portal
│       ├── partner-api/        Cloud Run service + Secret Manager
│       └── github-actions-wif/ Workload Identity Federation + the CI
│                               deployer service account
│                               (Not modules: Gemini and alerting are plain
│                               Python apps; IAM lives inline in each
│                               module; no bigquery-ml, dlp,
│                               dataplex-tagging, looker-studio or
│                               cost-labels modules exist.)
├── generator/                  Synthetic patient generator + patient pool
│                               (patient_profiles.py)
├── pipeline/
│   ├── dataflow-beam/          The actual streaming pipeline: parse, DLP
│   │                           de-identify, write to FHIR store AND
│   │                           BigQuery directly (no separate
│   │                           fhir-ingestion or dlp-deidentifier
│   │                           components - this one pipeline does both)
│   └── risk-insight-processor/ BigQuery ML score + Gemini explanation
│                               (containerized Cloud Run Job)
├── alerting/                   Email alert on high-risk flag (Gmail API,
│                               OAuth token from Secret Manager,
│                               containerized Cloud Run Job)
├── portal/backend/             Clinician portal - FastAPI + Jinja2 +
│                               Chart.js, no separate frontend/ dir
├── partner-api/backend/        Partner-clinic API - FastAPI, API-key
│                               auth via Secret Manager
├── sql/
│   ├── schema_*.sql            Original table schema references
│   ├── bqml_model_risk_score.sql
│   └── views/                  observations_wide, observations_wide_labeled,
│                               latest_risk_scores, clinician_dashboard_view
└── .github/workflows/
    ├── terraform.yml           plan on push/PR; manual, destroy-guarded apply
    └── build-and-deploy.yml    rebuilds + rolls out the 5 app images
                                (Dataflow deliberately excluded)
```
