# Stage 1: dùng poetry cài dependencies vào virtualenv
FROM python:3.14-slim AS builder

ENV POETRY_VIRTUALENVS_IN_PROJECT=true \
    POETRY_NO_INTERACTION=1

WORKDIR /app

RUN pip install --no-cache-dir poetry

COPY pyproject.toml poetry.lock ./
RUN poetry install --only main --no-root && rm -rf ~/.cache/pypoetry

# Stage 2: runtime chỉ có venv + code, không có poetry
FROM python:3.14-slim

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    WEB_CONCURRENCY=2

WORKDIR /app

RUN useradd --create-home --uid 1000 app

COPY --from=builder /app/.venv .venv
COPY main.py healthcheck.py ./

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "healthcheck.py"]

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
