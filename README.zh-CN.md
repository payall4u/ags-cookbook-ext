# AGS 扩展 Cookbook

本仓库用于存放腾讯云 AGS 客户场景的扩展 cookbook 和参考实现。每个场景以一个顶层目录交付，目录内包含说明文档、示例代码、脚本和必要的配置模板。

English version: [README.md](README.md)

## 目录

- [kafka-prometheus-exporter](kafka-prometheus-exporter/README.md)：将 AGS 沙箱监控数据从 CKafka 接入自建 Prometheus。
- [ags-sandbox-otel-log-delivery](ags-sandbox-otel-log-delivery/README.zh-CN.md)：将 AGS custom image 沙箱内的文件日志通过 VPC 投递到客户自建 OTLP/gRPC 日志系统。
- [ags-volume-api-design](ags-volume-api-design/README.zh-CN.md)：面向客户的 AGS Volume 云 API 说明，覆盖基础概念、云 API 和使用场景案例。

## 使用方式

1. 进入对应场景目录，先阅读该目录下的 README。
2. 根据场景 README 跳转到更完整的 cookbook、参考实现和脚本说明。
3. 在客户环境中复现前，先确认账号权限、网络连通性、镜像仓库和目标后端服务。
