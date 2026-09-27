# Known Deviations

Everything below is a place where the actual build differs from the
original architecture/plan, and why. Nothing here is hidden or silently
"fixed" in the docs — the goal is that anyone reading this repo can see
exactly what's real, what's approximated, and what's still open.

## Regions and infrastructure

- **Dataflow compute runs in `us-central1`, not `asia-south1`.** The primary
  region for everything else (BigQuery, Pub/Sub, Healthcare API, the main
  VPC subnet) is `asia-south1`. Dataflow hit
  `ZONE_RESOURCE_POOL_EXHAUSTED` across all three zones in that region, so
  Dataflow's compute (and its own VPC subnet, `10.20.0.0/24`) was moved to
  `us-central1` instead. Nothing else moved.
- **No default network, no external IPs, no auto-IAM-grants.** This
  project's org policy blocks all three, which shaped several other
  decisions below (Dataflow worker image, requirements installation,
  Partner API's public access).

## Data pipeline

- **DLP de-identification runs inline inside the Dataflow pipeline**, as a
  `DeidentifyEvent` DoFn right after parsing - not as a separate
  `dlp-deidentifier` component/service as originally planned. It calls
  Cloud DLP's `deidentify_content` API per event and fails safe (drops the
  text rather than risk writing raw text) if the call errors.
- **No separate `fhir-ingestion` component.** The single Dataflow pipeline
  (`pipeline/dataflow-beam/`) does both jobs: it writes Observation/
  DiagnosticReport rows directly to BigQuery *and* writes Patient/
  Observation/DiagnosticReport resources directly to the FHIR store via
  the Healthcare API REST API (`googleapiclient`), in the same job. The
  original diagram's "FHIR Store -> DLP -> BigQuery" (a single linear
  export path) doesn't reflect this - Dataflow writes to both destinations
  independently.
- **No Python Beam connector for FHIR I/O exists**, so the pipeline calls
  the Healthcare API's REST endpoints directly via `googleapiclient`
  rather than a `FhirIO` transform.
- **Worker images can't install packages at runtime.** Workers have no
  public internet (org policy), so `FLEX_TEMPLATE_PYTHON_REQUIREMENTS_FILE`
  was deliberately removed from the Dockerfile - all Python dependencies
  are baked into the container image at build time instead.
- **`patients` BigQuery table is empty (0 rows).** The pipeline only ever
  writes Patient resources to the FHIR store, never to this BigQuery
  table. The schema exists (with policy-tag-ready fields) but nothing
  populates it today.
- **Patient ID format changed mid-build**, from `PT-000X` to `UHID-000X`
  (matching real Indian hospital "Unique Health Identifier" terminology).
  This happened after some data already existed under the old format;
  BigQuery tables were truncated and regenerated to keep the dataset
  consistent, but the FHIR store still has a mix of both formats from
  before the cleanup.

## AI/ML

- **`gemini-2.0-flash-001` was retired June 1, 2026** (discovered mid-build,
  after the knowledge-cutoff date this was originally built against). The
  risk-insight-processor now uses `gemini-2.5-flash`, called through the
  current `google-genai` SDK rather than the older `vertexai.
  generative_models` module (also deprecated, removed June 24 2026).
- **The BigQuery ML risk label is rule-derived, not a real clinical
  outcome.** `high_risk_label` is a synthetic heuristic (elevated BP,
  heart rate, or low SpO2) used only so the demo has something structured
  to train a logistic regression against - documented in the SQL/schema
  comments. The resulting `ml_risk_score` is a demonstration output, not a
  validated clinical model.
- **`risk-insight-processor` runs manually today**, not on a schedule.
  Unlike the generator (which runs every 15 minutes via Cloud Scheduler),
  scoring + Gemini explanation generation is triggered by hand.

## Alerting

- **SMTP + Gmail App Password was the original plan; it doesn't work on
  this account.** Google's account-level "Compromised passwords found"
  security flag was actively auto-revoking every newly created app
  password within seconds, blocking SMTP auth entirely (unrelated to this
  project's code). The alerting service now uses the **Gmail API with
  OAuth** (a Desktop-app OAuth client, one-time browser consent, cached
  refresh token) instead of SMTP.
- **Alerting runs manually today**, same as risk-insight-processor - not
  yet on a schedule.

## Clinician Portal, domain, and networking

- **The custom domain's root DNS was broken for most of this build.**
  `dhg-caretrack.gcpcloudhub.in`'s parent domain, `gcpcloudhub.in`,
  returned `SERVFAIL` from every public resolver and its managed SSL
  certificate failed with `FAILED_CAA_CHECKING` - its nameservers pointed
  at a Cloud DNS zone that could not be located anywhere in the
  organization (despite the authenticated identity being the org owner).
  Fixed by reverting the domain's nameservers back to Hostinger (which
  still had the correct Google Workspace MX records saved, un-broken) and
  adding a plain **A record** for the `dhg-caretrack` subdomain pointing at
  the load balancer's static IP - not the NS-delegation-to-Cloud-DNS
  approach originally planned, since no working Cloud DNS zone for the
  parent domain could be found to delegate from.
- **Managed SSL certificate rotation needed a Terraform workaround.** GCP
  won't let you delete a certificate that's still attached to a target
  HTTPS proxy, so a straightforward `taint` + `apply` to force
  re-validation failed. Fixed with `create_before_destroy` plus a
  `random_id` suffix in the certificate's name (GCP also won't allow two
  certs with the same name to coexist, even momentarily).
- **The IAP service agent had to be explicitly created**
  (`google_project_service_identity`), not just assumed to exist once the
  IAP API was enabled - granting it `roles/run.invoker` failed with
  "service account does not exist" until this was added.
- **The IAP OAuth client was created manually via the console**, not
  through Terraform's `google_iap_brand`/`google_iap_client` resources.
  An OAuth consent screen ("brand") already existed for this project (from
  the Gmail alerting setup), and brand creation/management via Terraform
  is a fragile, largely one-time operation not worth re-attempting
  automatically once a brand exists.
- **The Clinician Portal was first built without real IAP**, using only
  Cloud Run's own IAM authentication (`gcloud run services proxy` for
  access), before the domain + Load Balancer + IAP + Cloud Armor stack was
  added. Both states are preserved in `terraform/modules/clinician-portal`
  via an `ingress` variable, so IAM-only access remains available as a
  fallback while `gcpcloudhub.in`'s domain health is verified over time.

## Partner-Clinic API

- **The API is IAM-restricted *and* API-key-authenticated, not API-key
  only.** This org's Domain Restricted Sharing policy blocks granting
  `roles/run.invoker` to `allUsers`, so the Cloud Run service itself
  cannot be made fully public the way a real anonymous external partner
  integration would need. The API-key check is fully implemented and
  enforced at the application layer exactly as designed (a request with a
  valid IAM-authenticated caller but no/wrong API key still gets a real
  401) - but a truly anonymous external caller with no Google identity at
  all cannot reach it today, unlike the original design.

## Security and governance

- **Dataplex column-level security is implemented via Data Catalog**
  (`google_data_catalog_taxonomy` + `google_data_catalog_policy_tag`),
  which is the actual underlying mechanism BigQuery column-level security
  uses - there's no separate "Dataplex" Terraform resource type for this.
  Two columns are tagged: `diagnostic_reports.report_text_redacted` and
  `risk_assessments.gemini_explanation`.
- **Cloud KMS (CMEK), VPC Service Controls, Cloud Monitoring dashboards/
  alert policies, Looker Studio, and cost/budget alerts** are all part of
  the original design and not yet built. BigQuery/Pub/Sub use
  Google-managed encryption; there's no custom monitoring beyond default
  Cloud Logging.

## Automation

- **No CI/CD.** Every deploy in this repo happened via a manual
  `terraform apply` or `gcloud builds submit` - there is no
  `.github/workflows/` pipeline yet.
- **Only the generator is scheduled.** The risk-insight-processor and
  alerting service both need to be run by hand; the diagram's implicit
  "always-on" pipeline is only true for data generation and the streaming
  Dataflow job itself.
