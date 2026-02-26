"""LLM provider implementations"""
import os
import google.genai as genai

_client: genai.Client | None = None

def _get_client() -> genai.Client:
    global _client
    if _client is None:
        _client = genai.Client(api_key=os.environ['GEMINI_API_KEY'])
    return _client

def gemini_complete(prompt: str) -> dict:
    response = _get_client().models.generate_content(
        model='gemini-2.5-flash',
        contents=prompt,
        config={
            'temperature': 0.2,
            'max_output_tokens': 8192,
        }
    )
    return {
        'text': response.text,
        'tokens': response.usage_metadata.total_token_count
    }
