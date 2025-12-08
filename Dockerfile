# CloudNativePG-compatible Babelfish for PostgreSQL
# Multi-stage build for minimal runtime image
#
# Build args:
#   BABELFISH_VERSION: Babelfish release tag (e.g., BABEL_5_3_0__PG_17_6)
#   PG_MAJOR: PostgreSQL major version (15, 16, or 17)

ARG DEBIAN_VERSION=trixie

# =============================================================================
# Stage 1: Builder - Compile PostgreSQL with Babelfish extensions
# =============================================================================
FROM debian:${DEBIAN_VERSION}-slim AS builder

ARG BABELFISH_VERSION=BABEL_5_3_0__PG_17_6
ARG PG_MAJOR=17
ARG JOBS=4

ENV DEBIAN_FRONTEND=noninteractive
ENV BABELFISH_HOME=/opt/babelfish
ENV PG_CONFIG=${BABELFISH_HOME}/bin/pg_config

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    flex \
    bison \
    libxml2-dev \
    libxml2-utils \
    libxslt-dev \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libldap2-dev \
    libpam0g-dev \
    gettext \
    uuid-dev \
    cmake \
    lld \
    libossp-uuid-dev \
    gnulib \
    xsltproc \
    icu-devtools \
    libicu-dev \
    gawk \
    curl \
    openjdk-21-jre-headless \
    openssl \
    g++ \
    python3-dev \
    libpq-dev \
    pkg-config \
    libutfcpp-dev \
    gnupg \
    unixodbc-dev \
    net-tools \
    unzip \
    wget \
    ca-certificates \
    libkrb5-dev \
    liblz4-dev \
    libzstd-dev \
    && rm -rf /var/lib/apt/lists/*

# Download Babelfish sources
WORKDIR /build
ENV BABELFISH_REPO=babelfish-for-postgresql/babelfish-for-postgresql
ENV BABELFISH_URL=https://github.com/${BABELFISH_REPO}

RUN wget -q ${BABELFISH_URL}/releases/download/${BABELFISH_VERSION}/${BABELFISH_VERSION}.tar.gz \
    && tar -xzf ${BABELFISH_VERSION}.tar.gz \
    && rm ${BABELFISH_VERSION}.tar.gz

ENV PG_SRC=/build/${BABELFISH_VERSION}

# Build ANTLR4 C++ runtime
# Detect ANTLR version from the Babelfish source (varies by version: 4.9.3 for PG15, 4.13.2 for PG16+)
WORKDIR /build

ENV ANTLR4_JAVA_BIN=/usr/bin/java

RUN ANTLR_JAR=$(ls ${PG_SRC}/contrib/babelfishpg_tsql/antlr/thirdparty/antlr/antlr-*-complete.jar) \
    && ANTLR4_VERSION=$(basename "$ANTLR_JAR" | sed 's/antlr-\(.*\)-complete.jar/\1/') \
    && echo "Detected ANTLR version: ${ANTLR4_VERSION}" \
    && cp "$ANTLR_JAR" /usr/local/lib/ \
    && wget -q http://www.antlr.org/download/antlr4-cpp-runtime-${ANTLR4_VERSION}-source.zip \
    && unzip -q -d antlr4-runtime antlr4-cpp-runtime-${ANTLR4_VERSION}-source.zip \
    && rm antlr4-cpp-runtime-${ANTLR4_VERSION}-source.zip \
    && echo "${ANTLR4_VERSION}" > /tmp/antlr_version \
    && mkdir -p /build/antlr4-runtime/build \
    && cd /build/antlr4-runtime/build \
    && cmake .. \
        -DANTLR_JAR_LOCATION=/usr/local/lib/antlr-${ANTLR4_VERSION}-complete.jar \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DWITH_DEMO=False \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_TESTS=OFF \
        -DCMAKE_CXX_STANDARD=17 \
    && make -j${JOBS} antlr4_shared \
    && make install \
    && ldconfig

WORKDIR /build

# Build PostgreSQL with Babelfish patches
WORKDIR ${PG_SRC}

RUN ./configure \
    --prefix=${BABELFISH_HOME} \
    --with-ldap \
    --with-libxml \
    --with-pam \
    --with-uuid=ossp \
    --enable-nls \
    --with-libxslt \
    --with-icu \
    --with-openssl \
    --with-gssapi \
    --with-lz4 \
    --with-zstd \
    CFLAGS="-O2" \
    && make -j${JOBS} world-bin \
    && make install-world-bin

# Build contrib modules
WORKDIR ${PG_SRC}/contrib
RUN make -j${JOBS} && make install

# Copy ANTLR runtime library (version detected earlier)
RUN ANTLR4_VERSION=$(cat /tmp/antlr_version) \
    && cp /usr/local/lib/libantlr4-runtime.so.${ANTLR4_VERSION} ${BABELFISH_HOME}/lib/

# Build ANTLR parser for Babelfish
WORKDIR ${PG_SRC}/contrib/babelfishpg_tsql/antlr
RUN cmake -Wno-dev . && make all

# Build Babelfish extensions
# Note: We disable -Werror to prevent warnings from failing the build
# This is needed due to stricter compiler warnings in newer GCC versions
ENV CFLAGS="-O2 -Wall -Wno-error"

WORKDIR ${PG_SRC}/contrib/babelfishpg_common
RUN make -j${JOBS} && make PG_CONFIG=${PG_CONFIG} install

WORKDIR ${PG_SRC}/contrib/babelfishpg_money
RUN make -j${JOBS} && make PG_CONFIG=${PG_CONFIG} install

WORKDIR ${PG_SRC}/contrib/babelfishpg_tds
RUN make -j${JOBS} && make PG_CONFIG=${PG_CONFIG} install

# For babelfishpg_tsql, we need to patch out -Werror from the Makefile
WORKDIR ${PG_SRC}/contrib/babelfishpg_tsql
RUN sed -i 's/-Werror//g' Makefile src/Makefile 2>/dev/null || true \
    && make -j${JOBS} && make PG_CONFIG=${PG_CONFIG} install

# =============================================================================
# Stage 2: Runtime - Minimal CloudNativePG-compatible image
# =============================================================================
FROM debian:${DEBIAN_VERSION}-slim AS runtime

ARG PG_MAJOR=17
ARG BABELFISH_VERSION=BABEL_5_3_0__PG_17_6

ENV DEBIAN_FRONTEND=noninteractive
ENV BABELFISH_HOME=/opt/babelfish
ENV PATH=${BABELFISH_HOME}/bin:$PATH
ENV PGDATA=/var/lib/postgresql/data
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Labels for CloudNativePG
LABEL maintainer="CloudNative Babelfish Contributors"
LABEL org.opencontainers.image.title="CloudNativePG Babelfish"
LABEL org.opencontainers.image.description="CloudNativePG-compatible PostgreSQL with Babelfish extensions"
LABEL org.opencontainers.image.source="https://github.com/nasus20202/cloudnative-babelfish"
LABEL org.opencontainers.image.vendor="CloudNative Babelfish"
LABEL org.opencontainers.image.version="${BABELFISH_VERSION}"
LABEL org.opencontainers.image.licenses="Apache-2.0"

# Install runtime dependencies and barman-cloud for CloudNativePG
# Use wildcard patterns to handle different Debian versions (bookworm vs trixie)
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Runtime libraries
    libssl3 \
    openssl \
    'libldap-2*' \
    libxml2 \
    libpam0g \
    uuid-runtime \
    libossp-uuid16 \
    libxslt1.1 \
    'libicu*' \
    libpq5 \
    unixodbc \
    'libreadline*' \
    zlib1g \
    libkrb5-3 \
    liblz4-1 \
    libzstd1 \
    # Locale support
    locales \
    # Barman cloud for CloudNativePG backup/restore
    python3 \
    python3-pip \
    python3-setuptools \
    # Build deps for psycopg2 (needed by barman)
    gcc \
    python3-dev \
    libpq-dev \
    # Utilities
    procps \
    coreutils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Generate locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

# Copy PostgreSQL and Babelfish binaries from builder
COPY --from=builder ${BABELFISH_HOME} ${BABELFISH_HOME}

# Create symlinks for CloudNativePG compatibility
# CloudNativePG expects binaries in standard locations
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
    && ln -sf ${BABELFISH_HOME}/bin/pg_archivecleanup /usr/bin/pg_archivecleanup

# Set library path
RUN echo "${BABELFISH_HOME}/lib" > /etc/ld.so.conf.d/babelfish.conf && ldconfig

# Install barman-cloud (required by CloudNativePG)
# Must be after copying PostgreSQL binaries so pg_config is available
RUN pip3 install --no-cache-dir --break-system-packages \
    barman[cloud,azure,google,snappy] \
    && rm -rf /root/.cache

# Create postgres user with UID 26 (CloudNativePG standard)
# Use -f flag to allow existing GID, or create if not exists
RUN (groupadd -r postgres --gid=26 2>/dev/null || groupmod -n postgres $(getent group 26 | cut -d: -f1) 2>/dev/null || true) \
    && (useradd -r -g postgres --uid=26 --home-dir=/var/lib/postgresql --shell=/bin/bash postgres 2>/dev/null || usermod -l postgres -d /var/lib/postgresql $(getent passwd 26 | cut -d: -f1) 2>/dev/null || true) \
    && mkdir -p /var/lib/postgresql \
    && chown -R 26:26 /var/lib/postgresql \
    && mkdir -p /var/run/postgresql \
    && chown -R 26:26 /var/run/postgresql \
    && chmod 2777 /var/run/postgresql

# Create data directory
RUN mkdir -p ${PGDATA} \
    && chown -R postgres:postgres ${PGDATA} \
    && chmod 700 ${PGDATA}

# Set ownership of babelfish installation
RUN chown -R postgres:postgres ${BABELFISH_HOME}

# Expose PostgreSQL and TDS ports
EXPOSE 5432 1433

# Switch to postgres user
USER 26

# Set working directory
WORKDIR /var/lib/postgresql

# Volume for data persistence
VOLUME ["/var/lib/postgresql/data"]

# No entrypoint - CloudNativePG manages the process
# For standalone use, you can override with docker run command
