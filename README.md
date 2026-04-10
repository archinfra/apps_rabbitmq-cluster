# apps_rabbitmq-cluster

RabbitMQ 集群离线交付仓库。

这个仓库不是只放一个 Helm chart，而是把：

- 镜像准备
- Helm 安装
- 监控接入
- 离线 `.run` 包交付

打成了一套可以直接给使用者落地的安装方案。

它沿用了 MySQL、Redis、MinIO、Milvus、Nacos 这几套仓库已经验证过的交付范式：

- 支持 `amd64` / `arm64` 多架构离线安装包
- 安装包内嵌 chart 和镜像 payload
- 安装时显式渲染内网镜像地址
- GitHub Actions 负责构建和发布 release
- 默认开启 RabbitMQ metrics 和 `ServiceMonitor`

## 这套安装器是怎么设计的

普通使用者可以把它理解成一个“RabbitMQ 离线安装器”，核心只有 4 个动作：

- `install`
- `status`
- `uninstall`
- `help`

其中 `install` 会自动完成这些事情：

1. 解包 `.run` 里的 chart、镜像元数据和镜像 tar
2. 按目标仓库地址准备镜像
3. 检查集群是否支持 `ServiceMonitor`
4. 生成最终的 Helm 参数
5. 执行 `helm upgrade --install`
6. 输出 Pod、Service、PVC、ServiceMonitor 状态

这意味着使用者不需要自己手动处理：

- `docker load`
- `docker tag`
- `docker push`
- `helm dependency build`
- `kubectl apply ServiceMonitor`

安装器已经把这些流程编排好了。

## 默认值

当前安装器的默认业务参数如下：

- namespace: `aict`
- release name: `rabbitmq-cluster`
- replicas: `3`
- username: `admin`
- password: `RabbitMQ@Passw0rd`
- erlang cookie: `ArchInfraRabbitMQCookie2026`
- storage class: `nfs`
- storage size: `8Gi`
- service type: `ClusterIP`
- AMQP NodePort: `30672`
- management NodePort: `31672`
- metrics: `true`
- ServiceMonitor: `true`
- ServiceMonitor interval: `30s`
- resource profile: `mid`

`--resource-profile` supports `low|mid|midd|high`.

- `low`: demo or lightweight validation
- `mid`: default profile, normal shared environment, baseline for `500-1000` concurrency and about `10000` users
- `high`: higher concurrency or heavier queue workload
- registry repo: `sealos.hub:5000/kube4`
- image pull policy: `IfNotPresent`
- wait timeout: `10m`

Per-profile baseline:

| Profile | RabbitMQ pod | volumePermissions init |
| --- | --- | --- |
| `low` | `250m / 512Mi` request, `500m / 1Gi` limit | `20m / 32Mi` request, `100m / 64Mi` limit |
| `mid` | `500m / 1Gi` request, `1 / 2Gi` limit | `50m / 64Mi` request, `200m / 128Mi` limit |
| `high` | `1 / 2Gi` request, `2 / 4Gi` limit | `100m / 128Mi` request, `300m / 256Mi` limit |

Default steady-state demand with `3` replicas and no extra features is:

| Item | Total |
| --- | --- |
| CPU request | `1500m` |
| Memory request | `3Gi` |
| CPU limit | `3` |
| Memory limit | `6Gi` |

## 默认部署拓扑

如果直接执行：

```bash
./rabbitmq-cluster-installer-amd64.run install -y
```

默认会部署：

- 1 个 RabbitMQ StatefulSet
- 3 个 RabbitMQ 副本
- 1 个 headless Service
- 1 个对内访问 Service
- 3 个 PVC
- 1 个 `ServiceMonitor`（如果集群支持）

默认不会依赖：

- MySQL
- Redis
- Nacos

RabbitMQ 本身是一个独立的消息组件，其他业务系统通常只是“连接它使用 AMQP”，而不是 RabbitMQ 启动时要先依赖这些组件。

## 资源需求矩阵

RabbitMQ 这套安装器现在会显式下发 `requests/limits`，不再依赖 Bitnami chart 的默认 `resourcesPreset`。

当前默认情况是：

- 主 RabbitMQ 容器：显式 `500m / 1Gi` request，`1 / 2Gi` limit
- `volumePermissions` init 容器：显式 `50m / 64Mi` request，`200m / 128Mi` limit
- 但 `volumePermissions.enabled = false`，所以默认不会起这个 init 容器

### 默认模式资源明细

当前默认 `mid` 档位下，单个 RabbitMQ Pod 的资源大致是：

- request: `500m CPU / 1Gi memory`
- limit: `1 CPU / 2Gi memory`

所以默认 `3` 副本下，RabbitMQ 主容器的总资源大致是：

| 项目 | 单 Pod | 3 副本合计 |
| --- | --- | --- |
| CPU request | `500m` | `1500m` |
| Memory request | `1Gi` | `3Gi` |
| CPU limit | `1` | `3` |
| Memory limit | `2Gi` | `6Gi` |

### volumePermissions 说明

默认 `volumePermissions.enabled=false`，所以安装时不会额外起这个 init 容器。

如果你以后手动启用了它，默认 `mid` 档位下它的资源大致是：

- request: `50m CPU / 64Mi memory`
- limit: `200m CPU / 128Mi memory`

但这不是当前默认安装路径的一部分。

### 存储需求

当前默认是：

- 单副本 PVC: `8Gi`
- 副本数: `3`

所以默认最低持久化存储需求是：

- `24Gi`

如果你把副本数改成 `5`，则最低存储需求会变成：

- `40Gi`

## 快速开始

### 1. 看帮助

```bash
./rabbitmq-cluster-installer-amd64.run --help
./rabbitmq-cluster-installer-amd64.run help
```

### 2. 用默认参数安装

```bash
./rabbitmq-cluster-installer-amd64.run install -y
```

### 3. 查看状态

```bash
./rabbitmq-cluster-installer-amd64.run status
```

### 4. 卸载

```bash
./rabbitmq-cluster-installer-amd64.run uninstall -y
```

如果还要连 PVC 一起删除：

```bash
./rabbitmq-cluster-installer-amd64.run uninstall --delete-pvc -y
```

## 最常见的使用场景

### 场景 1：标准集群，直接安装

```bash
./rabbitmq-cluster-installer-amd64.run install -y
```

### 场景 2：需要 NodePort 暴露 AMQP 和管理台

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --service-type NodePort \
  --amqp-node-port 30672 \
  --manager-node-port 31672 \
  -y
```

### 场景 3：自定义账号密码

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --username admin \
  --password 'RabbitMQ@Passw0rd' \
  --erlang-cookie 'ArchInfraRabbitMQCookie2026' \
  -y
```

### 场景 4：镜像仓库里已经有镜像，不想重复推送

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --skip-image-prepare \
  -y
```

### 场景 5：不想启用监控

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --disable-servicemonitor \
  --disable-metrics \
  -y
```

## 监控是怎么处理的

这个仓库里，监控默认是开启的：

- `metrics.enabled=true`
- `metrics.serviceMonitor.default.enabled=true`

并且默认会带平台统一标签：

- `monitoring.archinfra.io/stack=default`

RabbitMQ 这里使用的是内建的 `rabbitmq_prometheus` 插件，不需要额外 sidecar exporter。

默认监控对象是：

- RabbitMQ 主 Service 的 `/metrics`
- 端口 `9419`
- 对应 1 个 `ServiceMonitor`

如果集群里没有 `ServiceMonitor` CRD，安装器不会直接失败，而是会自动降级：

- 保留 metrics
- 关闭 `ServiceMonitor` 资源创建

## 普通使用者最常用的参数

### 核心参数

- `-n, --namespace <ns>`
- `--release-name <name>`
- `--replicas <num>`
- `--username <name>`
- `--password <pwd>`
- `--erlang-cookie <value>`
- `--storage-class <name>`
- `--storage-size <size>`
- `--service-type <ClusterIP|NodePort|LoadBalancer>`
- `--amqp-node-port <port>`
- `--manager-node-port <port>`
- `--registry <repo-prefix>`
- `--skip-image-prepare`
- `--wait-timeout <duration>`
- `-y, --yes`

### 监控参数

- `--enable-metrics`
- `--disable-metrics`
- `--enable-servicemonitor`
- `--disable-servicemonitor`
- `--service-monitor-namespace <ns>`
- `--service-monitor-interval <value>`
- `--service-monitor-scrape-timeout <value>`

### 清理参数

- `--delete-pvc`

## 想更自定义，应该怎么做

安装器提供了 3 层自定义能力。

### 第一层：直接使用安装器参数

这是最推荐的方式，适合大多数场景。

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --namespace aict \
  --release-name rabbitmq-demo \
  --replicas 5 \
  --storage-class nfs \
  --storage-size 20Gi \
  -y
```

### 第二层：透传 Helm 参数

如果某个 chart 原生能力安装器还没封装，可以在命令末尾用 `--` 继续追加 Helm 参数。

例如：

```bash
./rabbitmq-cluster-installer-amd64.run install \
  -y \
  -- \
  --set memoryHighWatermark.enabled=true \
  --set-string memoryHighWatermark.value=0.5
```

或者：

```bash
./rabbitmq-cluster-installer-amd64.run install \
  -y \
  -- \
  --set-string loadDefinition.enabled=true
```

### 第三层：直接使用 chart

如果你不走 `.run` 包，也可以直接用仓库里的 chart。

但这个仓库的主要推荐入口仍然是 `.run` 安装器，因为它已经处理好了：

- chart 依赖
- 镜像 payload
- 内网镜像地址
- ServiceMonitor 开关
- Bitnami 镜像安全校验

## 和其他组件对接时怎么理解

如果你的系统里还有 MySQL、Redis、Nacos、Milvus 或其他业务组件，RabbitMQ 最常见的对接方式是下面这些。

### 作为业务系统的消息中间件

业务系统通常只需要知道 RabbitMQ 的内部服务地址：

- AMQP: `<release-name>.<namespace>.svc:5672`
- 管理台: `<release-name>.<namespace>.svc:15672`
- metrics: `<release-name>.<namespace>.svc:9419`

按默认值展开后就是：

- `rabbitmq-cluster.aict.svc:5672`
- `rabbitmq-cluster.aict.svc:15672`
- `rabbitmq-cluster.aict.svc:9419`

### 作为 Prometheus 的被监控对象

RabbitMQ 默认会打上统一监控标签：

- `monitoring.archinfra.io/stack=default`

所以只要 Prometheus Stack 按平台规则启用了跨 namespace 自动发现，RabbitMQ 装完后通常就会自动被发现。

### 和 Nacos / 配置中心联动

如果业务系统是通过 Nacos 或其他配置中心拿连接信息，通常建议把这些值写进去：

- `rabbitmq.host=rabbitmq-cluster.aict.svc`
- `rabbitmq.port=5672`
- `rabbitmq.username=admin`
- `rabbitmq.password=<你的密码>`

## 使用前置条件与依赖

安装器要成功运行，建议满足下面这些前置条件。

### 必要条件

- Kubernetes 集群可用
- `kubectl` 可正常访问目标集群
- `helm` 已安装
- 集群里存在可用的 `StorageClass`
- 默认或指定的 `storageClass` 可以正常动态供给 PVC

### 镜像相关条件

- 如果不带 `--skip-image-prepare`，执行机器需要有 `docker`
- 如果带 `--skip-image-prepare`，目标镜像仓库里需要已经有安装器所需镜像

### 监控相关条件

- 如果集群里有 `ServiceMonitor` CRD，安装器会创建 `ServiceMonitor`
- 如果没有，安装器会自动降级，只保留 metrics

## 为什么这次会遇到 `allowInsecureImages` 报错

Bitnami 新版 chart 会检查当前镜像是不是它识别的标准来源。

而我们的离线交付模型是：

1. 从公网拉镜像
2. 重打标签到内网仓库
3. 再由 Helm 安装内网镜像

这种模式对离线交付是正确的，但对 Bitnami 的镜像来源校验来说属于“非标准镜像地址”，所以会报：

- `global.security.allowInsecureImages`

这个仓库现在已经默认处理好了：

- chart 默认 `global.security.allowInsecureImages=true`
- 安装器执行 Helm 时也会显式传 `--set global.security.allowInsecureImages=true`

所以后续再用内网镜像地址安装，不需要手工额外处理这一步。

## 安装后怎么验证

先看整体状态：

```bash
./rabbitmq-cluster-installer-amd64.run status
```

再看核心资源：

```bash
kubectl get sts,pods,svc,pvc -n aict -l app.kubernetes.io/instance=rabbitmq-cluster
```

再看监控资源：

```bash
kubectl get servicemonitor -n aict
```

如果 Prometheus 已接入平台自动发现，也可以再去 Prometheus targets 页面确认 RabbitMQ 已被抓取。

## 给 AI 或自动化系统使用时的建议

如果这份文档未来是给大模型、自动化代理或者运维机器人直接参考的，建议固定下面这些判断规则。

### 安装前先收集这些事实

```bash
uname -m
kubectl get nodes -o wide
kubectl get sc
kubectl get crd servicemonitors.monitoring.coreos.com
helm list -A | grep rabbitmq
```

至少要确认：

- 架构是 `amd64` 还是 `arm64`
- `storageClass` 是否存在
- 集群里是否已安装 Prometheus Operator CRD
- namespace 和 release 是否已存在
- 目标仓库里是否已经有镜像，可以使用 `--skip-image-prepare`

### AI 推荐的默认安装策略

如果对环境不熟，但只是想先把 RabbitMQ 正确装起来，建议从这个命令开始：

```bash
./rabbitmq-cluster-installer-amd64.run install \
  --skip-image-prepare \
  -y
```

如果镜像仓库还没准备好，则去掉 `--skip-image-prepare`。

### AI 需要知道的成功标准

自动化执行时，不能只看 Helm 返回码，还应确认：

- `helm status <release> -n <namespace>` 为 `deployed`
- StatefulSet Ready
- 所有 RabbitMQ Pod Ready
- PVC 为 `Bound`
- 如果集群支持 `ServiceMonitor`，则 `ServiceMonitor` 已创建

## 常见问题与排障

### 1. 报 `allowInsecureImages`

这通常说明使用的是内网重打标签镜像，而 chart 又开启了来源校验。

当前仓库已经默认处理了这件事。

如果你还是手工直接跑 Helm，可以显式加：

```bash
--set global.security.allowInsecureImages=true
```

### 2. PVC 一直 Pending

优先检查：

```bash
kubectl get pvc -n aict
kubectl get sc
kubectl describe pvc <pvc-name> -n aict
```

常见原因：

- `storageClass` 不存在
- NFS provisioner 没就绪
- 配额不够

### 3. Prometheus 没发现 RabbitMQ

优先检查：

```bash
kubectl get crd servicemonitors.monitoring.coreos.com
kubectl get servicemonitor -n aict
```

然后确认 Prometheus Stack 是否按平台约定抓取：

- `monitoring.archinfra.io/stack=default`

### 4. 想看最终 Helm 命令

安装器执行前会打印：

- `Helm Command Preview`

可以直接从终端里看到最终拼出来的 Helm 命令，方便排查参数有没有真正生效。

## 目录结构

- [build.sh](C:\Users\yuanyp8\Desktop\archinfra\apps_rabbitmq-cluster\build.sh)
- [install.sh](C:\Users\yuanyp8\Desktop\archinfra\apps_rabbitmq-cluster\install.sh)
- [images/image.json](C:\Users\yuanyp8\Desktop\archinfra\apps_rabbitmq-cluster\images\image.json)
- [charts/rabbitmq/Chart.yaml](C:\Users\yuanyp8\Desktop\archinfra\apps_rabbitmq-cluster\charts\rabbitmq\Chart.yaml)
- [.github/workflows/build-offline-installer.yml](C:\Users\yuanyp8\Desktop\archinfra\apps_rabbitmq-cluster\.github\workflows\build-offline-installer.yml)

## 本地构建

要求：

- `bash`
- `docker`
- `helm`
- `jq`

示例：

```bash
./build.sh --arch amd64
./build.sh --arch arm64
./build.sh --arch all
```

构建产物在 `dist/`：

- `rabbitmq-cluster-installer-amd64.run`
- `rabbitmq-cluster-installer-amd64.run.sha256`
- `rabbitmq-cluster-installer-arm64.run`
- `rabbitmq-cluster-installer-arm64.run.sha256`

## 镜像来源

当前离线包从这些公开多架构镜像构建，再重打为内网目标仓库格式：

- `bitnamilegacy/rabbitmq:4.1.3-debian-12-r1`
- `bitnamilegacy/os-shell:12-debian-12-r50`

之所以使用 `bitnamilegacy/*`，是因为对应公开 `bitnami/*` 标签当前并没有完整提供我们需要的多架构 manifest。

## GitHub Actions 发布流程

推送到 `main`：

- 构建 `amd64` / `arm64` 安装包
- 上传构建产物

推送 tag `v*`：

- 构建安装包
- 发布 GitHub Release
- 挂载 `.run` 和 `.sha256`
## Built-in Monitoring, Alerts, And Dashboards

Default install now enables:

- `metrics.enabled=true`
- `metrics.serviceMonitor.default.enabled=true`
- `metrics.prometheusRule.enabled=true`

Default monitoring resources:

- `ServiceMonitor`
- `PrometheusRule`
- Grafana dashboard `ConfigMap`

Grafana auto-import contract:

- dashboard label: `grafana_dashboard=1`
- platform label: `monitoring.archinfra.io/stack=default`
- folder annotation: `grafana_folder=Middleware/RabbitMQ`

Built-in alerts:

- `RabbitMQNodeDown`
- `RabbitMQClusterDown`
- `RabbitMQClusterPartition`
- `RabbitMQMemoryHigh`

Built-in dashboard panels:

- Running Nodes
- Connections
- Messages Ready
- Partitions
- Connections And Consumers
- Node Memory
