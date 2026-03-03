"""LLM provider implementations."""
import google.genai as genai


def gemini_complete(prompt: str, *, api_key: str) -> dict:
    """Call Gemini and return text + token count. No global state."""
    client = genai.Client(api_key=api_key)
    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=prompt,
        config={
            "temperature": 0.2,
            "max_output_tokens": 8192,
        },
    )
    return {
        "text": response.text,
        "tokens": response.usage_metadata.total_token_count,
    }
