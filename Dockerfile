# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.14
ARG DEBIAN_RELEASE=trixie
ARG UV_VERSION=0.13.5

FROM docker.io/astral/uv:${UV_VERSION} AS uv


FROM python:${PYTHON_VERSION}-slim-${DEBIAN_RELEASE} AS runtime

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get full-upgrade -y \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip uninstall -y pip \
    && rm -rf "$(python -c 'import ensurepip, os; print(os.path.dirname(ensurepip.__file__))')/_bundled" \
    && find / -xdev -type f -perm /6000 -exec chmod a-s {} + \
    && groupadd --system --gid 10001 query-exporter \
    && useradd --system --uid 10001 --gid query-exporter \
        --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin \
        query-exporter

COPY --from=uv /uv /bin/

ENV PATH="/virtualenv/bin:$PATH" \
    PYTHONUNBUFFERED="1" \
    UV_COMPILE_BYTECODE="1" \
    UV_LOCKED="1" \
    UV_NO_CACHE="1" \
    UV_NO_DEFAULT_GROUPS="1" \
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

HEALTHCHECK --interval=3s --timeout=3s --start-period=10s \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:9560/', timeout=2)"]


FROM runtime AS base

COPY pyproject.toml uv.lock /src/
RUN uv sync --no-install-project
COPY query_exporter /src/query_exporter
RUN uv sync

USER query-exporter


FROM runtime AS full-builder

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        default-libmysqlclient-dev \
        libpq-dev

COPY pyproject.toml uv.lock /src/
RUN uv sync --no-install-project --group=docker-dbs
COPY query_exporter /src/query_exporter
RUN uv sync --group=docker-dbs


FROM runtime AS full

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libmariadb3 \
        libpq5 \
        libxml2 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=full-builder /src /src
COPY --from=full-builder /virtualenv /virtualenv

USER query-exporter
