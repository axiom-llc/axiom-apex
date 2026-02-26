# llm/

LLM provider interface. Isolates all API calls from core logic.

## providers.py

Gemini API integration. Handles request formatting, response parsing, and error surface for the planner. To swap providers, implement the same interface here — core/ requires no changes.

**Model:** Gemini 2.5 Flash (configured via this module)
**Key:** `GEMINI_API_KEY` environment variable — read here, never passed through core.
