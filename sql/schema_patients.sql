-- Patients dimension table
-- Populated from Cloud Healthcare API FHIR export (Patient resources)
-- dummy_name_token is post-DLP tokenized, never a real identifier

CREATE TABLE IF NOT EXISTS `${project_id}.${dataset_id}.patients` (
  patient_id        STRING NOT NULL OPTIONS(description="Synthetic patient identifier, matches FHIR Patient.id"),
  dummy_name_token  STRING OPTIONS(description="DLP-tokenized dummy name, not a real identifier"),
  gender            STRING OPTIONS(description="Synthetic, for demo realism only"),
  age_band          STRING OPTIONS(description="Bucketed age range, e.g. 40-50 - never raw DOB"),
  region            STRING OPTIONS(description="Synthetic patient region/nationality, e.g. India, Global"),
  clinic_id         STRING OPTIONS(description="Dummy partner clinic identifier"),
  consent_flag      BOOL OPTIONS(description="Synthetic consent flag, always true in this demo"),
  created_at        TIMESTAMP NOT NULL
)
OPTIONS(
  description="Synthetic patient dimension table. All values are dummy data generated for demonstration purposes only."
);
