# RabbitMQ Cluster Offline Installer

`apps_rabbitmq-cluster` provides a multi-arch offline `.run` installer for a RabbitMQ cluster based on the official Bitnami Helm chart. It follows the same delivery pattern as the MySQL, Redis, MinIO, Milvus, and Nacos installers in this workspace.

## What It Does

- Builds `amd64` and `arm64` offline installers
- Prepares RabbitMQ runtime images for an internal registry such as `sealos.hub:5000/kube4`
- Installs or upgrades a clustered RabbitMQ release with Helm
- Enables Prometheus metrics by default
- Enables `ServiceMonitor` by default and labels it with `monitoring.archinfra.io/stack=default`
- Supports `status`, `uninstall`, and PVC cleanup

## Defaults

- Namespace: `aict`
- Release name: `rabbitmq-cluster`
- Replicas: `3`
- Username: `admin`
- Password: `RabbitMQ@Passw0rd`
- Erlang cookie: `ArchInfraRabbitMQCookie2026`
- StorageClass: `nfs`
- Storage size: `8Gi`
- Service type: `ClusterIP`
- Metrics: `true`
- ServiceMonitor: `true`
- Internal registry prefix: `sealos.hub:5000/kube4`

## Repository Layout

- [build.sh](C:/Users/yuanyp8/Desktop/archinfra/apps_rabbitmq-cluster/build.sh)
- [install.sh](C:/Users/yuanyp8/Desktop/archinfra/apps_rabbitmq-cluster/install.sh)
- [images/image.json](C:/Users/yuanyp8/Desktop/archinfra/apps_rabbitmq-cluster/images/image.json)
- [charts/rabbitmq/Chart.yaml](C:/Users/yuanyp8/Desktop/archinfra/apps_rabbitmq-cluster/charts/rabbitmq/Chart.yaml)
- [.github/workflows/build-offline-installer.yml](C:/Users/yuanyp8/Desktop/archinfra/apps_rabbitmq-cluster/.github/workflows/build-offline-installer.yml)

## Build

The build runs best in GitHub Actions because it needs Docker, Helm, and `jq`, and it must resolve the Bitnami `common` chart dependency before packaging.

```bash
./build.sh --arch amd64
./build.sh --arch arm64
./build.sh --arch all
```

Build output:

- `dist/rabbitmq-cluster-installer-amd64.run`
- `dist/rabbitmq-cluster-installer-amd64.run.sha256`
- `dist/rabbitmq-cluster-installer-arm64.run`
- `dist/rabbitmq-cluster-installer-arm64.run.sha256`

## Install

```bash
./rabbitmq-cluster-installer-amd64.run install -y
```

Use NodePort exposure when needed:

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --service-type NodePort \
  --amqp-node-port 30672 \
  --manager-node-port 31672 \
  -y
```

Reuse images already pushed to your internal registry:

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --skip-image-prepare \
  -y
```

## Monitoring

Monitoring is enabled by default:

- `metrics.enabled=true`
- `metrics.serviceMonitor.default.enabled=true`
- `metrics.serviceMonitor.labels.monitoring.archinfra.io/stack=default`

If the target cluster does not have the `ServiceMonitor` CRD, the installer will automatically disable `ServiceMonitor` creation and continue the deployment.

## GitHub Actions

The workflow builds both architectures on `main/master`, and publishes release assets when a `v*` tag is pushed.

See:

- [.github/workflows/build-offline-installer.yml](C:/Users/yuanyp8/Desktop/archinfra/apps_rabbitmq-cluster/.github/workflows/build-offline-installer.yml)

## Notes

- The installer runtime does not depend on `jq`
- The build process does depend on `jq`, `docker`, and `helm`
- The packaged Helm chart uses the official Bitnami RabbitMQ chart and resolves the `common` dependency during CI build
