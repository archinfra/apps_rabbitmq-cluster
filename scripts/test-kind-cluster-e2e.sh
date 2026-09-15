#!/usr/bin/env bash
set -Eeuo pipefail

RABBITMQ_IMAGE="${1:?usage: test-kind-cluster-e2e.sh <rabbitmq-image> <helper-image>}"
HELPER_IMAGE="${2:?usage: test-kind-cluster-e2e.sh <rabbitmq-image> <helper-image>}"
CLUSTER_NAME="rabbitmq-e2e-${RANDOM}"
NAMESPACE="rabbitmq-e2e"
RELEASE="rabbitmq-e2e"
PASSWORD='ArchInfra E2E #P@ss 2026'
COOKIE='ArchInfraE2ECookie2026AbCdEf0123456789'

cleanup() {
  kind delete cluster --name "${CLUSTER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for bin in kind kubectl helm python3; do command -v "$bin" >/dev/null || { echo "missing $bin" >&2; exit 1; }; done

kind create cluster --name "${CLUSTER_NAME}" --wait 180s
kind load docker-image --name "${CLUSTER_NAME}" "${RABBITMQ_IMAGE}" "${HELPER_IMAGE}"

kubectl create namespace "${NAMESPACE}" >/dev/null
kubectl create secret generic "${RELEASE}-auth" -n "${NAMESPACE}" \
  --from-literal=rabbitmq-password="${PASSWORD}" \
  --from-literal=rabbitmq-erlang-cookie="${COOKIE}" >/dev/null

image_registry="${RABBITMQ_IMAGE%%/*}"
image_tail="${RABBITMQ_IMAGE#*/}"
image_repository="${image_tail%:*}"
image_tag="${image_tail##*:}"
helper_registry="${HELPER_IMAGE%%/*}"
helper_tail="${HELPER_IMAGE#*/}"
helper_repository="${helper_tail%:*}"
helper_tag="${helper_tail##*:}"

helm upgrade --install "${RELEASE}" charts/rabbitmq \
  -n "${NAMESPACE}" \
  -f charts/rabbitmq/values-archinfra.yaml \
  --wait --timeout 12m \
  --set replicaCount=3 \
  --set-string podAntiAffinityPreset=soft \
  --set persistence.enabled=false \
  --set networkPolicy.enabled=false \
  --set metrics.serviceMonitor.default.enabled=false \
  --set metrics.prometheusRule.enabled=false \
  --set-string auth.existingPasswordSecret="${RELEASE}-auth" \
  --set-string auth.existingSecretPasswordKey=rabbitmq-password \
  --set-string auth.existingErlangSecret="${RELEASE}-auth" \
  --set-string auth.existingSecretErlangKey=rabbitmq-erlang-cookie \
  --set usePasswordFiles=true \
  --set-string image.registry="${image_registry}" \
  --set-string image.repository="${image_repository}" \
  --set-string image.tag="${image_tag}" \
  --set-string image.pullPolicy=Never \
  --set-string volumePermissions.image.registry="${helper_registry}" \
  --set-string volumePermissions.image.repository="${helper_repository}" \
  --set-string volumePermissions.image.tag="${helper_tag}" \
  --set-string volumePermissions.image.pullPolicy=Never

kubectl rollout status statefulset/${RELEASE} -n "${NAMESPACE}" --timeout=5m
[[ "$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/instance=${RELEASE} -o jsonpath='{.items[*].status.phase}' | tr ' ' '\n' | grep -c '^Running$')" -eq 3 ]]

for ordinal in 0 1 2; do
  pod="${RELEASE}-${ordinal}"
  kubectl exec -n "${NAMESPACE}" "${pod}" -- rabbitmq-diagnostics -q check_running
  kubectl exec -n "${NAMESPACE}" "${pod}" -- rabbitmq-diagnostics -q check_local_alarms
  kubectl exec -n "${NAMESPACE}" "${pod}" -- rabbitmqctl --version 2>&1 | grep -Fq '4.3.6'
done

cluster_status="$(kubectl exec -n "${NAMESPACE}" "${RELEASE}-0" -- rabbitmqctl cluster_status)"
printf '%s\n' "${cluster_status}"
for ordinal in 0 1 2; do grep -Fq "${RELEASE}-${ordinal}" <<<"${cluster_status}" || { echo "missing cluster node ${ordinal}" >&2; exit 1; }; done

api() {
  local method="$1" path="$2" body="${3:-}"
  kubectl exec -n "${NAMESPACE}" "${RELEASE}-0" -- env API_METHOD="${method}" API_PATH="${path}" API_BODY="${body}" bash -ec '
    password="$(cat /opt/bitnami/rabbitmq/secrets/rabbitmq-password)"
    args=(-fsS -u "admin:${password}" -H "content-type: application/json" -X "$API_METHOD")
    [[ -z "$API_BODY" ]] || args+=(-d "$API_BODY")
    curl "${args[@]}" "http://127.0.0.1:15672${API_PATH}"
  '
}

api PUT '/api/queues/%2F/archinfra-quorum' '{"durable":true,"arguments":{"x-queue-type":"quorum"}}' >/dev/null
queue_json="$(api GET '/api/queues/%2F/archinfra-quorum')"
python3 - "${queue_json}" <<'PY'
import json, sys
q = json.loads(sys.argv[1])
assert q.get('type') == 'quorum', q
assert q.get('durable') is True, q
assert q.get('leader'), q
members = q.get('members') or []
assert len(members) >= 3, q
print('quorum queue leader:', q.get('leader'))
print('quorum queue members:', members)
PY

publish_message() {
  local payload="$1" publish
  publish="$(api POST '/api/exchanges/%2F/amq.default/publish' "{\"properties\":{\"delivery_mode\":2},\"routing_key\":\"archinfra-quorum\",\"payload\":\"${payload}\",\"payload_encoding\":\"string\"}")"
  python3 - "${publish}" <<'PY'
import json, sys
assert json.loads(sys.argv[1]).get('routed') is True
PY
}

consume_expect() {
  local payload="$1" get
  get="$(api POST '/api/queues/%2F/archinfra-quorum/get' '{"count":1,"ackmode":"ack_requeue_false","encoding":"auto","truncate":50000}')"
  python3 - "${get}" "${payload}" <<'PY'
import json, sys
items = json.loads(sys.argv[1])
assert len(items) == 1, items
assert items[0].get('payload') == sys.argv[2], items
PY
}

publish_and_consume() {
  local payload="$1"
  publish_message "${payload}"
  consume_expect "${payload}"
}

publish_and_consume baseline-before-failover

queue_json="$(api GET '/api/queues/%2F/archinfra-quorum')"
leader_node="$(python3 - "${queue_json}" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get('leader') or '')
PY
)"
[[ -n "${leader_node}" ]] || { echo "quorum queue leader not reported" >&2; exit 1; }
leader_host="${leader_node#rabbit@}"
leader_pod="${leader_host%%.*}"

# Persist a message before terminating the current quorum leader. The test only
# passes if the message can be consumed after leader election/recovery.
publish_message durable-message-across-leader-failure

echo "Deleting quorum leader pod: ${leader_pod}"
kubectl delete pod -n "${NAMESPACE}" "${leader_pod}" --wait=true
kubectl wait --for=condition=Ready pod -n "${NAMESPACE}" "${leader_pod}" --timeout=5m
kubectl rollout status statefulset/${RELEASE} -n "${NAMESPACE}" --timeout=5m

# The API helper always executes through pod 0. If pod 0 was the deleted leader,
# give its management listener a short readiness window after Kubernetes Ready.
for _ in $(seq 1 30); do
  if api GET '/api/health/checks/ready-to-serve-clients' >/dev/null 2>&1; then break; fi
  sleep 2
done
api GET '/api/health/checks/ready-to-serve-clients' >/dev/null
consume_expect durable-message-across-leader-failure
publish_and_consume after-failover

post_queue_json="$(api GET '/api/queues/%2F/archinfra-quorum')"
python3 - "${post_queue_json}" <<'PY'
import json, sys
q = json.loads(sys.argv[1])
assert q.get('type') == 'quorum', q
assert q.get('state') == 'running', q
assert q.get('leader'), q
members = q.get('members') or []
assert len(members) >= 3, q
print('post-failover quorum leader:', q['leader'])
print('post-failover quorum members:', members)
PY

kubectl exec -n "${NAMESPACE}" "${RELEASE}-0" -- rabbitmqctl list_feature_flags name state | tee /tmp/rabbitmq-feature-flags.txt
if grep -E '[[:space:]]disabled$' /tmp/rabbitmq-feature-flags.txt; then
  echo "one or more feature flags are disabled on the 4.3 baseline" >&2
  exit 1
fi

echo "RabbitMQ three-node quorum E2E: OK"
