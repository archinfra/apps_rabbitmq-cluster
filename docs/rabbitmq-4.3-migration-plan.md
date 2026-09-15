# RabbitMQ 4.3 Migration Plan

This repository migrates the historical RabbitMQ 4.1.3 / Bitnami Legacy delivery baseline to an archinfra-owned RabbitMQ 4.3 production baseline.

## Target baseline

- RabbitMQ 4.3.6
- Erlang/OTP 27.3.4.16
- Debian 12 runtime
- non-root runtime UID 1001
- amd64 and arm64 native CI
- Secret-first RabbitMQ password and Erlang cookie
- archinfra-owned runtime image with a transitional Bitnami-compatible shell contract
- Khepri metadata store
- Quorum Queue failover E2E

## Supported series path

A running RabbitMQ 4.1.x cluster must **not** be upgraded directly to 4.3.x.

```text
4.1.x -> latest 4.2.x patch -> 4.3.6
```

The intermediate archinfra baseline is RabbitMQ **4.2.10**. RabbitMQ 4.2 has already reached end of community support, so it is an upgrade bridge rather than a long-lived deployment target.

The 4.3 installer fails closed when it detects 4.1.x. It only permits a 4.2.x -> 4.3.x transition after the embedded read-only preflight succeeds.

## Preflight

The offline installer embeds `scripts/rabbitmq-upgrade-preflight.sh` and exposes it directly:

```bash
./rabbitmq-cluster-installer-amd64.run preflight \
  --target-series 4.3 \
  --namespace aict \
  --release-name rabbitmq-cluster
```

The check is read-only and validates:

- all StatefulSet replicas are Ready
- RabbitMQ node ping/running/local alarms
- cluster status has no partition
- each node can be stopped without making a Quorum Queue/Stream lose quorum
- all reported feature flags are enabled
- `khepri_db` is enabled before a 4.2 -> 4.3 transition
- community plugins are surfaced for manual compatibility review
- no release series is skipped

The normal `install` action also runs this preflight automatically when it detects an existing 4.2.x cluster.

## Credential migration

A series upgrade must not silently change the Erlang cookie.

When upgrading an existing Bitnami-derived release and no explicit `--existing-secret` is provided, the installer:

1. discovers the Secret(s) currently referenced by the RabbitMQ StatefulSet and RabbitMQ-labelled Secrets;
2. finds the existing `rabbitmq-password` and `rabbitmq-erlang-cookie` values without printing them;
3. copies them into the archinfra-managed `<release>-auth` Secret;
4. points the new Chart at the managed Secret using password files.

If the old credentials cannot be identified unambiguously, the installer fails closed and requires `--existing-secret`.

This separates **software upgrade** from **credential rotation**. Password rotation remains explicit with `--rotate-password`; Erlang-cookie rotation remains an explicit downtime operation with `--rotate-erlang-cookie`.

## Recommended migration sequence

### Phase A: 4.1.x -> 4.2.10

Before upgrading:

1. back up RabbitMQ definitions and application-specific recovery data;
2. confirm all nodes are healthy and queues have the expected replicas;
3. inventory enabled community plugins;
4. validate clients against the target 4.2 release;
5. upgrade one supported release series at a time.

After the cluster is healthy on 4.2.10:

```bash
rabbitmqctl enable_feature_flag all
rabbitmqctl list_feature_flags name state
```

Confirm `khepri_db` is enabled and perform at least one healthy rolling restart if required by the feature-flag transition and application/plugin mix.

### Phase B: 4.2.10 -> 4.3.6

Run the packaged preflight first:

```bash
./rabbitmq-cluster-installer-amd64.run preflight --target-series 4.3 -n aict
```

Only after it passes, run the 4.3 installer. The installer repeats the preflight automatically before changing the release.

After rollout, validate:

```bash
rabbitmqctl cluster_status
rabbitmqctl list_feature_flags name state
rabbitmq-diagnostics -q check_running
rabbitmq-diagnostics -q check_local_alarms
```

Also perform application-level publish/consume and Quorum Queue failover checks before restoring normal traffic.

## RabbitMQ 4.3 semantic changes

RabbitMQ 4.3 uses Khepri as its metadata store and removes Mnesia-era partition-handling configuration. The fork therefore removes obsolete generated directives such as:

- `cluster_partition_handling`
- `queue_master_locator`

The transitional Bitnami shell layer can still expose historical compatibility environment names internally; those are not a reason to emit removed RabbitMQ 4.3 server configuration.

## Queue HA contract

Three RabbitMQ broker Pods do not by themselves make classic queues replicated.

For workloads that require replicated message durability, archinfra recommends **Quorum Queues**. CI creates a three-member Quorum Queue, publishes/consumes messages, deletes a queue member Pod and verifies that the queue remains usable after the cluster heals.

Do not globally force all application queues to Quorum Queues without validating application behavior, throughput, retention and resource requirements. Prefer explicit queue arguments, policies or imported definitions owned by the application/platform team.

## Storage contract

`nfs` remains an archinfra **compatibility default** for environments that depend on the historical StorageClass name. It is not presented as the preferred production storage for RabbitMQ.

For durable Quorum Queues and Streams, prefer a tested low-latency block storage class or local SSD/NVMe with well-understood failure/recovery semantics. The installer emits a warning when the selected StorageClass name contains `nfs`.

The default PVC request is 20Gi per RabbitMQ Pod. Capacity must be sized from real queue backlog/retention requirements rather than treated as a universal production size.

## Rollback boundary

Do not treat a 4.3 metadata-store migration as a normal image-tag rollback. Before each series transition, maintain an external recovery point (definitions and application-appropriate backup/replay strategy). If a migration fails after irreversible metadata changes, restore through the documented RabbitMQ recovery path instead of forcing an unsupported downgrade.
