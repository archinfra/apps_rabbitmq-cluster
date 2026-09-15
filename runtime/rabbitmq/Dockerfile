# syntax=docker/dockerfile:1.7

ARG DEBIAN_BASE=docker.io/library/debian:bookworm-slim

FROM ${DEBIAN_BASE} AS erlang-builder
ARG ERLANG_VERSION=27.3.4.16
ARG ERLANG_SHA256=b945362f125ecdba4281723595f08716808bafd9137ad153f12e1db917ce8517
SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install -y --no-install-recommends \
      autoconf ca-certificates curl dpkg-dev gcc g++ libncurses-dev libsctp-dev libssl-dev make perl unixodbc-dev \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/otp.tar.gz \
      "https://github.com/erlang/otp/releases/download/OTP-${ERLANG_VERSION}/otp_src_${ERLANG_VERSION}.tar.gz" \
    && echo "${ERLANG_SHA256}  /tmp/otp.tar.gz" | sha256sum -c - \
    && mkdir -p /usr/src/otp \
    && tar -xzf /tmp/otp.tar.gz -C /usr/src/otp --strip-components=1 \
    && cd /usr/src/otp \
    && ./otp_build autoconf \
    && gnu_arch="$(dpkg-architecture --query DEB_HOST_GNU_TYPE)" \
    && ./configure \
         --build="${gnu_arch}" \
         --prefix=/opt/bitnami/erlang \
         --without-javac \
         --without-wx \
    && make -j"$(nproc)" \
    && make install \
    && /opt/bitnami/erlang/bin/erl -noshell -eval 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().' \
    && rm -rf /tmp/otp.tar.gz /usr/src/otp

FROM ${DEBIAN_BASE} AS rabbitmq-dist
ARG RABBITMQ_VERSION=4.3.6
ARG RABBITMQ_SHA256=aa0ff5de9ff0136dc42eba21dc3a973cc3b286437cdba0f45556e890509c1614
SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/rabbitmq.tar.xz \
      "https://github.com/rabbitmq/rabbitmq-server/releases/download/v${RABBITMQ_VERSION}/rabbitmq-server-generic-unix-${RABBITMQ_VERSION}.tar.xz" \
    && echo "${RABBITMQ_SHA256}  /tmp/rabbitmq.tar.xz" | sha256sum -c - \
    && mkdir -p /opt/bitnami \
    && tar -xJf /tmp/rabbitmq.tar.xz -C /tmp \
    && rabbitmq_dir="$(find /tmp -maxdepth 1 -type d -name 'rabbitmq_server-*' -print -quit)" \
    && test -n "${rabbitmq_dir}" \
    && mv "${rabbitmq_dir}" /opt/bitnami/rabbitmq \
    && test -x /opt/bitnami/rabbitmq/sbin/rabbitmq-server \
    && rm -f /tmp/rabbitmq.tar.xz

FROM ${DEBIAN_BASE} AS bitnami-source
ARG BITNAMI_CONTAINERS_REF=bcdcdbfba18dbd3483588fb1900f7a4aee9bb450
SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*
RUN git init /src/bitnami-containers \
    && cd /src/bitnami-containers \
    && git remote add origin https://github.com/bitnami/containers.git \
    && git config core.sparseCheckout true \
    && printf '%s\n' 'bitnami/rabbitmq/4.3/debian-12/' > .git/info/sparse-checkout \
    && git fetch --depth 1 origin "${BITNAMI_CONTAINERS_REF}" \
    && git checkout --detach FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${BITNAMI_CONTAINERS_REF}"

FROM ${DEBIAN_BASE}
ARG TARGETARCH
ARG RABBITMQ_VERSION=4.3.6
ARG ERLANG_VERSION=27.3.4.16
ARG BITNAMI_CONTAINERS_REF=bcdcdbfba18dbd3483588fb1900f7a4aee9bb450

LABEL org.opencontainers.image.title="archinfra RabbitMQ" \
      org.opencontainers.image.description="Archinfra-owned RabbitMQ Cluster runtime with transitional Bitnami shell compatibility" \
      org.opencontainers.image.source="https://github.com/archinfra/apps_rabbitmq-cluster" \
      org.opencontainers.image.version="4.3.6-r1" \
      io.archinfra.rabbitmq.version="4.3.6" \
      io.archinfra.erlang.version="27.3.4.16" \
      io.archinfra.bitnami.compat-ref="${BITNAMI_CONTAINERS_REF}"

ENV HOME="/opt/bitnami/rabbitmq/.rabbitmq" \
    OS_ARCH="${TARGETARCH:-amd64}" \
    OS_FLAVOUR="debian-12" \
    OS_NAME="linux" \
    PATH="/opt/bitnami/erlang/bin:/opt/bitnami/rabbitmq/sbin:$PATH" \
    APP_VERSION="4.3.6" \
    BITNAMI_APP_NAME="rabbitmq" \
    IMAGE_REVISION="archinfra.1" \
    LANG="C.UTF-8" \
    LANGUAGE="C.UTF-8"

SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates curl hostname libgcc-s1 libncurses6 libsctp1 libssl3 libstdc++6 libtinfo6 locales procps zlib1g \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY --from=erlang-builder /opt/bitnami/erlang /opt/bitnami/erlang
COPY --from=rabbitmq-dist /opt/bitnami/rabbitmq /opt/bitnami/rabbitmq
COPY --from=bitnami-source /src/bitnami-containers/bitnami/rabbitmq/4.3/debian-12/prebuildfs /
COPY --from=bitnami-source /src/bitnami-containers/bitnami/rabbitmq/4.3/debian-12/rootfs /

RUN sed -i '/^cluster_partition_handling = ${RABBITMQ_CLUSTER_PARTITION_HANDLING}$/d' /opt/bitnami/scripts/librabbitmq.sh \
    && ! grep -Fq 'cluster_partition_handling = ${RABBITMQ_CLUSTER_PARTITION_HANDLING}' /opt/bitnami/scripts/librabbitmq.sh \
    && mkdir -p \
      /bitnami/rabbitmq \
      /opt/bitnami/rabbitmq/.rabbitmq \
      /opt/bitnami/rabbitmq/etc/rabbitmq \
      /opt/bitnami/rabbitmq/etc/rabbitmq.default \
      /opt/bitnami/rabbitmq/var/lib/rabbitmq \
      /opt/bitnami/rabbitmq/var/log/rabbitmq \
    && rm -rf /opt/bitnami/checksums \
    && /opt/bitnami/scripts/rabbitmq/postunpack.sh \
    && chmod g+rwX /opt/bitnami /bitnami \
    && find / -xdev -perm /6000 -type f -exec chmod a-s {} \; || true

RUN /opt/bitnami/erlang/bin/erl -noshell -eval 'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().' \
    && /opt/bitnami/rabbitmq/sbin/rabbitmqctl --version | grep -F "${RABBITMQ_VERSION}"

EXPOSE 4369 5551 5552 5671 5672 9419 15671 15672 25672
USER 1001
ENTRYPOINT ["/opt/bitnami/scripts/rabbitmq/entrypoint.sh"]
CMD ["/opt/bitnami/scripts/rabbitmq/run.sh"]
