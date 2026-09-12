"""HTTP-only public storage adapters; no storage-owner handles are exposed."""
from rag.remote import (
    upsert,
    store_query,
    store_query as query,
    delete_document,
    list_documents,
    collection_stats,
    inspect,
    create_collection,
)
