-- Convenience view for the clinician portal and Looker Studio dashboard.
-- Joins each patient to their latest observations and latest risk assessment.

CREATE OR REPLACE VIEW `${project_id}.${dataset_id}.clinician_dashboard_view` AS
WITH latest_obs AS (
  SELECT
    patient_id,
    observation_type,
    value,
    event_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY patient_id, observation_type
      ORDER BY event_timestamp DESC
    ) AS rn
  FROM `${project_id}.${dataset_id}.observations`
),
latest_risk AS (
  SELECT
    patient_id,
    ml_risk_score,
    gemini_explanation,
    risk_level,
    created_at,
    ROW_NUMBER() OVER (
      PARTITION BY patient_id
      ORDER BY created_at DESC
    ) AS rn
  FROM `${project_id}.${dataset_id}.risk_assessments`
)
SELECT
  p.patient_id,
  p.dummy_name_token,
  p.region,
  p.age_band,
  MAX(IF(o.observation_type = 'bp_systolic', o.value, NULL))  AS bp_systolic,
  MAX(IF(o.observation_type = 'bp_diastolic', o.value, NULL)) AS bp_diastolic,
  MAX(IF(o.observation_type = 'bmi', o.value, NULL))          AS bmi,
  MAX(IF(o.observation_type = 'heart_rate', o.value, NULL))   AS heart_rate,
  MAX(IF(o.observation_type = 'spo2', o.value, NULL))         AS spo2,
  r.ml_risk_score,
  r.gemini_explanation,
  r.risk_level
FROM `${project_id}.${dataset_id}.patients` p
LEFT JOIN latest_obs o ON o.patient_id = p.patient_id AND o.rn = 1
LEFT JOIN latest_risk r ON r.patient_id = p.patient_id AND r.rn = 1
GROUP BY
  p.patient_id, p.dummy_name_token, p.region, p.age_band,
  r.ml_risk_score, r.gemini_explanation, r.risk_level;
