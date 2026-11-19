# syntax=docker/dockerfile:1

FROM ghcr.io/dbca-wa/gokart-sss-django:latest AS dev

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        curl \
        dnsutils \
        git \
        graphviz \
        jq \
        less \
        libpq-dev \
        netcat-openbsd \
        patch \
        postgresql-client \
        procps \
        python3-pydot \
        screen \
        ssh \
        sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN openssl req \
        -new \
        -newkey rsa:4096 \
        -days 3650 \
        -nodes \
        -x509 \
        -subj "/C=AU/ST=Western Australia/L=Perth/O=Development Environment/OU=IT Department/CN=example.com" \
        -keyout /etc/ssl/private/selfsignedssl.key \
        -out /etc/ssl/private/selfsignedssl.crt

RUN { \
        echo 'if ! [ -n "${SUDO_USER}" -a -n "${SUDO_PS1}" ]; then'; \
        echo "export PS1='\[\e[;31m\]dev:\[\e[m\] \[\e[;32m\]\u@\h:\w \$ \[\e[m\]'"; \
        echo 'fi'; \
    } >> /etc/bash.bashrc

RUN groupadd -g 20000 container && \
    useradd -g 20000 -u 200000 -m -s /bin/bash container && \
    cp /root/.bashrc /home/container/.bashrc && \
    cp /root/.profile /home/container/.profile && \
    chown -R container:container /home/container

EXPOSE 8080

HEALTHCHECK --interval=1m --timeout=5s --start-period=10s --retries=3 \
    CMD ["wget", "-q", "-O", "-", "http://localhost:8080/"]

CMD ["/startup.sh"]