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
- **`risk-insight-processor` is now scheduled** (5, 20, 35, 50 minutes past
  each hour - 5 minutes after each generator run), as a Cloud Run Job via
  Cloud Scheduler, same pattern as the generator. It ran manually for most
  of this build before being automated - see the Automation section below.

## Alerting

- **SMTP + Gmail App Password was the original plan; it doesn't work on
  this account.** Google's account-level "Compromised passwords found"
  security flag was actively auto-revoking every newly created app
  password within seconds, blocking SMTP auth entirely (unrelated to this
  project's code). The alerting service now uses the **Gmail API with
  OAuth** (a Desktop-app OAuth client, one-time browser consent, cached
  refresh token) instead of SMTP.
- **Alerting is now scheduled** (10, 25, 40, 55 minutes past each hour - 5
  minutes after each risk-insight-processor run), same pattern as the
  generator and risk-insight-processor. Its cached OAuth token is fetched
  from Secret Manager at each run rather than relying on a local file,
  since Cloud Run Jobs have no persistent disk between executions - see
  the Automation section below for the token-expiry caveat this doesn't
  remove.

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
- **Cloud KMS (CMEK) is applied to the BigQuery dataset only, not
  Pub/Sub.** The dataset's default encryption config only affects tables
  created after it's set - the 4 existing, populated tables keep
  Google-managed encryption unless individually recreated (BigQuery
  doesn't retroactively re-encrypt). Pub/Sub CMEK was deliberately
  skipped: changing `kms_key_name` on an existing topic forces Terraform
  to destroy and recreate it, which would have disrupted the live,
  actively-publishing generator and its subscriptions for no real
  benefit this late in the build. The KMS key and the Pub/Sub service
  agent's grant on it both already exist and are ready for this, whenever
  a deliberate, carefully-timed topic recreation (or a fresh project) is
  worth doing.
- **VPC Service Controls was not attempted.** This is a fundamentally
  different class of change from everything else in this repo: an
  **org-level** singleton resource (one Access Context Manager policy per
  organization, not per project), where a misconfigured perimeter can
  instantly cut off access to BigQuery/Healthcare API/Cloud Build/GitHub
  Actions CI for every identity not explicitly allowed - all at once,
  across a project with several live, actively-used services. Given that,
  this was judged not worth attempting as a late addition to a working
  system. A real implementation would need: an Access Context Manager
  policy at the org level, a service perimeter around this project
  restricting `bigquery.googleapis.com`/`healthcare.googleapis.com`/
  `storage.googleapis.com`, and carefully scoped ingress/egress rules for
  Cloud Build and GitHub Actions' Workload Identity Federation calls
  specifically (both come from outside the perimeter and would otherwise
  be blocked along with everything else).
- **Cloud Monitoring is a log-based metric + threshold alert, not
  Dataflow-specific system metrics or uptime checks.** Scope: email the
  clinician if any of the 3 scheduled Cloud Run Jobs (generator,
  risk-processor, alerting) logs an ERROR or higher. Uptime checks were
  skipped for the portal/partner-api specifically because both are
  IAM-protected - a standard anonymous uptime check would always get
  `403` and constantly "fail," which isn't a real health signal, just
  noise.

## Automation

All three pipeline stages (generator, risk-insight-processor, alerting)
are now scheduled Cloud Run Jobs via Cloud Scheduler, cron-staggered 5
minutes apart so each stage has fresh upstream data. This is **not** true
event-driven chaining (e.g. Pub/Sub/Eventarc triggering the next stage the
moment the previous one finishes) - it's simpler cron staggering instead,
which means each stage waits out a fixed offset rather than reacting
immediately. A generator run that's unusually slow, or produces no new
high-risk patients, won't change when the next stage fires.

- **The Dataflow pipeline is deliberately excluded from CI/CD.**
  `.github/workflows/build-and-deploy.yml` rebuilds and redeploys the 5
  app containers (generator, portal, partner-api, risk-processor,
  alerting) automatically on push, but bumping the Dataflow job's version
  (v7 -> v8, etc.) to roll out a pipeline change is still a deliberate,
  manual Terraform edit - not something safe to trigger on every push to
  `pipeline/dataflow-beam/`.

### Setting up CI/CD: what actually went wrong, in order

Getting GitHub Actions to a genuinely clean, working `terraform apply`
took five real, separate failures - each one a legitimate gap, not a
typo. In the order they were hit:

1. **No shared state backend.** `main.tf`'s backend block was left
   commented out (local state only, gitignored, living solely on one
   machine). The first real CI run couldn't see any of the ~50 resources
   already deployed and tried to create all 87 of them from scratch,
   colliding with everything that already existed (`409 Already Exists`)
   and failing outright on the one thing that WAS genuinely new (a `403`
   on the Workload Identity Pool itself, since the CI identity's IAM
   grants hadn't propagated yet either). Fixed by creating a GCS bucket
   (`dhg-caretrack-tfstate`, versioned) and running
   `terraform init -migrate-state` locally to move the existing state
   there, so local and CI now read/write the same source of truth.
2. **`workflow_dispatch` didn't match either job condition.** The `plan`
   step only ran `if: github.event_name == 'pull_request'`; the `apply`
   step only ran `if: ... && github.event_name == 'push'`. A manual
   "Run workflow" click matched neither, so it "succeeded" in ~13 seconds
   having done nothing but `init`/`validate` - a false green, not a real
   test. Fixed by widening the apply condition to also accept
   `workflow_dispatch`.
3. **`terraform fmt -check` blocked on pure style, not substance.** A few
   files weren't in Terraform's canonical alignment (spacing edits made
   by hand, not run through `terraform fmt`), and `-check` fails the
   whole job on any mismatch. Rather than hand-compute exact column
   alignment across every file, the step was changed to
   `terraform fmt -recursive` (auto-fixes in the runner, never blocks) -
   a defensible tradeoff: don't gate real infrastructure changes on
   whitespace.
4. **`roles/editor` doesn't include Secret Manager payload access.** This
   is deliberate GCP design, not a bug: Editor grants managing Secret
   Manager *resources* but specifically excludes
   `secretmanager.versions.access` (reading a secret's actual value), so
   a broad Editor grant can't casually read every secret in a project.
   Since this repo's Terraform manages a live secret version (the
   partner API key), the CI deployer needed `roles/secretmanager.admin`
   explicitly - reading that secret's current value during a plan
   refresh failed with a `403` until this was added.
5. **The CI deployer's role list is broader than a real production setup
   should use for one identity** (`roles/editor` plus several
   IAM/security/secret-admin roles - see
   `terraform/modules/github-actions-wif/main.tf`). This was a deliberate
   choice for this demo, to avoid hand-curating a minimal permission set
   per resource type across ~15 Google APIs. A real production CI/CD
   identity should be scoped far more narrowly (e.g. per-service custom
   roles), and the Workload Identity Federation trust itself is
   correctly locked to this exact repo (`attribute_condition`) so at
   least the *identity* can't be impersonated from anywhere else.
