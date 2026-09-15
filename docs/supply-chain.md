# RabbitMQ Runtime Supply Chain

The target RabbitMQ 4.3 runtime removes the historical `bitnamilegacy` binary dependency.

## Planned composition

- Erlang/OTP: built from a pinned upstream source release
- RabbitMQ: official RabbitMQ generic UNIX distribution for the pinned RabbitMQ release
- Compatibility shell: public Bitnami 4.3 runtime scripts, retained temporarily to preserve the existing chart contract
- Final runtime: Debian 12, non-root UID 1001, archinfra-owned image

Every downloaded release artifact must be pinned and checksum-verified. The Bitnami binary component download mechanism is not part of the production runtime supply chain.
