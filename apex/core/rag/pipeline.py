"""HTTP-only APEX pipeline adapters; file reads remain local."""
from rag.remote import (
    ingest,
    ingest_file,
    ingest_directory,
    pipeline_query,
    query,
)
