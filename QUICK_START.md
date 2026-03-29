# Quick Start — Local Development

Get the full stack running on your machine in under 5 minutes using Docker + LocalStack (no AWS account needed).

---

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker Engine + Compose)
- `make`
- Python 3.11+ (for running tests locally)
- AWS CLI (optional — for inspecting LocalStack resources)

---

## 1. Clone the three repos as siblings

```bash
git clone https://github.com/koss110/cp-infra
git clone https://github.com/koss110/cp-api
git clone https://github.com/koss110/cp-worker
```

The repos must sit in the same parent directory:

```
parent-dir/
├── cp-infra/    ← this repo
├── cp-api/
└── cp-worker/
```

---

## 2. Start LocalStack and seed AWS resources

```bash
cd cp-infra
make local-up
```

This starts LocalStack and seeds:
- SQS queue: `exam-costa-local-messages`
- S3 bucket: `exam-costa-local-messages`
- SSM token: `/exam-costa/local/api/token` = `local-dev-token`

---

## 3. Build images and start the full stack

```bash
make local-build
```

Services started:

| Service | URL |
|---------|-----|
| cp-api | http://localhost:8000 |
| LocalStack | http://localhost:4566 |

---

## 4. Verify everything is running

```bash
curl http://localhost:8000/healthz
# {"status":"healthy","service":"api","version":"local-<sha>"}
```

---

## 5. Send a test message

```bash
curl -s -X POST http://localhost:8000/message \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "email_subject": "Happy new year!",
      "email_sender": "John Doe",
      "email_timestream": "1693561101",
      "email_content": "Just want to say... Happy new year!!!"
    },
    "token": "local-dev-token"
  }' | python3 -m json.tool
```

Expected response:
```json
{"status": "published", "message_id": "<uuid>"}
```

---

## 6. Verify the worker uploaded the message to S3

```bash
aws --endpoint-url=http://localhost:4566 --region us-east-2 \
  s3 ls s3://exam-costa-local-messages/messages/ --recursive
```

---

## 7. Run tests

```bash
# Unit tests (no Docker needed)
make app-test

# Integration tests (requires local stack running)
make app-test-integration
```

---

## 8. Tear down

```bash
make local-down
```

---

## Optional: local monitoring (Prometheus + Grafana)

```bash
make local-monitoring-up
```

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | `admin` / `admin` |
| Prometheus | http://localhost:9090 | — |

To stop: `make local-monitoring-down`

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `curl: connection refused` on port 8000 | Wait ~10s for LocalStack to finish seeding, then run `make local-build` again |
| `401 Unauthorized` | Ensure the token in your request matches `local-dev-token` |
| S3 ls returns empty | The worker polls every few seconds — wait and retry |
| Port 4566 already in use | Another LocalStack instance is running: `docker ps` and stop it |
