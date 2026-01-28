"""Basic tool implementations"""
import subprocess
import requests
from pathlib import Path
from core.types import Tool

def shell_effect(args: dict) -> dict:
    result = subprocess.run(
        args['cmd'],
        shell=True,
        capture_output=True,
        text=True,
        timeout=300
    )
    return {
        'stdout': result.stdout,
        'stderr': result.stderr,
        'code': result.returncode
    }

def read_file_effect(args: dict) -> dict:
    content = Path(args['path']).read_text()
    return {'content': content}

def write_file_effect(args: dict) -> dict:
    path = Path(args['path'])
    path.parent.mkdir(parents=True, exist_ok=True)
    bytes_written = path.write_text(args['content'])
    return {'bytes_written': bytes_written}

def http_get_effect(args: dict) -> dict:
    response = requests.get(
        args['url'],
        headers=args.get('headers', {}),
        timeout=30
    )
    return {
        'body': response.text,
        'status': response.status_code
    }

SHELL = Tool(
    name='shell',
    input_spec={'cmd': str},
    output_spec={'stdout': str, 'stderr': str, 'code': int},
    effect=shell_effect
)

READ_FILE = Tool(
    name='read_file',
    input_spec={'path': str},
    output_spec={'content': str},
    effect=read_file_effect
)

WRITE_FILE = Tool(
    name='write_file',
    input_spec={'path': str, 'content': str},
    output_spec={'bytes_written': int},
    effect=write_file_effect
)

HTTP_GET = Tool(
    name='http_get',
    input_spec={'url': str, 'headers': dict},
    output_spec={'body': str, 'status': int},
    effect=http_get_effect
)
