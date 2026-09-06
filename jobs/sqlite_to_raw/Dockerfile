FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Keep the SQLite runtime explicit instead of relying on transitive image contents.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN python -m pip install \
    --disable-pip-version-check \
    --no-cache-dir \
    --requirement requirements.txt

COPY main.py sqlite_loader.py ./

RUN useradd --create-home --uid 10001 appuser
USER appuser

CMD ["python", "main.py"]
