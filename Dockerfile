# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/dbca-wa/docker-apps-dev:ubuntu_2604_base_python_node26

# ----------------------------------------------------------------------
# Builder
# ----------------------------------------------------------------------
FROM ${BASE_IMAGE} AS builder

LABEL maintainer="asi@dbca.wa.gov.au"
LABEL org.opencontainers.image.source="https://github.com/dbca-wa/gokart-sss-django"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Australia/Perth \
    DEFAULT_FROM_EMAIL=no-reply@dbca.wa.gov.au \
    NOTIFICATION_EMAIL=no-reply@dbca.wa.gov.au \
    NON_PROD_EMAIL=none@none.com \
    PRODUCTION_EMAIL=False \
    EMAIL_INSTANCE=DEV \
    SECRET_KEY="ThisisNotRealKey" \
    SITE_DOMAIN=dbca.wa.gov.au

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        bzip2 \
        pdftk \
        unzip && \
    update-ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -g 5000 oim && \
    useradd -g 5000 -u 5000 oim -s /bin/bash -d /app && \
    mkdir /app && \
    chown -R oim:oim /app

WORKDIR /app
USER oim

ENV VIRTUAL_ENV=/app/venv
ENV PATH=$VIRTUAL_ENV/bin:$PATH

# ----------------------------------------------------------------------
# Python dependencies (cached separately from source changes)
# ----------------------------------------------------------------------

COPY --chown=oim:oim requirements.txt ./

RUN python3 -m venv $VIRTUAL_ENV && \
    $VIRTUAL_ENV/bin/pip install --upgrade pip && \
    $VIRTUAL_ENV/bin/uv pip install -r requirements.txt

# ----------------------------------------------------------------------
# Frontend dependencies (cached separately from frontend source changes)
# ----------------------------------------------------------------------

COPY --chown=oim:oim \
    sss/frontend/sss/package*.json \
    /app/sss/frontend/sss/

WORKDIR /app/sss/frontend/sss

RUN npm ci

# ----------------------------------------------------------------------
# Application source
# ----------------------------------------------------------------------

WORKDIR /app

COPY --chown=oim:oim gunicorn.ini ./
COPY --chown=oim:oim manage.py ./
COPY --chown=oim:oim uwsgi_prod.ini ./
COPY --chown=oim:oim profile.py ./

COPY --chown=oim:oim python-cron ./python-cron
COPY --chown=oim:oim packages ./packages
COPY --chown=oim:oim sss ./sss

# ----------------------------------------------------------------------
# Build Vue frontend
# ----------------------------------------------------------------------

WORKDIR /app/sss/frontend/sss

RUN npm run build && \
    rm -rf node_modules

# ----------------------------------------------------------------------
# Django static build
# ----------------------------------------------------------------------

WORKDIR /app

RUN touch /app/.env && \
    $VIRTUAL_ENV/bin/python manage.py collectstatic --noinput

# ----------------------------------------------------------------------
# Runtime
# ----------------------------------------------------------------------

FROM ${BASE_IMAGE} AS runtime

ARG IMAGE_TAG
ARG IMAGE_NAME

LABEL maintainer="asi@dbca.wa.gov.au"
LABEL org.opencontainers.image.source="https://github.com/dbca-wa/gokart-sss-django"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Australia/Perth \
    DEFAULT_FROM_EMAIL=no-reply@dbca.wa.gov.au \
    NOTIFICATION_EMAIL=no-reply@dbca.wa.gov.au \
    NON_PROD_EMAIL=none@none.com \
    PRODUCTION_EMAIL=False \
    EMAIL_INSTANCE=DEV \
    SECRET_KEY="ThisisNotRealKey" \
    SITE_DOMAIN=dbca.wa.gov.au \
    CONTAINER_IMAGE_TAG=${IMAGE_TAG} \
    CONTAINER_IMAGE_NAME=${IMAGE_NAME}

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        bzip2 \
        pdftk \
        unzip \
        wget && \
    update-ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -g 5000 oim && \
    useradd -g 5000 -u 5000 oim -s /bin/bash -d /app && \
    mkdir -p /app/tmp /app/logs /container-config && \
    chown -R oim:oim /app /container-config && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

COPY startup.sh /
COPY pre_startup.sh /

RUN chmod 755 /startup.sh /pre_startup.sh

USER oim
WORKDIR /app

ENV VIRTUAL_ENV=/app/venv
ENV PATH=$VIRTUAL_ENV/bin:$PATH

COPY --from=builder --chown=oim:oim /app/venv /app/venv
COPY --from=builder --chown=oim:oim /app/sss /app/sss
COPY --from=builder --chown=oim:oim /app/packages /app/packages
COPY --from=builder --chown=oim:oim /app/python-cron /app/python-cron
COPY --from=builder --chown=oim:oim /app/staticfiles /app/staticfiles

COPY --from=builder --chown=oim:oim /app/.env /app/.env
COPY --from=builder --chown=oim:oim /app/gunicorn.ini /app/gunicorn.ini
COPY --from=builder --chown=oim:oim /app/manage.py /app/manage.py
COPY --from=builder --chown=oim:oim /app/uwsgi_prod.ini /app/uwsgi_prod.ini

# ----------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------

USER root

RUN wget https://raw.githubusercontent.com/dbca-wa/wagov_utils/refs/heads/main/wagov_utils/bin/package_cleanup_2604.sh \
        -O /tmp/package_cleanup_2604.sh && \
    chmod 755 /tmp/package_cleanup_2604.sh && \
    /tmp/package_cleanup_2604.sh

USER oim

EXPOSE 8080

HEALTHCHECK --interval=1m --timeout=5s --start-period=10s --retries=3 \
    CMD ["wget", "-q", "-O", "-", "http://localhost:8080/"]

CMD ["/startup.sh"]