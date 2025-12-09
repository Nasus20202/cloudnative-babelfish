# CloudNativePG-compatible Babelfish for PostgreSQL
        -DCMAKE_CXX_STANDARD=17 \
    && cmake --build build --target antlr4_shared -j${JOBS} \
    && cmake --install build \
    && ldconfig

# Build PostgreSQL with Babelfish patches and extensions
WORKDIR /build/${BABELFISH_VERSION}
RUN ./configure \
    --prefix=${BABELFISH_HOME} \
    --with-ldap --with-libxml --with-pam --with-uuid=ossp \
    --enable-nls --with-libxslt --with-icu --with-openssl \
    --with-gssapi --with-lz4 --with-zstd \
    CFLAGS="-O2" \
    && make -j${JOBS} world-bin \
    && make install-world-bin \
    && cd contrib \
    && make -j${JOBS} && make install

# Copy ANTLR runtime and build ANTLR parser
RUN ANTLR4_VERSION=$(cat /tmp/antlr_version) \
    && cp /usr/local/lib/libantlr4-runtime.so.${ANTLR4_VERSION} ${BABELFISH_HOME}/lib/ \
    && cd /build/${BABELFISH_VERSION}/contrib/babelfishpg_tsql/antlr \
    && cmake -Wno-dev . && make all

# Build Babelfish extensions in sequence
RUN cd /build/${BABELFISH_VERSION}/contrib/babelfishpg_common \
    && make -j${JOBS} && make PG_CONFIG=${PG_CONFIG} install \
    && cd ../babelfishpg_money \
    && make -j${JOBS} && make PG_CONFIG=${PG_CONFIG} install \
    && cd ../babelfishpg_tds \
    && make -j${JOBS} && make PG_CONFIG=${PG_CONFIG} install \
    && cd ../babelfishpg_tsql \
    && sed -i 's/-Werror//g' Makefile src/Makefile 2>/dev/null || true \
    && make -j${JOBS} && make PG_CONFIG=${PG_CONFIG} install

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

# Install runtime dependencies and barman-cloud
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 openssl 'libldap-2*' libxml2 libpam0g uuid-runtime \
    libossp-uuid16 libxslt1.1 'libicu*' libpq5 unixodbc \
    'libreadline*' zlib1g libkrb5-3 liblz4-1 libzstd1 \
    locales python3 python3-pip python3-setuptools \
    gcc python3-dev libpq-dev procps coreutils ca-certificates \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# Copy PostgreSQL and Babelfish binaries from builder
COPY --from=builder ${BABELFISH_HOME} ${BABELFISH_HOME}

# Create symlinks and configure library path
RUN for bin in initdb postgres pg_ctl pg_controldata pg_basebackup psql \
               pg_dump pg_dumpall pg_restore pg_isready pg_rewind pg_archivecleanup; do \
        ln -sf ${BABELFISH_HOME}/bin/$bin /usr/bin/$bin; \
    done \
    && echo "${BABELFISH_HOME}/lib" > /etc/ld.so.conf.d/babelfish.conf && ldconfig

# Install barman-cloud
RUN pip3 install --no-cache-dir --break-system-packages \
    barman[cloud,azure,google,snappy] \
    && rm -rf /root/.cache \
    && apt-get purge -y --auto-remove gcc python3-dev libpq-dev

# Create postgres user with UID 26 and setup directories
RUN (groupadd -r postgres --gid=26 2>/dev/null || groupmod -n postgres $(getent group 26 | cut -d: -f1) 2>/dev/null || true) \
    && (useradd -r -g postgres --uid=26 --home-dir=/var/lib/postgresql --shell=/bin/bash postgres 2>/dev/null || usermod -l postgres -d /var/lib/postgresql $(getent passwd 26 | cut -d: -f1) 2>/dev/null || true) \
    && mkdir -p /var/lib/postgresql ${PGDATA} /var/run/postgresql \
    && chown -R 26:26 /var/lib/postgresql /var/run/postgresql ${BABELFISH_HOME} \
    && chmod 700 ${PGDATA} \
    && chmod 2777 /var/run/postgresql

# Expose PostgreSQL and TDS ports
EXPOSE 5432 1433

# Switch to postgres user
USER 26

# Set working directory
WORKDIR /var/lib/postgresql
