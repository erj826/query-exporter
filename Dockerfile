FROM python:3.14-slim-trixie AS runtime

RUN apt-get update \
    && apt-get full-upgrade -y \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip uninstall -y pip \
    && rm -rf /usr/local/lib/python3.*/ensurepip/_bundled \
    && useradd --system --uid 10001 --user-group query-exporter

COPY --from=docker.io/astral/uv:0.13.5 /uv /bin/

ENV PATH="/virtualenv/bin:$PATH" \
    UV_COMPILE_BYTECODE="1" \
    UV_LOCKED="1" \
    UV_NO_CACHE="1" \
    UV_NO_DEFAULT_GROUPS="1" \
    UV_NO_EDITABLE="1" \
    UV_PROJECT_ENVIRONMENT="/virtualenv" \
    UV_PYTHON_DOWNLOADS="never" \
    UV_WORKING_DIR="/src" \
    VIRTUAL_ENV="/virtualenv"

# IPv6 support is not enabled by default, only bind IPv4
ENV QE_HOST="0.0.0.0"

EXPOSE 9560/tcp
VOLUME /config
WORKDIR /config
ENTRYPOINT ["query-exporter"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --start-interval=1s CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:9560/', timeout=2)"]


FROM runtime AS base

COPY . /src
RUN uv sync

USER query-exporter


FROM runtime AS full-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        default-libmysqlclient-dev \
        libpq-dev
COPY . /src
RUN uv sync --group=docker-dbs


FROM runtime AS full

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libmariadb3 \
        libpq5 \
        libxml2 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=full-builder /virtualenv /virtualenv

USER query-exporter
