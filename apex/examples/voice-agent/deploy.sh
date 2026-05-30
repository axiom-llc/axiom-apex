#!/bin/bash
# deploy.sh - Deploy to Google Cloud Run

PROJECT_ID=""       # GCP project ID
SERVICE_NAME=""     # Cloud Run service name
REGION="us-east1"

gcloud run deploy $SERVICE_NAME \
  --source . \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --set-env-vars GEMINI_API_KEY="$GEMINI_API_KEY" \
  --set-env-vars TWILIO_ACCOUNT_SID="$TWILIO_ACCOUNT_SID" \
  --set-env-vars TWILIO_AUTH_TOKEN="$TWILIO_AUTH_TOKEN" \
  --set-env-vars CONTACT_PHONE="$CONTACT_PHONE" \
  --project $PROJECT_ID

echo "Done. Update Twilio webhook to the service URL above."
