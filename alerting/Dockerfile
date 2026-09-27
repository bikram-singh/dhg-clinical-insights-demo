FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# credentials.json/token.json are deliberately NOT copied into the image -
# they're git-ignored secrets. In Cloud Run, set TOKEN_SECRET_NAME so the
# cached OAuth token is fetched from Secret Manager at startup instead.
#
# Cloud Run Jobs pass args via the container command/args config, not CMD
# here. Local run example:
#   docker run --rm -v ${PWD}:/app/local -e GOOGLE_APPLICATION_CREDENTIALS=/creds/sa.json \
#     -v $HOME/.config/gcloud:/creds:ro \
#     dhg-caretrack-alerting --project-id dhg-caretrack --bq-dataset dhg_caretrack \
#     --from-email you@example.com --to-email you@example.com --lookback-hours 1
ENTRYPOINT ["python", "main.py"]
CMD ["--project-id", "dhg-caretrack", "--bq-dataset", "dhg_caretrack", "--lookback-hours", "1"]
