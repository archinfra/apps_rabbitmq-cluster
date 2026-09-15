# archinfra RabbitMQ Cluster

面向私有化、离线和生产环境的 RabbitMQ Cluster 交付仓库。

本仓库不是简单重新打包一个 Bitnami Chart，而是由 archinfra 明确接管：

- RabbitMQ / Erlang 版本基线
- RabbitMQ runtime 镜像供应链
- Helm Chart fork 与 RabbitMQ 4.3 语义适配
- Kubernetes Secret 凭据生命周期
- amd64 / arm64 原生构建
- 离线 `.run` 安装包
- 资源、水位和磁盘保护
- Prometheus / Grafana Monitoring V2
- 三节点 Quorum Queue E2E
- 存量集群跨版本升级保护

## 当前版本基线

| 组件 | 版本 / 策略 |
| --- | --- |
| RabbitMQ | `4.3.6` |
| Erlang/OTP | `27.3.4.16` |
| Helm Chart | `16.0.16-archinfra.1` |
| Upstream Chart | `bitnami/rabbitmq 16.0.16` |
| Installer | `0.2.0` |
| Runtime OS | Debian 12 |
| Runtime UID | `1001` |
| RabbitMQ image | `sealos.hub:5000/kube4/rabbitmq:4.3.6-r1` |
| Helper image | `sealos.hub:5000/kube4/os-shell:12-r1` |
| Architectures | `amd64`, `arm64` |

版本与供应链来源以 `VERSION`、`UPSTREAM.yaml` 和 `images/image.json` 为准。

## 0.2.0 主要变化

相对历史 RabbitMQ 4.1.3 / `bitnamilegacy` 交付方式，这个版本重点完成：

- RabbitMQ 升级到 `4.3.6`；
- Erlang/OTP 固定为 `27.3.4.16`；
- RabbitMQ runtime 由 archinfra 构建和维护；
- Erlang/OTP 从固定上游源码构建并校验 SHA256；
- RabbitMQ 使用官方 Generic UNIX 4.3.6 分发包并校验官方 SHA256；
- 不再把 `bitnamilegacy/rabbitmq` 作为生产二进制供应链；
- 暂时保留 Bitnami 4.3.6 的公开 shell/runtime contract，以保证 Chart 行为连续；
- RabbitMQ 4.3 配置不再生成已经淘汰的 `cluster_partition_handling` / `queue_master_locator`；
- 密码和 Erlang cookie 改成 Secret-first + `*_FILE`；
- 删除安装器内置固定 RabbitMQ / Registry 密码；
- amd64 / arm64 改为原生 runner 构建，不使用 QEMU 作为正式发布门禁；
- 增加真实三节点 Quorum Queue publish/consume/failover E2E；
- 增加 RabbitMQ 4.1 -> 4.2 -> 4.3 跨版本升级门禁；
- 增加 Monitoring V2、资源档位、memory watermark、disk free limit 和 PVC 告警。

## 供应链模型

生产 RabbitMQ runtime 的来源关系如下：

```text
Erlang/OTP 27.3.4.16 source
        |
        | source build + SHA256
        v
/opt/bitnami/erlang

RabbitMQ official generic-unix 4.3.6
        |
        | official SHA256
        v
/opt/bitnami/rabbitmq

Bitnami RabbitMQ 4.3.6 public scripts
        |
        | pinned source commit
        v
transitional runtime compatibility contract
        |
        v
archinfra rabbitmq:4.3.6-r1
```

Bitnami 在这里是 **Chart fork 来源和临时 runtime compatibility source**，不是生产 RabbitMQ 二进制供应商。

后续只有在 entrypoint/setup/run/health/graceful-shutdown/Secret/TLS/cluster 行为全部有测试覆盖后，才逐步把 `/opt/bitnami` compatibility contract 替换成 archinfra 自有 runtime contract。

## 离线安装包

正式交付物：

```text
rabbitmq-cluster-installer-amd64.run
rabbitmq-cluster-installer-amd64.run.sha256

rabbitmq-cluster-installer-arm64.run
rabbitmq-cluster-installer-arm64.run.sha256
```

`.run` 内嵌：

- RabbitMQ Helm Chart fork；
- `values-archinfra.yaml`；
- RabbitMQ runtime image tar；
- helper image tar；
- image metadata；
- RabbitMQ upgrade preflight 工具。

目标服务器 **不需要 jq**。`jq` 只允许作为构建机依赖。

## 使用帮助

```bash
./rabbitmq-cluster-installer-amd64.run --help
```

支持动作：

```text
install
preflight
status
uninstall
help
```

### 默认安装

```bash
./rabbitmq-cluster-installer-amd64.run install -y
```

默认核心参数：

| 参数 | 默认值 |
| --- | --- |
| namespace | `aict` |
| release | `rabbitmq-cluster` |
| replicas | `3` |
| username | `admin` |
| auth Secret | `rabbitmq-cluster-auth` |
| storageClass | `nfs`（兼容默认，不是生产推荐） |
| PVC | `20Gi / Pod` |
| resource profile | `mid` |
| service | `ClusterIP` |
| AMQP | `5672` |
| Management | `15672` |
| Metrics | `9419` |
| metrics | enabled |
| ServiceMonitor | enabled when CRD exists |
| PrometheusRule | enabled when CRD exists |

生产安装器要求 RabbitMQ 副本数 **至少 3 个并且为奇数**，例如 3 或 5。

## Secret-first 认证

### 首次安装

如果没有指定 Secret 或密码文件：

```bash
./rabbitmq-cluster-installer-amd64.run install -y
```

安装器会创建：

```text
rabbitmq-cluster-auth
  rabbitmq-password
  rabbitmq-erlang-cookie
```

两项值均随机生成，不打印到终端，也不会出现在 Helm CLI 参数里。

Chart 使用：

```text
auth.existingPasswordSecret
auth.existingErlangSecret
usePasswordFiles=true
RABBITMQ_PASSWORD_FILE
RABBITMQ_ERL_COOKIE_FILE
```

### 使用外部 Secret

Secret 必须包含：

```text
rabbitmq-password
rabbitmq-erlang-cookie
```

然后：

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --existing-secret rabbitmq-prod-auth \
  -y
```

如 key 名不同：

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --existing-secret rabbitmq-prod-auth \
  --secret-password-key password \
  --secret-erlang-cookie-key erlang-cookie \
  -y
```

### 从文件初始化密码

推荐文件输入，不推荐把明文密码放到 shell history：

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --password-file /secure/rabbitmq.password \
  --erlang-cookie-file /secure/rabbitmq.cookie \
  -y
```

兼容参数 `--password` / `--erlang-cookie` 仍保留，但只用于兼容场景。

### 密码轮转

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --rotate-password \
  --password-file /secure/new-rabbitmq.password \
  -y
```

### Erlang cookie 轮转

Erlang cookie 是 RabbitMQ 节点间身份凭据，不应作为普通密码随意轮换。

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --rotate-erlang-cookie \
  --erlang-cookie-file /secure/new-rabbitmq.cookie \
  -y
```

安装器会先把整个 RabbitMQ StatefulSet 缩到 0，再修改 cookie，然后整体恢复。因此这个动作意味着 **集群停机**。

## 老环境凭据迁移

升级已经存在的 Bitnami-derived RabbitMQ 时，不能在升级软件的同时默默生成新 Erlang cookie。

如果没有显式传 `--existing-secret`，安装器会：

1. 读取当前 StatefulSet 的 `rabbitmq-secrets` 引用；
2. 同时检查 RabbitMQ release label 下的 Secret；
3. 唯一确定当前 `rabbitmq-password` 和 `rabbitmq-erlang-cookie` 来源；
4. 不打印 Secret 值；
5. 复制到新的 `<release>-auth` archinfra managed Secret；
6. 再执行新 Chart upgrade。

如果密码或 cookie 来源不唯一，安装器会 fail-closed，要求管理员显式指定 `--existing-secret`。

## RabbitMQ 4.1 -> 4.3 升级

**不支持直接升级：**

```text
4.1.x  ----------------X---------------->  4.3.x
```

支持路径：

```text
4.1.x
  |
  v
4.2.10
  |
  | enable required feature flags
  | enable / verify khepri_db
  | health + quorum preflight
  v
4.3.6
```

RabbitMQ 4.2.10 在本项目里是升级桥接版本，不建议作为新的长期部署基线。

### 4.3 preflight

离线安装包可以直接运行只读检查：

```bash
./rabbitmq-cluster-installer-amd64.run preflight \
  --target-series 4.3 \
  --namespace aict \
  --release-name rabbitmq-cluster
```

它检查：

- StatefulSet 所有副本 Ready；
- `rabbitmq-diagnostics ping`；
- node running；
- local alarms；
- cluster partition；
- 每个节点是否 quorum-critical；
- feature flags 是否全部启用；
- 从 4.2 进入 4.3 前 `khepri_db` 是否启用；
- community plugin 是否需要人工确认兼容性；
- 是否跳过了 release series。

正常执行 `install` 时，如果检测到现有 RabbitMQ 4.2.x，安装器会 **自动再次运行 4.3 preflight**；只有通过才继续。

如果发现 4.1.x，则直接停止，并要求先完成 4.1 -> 4.2.10。

完整迁移流程见：

```text
docs/rabbitmq-4.3-migration-plan.md
```

## RabbitMQ 4.3 / Khepri 适配

RabbitMQ 4.3 使用 Khepri 作为 metadata store。

Chart fork 不允许继续把以下 Mnesia-era 配置写入 `rabbitmq.conf`：

```text
cluster_partition_handling
queue_master_locator
```

CI 会直接检查最终渲染后的 `rabbitmq.conf`，不是只检查 values 文件。

Bitnami compatibility shell 内部仍可能保留历史变量名，例如 `RABBITMQ_MNESIA_BASE`。这是 transitional compatibility implementation，不代表 RabbitMQ 4.3 server config 仍然使用 Mnesia。

## Queue HA 语义

**三个 RabbitMQ Pod 不等于每个队列自动三副本。**

Broker HA 与 Message HA 是两件事：

```text
Broker HA
  3+ RabbitMQ nodes

Message HA
  Quorum Queue / Stream replication
```

需要复制和 leader election 的业务队列，推荐使用 Quorum Queue。

例如声明队列时：

```json
{"x-queue-type":"quorum"}
```

不要在没有评估业务语义、吞吐、磁盘和 retention 的情况下，全局强制所有队列变成 quorum 类型。

CI 的真实 E2E 会创建三成员 Quorum Queue，并执行：

```text
publish
  -> consume
  -> identify queue leader/member
  -> delete one RabbitMQ Pod
  -> wait recovery
  -> verify message survives
  -> publish/consume again
```

## 资源档位

安装器提供：

```text
low
mid
high
```

| Profile | Request | Limit | Memory watermark | Disk free limit |
| --- | --- | --- | --- | --- |
| low | `250m / 512Mi` | `500m / 1Gi` | `640Mi` | `1GB` |
| mid | `500m / 1Gi` | `1 CPU / 2Gi` | `1280Mi` | `2GB` |
| high | `1 CPU / 2Gi` | `2 CPU / 4Gi` | `2560Mi` | `4GB` |

例如：

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --resource-profile high \
  -y
```

这里使用 **absolute memory watermark**，避免 RabbitMQ 根据节点可见宿主机内存计算出远大于容器 limit 的水位。

## 存储

默认仍保留：

```text
storageClass: nfs
```

这是为了兼容 archinfra 历史私有化环境，不代表 NFS 是 RabbitMQ 的生产首选。

安装器看到 StorageClass 名包含 `nfs` 时会明确警告。

对 Quorum Queue / Stream 等 durable workload，更推荐经过验证的：

- 低延迟 block storage；
- local SSD；
- NVMe；
- 明确验证过 fsync、故障恢复和延迟抖动的存储后端。

默认 PVC：

```text
20Gi / RabbitMQ Pod
```

三节点默认最少申请 60Gi，但实际生产容量必须按消息 backlog、retention、publisher/consumer 行为和磁盘告警策略计算。

## NetworkPolicy

生产 overlay 默认开启 NetworkPolicy，但当前仍属于 **兼容性基线**，不是零信任严格模式。

如果交付环境需要严格隔离，应显式收敛：

- AMQP 来源 namespace / pod selector；
- Management API 来源；
- Prometheus scrape 来源；
- DNS egress；
- RabbitMQ 节点间 4369 / 25672；
- 必要的外部依赖。

不要把“NetworkPolicy enabled”误解成已经完成最小权限网络隔离。

## Monitoring V2

RabbitMQ 使用内建 `rabbitmq_prometheus` 插件，不需要额外 exporter sidecar。

默认开启：

```text
metrics.enabled=true
ServiceMonitor=true (CRD 存在时)
PrometheusRule=true (CRD 存在时)
```

统一 label：

```text
monitoring.archinfra.io/stack=default
```

同时使用 RabbitMQ `/metrics/detailed` 选择性采集：

```text
queue_coarse_metrics
queue_consumer_count
ra_metrics
```

Detailed endpoint 的指标使用 `rabbitmq_detailed_` 前缀，可与标准 `/metrics` 同时使用。

### Dashboard

提供两套 Grafana dashboard：

```text
RabbitMQ / Overview
RabbitMQ / Queues & Performance
```

主要覆盖：

- target / node availability；
- memory / resident memory limit；
- disk available / disk limit；
- connections / channels；
- publish / deliver / ack / redelivery；
- queue ready / unacked；
- Quorum / Raft commit index；
- PVC 使用率。

### Alert

生产规则覆盖：

- Prometheus target down；
- cluster node missing；
- memory warning / critical；
- disk free low；
- file descriptor high；
- Erlang process high；
- ready backlog；
- unacked backlog；
- redelivery rate high；
- unroutable message；
- Raft commit lag；
- Pod repeated restart；
- OOMKilled；
- PVC 80% / 90%。

RabbitMQ 4.2+ 的 Raft metric 名称由官方 `rabbitmq_prometheus` 定义；详细 endpoint 只改变前缀为 `rabbitmq_detailed_`。

## Service 类型

默认只暴露集群内部：

```text
ClusterIP
```

内部地址通常为：

```text
AMQP        rabbitmq-cluster.aict.svc:5672
Management  rabbitmq-cluster.aict.svc:15672
Metrics     rabbitmq-cluster.aict.svc:9419
```

需要 NodePort：

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --service-type NodePort \
  --amqp-node-port 30672 \
  --manager-node-port 31672 \
  -y
```

生产环境如需外部访问，优先结合 TLS、受控入口和 NetworkPolicy，不建议直接把 Management UI 暴露给不可信网络。

## Registry

安装包默认目标镜像前缀：

```text
sealos.hub:5000/kube4
```

如果执行环境已经登录目标仓库，不需要传 registry 密码。

显式登录推荐：

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --registry harbor.example.com/kube4 \
  --registry-user robot-rabbitmq \
  --registry-password-file /secure/harbor.password \
  -y
```

不再提供任何默认：

```text
admin / passw0rd
```

如果镜像已经提前推送：

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --skip-image-prepare \
  -y
```

注意：registry push credential 与 Kubernetes `imagePullSecret` 是两套不同的认证边界。如果 Kubernetes 节点本身拉取私有仓库需要认证，应按集群规范准备 `imagePullSecret`。

## 安装后验收

### Kubernetes

```bash
kubectl get sts,pod,svc,pvc -n aict \
  -l app.kubernetes.io/instance=rabbitmq-cluster
```

### RabbitMQ cluster

```bash
kubectl exec -n aict rabbitmq-cluster-0 -- rabbitmqctl cluster_status
kubectl exec -n aict rabbitmq-cluster-0 -- rabbitmq-diagnostics -q check_running
kubectl exec -n aict rabbitmq-cluster-0 -- rabbitmq-diagnostics -q check_local_alarms
```

### Feature flags

```bash
kubectl exec -n aict rabbitmq-cluster-0 -- \
  rabbitmqctl list_feature_flags name state
```

### Secret

```bash
kubectl get secret rabbitmq-cluster-auth -n aict
```

正常运维流程不要把 Secret 值打印进工单、流水线日志或 shell history。

## Status / Uninstall

```bash
./rabbitmq-cluster-installer-amd64.run status
```

卸载 release：

```bash
./rabbitmq-cluster-installer-amd64.run uninstall -y
```

默认 **保留 PVC 和认证 Secret**。

显式删除 PVC：

```bash
./rabbitmq-cluster-installer-amd64.run uninstall --delete-pvc -y
```

删除数据卷是破坏性操作，生产环境执行前必须有明确恢复方案。

## CI / 发布门禁

### Native architecture

```text
amd64 -> ubuntu-24.04
arm64 -> ubuntu-24.04-arm
```

正式门禁不使用 QEMU 模拟 ARM。

### 每个架构都会执行

```text
production contract validation
        ->
Erlang source build
        ->
RabbitMQ runtime build
        ->
runtime contract
        ->
helper contract
        ->
3-node Kind cluster
        ->
Quorum Queue E2E + Pod failure/recovery
        ->
installer checksum
        ->
artifact upload
```

### Helm gate

Helm workflow 检查：

- fork 不允许在未加载 `values-archinfra.yaml` 时被误用；
- production values 可 lint/render；
- Secret file contract 存在；
- 不出现 `bitnamilegacy`；
- 最终 RabbitMQ 4.3 配置没有 obsolete Mnesia-era directives；
- absolute memory watermark / disk guardrail 存在；
- 两套 dashboard 可渲染。

### Artifacts 与 Release

`main` / PR 构建得到 GitHub Actions artifacts。

`v*` tag 构建在双架构门禁通过后发布 GitHub Release assets。

## 本地构建

构建机需要：

```text
docker
helm
jq
```

构建 amd64：

```bash
./build.sh --arch amd64
```

构建 arm64：

```bash
./build.sh --arch arm64
```

构建两个架构：

```bash
./build.sh --arch all
```

注意：跨架构本地构建是否能成功仍取决于本机 Docker/CPU 能否执行对应平台镜像。正式发布以 GitHub 原生架构 runner 为准。

## 重要边界

当前版本仍有几个刻意保留的边界：

1. **Bitnami runtime shell contract 仍是 transitional compatibility layer**。镜像二进制供应链已归 archinfra，但 shell contract 还没有一次性重写。
2. **NFS 是兼容默认，不是 RabbitMQ durable workload 的生产推荐。**
3. **Quorum Queue 不会被全局强制。** 队列类型属于应用与平台共同设计的消息语义。
4. **4.1 -> 4.3 绝不直接升级。** 必须经过最新 4.2.x bridge，并完成 feature flags / Khepri 检查。
5. **跨 major/minor series 的 rollback 不能当成普通镜像 tag 回滚。** 必须准备 definitions 和应用级恢复/重放方案。
6. **NetworkPolicy 当前是兼容性安全基线。** 严格生产环境仍应按业务流量收敛 ingress/egress。

## 相关文档

- `docs/rabbitmq-4.3-migration-plan.md`：4.1 -> 4.2 -> 4.3 升级流程
- `docs/runtime-ownership.md`：runtime ownership 与 Bitnami compatibility 边界
- `docs/supply-chain.md`：镜像、RabbitMQ、Erlang 来源和校验策略
- `UPSTREAM.yaml`：upstream/fork/runtime 元数据
- `VERSION`：当前交付版本矩阵
