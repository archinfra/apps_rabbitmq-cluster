# Runtime Ownership

The production RabbitMQ image is owned by archinfra.

The first 4.3 release keeps the Bitnami runtime contract only as a compatibility boundary for the existing chart templates. This means paths such as `/opt/bitnami/scripts/rabbitmq/entrypoint.sh`, `/opt/bitnami/scripts/rabbitmq/run.sh`, password-file handling, plugin preparation, health checks, and graceful shutdown behavior remain available while the underlying RabbitMQ/Erlang distribution is moved out of the legacy image supply chain.

## Keep initially

- non-root UID 1001
- `*_FILE` secret handling
- entrypoint/setup/run lifecycle
- Kubernetes peer discovery wiring
- plugin preparation
- TLS/LDAP/load-definition behavior
- graceful node shutdown and health checks

## Replace over time

- Bitnami-specific binary download mechanism
- broad generic helper libraries once behavior is covered by tests
- `/opt/bitnami` naming after chart templates no longer depend on it

## Release rule

No compatibility helper may be removed until native amd64/arm64 E2E tests cover the behavior it provides.
