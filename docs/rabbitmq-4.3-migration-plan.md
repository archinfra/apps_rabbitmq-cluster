# RabbitMQ 4.3 Migration Plan

This repository is migrating from the historical RabbitMQ 4.1.3 / Bitnami Legacy delivery baseline to an archinfra-owned RabbitMQ 4.3 production baseline.

## Target baseline

- RabbitMQ 4.3.6
- Erlang/OTP 27.3.4
- Debian 12 runtime
- non-root runtime UID 1001
- amd64 and arm64 native CI
- Secret-first RabbitMQ password and Erlang cookie
- archinfra-owned runtime image with a transitional Bitnami-compatible shell contract

## Important upgrade constraint

A running RabbitMQ 4.1.x cluster must not be upgraded directly to 4.3.x. The supported series path is:

```text
4.1.x -> 4.2.x -> 4.3.x
```

Before crossing a feature-flag boundary, all stable feature flags required by the target series must be enabled and cluster health must be verified.

## RabbitMQ 4.3 semantic changes

RabbitMQ 4.3 uses Khepri as its metadata store and removes Mnesia-era partition-handling semantics. The chart fork must therefore be reviewed for settings and environment variables that were historically tied to Mnesia or classic partition handling instead of only changing the image tag.

## Delivery strategy

1. Fork the existing Bitnami-derived chart as the archinfra baseline.
2. Build and own the RabbitMQ runtime image while keeping the current `/opt/bitnami/...` runtime contract temporarily.
3. Replace fixed credentials with Kubernetes Secret files.
4. Add production memory/disk guardrails and quorum-queue guidance.
5. Add native amd64/arm64 runtime and real three-node cluster E2E gates.
6. Add an explicit 4.1 -> 4.2 -> 4.3 upgrade test path before supporting in-place upgrades from the historical release.
7. Gradually replace Bitnami helper scripts with archinfra-owned equivalents after behavior is covered by tests.
