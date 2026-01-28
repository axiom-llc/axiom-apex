"""Tool registry"""
from tools.basic import SHELL, READ_FILE, WRITE_FILE, HTTP_GET
from memory.sqlite import MEMORY_READ, MEMORY_WRITE

REGISTRY = {
    'shell': SHELL,
    'read_file': READ_FILE,
    'write_file': WRITE_FILE,
    'http_get': HTTP_GET,
    'memory_read': MEMORY_READ,
    'memory_write': MEMORY_WRITE,
}
