"""
DHG CareTrack — Synthetic Telemetry Generator

Publishes fake wearable/vitals readings to Pub/Sub for the DHG CareTrack
demo pipeline. ALL DATA PRODUCED HERE IS SYNTHETIC. No real patient, device,
or hospital system is involved.

Usage:
    python main.py --project-id caretrack --topic patient-telemetry-raw --count 50

Designed to run as a one-shot Cloud Run job (triggered by Cloud Scheduler)
or locally for testing.
"""

import argparse
import json
import random
import uuid
from datetime import datetime, timezone

from google.cloud import pubsub_v1

from patient_profiles import get_patient_pool, random_report_note


def generate_reading(patient):
    """Builds one synthetic telemetry event for a given dummy patient."""
    now = datetime.now(timezone.utc).isoformat()

    # Base vitals with mild randomness. Occasionally push a patient into a
    # "high risk" range so the risk-scoring/alerting stages have something
    # real to catch during testing.
    high_risk_roll = random.random() < 0.15

    bp_systolic = random.randint(150, 180) if high_risk_roll else random.randint(105, 135)
    bp_diastolic = random.randint(95, 110) if high_risk_roll else random.randint(65, 85)
    heart_rate = random.randint(95, 120) if high_risk_roll else random.randint(60, 90)
    weight_kg = round(random.uniform(55, 95), 1)
    height_cm = round(random.uniform(150, 190), 1)
    bmi = round(weight_kg / ((height_cm / 100) ** 2), 1)
    spo2 = round(random.uniform(90, 94), 1) if high_risk_roll else round(random.uniform(96, 99), 1)
    body_temp_c = round(random.uniform(36.1, 37.2), 1)
    steps = random.randint(500, 12000)
    battery_pct = random.randint(20, 100)

    event = {
        "event_id": str(uuid.uuid4()),
        "patient_id": patient["patient_id"],
        "device_id": f"DEV-{patient['patient_id'][-4:]}",
        "event_timestamp": now,
        "observations": {
            "heart_rate": heart_rate,
            "spo2": spo2,
            "bp_systolic": bp_systolic,
            "bp_diastolic": bp_diastolic,
            "weight_kg": weight_kg,
            "height_cm": height_cm,
            "bmi": bmi,
            "body_temp_c": body_temp_c,
            "steps": steps,
            "battery_pct": battery_pct,
        },
        "diagnostic_report": {
            "report_id": str(uuid.uuid4()),
            "report_date": now[:10],
            "report_text": random_report_note(),
        },
        "meta": {
            "synthetic": True,
            "source": "dhg-caretrack-generator",
        },
    }
    return event


def publish_events(project_id, topic_name, count, dry_run=False):
    patients = get_patient_pool()
    events = [generate_reading(random.choice(patients)) for _ in range(count)]

    if dry_run:
        for e in events:
            print(json.dumps(e, indent=2))
        return

    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name)

    futures = []
    for event in events:
        data = json.dumps(event).encode("utf-8")
        futures.append(publisher.publish(topic_path, data))

    for f in futures:
        f.result()  # raises on failure

    print(f"Published {len(events)} synthetic telemetry events to {topic_path}")


def main():
    parser = argparse.ArgumentParser(description="DHG CareTrack synthetic telemetry generator")
    parser.add_argument("--project-id", required=True, help="GCP project ID")
    parser.add_argument("--topic", default="patient-telemetry-raw", help="Pub/Sub topic name")
    parser.add_argument("--count", type=int, default=20, help="Number of synthetic events to generate")
    parser.add_argument("--dry-run", action="store_true", help="Print events instead of publishing")
    args = parser.parse_args()

    publish_events(args.project_id, args.topic, args.count, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
