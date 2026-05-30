"""Smoke tests for the Axiom LLC AI Voice IVR (voice-agent/main.py).

The app has a module-level genai.Client() call that fires on import.
We set GEMINI_API_KEY in the environment (CI sets it to a dummy value)
and patch the client before any live calls can be made.

All Twilio webhook calls, Gemini API calls, and outbound HTTP requests
are mocked. No network access required.
"""
from __future__ import annotations
import os
import sys
import pytest
from unittest.mock import patch, MagicMock

# Ensure the voice-agent directory is on the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "voice-agent"))


@pytest.fixture(scope="module", autouse=True)
def patch_genai_client():
    """Patch genai.Client before the module is imported so the module-level
    client instantiation doesn't attempt a live API call."""
    mock_response = MagicMock()
    mock_response.text = "Thank you for contacting Axiom LLC."
    mock_client = MagicMock()
    mock_client.models.generate_content.return_value = mock_response

    with patch("google.genai.Client", return_value=mock_client):
        yield mock_client


@pytest.fixture(scope="module")
def client():
    import importlib
    import main as voice_main
    importlib.reload(voice_main)   # reload so patched client takes effect
    voice_main.app.config["TESTING"] = True
    return voice_main.app.test_client()


# ── Main menu ──────────────────────────────────────────────────────────────

class TestMainMenu:
    def test_post_returns_twiml(self, client):
        r = client.post("/")
        assert r.status_code == 200
        assert b"<Response>" in r.data
        assert b"<Gather" in r.data

    def test_response_content_type_is_xml(self, client):
        r = client.post("/")
        assert "xml" in r.content_type


# ── Routing ────────────────────────────────────────────────────────────────

class TestRoute:
    @pytest.mark.parametrize("digit", ["1", "2", "3", "4", "5", "6", "7"])
    def test_preset_digits_return_say_verb(self, client, digit):
        r = client.post("/route", data={"Digits": digit})
        assert r.status_code == 200
        assert b"<Say>" in r.data

    def test_digit_8_returns_record_verb(self, client):
        r = client.post("/route", data={"Digits": "8"})
        assert r.status_code == 200
        assert b"<Record" in r.data

    def test_digit_9_returns_dial_verb(self, client):
        r = client.post("/route", data={"Digits": "9"})
        assert r.status_code == 200
        assert b"<Dial" in r.data  # matches <Dial> and <Dial attr="...">

    def test_unknown_digit_redirects_to_root(self, client):
        r = client.post("/route", data={"Digits": "0"})
        assert r.status_code == 200
        assert b"<Redirect>" in r.data


# ── Navigation ─────────────────────────────────────────────────────────────

class TestNav:
    def test_pound_repeats_route(self, client):
        r = client.post("/nav", data={"Digits": "#"})
        assert r.status_code == 200
        assert b"<Redirect>/route</Redirect>" in r.data

    def test_star_returns_to_menu(self, client):
        r = client.post("/nav", data={"Digits": "*"})
        assert r.status_code == 200
        assert b"<Redirect>/</Redirect>" in r.data


# ── AI conversation ────────────────────────────────────────────────────────

class TestAIConversation:
    def test_missing_recording_url_redirects(self, client):
        r = client.post("/ai", data={"From": "+15551234567"})
        assert r.status_code == 200
        assert b"<Redirect>" in r.data

    def test_recording_url_triggers_ai_response(self, client):
        with patch("requests.get") as mock_get:
            mock_get.return_value = MagicMock(content=b"fake-audio-bytes")
            r = client.post("/ai", data={
                "From": "+15551234567",
                "RecordingUrl": "https://api.twilio.com/fake-recording",
            })
        assert r.status_code == 200
        assert b"<Say>" in r.data


# ── Voicemail ──────────────────────────────────────────────────────────────

class TestVoicemail:
    def test_no_answer_triggers_voicemail(self, client):
        r = client.post("/voicemail", data={"DialCallStatus": "no-answer"})
        assert r.status_code == 200
        assert b"<Record" in r.data

    def test_completed_call_hangs_up(self, client):
        r = client.post("/voicemail", data={"DialCallStatus": "completed"})
        assert r.status_code == 200
        assert b"<Hangup/>" in r.data
