# Containerized Twilio Telephony Voice Agent

This deployment blueprint details a serverless voice agent architecture. It integrates **Twilio Voice Streams** with **Gemini’s Reasoning Model** inside an optimized Docker container to handle conversational call routing and dynamic customer workflows.

---

## 1. Operational Architecture

```
Incoming Call ──> Twilio ──(HTTP POST Webhook)──> ngrok / Load Balancer
                                                          │
  TwiML XML response <── [main.py (Flask)] ◄──────────────┘
                             │
                     Gemini 2.5 Flash
```

1.  **Call Initiation**: An incoming call triggers Twilio to issue an HTTP POST request containing call parameters to our server webhook.
2.  **Webhook Router (`main.py`)**: Handles the request, queries Gemini for the next conversational response, and generates dynamic **TwiML XML** structures (e.g., `<Say>`, `<Gather>`, `<Hangup>`).
3.  **Process Isolation**: Containerization ensures clean runtime environments with minimal package surfaces.

---

## 2. Configuration & Local Execution

### Step 1: Export Telephony Credentials
Configure your terminal environment variables:
```bash
export TWILIO_ACCOUNT_SID="your-twilio-sid"
export TWILIO_AUTH_TOKEN="your-twilio-auth-token"
export GEMINI_API_KEY="your-gemini-key"
```

### Step 2: Install Package Requirements
```bash
pip install -r requirements.txt
```

### Step 3: Run the Server
Launch the Flask telephony server on port `5000`:
```bash
python main.py
```

### Step 4: Secure Port Tunneling
Twilio requires a public HTTPS URL to route calls. Create a secure tunnel using ngrok:
```bash
ngrok http 5000
```
Copy the public HTTPS URL (e.g., `https://abcd.ngrok-free.app`) and configure it as the Voice webhook URL inside your Twilio Console.

---

## 3. Containerized Deployment (GCP Cloud Run)

To compile, build, and deploy this voice agent to Google Cloud Run, execute the deployment script:
```bash
chmod +x deploy.sh
./deploy.sh
```
This compiles your local directory assets, pushes the image to Google Artifact Registry, and deploys it on Google Cloud Run serverless container instances.
