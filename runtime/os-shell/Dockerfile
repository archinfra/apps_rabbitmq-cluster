FROM docker.io/library/debian:bookworm-slim

LABEL org.opencontainers.image.title="archinfra os-shell" \
      org.opencontainers.image.description="Minimal Debian 12 helper image for middleware init containers" \
      org.opencontainers.image.source="https://github.com/archinfra/apps_rabbitmq-cluster" \
      org.opencontainers.image.version="12-r1"

SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends bash coreutils findutils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    && find / -xdev -perm /6000 -type f -exec chmod a-s {} \; || true

USER 0
CMD ["/bin/bash"]
