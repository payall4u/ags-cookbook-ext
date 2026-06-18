# AGS Volume API 变更说明

本目录是面向客户的 AGS Volume API 变更说明，重点解释新增 API、现有 API 字段变化、请求/响应语义和首期范围。

中文说明文档：[cookbook.zh-CN.md](cookbook.zh-CN.md)

## 内容

- API 变更总览：新增 API 和已有 API 调整。
- 新增 API：`CreateVolumeTemplate`、`DescribeVolumeTemplates`、`DeleteVolumeTemplate`、`DescribeAgentCBS`、`DeleteAgentCBS`。
- 现有 API 调整：`CreateSandboxTool`、`StartSandboxInstance`、`DescribeSandboxTool` / `DescribeSandboxToolList`、`DescribeSandboxInstance` / `DescribeSandboxInstanceList`。
- 关键字段：`VolumeTemplate`、`VolumeMounts[]`、`MountOptions[]`、`Metadata[]`、实例最终 `VolumeMounts[]`。
- 首期范围：AgentCBS、`${sessionId}` 模板变量、tag 归属和兼容关系。
