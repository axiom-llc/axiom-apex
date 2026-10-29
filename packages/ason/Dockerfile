FROM python:3.12-slim
WORKDIR /app
COPY axiom-rag/pyproject.toml axiom-rag/README.md axiom-rag/cli.py /app/axiom-rag/
COPY axiom-rag/rag /app/axiom-rag/rag
COPY axiom-rag/server /app/axiom-rag/server
COPY axiom-apex/pyproject.toml axiom-apex/README.md /app/axiom-apex/
COPY axiom-apex/apex /app/axiom-apex/apex
COPY axiom-ason/pyproject.toml /app/axiom-ason/
COPY axiom-ason/ason /app/axiom-ason/ason
RUN pip install --no-cache-dir /app/axiom-rag /app/axiom-apex /app/axiom-ason
CMD ["ason"]
