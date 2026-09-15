#!/usr/bin/env python3

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
chart = (ROOT / "charts/rabbitmq/Chart.yaml").read_text()
values = (ROOT / "charts/rabbitmq/values-archinfra.yaml").read_text()
config_secret = (ROOT / "charts/rabbitmq/templates/config-secret.yaml").read_text()
installer = (ROOT / "install.sh").read_text()
build = (ROOT / "build.sh").read_text()
upstream = (ROOT / "UPSTREAM.yaml").read_text()
version = (ROOT / "VERSION").read_text()
runtime = (ROOT / "runtime/rabbitmq/Dockerfile").read_text()
helper = (ROOT / "runtime/os-shell/Dockerfile").read_text()
images = json.loads((ROOT / "images/image.json").read_text())

for marker in [
    "version: 16.0.16-archinfra.1",
    "appVersion: 4.3.6",
    "archinfra.io/upstream-chart: bitnami/rabbitmq@16.0.16",
    "archinfra.io/runtime-contract: bitnami-rabbitmq-runtime-v1",
]:
    if marker not in chart:
        raise SystemExit(f"chart fork mismatch: missing {marker!r}")

for marker in [
    "version: 4.3.6",
    "version: 27.3.4.16",
    "direct41To43: false",
    "requireStableFeatureFlagsBeforeSeriesUpgrade: true",
    "bcdcdbfba18dbd3483588fb1900f7a4aee9bb450",
    "aa0ff5de9ff0136dc42eba21dc3a973cc3b286437cdba0f45556e890509c1614",
    "b945362f125ecdba4281723595f08716808bafd9137ad153f12e1db917ce8517",
]:
    if marker not in upstream:
        raise SystemExit(f"UPSTREAM.yaml mismatch: missing {marker!r}")

for marker in [
    "installer:\n  version: 0.2.0",
    "rabbitmq:\n  version: 4.3.6",
    "erlang:\n  version: 27.3.4.16",
]:
    if marker not in version:
        raise SystemExit(f"VERSION mismatch: missing {marker!r}")

for marker in [
    "ERLANG_VERSION=27.3.4.16",
    "RABBITMQ_VERSION=4.3.6",
    "b945362f125ecdba4281723595f08716808bafd9137ad153f12e1db917ce8517",
    "aa0ff5de9ff0136dc42eba21dc3a973cc3b286437cdba0f45556e890509c1614",
    "bcdcdbfba18dbd3483588fb1900f7a4aee9bb450",
    "rabbitmq-server-generic-unix-${RABBITMQ_VERSION}.tar.xz",
    "/opt/bitnami/scripts/rabbitmq/entrypoint.sh",
    "USER 1001",
    "cluster_partition_handling = ${RABBITMQ_CLUSTER_PARTITION_HANDLING}",
]:
    if marker not in runtime:
        raise SystemExit(f"runtime contract mismatch: missing {marker!r}")

if "FROM bitnami/" in runtime or "bitnamilegacy" in runtime:
    raise SystemExit("production runtime must not inherit Bitnami binary images")
if "sed -i '/^cluster_partition_handling" not in runtime:
    raise SystemExit("RabbitMQ 4.3 runtime must remove obsolete partition-handling configuration")

for marker in [
    'semverCompare ">=4.3.0-0"',
    "regexReplaceAll",
    'dig "archinfra" "diskFreeLimit"',
    "disk_free_limit.absolute = %s",
]:
    if marker not in config_secret:
        raise SystemExit(f"RabbitMQ 4.3 config adaptation mismatch: missing {marker!r}")

for marker in [
    "diskFreeLimit: 2GB",
    "usePasswordFiles: true",
    "existingSecretPasswordKey: rabbitmq-password",
    "existingSecretErlangKey: rabbitmq-erlang-cookie",
    "memoryHighWatermark:\n  enabled: true\n  type: absolute\n  value: 1280Mi",
    "rabbitmq:4.3.6-r1",
    "os-shell",
    "tag: 12-r1",
    "monitoring.archinfra.io/stack: default",
]:
    if marker not in values and marker not in chart:
        raise SystemExit(f"production values mismatch: missing {marker!r}")

for marker in [
    'APP_VERSION="0.2.0"',
    'RABBITMQ_PASSWORD=""',
    'RABBITMQ_ERLANG_COOKIE=""',
    'REGISTRY_USER=""',
    'REGISTRY_PASS=""',
    "--existing-secret",
    "--password-file",
    "--erlang-cookie-file",
    "--rotate-password",
    "--rotate-erlang-cookie",
    "--registry-password-file",
    'auth.existingPasswordSecret=${RABBITMQ_SECRET_NAME}',
    'auth.existingErlangSecret=${RABBITMQ_SECRET_NAME}',
    '--set "usePasswordFiles=true"',
    '-f "${CHART_DIR}/values-archinfra.yaml"',
    "Direct RabbitMQ 4.1.x -> 4.3.x upgrade is unsupported",
    "RabbitMQ 4.2.x -> 4.3.x requires feature-flag/Khepri preflight",
    "Scaling ${sts} to 0 before Erlang cookie rotation",
    "memoryHighWatermark.value=640Mi",
    "memoryHighWatermark.value=1280Mi",
    "memoryHighWatermark.value=2560Mi",
    "archinfra.diskFreeLimit=1GB",
    "archinfra.diskFreeLimit=2GB",
    "archinfra.diskFreeLimit=4GB",
]:
    if marker not in installer:
        raise SystemExit(f"installer contract mismatch: missing {marker!r}")

for forbidden in [
    "RabbitMQ@Passw0rd",
    "ArchInfraRabbitMQCookie2026",
    'REGISTRY_USER="admin"',
    'REGISTRY_PASS="passw0rd"',
    '--set-string "auth.password=${RABBITMQ_PASSWORD}"',
    '--set-string "auth.erlangCookie=${RABBITMQ_ERLANG_COOKIE}"',
]:
    if forbidden in installer:
        raise SystemExit(f"forbidden credential pattern remains: {forbidden!r}")

if "command -v jq" in installer or "jq " in installer:
    raise SystemExit("target installer must not require jq")
if 'build_context="$(jq -r' not in build:
    raise SystemExit("build.sh must support archinfra-owned image build contexts")

if "/bin/bash" not in helper or "findutils" not in helper:
    raise SystemExit("os-shell helper must satisfy chart bash/find/xargs contract")

for arch in ("amd64", "arm64"):
    entries = [item for item in images if item.get("arch") == arch]
    if len(entries) != 2:
        raise SystemExit(f"expected exactly 2 image entries for {arch}, got {len(entries)}")
    for item in entries:
        if item.get("platform") != f"linux/{arch}":
            raise SystemExit(f"platform mismatch: {item}")
        if bool(item.get("pull")) == bool(item.get("build")):
            raise SystemExit(f"image must have exactly one source: {item}")
        if "bitnamilegacy" in json.dumps(item) or "bitnami/rabbitmq" in json.dumps(item):
            raise SystemExit(f"production BOM still depends on Bitnami RabbitMQ image: {item}")

rabbitmq_entries = [i for i in images if i["tar"].startswith("rabbitmq-")]
helper_entries = [i for i in images if i["tar"].startswith("os-shell-")]
if any(i.get("build") != "runtime/rabbitmq" for i in rabbitmq_entries):
    raise SystemExit("RabbitMQ runtime must be built by archinfra CI")
if any(i.get("build") != "runtime/os-shell" for i in helper_entries):
    raise SystemExit("RabbitMQ helper must be built by archinfra CI")

print("archinfra rabbitmq production contract: OK")
