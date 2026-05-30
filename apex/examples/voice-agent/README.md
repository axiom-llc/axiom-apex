# Twilio Telephony Voice Agent

This directory contains a containerized voice agent blueprint integrating Twilio programmatic voice streams with Gemini's reasoning pipelines to execute real-time call center workflows [2].

## Directory Components

*   `main.py` — Core Flask server handling Twilio webhook routing, dynamic TwiML generation, and model response generation [2].
*   `deploy.sh` — Shell automation compiling, building, and deploying the containerized microservice to Google Cloud Run.
*   `Dockerfile` — Optimized container build configuration.
*   `requirements.txt` — Frozen application dependencies (Flask, twilio, google-generativeai) [2].

---

## Setup & Local Run

1. Configure your local runtime parameters:
   ```bash
   export TWILIO_ACCOUNT_SID="your-sid"
   export TWILIO_AUTH_TOKEN="your-token"
   export GEMINI_API_KEY="your-key"
   ```
2. Execute the Flask entry point:
   ```bash
   python main.py
   ```
3. Tunnel port `5000` via a secure reverse proxy (such as ngrok) to expose your webhook securely to Twilio:
   ```bash
   ngrok http 5000
   ```
