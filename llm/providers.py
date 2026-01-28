"""LLM provider implementations"""
import os
import google.genai as genai

def gemini_complete(prompt: str) -> dict:
    client = genai.Client(api_key=os.environ['GEMINI_API_KEY'])
    
    response = client.models.generate_content(
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
