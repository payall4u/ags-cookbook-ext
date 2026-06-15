# AGS Cookbook Extensions / AGS 扩展 Cookbook

This repository contains extension cookbooks and reference implementations for Tencent Cloud AGS customer scenarios.

本仓库用于存放腾讯云 AGS 客户场景的扩展 cookbook 和参考实现。

## Cookbooks

- [kafka-prometheus-exporter](kafka-prometheus-exporter/README.md): consume AGS monitoring data from CKafka and expose it to self-managed Prometheus.
- [ags-sandbox-otel-log-delivery](ags-sandbox-otel-log-delivery/README.md): deliver file-based logs from AGS custom-image sandboxes to a customer-owned OTLP/gRPC logging system over VPC networking.

## 目录

- [kafka-prometheus-exporter](kafka-prometheus-exporter/README.md)：将 AGS 沙箱监控数据从 CKafka 接入自建 Prometheus。
- [ags-sandbox-otel-log-delivery](ags-sandbox-otel-log-delivery/README.md)：将 AGS custom image 沙箱内的文件日志通过 VPC 投递到客户自建 OTLP/gRPC 日志系统。
