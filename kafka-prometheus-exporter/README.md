# AGS Kafka Prometheus Exporter

将腾讯云 AGS 沙箱监控数据（经由云监控数据传输 → CKafka）接入自建 Prometheus 的参考实现。

## 背景

AGS 沙箱生命周期短、数量大，直接轮询云监控 API 成本高且容易遗漏。推荐通过云监控数据传输将数据推送到 CKafka，本程序消费 Kafka 消息并以 `/metrics` 接口暴露给 Prometheus。

数据链路：`AGS 沙箱 → 云监控 → CKafka → 本程序 → Prometheus`

## 前置条件

1. 已创建 CKafka 实例和 Topic
2. 已在云监控控制台配置数据传输任务，目标为上述 Topic
3. 本程序与 CKafka 网络互通（同 VPC 内网，或公网 + SASL/TLS）

## 快速启动

```bash
cp .env.example .env   # 填写 KAFKA_BROKERS 等参数
docker-compose up -d
curl http://localhost:8080/metrics | grep ags_sandbox
```

## 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `KAFKA_BROKERS` | — | Broker 地址，多个用逗号分隔 |
| `KAFKA_TOPIC` | `ags-monitor` | 消费的 Topic |
| `KAFKA_GROUP` | `ags-prometheus-exporter` | Consumer Group ID |
| `KAFKA_SASL_ENABLE` | `false` | 是否启用 SASL 认证 |
| `KAFKA_SASL_USER` | — | SASL 用户名 |
| `KAFKA_SASL_PASSWORD` | — | SASL 密码 |
| `KAFKA_TLS_ENABLE` | `false` | 是否启用 TLS（公网接入时需开启） |
| `KAFKA_OFFSET_NEWEST` | `false` | `true` = 从最新消息消费，首次接入建议设为 true |
| `LISTEN_ADDR` | `:8080` | metrics 监听地址 |
| `METRIC_TTL_SECONDS` | `300` | 沙箱停止后指标保留时长，0 表示永久保留 |

## 暴露的指标

所有指标均携带 `appid`、`instance_id`、`tool_id`、`statistic` 四个 label。

| 指标名 | 说明 |
|---|---|
| `ags_sandbox_cpu_usage_percent` | CPU 使用率（%） |
| `ags_sandbox_cpu_used_cores` | 已使用 CPU 核数 |
| `ags_sandbox_memory_usage_percent` | 内存使用率（%） |
| `ags_sandbox_memory_used_bytes` | 已使用内存（Bytes） |
| `ags_sandbox_fs_usage_percent` | 磁盘使用率（%） |
| `ags_sandbox_fs_used_bytes` | 已使用磁盘（Bytes） |
| `ags_sandbox_disk_read_bytes_per_second` | 磁盘读吞吐（Bytes/s） |
| `ags_sandbox_disk_write_bytes_per_second` | 磁盘写吞吐（Bytes/s） |
| `ags_sandbox_network_rx_bytes_per_second` | 网络入流量（Bytes/s） |
| `ags_sandbox_network_tx_bytes_per_second` | 网络出流量（Bytes/s） |
| `ags_kafka_consumer_messages_total` | 已消费消息总数（含 status=ok/error） |

## Prometheus 配置

```yaml
scrape_configs:
  - job_name: 'ags-sandbox'
    scrape_interval: 60s
    static_configs:
      - targets: ['<exporter-host>:8080']
```

## 注意事项

- **高基数**：`instance_id` 随沙箱频繁变化，请合理配置 `METRIC_TTL_SECONDS` 控制 Prometheus series 数量。
- **多实例部署**：同一 Consumer Group 可横向扩展，Kafka 自动分配分区。
- **首次启动**：建议 `KAFKA_OFFSET_NEWEST=true`，避免回放大量历史数据。
