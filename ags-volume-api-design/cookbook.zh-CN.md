# AGS Volume 云 API 说明

本文面向需要接入 AGS Volume 能力的客户，说明基础概念、相关云 API，以及典型使用场景。本文只描述 Volume 首期对外暴露的接口形态和关键字段；未在本文列出的字段，仍以对应云 API 的正式定义为准。

## 1. 基础概念

### 1.1 VolumeTemplate

`VolumeTemplate` 是 AGS 的存储声明资源，用来描述 AGS 可以使用的一份存储能力。

首期支持以下 `SourceType`：

| SourceType | 含义 |
|------------|------|
| `Cos` | 客户已有 COS 存储桶中的指定路径 |
| `Cfs` | 客户已有 CFS 文件系统中的指定路径 |
| `AgentBucket` | 客户已有 Agent Bucket 空间 |
| `AgentCBS` | AGS 托管的数据盘模板 |

共享存储类型的 `VolumeTemplate` 用来声明 AGS 可使用的存储范围。`AgentCBS` 类型的 `VolumeTemplate` 用来声明 AGS 如何自动创建或复用托管数据盘。

### 1.2 VolumeMount

`VolumeMount` 是 `SandboxTool` 上的挂载声明。它通过 `VolumeTemplateId` 引用一个 `VolumeTemplate`，并声明默认挂载路径、只读配置和是否默认挂载。

`VolumeMount` 不是独立云资源，它是 `CreateSandboxTool` / `DescribeSandboxTool` 中的字段。

### 1.3 MountOptions

`MountOptions[]` 是 `StartSandboxInstance` 的已有字段。本次 Volume 能力继续复用该字段。

实例启动时，`MountOptions[]` 只能按 `Name` 引用 Tool 已声明的同名 `VolumeMount`，用于覆盖本次实例的挂载路径、只读配置，或启用 Tool 中默认不挂载的存储。

实例启动时不直接传新的 `VolumeTemplateId`。

### 1.4 Metadata

`Metadata[]` 是 `StartSandboxInstance` 的已有字段。本次 Volume 能力使用其中的 `sessionId` 来渲染模板变量。

首期只支持 `${sessionId}`：

| 字段 | 用途 | 示例 |
|------|------|------|
| `SubPathTemplate` | 共享存储的子目录模板 | `${sessionId}` -> `sess-001` |
| `NameTemplate` | AgentCBS 名称模板 | `agent-${sessionId}` -> `agent-sess-001` |

### 1.5 AgentCBS

`AgentCBS` 是 AGS 托管的数据盘。客户不需要提供 CBS `DiskId`。AGS 会根据 AgentCBS 类型的 `VolumeTemplate`，在启动实例时自动创建或复用对应的数据盘。

客户可以通过 `DescribeAgentCBS` 查询 AGS 托管数据盘，通过 `DeleteAgentCBS` 删除不再使用的数据盘。

### 1.6 实例最终挂载结果

`DescribeSandboxInstance` 和 `DescribeSandboxInstanceList` 会返回实例最终实际挂载结果，字段为 `VolumeMounts[]`。

该字段用于让客户看到实例最终使用了哪个 `VolumeTemplate`、挂载到了哪个路径，以及共享存储最终子目录或 AgentCBS ID。

## 2. 云 API

本章列出与 Volume 能力相关的云 API。每个接口只列 Volume 相关参数；其他已有参数保持原接口定义。

### 2.1 CreateVolumeTemplate

接口名称：`CreateVolumeTemplate`

接口说明：创建 `VolumeTemplate`。

请求参数：

| 参数名称 | 类型 | 必选 | 描述 |
|----------|------|------|------|
| `VolumeTemplateName` | String | 是 | VolumeTemplate 名称 |
| `Description` | String | 否 | 描述 |
| `Tags` | Array of Tag | 否 | 标签 |
| `SourceType` | String | 是 | 存储类型，取值：`Cos` / `Cfs` / `AgentBucket` / `AgentCBS` |
| `Source` | VolumeSource | 是 | 存储源配置 |
| `SubPathTemplate` | String | 否 | 共享存储子目录模板，首期支持 `${sessionId}` |
| `NameTemplate` | String | 否 | AgentCBS 名称模板，首期支持 `${sessionId}` |
| `DefaultCapacity` | String | AgentCBS 必填 | AgentCBS 默认容量，例如 `20Gi` |
| `DiskType` | String | AgentCBS 必填 | AgentCBS 盘型 |
| `ReclaimPolicy` | String | 是 | 回收策略，取值：`Retain` / `Delete` |

`Source` 参数：

| SourceType | Source 字段 | 参数名称 | 类型 | 必选 | 描述 |
|------------|-------------|----------|------|------|------|
| `Cos` | `Cos` | `BucketName` | String | 是 | COS Bucket 名称 |
| `Cos` | `Cos` | `BucketPath` | String | 是 | COS Bucket 内路径 |
| `Cfs` | `Cfs` | `FileSystemId` | String | 是 | CFS 文件系统 ID |
| `Cfs` | `Cfs` | `Path` | String | 是 | CFS 文件系统内路径 |
| `AgentBucket` | `AgentBucket` | `AccessDomain` | String | 是 | Agent Bucket 访问域名 |
| `AgentBucket` | `AgentBucket` | `SpaceId` | String | 否 | Agent Bucket 空间 ID |
| `AgentCBS` | `AgentCBS` | - | Object | 是 | 传空对象 `{}` |

返回参数：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `VolumeTemplate` | VolumeTemplate | 创建后的 VolumeTemplate 信息 |
| `RequestId` | String | 请求 ID |

### 2.2 DescribeVolumeTemplates

接口名称：`DescribeVolumeTemplates`

接口说明：查询 `VolumeTemplate`。

请求参数：

| 参数名称 | 类型 | 必选 | 描述 |
|----------|------|------|------|
| `VolumeTemplateIds` | Array of String | 否 | VolumeTemplate ID 列表 |
| `VolumeTemplateName` | String | 否 | VolumeTemplate 名称 |
| `SourceType` | String | 否 | 存储类型 |
| `Tags` | Array of TagFilter | 否 | 标签过滤条件 |
| `Offset` | Integer | 否 | 偏移量 |
| `Limit` | Integer | 否 | 返回数量 |

返回参数：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `TotalCount` | Integer | 符合条件的总数 |
| `VolumeTemplates` | Array of VolumeTemplate | VolumeTemplate 列表 |
| `RequestId` | String | 请求 ID |

### 2.3 DeleteVolumeTemplate

接口名称：`DeleteVolumeTemplate`

接口说明：删除 `VolumeTemplate`。共享存储类型的 `VolumeTemplate` 删除后，不删除客户底层 COS / CFS / Agent Bucket 数据。

请求参数：

| 参数名称 | 类型 | 必选 | 描述 |
|----------|------|------|------|
| `VolumeTemplateId` | String | 是 | VolumeTemplate ID |

返回参数：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `RequestId` | String | 请求 ID |

### 2.4 CreateSandboxTool

接口名称：`CreateSandboxTool`

接口说明：创建 SandboxTool。Volume 能力在该接口中增加 `VolumeMounts[]` 参数，用于声明 Tool 可使用的存储。

请求参数：

| 参数名称 | 类型 | 必选 | 描述 |
|----------|------|------|------|
| `VolumeMounts` | Array of VolumeMount | 否 | Tool 级 Volume 挂载声明 |

`VolumeMount` 参数：

| 参数名称 | 类型 | 必选 | 描述 |
|----------|------|------|------|
| `Name` | String | 是 | Tool 内唯一名称，实例级 `MountOptions[]` 按该名称引用 |
| `VolumeTemplateId` | String | 是 | VolumeTemplate ID |
| `MountPath` | String | 是 | 容器内挂载路径 |
| `ReadOnly` | Boolean | 否 | 是否只读 |
| `SubPath` | String | 否 | 共享存储子路径 |
| `Inherit` | Boolean | 否 | 是否默认挂载到实例；不传时按默认挂载处理 |

返回参数：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `ToolId` | String | SandboxTool ID |
| `RequestId` | String | 请求 ID |

### 2.5 DescribeSandboxTool

接口名称：`DescribeSandboxTool`

接口说明：查询 SandboxTool。对使用 `VolumeMounts[]` 创建的 Tool，返回 Tool 级 Volume 挂载声明。

返回参数：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `ToolId` | String | SandboxTool ID |
| `ToolName` | String | SandboxTool 名称 |
| `VolumeMounts` | Array of VolumeMount | Tool 级 Volume 挂载声明 |
| `RequestId` | String | 请求 ID |

### 2.6 DescribeSandboxToolList

接口名称：`DescribeSandboxToolList`

接口说明：查询 SandboxTool 列表。返回列表项中包含 `VolumeMounts[]`。

返回参数：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `SandboxToolSet` | Array of SandboxTool | SandboxTool 列表 |
| `SandboxToolSet[].VolumeMounts` | Array of VolumeMount | Tool 级 Volume 挂载声明 |
| `TotalCount` | Integer | 符合条件的总数 |
| `RequestId` | String | 请求 ID |

### 2.7 StartSandboxInstance

接口名称：`StartSandboxInstance`

接口说明：启动沙箱实例。Volume 能力复用已有 `Metadata[]` 和 `MountOptions[]`。

请求参数：

| 参数名称 | 类型 | 必选 | 描述 |
|----------|------|------|------|
| `Metadata` | Array of Metadata | 否 | 实例元数据；可用于传入 `sessionId` |
| `MountOptions` | Array of MountOption | 否 | 实例级挂载覆盖参数 |

`Metadata` 参数：

| 参数名称 | 类型 | 必选 | 描述 |
|----------|------|------|------|
| `Name` | String | 是 | 元数据名称，例如 `sessionId` |
| `Value` | String | 是 | 元数据值 |

`MountOption` 参数：

| 参数名称 | 类型 | 必选 | 描述 |
|----------|------|------|------|
| `Name` | String | 是 | Tool 中已声明的 `VolumeMount.Name` |
| `MountPath` | String | 否 | 覆盖本次实例的挂载路径 |
| `ReadOnly` | Boolean | 否 | 覆盖本次实例的只读配置 |
| `SubPath` | String | 否 | 覆盖本次实例的共享存储子路径 |

返回参数：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `Instance` | SandboxInstance | 启动后的实例信息 |
| `Instance.VolumeMounts` | Array of InstanceVolumeMount | 实例最终挂载结果 |
| `RequestId` | String | 请求 ID |

### 2.8 DescribeSandboxInstance

接口名称：`DescribeSandboxInstance`

接口说明：查询沙箱实例。返回实例最终挂载结果 `VolumeMounts[]`。

返回参数：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `InstanceId` | String | 实例 ID |
| `VolumeMounts` | Array of InstanceVolumeMount | 实例最终挂载结果 |
| `RequestId` | String | 请求 ID |

`InstanceVolumeMount` 字段：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `Name` | String | Tool 侧挂载名称 |
| `VolumeTemplateId` | String | VolumeTemplate ID |
| `SourceType` | String | 存储类型 |
| `MountPath` | String | 最终容器内挂载路径 |
| `ReadOnly` | Boolean | 最终只读配置 |
| `ResolvedSubPath` | String | 共享存储最终子路径 |
| `ResolvedAgentCBSId` | String | AgentCBS ID |
| `ResolvedAgentCBSName` | String | AgentCBS 名称 |
| `ResolvedReclaimPolicy` | String | 实例创建时使用的回收策略 |

### 2.9 DescribeSandboxInstanceList

接口名称：`DescribeSandboxInstanceList`

接口说明：查询沙箱实例列表。返回列表项中包含 `VolumeMounts[]`。

返回参数：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `InstanceSet` | Array of SandboxInstance | 实例列表 |
| `InstanceSet[].VolumeMounts` | Array of InstanceVolumeMount | 实例最终挂载结果 |
| `TotalCount` | Integer | 符合条件的总数 |
| `RequestId` | String | 请求 ID |

### 2.10 DescribeAgentCBS

接口名称：`DescribeAgentCBS`

接口说明：查询 AGS 托管数据盘。

请求参数：

| 参数名称 | 类型 | 必选 | 描述 |
|----------|------|------|------|
| `AgentCBSIds` | Array of String | 否 | AgentCBS ID 列表 |
| `VolumeTemplateId` | String | 否 | 所属 VolumeTemplate ID |
| `BoundInstanceId` | String | 否 | 绑定的实例 ID |
| `Offset` | Integer | 否 | 偏移量 |
| `Limit` | Integer | 否 | 返回数量 |

返回参数：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `TotalCount` | Integer | 符合条件的总数 |
| `AgentCBSSet` | Array of AgentCBS | AgentCBS 列表 |
| `RequestId` | String | 请求 ID |

`AgentCBS` 字段：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `AgentCBSId` | String | AGS 托管数据盘 ID |
| `VolumeTemplateId` | String | 所属 VolumeTemplate ID |
| `Name` | String | AgentCBS 名称 |
| `Status` | String | AgentCBS 状态 |
| `BoundInstanceId` | String | 绑定的实例 ID |
| `Capacity` | String | 容量 |
| `DiskType` | String | 盘型 |
| `CreateTime` | String | 创建时间 |

### 2.11 DeleteAgentCBS

接口名称：`DeleteAgentCBS`

接口说明：删除 AGS 托管数据盘。

请求参数：

| 参数名称 | 类型 | 必选 | 描述 |
|----------|------|------|------|
| `AgentCBSId` | String | 是 | AgentCBS ID |

返回参数：

| 参数名称 | 类型 | 描述 |
|----------|------|------|
| `RequestId` | String | 请求 ID |

## 3. 使用场景和案例

### 3.1 AgentCBS 会话复用

适用场景：客户希望同一个会话多次启动实例时复用同一块 AGS 托管数据盘。

调用步骤：

1. 调用 `CreateVolumeTemplate`，创建 `SourceType=AgentCBS` 的 `VolumeTemplate`。
2. 在 `VolumeTemplate` 中设置 `NameTemplate=agent-${sessionId}`。
3. 调用 `CreateSandboxTool`，在 `VolumeMounts[]` 中引用该 `VolumeTemplateId`。
4. 调用 `StartSandboxInstance`，在 `Metadata[]` 中传入 `sessionId`。
5. 查询实例时，通过 `VolumeMounts[].ResolvedAgentCBSId` 查看最终绑定的 AgentCBS。

示例：

```json
{
  "Action": "CreateVolumeTemplate",
  "VolumeTemplateName": "session-agent-cbs",
  "SourceType": "AgentCBS",
  "Source": {
    "AgentCBS": {}
  },
  "DefaultCapacity": "20Gi",
  "DiskType": "CLOUD_SSD",
  "NameTemplate": "agent-${sessionId}",
  "ReclaimPolicy": "Retain"
}
```

```json
{
  "Action": "CreateSandboxTool",
  "ToolName": "code-interpreter",
  "VolumeMounts": [
    {
      "Name": "data",
      "VolumeTemplateId": "vt-xxxxxxxx",
      "MountPath": "/data",
      "Inherit": true
    }
  ]
}
```

```json
{
  "Action": "StartSandboxInstance",
  "ToolId": "sdt-xxxxxxxx",
  "Metadata": [
    {"Name": "sessionId", "Value": "sess-001"}
  ]
}
```

### 3.2 共享存储会话目录

适用场景：客户已有 COS / CFS / Agent Bucket，希望每个会话使用独立目录。

调用步骤：

1. 调用 `CreateVolumeTemplate`，创建共享存储类型的 `VolumeTemplate`。
2. 设置 `SubPathTemplate=${sessionId}`。
3. 调用 `CreateSandboxTool`，在 `VolumeMounts[]` 中引用该 `VolumeTemplateId`。
4. 调用 `StartSandboxInstance`，在 `Metadata[]` 中传入 `sessionId`。
5. 查询实例时，通过 `VolumeMounts[].ResolvedSubPath` 查看最终子路径。

示例：

```json
{
  "Action": "CreateVolumeTemplate",
  "VolumeTemplateName": "session-workspace",
  "SourceType": "Cos",
  "Source": {
    "Cos": {
      "BucketName": "agent-workspaces",
      "BucketPath": "/sessions"
    }
  },
  "SubPathTemplate": "${sessionId}",
  "ReclaimPolicy": "Retain"
}
```

```json
{
  "Action": "StartSandboxInstance",
  "ToolId": "sdt-xxxxxxxx",
  "Metadata": [
    {"Name": "sessionId", "Value": "sess-001"}
  ]
}
```

### 3.3 Tool 声明存储，实例按需启用

适用场景：Tool 预先声明可用存储，但实例默认不挂载，只有需要时才启用。

调用步骤：

1. 调用 `CreateSandboxTool`，在 `VolumeMounts[]` 中设置 `Inherit=false`。
2. 默认调用 `StartSandboxInstance` 时不传 `MountOptions[]`，该存储不挂载。
3. 需要启用时，在 `StartSandboxInstance.MountOptions[]` 中传入同名 `Name`。

示例：

```json
{
  "Action": "CreateSandboxTool",
  "ToolName": "analysis-tool",
  "VolumeMounts": [
    {
      "Name": "dataset",
      "VolumeTemplateId": "vt-xxxxxxxx",
      "MountPath": "/mnt/dataset",
      "ReadOnly": true,
      "Inherit": false
    }
  ]
}
```

```json
{
  "Action": "StartSandboxInstance",
  "ToolId": "sdt-xxxxxxxx",
  "MountOptions": [
    {
      "Name": "dataset",
      "MountPath": "/mnt/dataset",
      "ReadOnly": true
    }
  ]
}
```
