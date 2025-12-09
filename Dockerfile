# CloudNativePG-compatible Babelfish for PostgreSQL
    && cd /build/${BABELFISH_VERSION}/contrib/babelfishpg_money \
    && make -j${JOBS} \
    && make PG_CONFIG=${PG_CONFIG} install \
    && cd /build/${BABELFISH_VERSION}/contrib/babelfishpg_tds \
    && make -j${JOBS} \
    && make PG_CONFIG=${PG_CONFIG} install \
    && cd /build/${BABELFISH_VERSION}/contrib/babelfishpg_tsql \
    && sed -i 's/-Werror//g' Makefile src/Makefile 2>/dev/null || true \
    && make -j${JOBS} \
    && make PG_CONFIG=${PG_CONFIG} install

# =============================================================================
# Stage 2: Runtime - Minimal CloudNativePG-compatible image
# =============================================================================
FROM debian:${DEBIAN_VERSION}-slim AS runtime

ARG PG_MAJOR=17
ARG BABELFISH_VERSION=BABEL_5_3_0__PG_17_6

ENV DEBIAN_FRONTEND=noninteractive \
    BABELFISH_HOME=/opt/babelfish \
    PATH=/opt/babelfish/bin:$PATH \
    PGDATA=/var/lib/postgresql/data \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Labels for CloudNativePG
LABEL maintainer="CloudNative Babelfish Contributors" \
      org.opencontainers.image.title="CloudNativePG Babelfish" \
      org.opencontainers.image.description="CloudNativePG-compatible PostgreSQL with Babelfish extensions" \
      org.opencontainers.image.source="https://github.com/nasus20202/cloudnative-babelfish" \
      org.opencontainers.image.vendor="CloudNative Babelfish" \
      org.opencontainers.image.version="${BABELFISH_VERSION}" \
      org.opencontainers.image.licenses="Apache-2.0"

# Install runtime dependencies and build tools for barman (removed after)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 openssl 'libldap-2*' libxml2 libpam0g uuid-runtime \
    libossp-uuid16 libxslt1.1 'libicu*' libpq5 unixodbc \
    'libreadline*' zlib1g libkrb5-3 liblz4-1 libzstd1 \
    locales python3 python3-pip python3-setuptools \
    gcc python3-dev libpq-dev \
    procps coreutils ca-certificates \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# Copy PostgreSQL and Babelfish binaries from builder
COPY --from=builder ${BABELFISH_HOME} ${BABELFISH_HOME}

# Create symlinks, configure library path, install barman, and cleanup in one layer
RUN ln -sf ${BABELFISH_HOME}/bin/initdb /usr/bin/initdb \
    && ln -sf ${BABELFISH_HOME}/bin/postgres /usr/bin/postgres \
    && ln -sf ${BABELFISH_HOME}/bin/pg_ctl /usr/bin/pg_ctl \
    && ln -sf ${BABELFISH_HOME}/bin/pg_controldata /usr/bin/pg_controldata \
    && ln -sf ${BABELFISH_HOME}/bin/pg_basebackup /usr/bin/pg_basebackup \
    && ln -sf ${BABELFISH_HOME}/bin/psql /usr/bin/psql \
    && ln -sf ${BABELFISH_HOME}/bin/pg_dump /usr/bin/pg_dump \
    && ln -sf ${BABELFISH_HOME}/bin/pg_dumpall /usr/bin/pg_dumpall \
    && ln -sf ${BABELFISH_HOME}/bin/pg_restore /usr/bin/pg_restore \
    && ln -sf ${BABELFISH_HOME}/bin/pg_isready /usr/bin/pg_isready \
    && ln -sf ${BABELFISH_HOME}/bin/pg_rewind /usr/bin/pg_rewind \
    && ln -sf ${BABELFISH_HOME}/bin/pg_archivecleanup /usr/bin/pg_archivecleanup \
    && echo "${BABELFISH_HOME}/lib" > /etc/ld.so.conf.d/babelfish.conf \
    && ldconfig \
    && pip3 install --no-cache-dir --break-system-packages \
        barman[cloud,azure,google,snappy] \
    && rm -rf /root/.cache \
    && apt-get purge -y --auto-remove gcc python3-dev libpq-dev

# Create postgres user and directories
RUN groupadd -r postgres --gid=26 || true \
    && useradd -r -g postgres --uid=26 --home-dir=/var/lib/postgresql --shell=/bin/bash postgres || true \
    && mkdir -p /var/lib/postgresql /var/run/postgresql ${PGDATA} \
    && chown -R 26:26 /var/lib/postgresql /var/run/postgresql ${BABELFISH_HOME} \
    && chmod 2777 /var/run/postgresql \
    && chmod 700 ${PGDATA}

# Expose PostgreSQL and TDS ports
EXPOSE 5432 1433

# Switch to postgres user
USER 26

# Set working directory
WORKDIR /var/lib/postgresql
