# Architecture — DHG CareTrack

## Data flow

```
[Synthetic Data Generator]  (Cloud Run job, scheduled)
          |
          v
      [Pub/Sub]  --topic: patient-telemetry-raw--
          |
          v
     [Dataflow]  (streaming job: parse, validate, route)
          |
          v
[Cloud Healthcare API — FHIR Store]
   Patient / Observation / DiagnosticReport resources
          |
          |---> [Cloud DLP]  (de-identifies DiagnosticReport free text)
          |
          v
[BigQuery]  (FHIR export: patients, observations, diagnostic_reports)
   - Dataplex column-level security tags on sensitive fields
   - Cloud Audit Logs (Data Access) enabled
          |
          |---> [BigQuery ML]  --> numeric risk_score
          |---> [Vertex AI / Gemini]  --> plain-language risk explanation
          |
          v
   [risk_assessments table]
          |
          |---> high risk? --> [Alerting service] --> email to clinician
          |
          v
   +-------------------------+-------------------------+
   |                                                     |
[Clinician Portal]                              [Partner-Clinic API]
 Cloud Run, behind IAP                            Cloud Run, API-key auth
 - patient list, vitals charts, risk insight       - GET patient telemetry
                                                    - OpenAPI spec published
```

## Supporting infrastructure (cross-cutting)

| Concern | Service |
|---|---|
| Secrets (API keys) | Secret Manager |
| Encryption at rest | Cloud KMS (CMEK on BigQuery, Pub/Sub) |
| Portal auth | Identity-Aware Proxy (IAP) |
| API/network protection | Cloud Armor (WAF, rate limiting) |
| Data exfiltration boundary | VPC Service Controls |
| Networking | Serverless VPC Connector |
| CI/CD | GitHub Actions |
| Observability | Cloud Monitoring dashboards + alert policies, Cloud Logging |
| Cost tracking | Resource labels + budget alert |
| Reporting | Looker Studio dashboard on BigQuery |

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
  redacted/tokenized before storage?
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

## Repository layout

```
dhg-clinical-insights-demo/
├── README.md
├── docs/                      Architecture, compliance, deviations
├── terraform/                 All infrastructure as code
│   ├── environments/prod/
│   └── modules/
│       ├── pubsub/
│       ├── dataflow/
│       ├── healthcare-api/
│       ├── bigquery/
│       ├── bigquery-ml/
│       ├── dlp/
│       ├── dataplex-tagging/
│       ├── audit-logging/
│       ├── cloud-run-portal/
│       ├── cloud-run-api/
│       ├── cloud-run-generator/
│       ├── vertex-ai-gemini/
│       ├── alerting-email/
│       ├── iam-security/
│       ├── networking/
│       ├── monitoring/
│       ├── looker-studio/
│       └── cost-labels/
├── generator/                 Synthetic patient data generator
├── pipeline/
│   ├── fhir-ingestion/         Writes Observations/Patients to Healthcare API
│   ├── dlp-deidentifier/       Runs DLP on report text before storage
│   └── risk-insight-processor/ BigQuery ML score + Gemini explanation
├── alerting/                   Email alert on high-risk flag
├── portal/                     Clinician portal (backend + frontend)
├── partner-api/                Partner-clinic API + OpenAPI spec
├── sql/                        Table schemas, BQML model, views
└── .github/workflows/          CI/CD pipelines
```
