FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt
RUN pip install --upgrade pip \
    && pip install -r /app/requirements.txt

COPY . /app

RUN addgroup --system django \
    && adduser --system --ingroup django django \
    && chown -R django:django /app

USER django

EXPOSE 8000

# Self-sufficient by default: migrate + collectstatic + serve, and honor a
# platform-assigned $PORT (Railway/Render/Fly set this; falls back to 8000
# for a plain `docker run`). docker-compose.yml overrides this with its own
# `command:` for local dev, so this only matters when the image runs without
# that override — i.e. on a hosting platform that just runs the Dockerfile.
CMD ["sh", "-c", "python manage.py migrate --noinput && python manage.py collectstatic --noinput && daphne -b 0.0.0.0 -p ${PORT:-8000} backend_core.asgi:application"]
