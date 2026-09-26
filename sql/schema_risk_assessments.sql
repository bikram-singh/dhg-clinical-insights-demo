-- Risk assessments table
-- ml_risk_score comes from BigQuery ML; gemini_explanation from Vertex AI Gemini
-- Both are demonstration outputs, not validated medical assessments

CREATE TABLE IF NOT EXISTS `${project_id}.${dataset_id}.risk_assessments` (
  assessment_id       STRING NOT NULL,
  patient_id          STRING NOT NULL,
  ml_risk_score       FLOAT64 OPTIONS(description="BigQuery ML model output, 0.0-1.0"),
  gemini_explanation  STRING OPTIONS(description="Gemini-generated plain-language explanation, NOT a medical diagnosis"),
  risk_level          STRING OPTIONS(description="low | medium | high, derived from ml_risk_score thresholds"),
  created_at          TIMESTAMP NOT NULL
)
OPTIONS(
  description="Synthetic risk assessment outputs (BigQuery ML + Gemini). Demonstration only, not a medical diagnosis."
);
