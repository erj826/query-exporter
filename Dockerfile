FROM python:3.14-slim AS runtime

RUN apt-get update && apt-get full-upgrade -y
RUN python -m pip uninstall -y pip \
    && rm -rf "$(python -c 'import ensurepip, os; print(os.path.dirname(ensurepip.__file__))')/_bundled"

COPY --from=docker.io/astral/uv:latest /uv /bin/

COPY . /src

ENV PATH="/virtualenv/bin:$PATH" \
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

HEALTHCHECK --interval=3s --timeout=3s CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:9560/', timeout=2)"]


FROM runtime AS base

RUN uv sync


FROM runtime AS full-builder

RUN apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    default-libmysqlclient-dev \
    libpq-dev

RUN uv sync --group=docker-dbs


FROM runtime AS full

RUN apt-get install -y --no-install-recommends \
    libmariadb3 \
    libpq5 \
    libxml2

COPY --from=full-builder /virtualenv /virtualenv
