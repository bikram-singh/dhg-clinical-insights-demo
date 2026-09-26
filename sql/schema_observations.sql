-- Observations fact table
-- One row per vital-sign measurement, mirroring FHIR Observation resources
-- Partitioned by event_timestamp (daily), clustered by patient_id

CREATE TABLE IF NOT EXISTS `${project_id}.${dataset_id}.observations` (
  observation_id     STRING NOT NULL,
  patient_id         STRING NOT NULL,
  observation_type   STRING NOT NULL OPTIONS(description="heart_rate | spo2 | bp_systolic | bp_diastolic | weight_kg | height_cm | bmi | body_temp_c | steps | battery_pct"),
  value              FLOAT64 NOT NULL,
  unit               STRING OPTIONS(description="bpm, %, mmHg, kg, cm, C, count"),
  device_id          STRING OPTIONS(description="Synthetic wearable device identifier"),
  event_timestamp    TIMESTAMP NOT NULL OPTIONS(description="When the synthetic reading was generated"),
  ingestion_time     TIMESTAMP NOT NULL OPTIONS(description="Set by Dataflow at write time, not by the device")
)
PARTITION BY DATE(event_timestamp)
CLUSTER BY patient_id
OPTIONS(
  description="Synthetic vitals observation table. All values are dummy data generated for demonstration purposes only."
);
