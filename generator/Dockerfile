FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py patient_profiles.py ./

# Cloud Run Jobs pass args via the container command/args config, not CMD here.
# Local run example:
#   docker run --rm -e GOOGLE_APPLICATION_CREDENTIALS=/creds/sa.json \
#     -v $HOME/.config/gcloud:/creds:ro \
#     dhg-caretrack-generator --project-id dhg-caretrack --count 20
ENTRYPOINT ["python", "main.py"]
CMD ["--project-id", "dhg-caretrack", "--count", "20"]
