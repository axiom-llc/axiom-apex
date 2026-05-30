"""Text chunking strategies.

Both functions return list[str].  Strategy is selected at ingest time via
pipeline.ingest(strategy=...).

chunk_size is measured in **words**, not tokens.  For English prose,
word count ≈ 0.75 × token count, so the default of 512 words corresponds
to roughly 680 tokens — comfortably within Gemini's embedding context window.
Adjust RAG_CHUNK_SIZE empirically for your domain and script.

Fixed-size (default)
    Splits on word boundaries to approximately chunk_size words, with a
    configurable word-level overlap between consecutive chunks.  Overlap
    preserves context that would otherwise be severed at a boundary.

Sentence
    Groups sentences (split on sentence-ending punctuation) until chunk_size
    words is reached.  Better recall for prose; less predictable for structured
    or technical documents.
"""
from __future__ import annotations
import re


def chunk_fixed(text: str, chunk_size: int, overlap: int) -> list[str]:
    """Split text into overlapping fixed-size chunks (word-boundary aligned).

    Args:
        text:       Input text.
        chunk_size: Maximum words per chunk.
        overlap:    Words of overlap between consecutive chunks. Must be < chunk_size.
    """
    if overlap >= chunk_size:
        raise ValueError("overlap must be less than chunk_size")
    words = text.split()
    chunks: list[str] = []
    i = 0
    while i < len(words):
        chunks.append(" ".join(words[i : i + chunk_size]))
        i += chunk_size - overlap
    return [c for c in chunks if c.strip()]


def chunk_sentences(text: str, chunk_size: int) -> list[str]:
    """Group sentences into chunks of up to chunk_size words.

    Args:
        text:       Input text.
        chunk_size: Maximum words per chunk.
    """
    sentences = re.split(r"(?<=[.!?])\s+", text)
    chunks: list[str] = []
    current: list[str] = []
    count = 0
    for sentence in sentences:
        word_count = len(sentence.split())
        if count + word_count > chunk_size and current:
            chunks.append(" ".join(current))
            current, count = [], 0
        current.append(sentence)
        count += word_count
    if current:
        chunks.append(" ".join(current))
    return [c for c in chunks if c.strip()]
"""Gemini embedding adapter.

Stateless — takes text, returns float vectors.  Batches up to 100 texts per
API call (Gemini embedding API limit).

task_type asymmetry
    Gemini's text-embedding-004 model is trained with asymmetric tasks:
    - "retrieval_document" for content being indexed
    - "retrieval_query"    for the search query at retrieval time
    Using the wrong type measurably degrades retrieval precision.
    Both are set explicitly; do not remove them.
"""
from __future__ import annotations
from google import genai
from google.genai import types
from rag.config import Config

_BATCH_LIMIT = 100


def _client(config: Config) -> genai.Client:
    return genai.Client(api_key=config.gemini_api_key)


def embed_texts(texts: list[str], config: Config) -> list[list[float]]:
    """Embed a list of document texts.  Returns one vector per text."""
    config.requires_api_key()
    client = _client(config)
    all_embeddings: list[list[float]] = []
    for i in range(0, len(texts), _BATCH_LIMIT):
        batch = texts[i : i + _BATCH_LIMIT]
        response = client.models.embed_content(
            model=config.embedding_model,
            contents=batch,
            config=types.EmbedContentConfig(task_type="RETRIEVAL_DOCUMENT"),
        )
        all_embeddings.extend(e.values for e in response.embeddings)
    return all_embeddings


def embed_query(query: str, config: Config) -> list[float]:
    """Embed a single query string for retrieval."""
    config.requires_api_key()
    client = _client(config)
    response = client.models.embed_content(
        model=config.embedding_model,
        contents=query,
        config=types.EmbedContentConfig(task_type="RETRIEVAL_QUERY"),
    )
    return list(response.embeddings[0].values)
"""LLM answer generation over retrieved context.

Stateless.  Takes retrieved chunks and the original query; returns a grounded
answer dict.

Grounding discipline (enforced in the system prompt, not configurable by
default): the model must answer only from the provided context passages, cite
doc_id inline, and explicitly state when context is insufficient rather than
speculate.  The system_prompt parameter exists for domain adaptation
(different languages, specialised instruction sets) but changing it to allow
prior-knowledge use defeats the purpose of the pipeline.
"""
from __future__ import annotations
from google import genai
from google.genai import types
from rag.config import Config

_DEFAULT_SYSTEM_PROMPT = """\
You are a precise question-answering assistant.
Answer the question using ONLY the provided context passages.
If the context does not contain enough information to answer, say so clearly.
Do not use prior knowledge. Do not speculate beyond the context.
Cite the source document (doc_id) inline when referencing specific facts."""


def generate_answer(
    query: str,
    context_chunks: list[dict],
    config: Config,
    system_prompt: str = _DEFAULT_SYSTEM_PROMPT,
) -> dict:
    """Generate a grounded answer from retrieved chunks.

    Args:
        query:          The user's question.
        context_chunks: Output of store.query() — list of {text, metadata, score}.
        config:         Resolved Config instance.
        system_prompt:  Override for domain adaptation; default enforces strict
                        grounding.

    Returns:
        {
            "answer":      str,
            "sources":     list[str],   # unique doc_ids referenced
            "chunk_count": int,
        }
    """
    if not context_chunks:
        return {
            "answer": "No relevant documents found for this query.",
            "sources": [],
            "chunk_count": 0,
        }

    config.requires_api_key()
    context_block = "\n\n".join(
        f"[{c['metadata'].get('doc_id', 'unknown')}] {c['text']}"
        for c in context_chunks
    )
    prompt = f"Context:\n{context_block}\n\nQuestion: {query}"

    config.requires_api_key()
    client = genai.Client(api_key=config.gemini_api_key)
    response = client.models.generate_content(
        model=config.generation_model,
        contents=prompt,
        config=types.GenerateContentConfig(system_instruction=system_prompt),
    )
    sources = sorted({c["metadata"].get("doc_id", "unknown") for c in context_chunks})

    return {
        "answer": response.text,
        "sources": sources,
        "chunk_count": len(context_chunks),
    }
"""ChromaDB vector store abstraction.

All ChromaDB access is contained here.  To swap in pgvector: implement the
same public functions (upsert, query, delete_document, list_documents,
collection_stats) in a new store_pg.py and update the import in pipeline.py.
Nothing else changes.

Client caching
    _get_client() is LRU-cached on the resolved path string.  A threading lock
    serialises first-time initialisation — ChromaDB's Rust backend is not
    thread-safe during construction.  Subsequent calls hit the cache and bypass
    the lock entirely.  Tests should call _get_client.cache_clear() in teardown.
"""
from __future__ import annotations
import threading
from functools import lru_cache
from pathlib import Path

import chromadb
from chromadb.config import Settings

from rag.config import Config

_init_lock = threading.Lock()


@lru_cache(maxsize=8)
def _get_client(path: str) -> chromadb.PersistentClient:
    with _init_lock:
        return chromadb.PersistentClient(
            path=path,
            settings=Settings(anonymized_telemetry=False),
        )


def _get_collection(config: Config):
    path = str(Path(config.chroma_path).expanduser())
    return _get_client(path).get_or_create_collection(
        name=config.collection_name,
        metadata={"hnsw:space": "cosine"},
    )


def upsert(
    chunks: list[str],
    embeddings: list[list[float]],
    doc_id: str,
    config: Config,
    metadata: dict | None = None,
) -> None:
    """Upsert chunks into the vector store.  Idempotent on doc_id + chunk index."""
    collection = _get_collection(config)
    ids = [f"{doc_id}::{i}" for i in range(len(chunks))]
    metas = [
        {**(metadata or {}), "doc_id": doc_id, "chunk_index": i}
        for i in range(len(chunks))
    ]
    collection.upsert(
        ids=ids,
        embeddings=embeddings,
        documents=chunks,
        metadatas=metas,
    )


def query(query_embedding: list[float], config: Config) -> list[dict]:
    """Return top-k chunks at or above score_threshold, sorted by relevance desc."""
    collection = _get_collection(config)
    results = collection.query(
        query_embeddings=[query_embedding],
        n_results=config.top_k,
        include=["documents", "metadatas", "distances"],
    )
    chunks = []
    for doc, meta, dist in zip(
        results["documents"][0],
        results["metadatas"][0],
        results["distances"][0],
    ):
        score = 1.0 - dist  # cosine distance → cosine similarity
        if score >= config.score_threshold:
            chunks.append({"text": doc, "metadata": meta, "score": score})
    return sorted(chunks, key=lambda x: x["score"], reverse=True)


def delete_document(doc_id: str, config: Config) -> int:
    """Delete all chunks for a document.  Returns the count deleted."""
    collection = _get_collection(config)
    results = collection.get(where={"doc_id": doc_id})
    if results["ids"]:
        collection.delete(ids=results["ids"])
    return len(results["ids"])


def list_documents(config: Config) -> list[str]:
    """Return sorted unique doc_ids present in the collection."""
    collection = _get_collection(config)
    results = collection.get(include=["metadatas"])
    return sorted({m.get("doc_id", "unknown") for m in results["metadatas"]})


def collection_stats(config: Config) -> dict:
    """Return total chunk count and document list in a single collection access."""
    collection = _get_collection(config)
    results = collection.get(include=["metadatas"])
    doc_ids = sorted({m.get("doc_id", "unknown") for m in results["metadatas"]})
    return {
        "total_chunks": collection.count(),
        "documents": doc_ids,
    }
"""Public interface for the RAG pipeline.

Two primary functions: ingest() and query().
All other modules are implementation details; callers should not import them.

ingest() — chunk → embed → store
query()  — embed query → retrieve → generate
"""
from __future__ import annotations
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from rag.config import Config
from rag import chunker, embedder, store, generator


def ingest(
    text: str,
    doc_id: str,
    config: Config,
    metadata: dict | None = None,
    strategy: str = "fixed",
) -> dict:
    """Chunk, embed, and store a document.

    Args:
        text:     Full document text.
        doc_id:   Stable unique identifier (filename, URL, UUID, …).
        config:   Resolved Config instance.
        metadata: Optional key-value pairs stored alongside every chunk.
        strategy: "fixed" (default) or "sentences".

    Returns:
        {"doc_id": str, "chunks_stored": int}
    """
    if strategy == "sentences":
        chunks = chunker.chunk_sentences(text, config.chunk_size)
    else:
        chunks = chunker.chunk_fixed(text, config.chunk_size, config.chunk_overlap)

    if not chunks:
        return {"doc_id": doc_id, "chunks_stored": 0}

    all_embeddings = embedder.embed_texts(chunks, config)
    store.upsert(chunks, all_embeddings, doc_id, config, metadata)
    return {"doc_id": doc_id, "chunks_stored": len(chunks)}


def query(question: str, config: Config) -> dict:
    """Retrieve relevant chunks and generate a grounded answer.

    Returns:
        {
            "answer":      str,
            "sources":     list[str],
            "chunks":      list[dict],  # retrieved context with scores
            "chunk_count": int,
        }
    """
    q_embedding = embedder.embed_query(question, config)
    chunks = store.query(q_embedding, config)
    result = generator.generate_answer(question, chunks, config)
    return {**result, "chunks": chunks}


def ingest_file(
    path: str,
    config: Config,
    metadata: dict | None = None,
    strategy: str = "fixed",
) -> dict:
    """Read a file and ingest it.  doc_id is set to the filename."""
    p = Path(path).expanduser()
    text = p.read_text(encoding="utf-8", errors="replace")
    return ingest(text, doc_id=p.name, config=config, metadata=metadata, strategy=strategy)


def ingest_directory(
    directory: str,
    config: Config,
    extensions: list[str] | None = None,
    strategy: str = "fixed",
    max_workers: int = 4,
) -> list[dict]:
    """Ingest all matching files in a directory (recursive), in parallel.

    Files are embedded concurrently using a thread pool.  The Gemini embedding
    API is network-bound, so parallel requests reduce wall-clock time
    significantly for large corpora.

    ChromaDB's Rust backend is not thread-safe during first initialisation, so
    the client is pre-warmed on the calling thread before the pool spawns.
    Subsequent upserts are serialised internally by ChromaDB's write lock.

    Args:
        extensions:  File extensions to match (default: [".txt", ".md"]).
        max_workers: Thread pool size.  4 is a safe default; increase for
                     large corpora with low API latency.

    Returns:
        List of ingest result dicts, one per file, in completion order.
    """
    d = Path(directory).expanduser()
    exts = set(extensions or [".txt", ".md"])
    paths = [p for p in d.rglob("*") if p.is_file() and p.suffix in exts]

    # Pre-warm the ChromaDB client on the calling thread before spawning workers.
    # This ensures the LRU cache is populated and the Rust backend is fully
    # initialised before any worker thread touches it.
    store._get_client(str(Path(config.chroma_path).expanduser()))

    results: list[dict] = []
    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = {
            pool.submit(ingest_file, str(p), config, None, strategy): p
            for p in paths
        }
        for future in as_completed(futures):
            results.append(future.result())
    return results
