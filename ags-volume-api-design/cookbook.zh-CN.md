# 新版 Volume 使用方式和 API 设计

## 1. 概念

本节只说明新增实体及其实际意义。

### 1.1 VolumeTemplate

`VolumeTemplate` 是存储声明资源，用来描述 AGS 可使用的一份存储能力。

在不同存储类型下，`VolumeTemplate` 有一些区别：

| 类型 | VolumeTemplate 表达什么 |
|------|-------------------------|
| COS / CFS / Agent Bucket （共享存储） | 客户已有共享介质中允许 AGS 使用的路径、前缀或空间，以及可选的子目录模板 |
| AgentCBS （沙箱独占块设备） | AGS 如何派生数据盘，包括默认容量、盘类型、名称模板和回收策略 |

`VolumeTemplate` 也是鉴权、审计的入口，同时也是 AgentCBS 的计费单位。通过 `VolumeTemplate` 客户不仅可以更好的管理权限、也能清楚观测到哪些存储正在使用中。

### 1.2 VolumeMount

`VolumeMount` 是 Tool 对 `VolumeTemplate` 的挂载声明，也是实例详情中最终挂载结果的表达。实例启动时不直接传 `VolumeMounts[]`，仍然通过已有 `StartSandboxInstance.MountOptions[]` 按名称覆盖或启用 Tool 已声明的挂载。

Tool 侧 `VolumeMounts[]` 表示这个 Tool 可以使用哪些存储，以及默认挂载到沙箱内哪个路径。实例启动时的挂载覆盖字段只能按 `Name` 引用 Tool 中已经声明的挂载，用于：

- 启用 Tool 中默认不挂载的同名存储。
- 覆盖本次实例的 `MountPath`。
- 将权限从可写收紧为只读。
- 在允许范围内指定本次实例的 `SubPath`。

`VolumeMount.Inherit` 用来控制该挂载是否随 Tool 默认挂载：

| Inherit | 语义 |
|---------|------|
| `true` 或不传 | 默认挂载；从该 Tool 启动的实例会自动继承该挂载 |
| `false` | Tool 只声明这份存储可用；实例默认不挂载，只有启动实例时显式传同名 `MountOption` 才启用 |

### 1.3 AgentCBS

`AgentCBS` 是 AGS 提供的新的存储方案，由 AgentCBS 类型 `VolumeTemplate` 派生。客户不需要传入 CBS ID；AGS 会在启动沙箱实例时根据 `VolumeTemplate` 自动创建或复用 AgentCBS（详见下文中的使用方式）。

AgentCBS 有独立状态：

| 状态 | 说明 |
|------|------|
| `Bound` | 已绑定到某个沙箱实例 |
| `Available` | 当前空闲，后续可复用 |

删除实例时，AgentCBS 根据 `ReclaimPolicy` 决定保留或删除。

### 1.4 Metadata

`Metadata` 是启动实例时传入的变量集合，用于渲染 `VolumeTemplate` 中声明的模板。例如在 `Metadata` 中声明 `sessionId` 后，沙箱挂载时可以使用特定的 AgentCBS，或使用特定共享存储的子路径：

| 模板位置 | 用途 | 示例 |
|----------|------|------|
| `VolumeTemplate.SubPathTemplate` | 生成共享介质子目录 | `${sessionId}` -> `sess-001` |
| `AgentCBS.NameTemplate` | 生成 AgentCBS 名称 | `agent-${sessionId}` -> `agent-sess-001` |

如果模板引用的变量没有在 `StartSandboxInstance.Metadata` 中提供，系统应拒绝启动实例（详见下文中的使用方式）。

### 1.5 SandboxInstance.VolumeMounts

`SandboxInstance.VolumeMounts[]` 是实例最终实际挂载结果，不是新的独立云资源。

它用于查询、审计和排查问题：

- 共享介质场景返回最终 `ResolvedSubPath`。
- AgentCBS 场景返回最终绑定的 `ResolvedAgentCBSId`。
- 实例级覆盖后的 `MountPath`、`ReadOnly` 等参数也会体现在这里。

系统拒绝以下实例级行为：

- 启动实例时引用 Tool 未声明的存储。
- 启动实例时引用新的 `VolumeTemplate`。
- 修改 `VolumeTemplateId`。
- 修改容量、盘类型、回收策略等资源定义字段。
- 将只读挂载放宽为可写。
- 将挂载范围扩大到 `VolumeTemplate` 允许边界之外。

## 2. 场景

### 2.1 AgentCBS 会话复用数据盘

客户希望同一个会话多次启动沙箱时复用同一块数据盘。典型场景是会话重连、长期工作区或需要保留工作现场的 Agent。

#### 2.1.1 创建 VolumeTemplate

```go
vt, err := client.CreateVolumeTemplate(ctx, &ags.CreateVolumeTemplateRequest{
    VolumeTemplateName: "session-agent-cbs",
    Description:        "AgentCBS data disk reused by sessionId",
    ProvisionMode:      "Dedicated",
    ReclaimPolicy:      "Retain",
    DefaultCapacity:    "20Gi",
    Source: ags.VolumeSource{
        Type: "AgentCBS",
        AgentCBS: &ags.AgentCBSVolumeSource{
            NameTemplate: "agent-${sessionId}",
            DiskType:     "CLOUD_SSD",
        },
    },
})
```

#### 2.1.2 创建 SandboxTool 并绑定挂载

```go
tool, err := client.CreateSandboxTool(ctx, &ags.CreateSandboxToolRequest{
    ToolName: "code-interpreter",
    VolumeMounts: []ags.VolumeMount{
        {
            Name:              "data",
            VolumeTemplateId: vt.VolumeTemplateId,
            MountPath:         "/data",
            Inherit:           ptr.Bool(true),
        },
    },
})
```

#### 2.1.3 启动实例

```go
inst, err := client.StartSandboxInstance(ctx, &ags.StartSandboxInstanceRequest{
    ToolId: tool.ToolId,
    Metadata: []ags.Metadata{
        {Name: "sessionId", Value: "sess-001"},
    },
})
```

预期结果：

- AGS 渲染 AgentCBS 名称：`agent-sess-001`。
- 如果不存在同名 AgentCBS，则创建默认大小为 `20Gi` 的数据盘。
- 沙箱内 `/data` 挂载到该 AgentCBS。
- 实例详情中返回 `ResolvedAgentCBSId`。
- AgentCBS 复用的匹配条件是同一个 `VolumeTemplate` 下渲染出相同名称；只有空闲的 `Available` AgentCBS 可以复用。如果同名 AgentCBS 仍处于 `Bound` 状态，需要先停止原实例，不能被两个实例同时挂载。

```go
fmt.Println(inst.VolumeMounts[0].ResolvedAgentCBSId) // acbs-xxx
```

#### 2.1.4 删除实例并保留数据盘

```go
_, err = client.StopSandboxInstance(ctx, &ags.StopSandboxInstanceRequest{
    InstanceId: inst.InstanceId,
})
```

预期结果：

- 沙箱实例删除。
- 因为 `ReclaimPolicy=Retain`，AgentCBS 不删除。
- AgentCBS 状态变为 `Available`。

#### 2.1.5 再次启动同一会话

```go
inst2, err := client.StartSandboxInstance(ctx, &ags.StartSandboxInstanceRequest{
    ToolId: tool.ToolId,
    Metadata: []ags.Metadata{
        {Name: "sessionId", Value: "sess-001"},
    },
})
```

预期结果：

- AGS 再次渲染出 `agent-sess-001`。
- 查询到已有空闲 AgentCBS 后直接复用。
- `inst2.VolumeMounts[0].ResolvedAgentCBSId` 与上一次相同。

#### 2.1.6 查询 AgentCBS

```go
resp, err := client.DescribeAgentCBS(ctx, &ags.DescribeAgentCBSRequest{
    Filters: []ags.Filter{
        {Name: "VolumeTemplateId", Values: []string{vt.VolumeTemplateId}},
    },
})
```

返回示例：

```go
[]ags.AgentCBS{
    {
        AgentCBSId:      "acbs-001",
        Name:            "agent-sess-001",
        Status:          "Bound",
        BoundInstanceId: "ins-xxx",
        Capacity:        "20Gi",
        DiskType:        "CLOUD_SSD",
    },
    {
        AgentCBSId: "acbs-002",
        Name:       "agent-sess-002",
        Status:     "Available",
        Capacity:   "20Gi",
        DiskType:   "CLOUD_SSD",
    },
}
```

### 2.2 AgentCBS 普通独占数据盘

客户希望每个沙箱启动时获得一块独立数据盘，实例删除后数据盘也删除。

```go
vt, err := client.CreateVolumeTemplate(ctx, &ags.CreateVolumeTemplateRequest{
    VolumeTemplateName: "temporary-agent-cbs",
    ProvisionMode:      "Dedicated",
    ReclaimPolicy:      "Delete",
    DefaultCapacity:    "20Gi",
    Source: ags.VolumeSource{
        Type: "AgentCBS",
        AgentCBS: &ags.AgentCBSVolumeSource{
            DiskType: "CLOUD_SSD",
        },
    },
})
```

```go
tool, err := client.CreateSandboxTool(ctx, &ags.CreateSandboxToolRequest{
    ToolName: "batch-runner",
    VolumeMounts: []ags.VolumeMount{
        {
            Name:              "data",
            VolumeTemplateId: vt.VolumeTemplateId,
            MountPath:         "/data",
            Inherit:           ptr.Bool(true),
        },
    },
})
```

```go
inst, err := client.StartSandboxInstance(ctx, &ags.StartSandboxInstanceRequest{
    ToolId: tool.ToolId,
})
```

预期结果：

- 每次启动实例都会创建一块新的 AgentCBS。
- 实例详情返回 `ResolvedAgentCBSId`。
- 删除实例时，因为 `ReclaimPolicy=Delete`，AgentCBS 一起删除。

### 2.3 COS / CFS / Agent Bucket 会话独立工作目录

客户希望每个会话拥有独立目录，沙箱重建后仍能回到同一份数据。

#### 2.3.1 创建共享介质 VolumeTemplate

```go
vt, err := client.CreateVolumeTemplate(ctx, &ags.CreateVolumeTemplateRequest{
    VolumeTemplateName: "session-workspace",
    Description:        "COS workspace split by sessionId",
    ProvisionMode:      "Dedicated",
    ReclaimPolicy:      "Retain",
    SubPathTemplate:    "${sessionId}",
    Source: ags.VolumeSource{
        Type: "Cos",
        Cos: &ags.CosVolumeSource{
            BucketName: "agent-workspaces",
            BucketPath: "/sessions",
        },
    },
})
```

#### 2.3.2 Tool 引用 VolumeTemplate

```go
tool, err := client.CreateSandboxTool(ctx, &ags.CreateSandboxToolRequest{
    ToolName: "code-interpreter",
    VolumeMounts: []ags.VolumeMount{
        {
            Name:              "workspace",
            VolumeTemplateId: vt.VolumeTemplateId,
            MountPath:         "/workspace",
            Inherit:           ptr.Bool(true),
        },
    },
})
```

#### 2.3.3 启动实例

```go
inst, err := client.StartSandboxInstance(ctx, &ags.StartSandboxInstanceRequest{
    ToolId: tool.ToolId,
    Metadata: []ags.Metadata{
        {Name: "sessionId", Value: "sess-001"},
    },
})
```

预期结果：

- AGS 渲染最终子目录：`sess-001`。
- 最终挂载到 `BucketPath=/sessions` 下的会话子目录。
- 同一个 `sessionId` 再次启动时，挂载到同一目录。
- 客户不需要维护 `sessionId -> SubPath` 映射。

查询实例可看到最终解析结果：

```go
ins, err := client.DescribeSandboxInstance(ctx, &ags.DescribeSandboxInstanceRequest{
    InstanceId: inst.InstanceId,
})

fmt.Println(ins.VolumeMounts[0].ResolvedSubPath) // sess-001
```

### 2.4 多实例共享数据

客户希望多个沙箱同时读写同一份共享数据，例如团队数据集、共享任务目录或共享输出目录。

#### 2.4.1 创建共享 VolumeTemplate

```go
vt, err := client.CreateVolumeTemplate(ctx, &ags.CreateVolumeTemplateRequest{
    VolumeTemplateName: "shared-dataset",
    ProvisionMode:      "Shared",
    ReclaimPolicy:      "Retain",
    Source: ags.VolumeSource{
        Type: "Cfs",
        Cfs: &ags.CfsVolumeSource{
            FileSystemId: "cfs-xxx",
            Path:         "/datasets/team-a",
        },
    },
})
```

#### 2.4.2 Tool 默认挂载共享数据

```go
tool, err := client.CreateSandboxTool(ctx, &ags.CreateSandboxToolRequest{
    ToolName: "data-agent",
    VolumeMounts: []ags.VolumeMount{
        {
            Name:              "dataset",
            VolumeTemplateId: vt.VolumeTemplateId,
            MountPath:         "/mnt/dataset",
            Inherit:           ptr.Bool(true),
        },
    },
})
```

#### 2.4.3 多个实例启动

```go
instA, err := client.StartSandboxInstance(ctx, &ags.StartSandboxInstanceRequest{
    ToolId: tool.ToolId,
})

instB, err := client.StartSandboxInstance(ctx, &ags.StartSandboxInstanceRequest{
    ToolId: tool.ToolId,
})
```

预期结果：

- 多个实例都挂载同一份共享数据。
- 底层 CFS 文件系统由客户提供和管理。
- AGS 只负责在 `VolumeTemplate` 声明边界内完成挂载和权限控制。

### 2.5 Tool 声明可用存储，实例按需启用

客户希望 Tool 预先声明可用的数据集，但默认启动实例时不挂载，只有需要时才显式启用。

#### 2.5.1 Tool 声明但默认不挂载

```go
tool, err := client.CreateSandboxTool(ctx, &ags.CreateSandboxToolRequest{
    ToolName: "analysis-tool",
    VolumeMounts: []ags.VolumeMount{
        {
            Name:              "dataset",
            VolumeTemplateId: vt.VolumeTemplateId,
            MountPath:         "/mnt/dataset",
            Inherit:           ptr.Bool(false),
        },
    },
})
```

#### 2.5.2 默认启动不挂载

```go
inst, err := client.StartSandboxInstance(ctx, &ags.StartSandboxInstanceRequest{
    ToolId: tool.ToolId,
})
```

预期结果：

- `dataset` 不进入该实例的最终挂载列表。

#### 2.5.3 实例启动时显式启用

```go
inst, err := client.StartSandboxInstance(ctx, &ags.StartSandboxInstanceRequest{
    ToolId: tool.ToolId,
    MountOptions: []ags.MountOption{
        {
            Name:     "dataset",
            MountPath: "/mnt/dataset",
            ReadOnly: ptr.Bool(true),
        },
    },
})
```

预期结果：

- 因为 Tool 已声明同名 `dataset`，实例可以启用它。
- 本次实例将其挂载到 `/mnt/dataset`。
- 本次实例将权限收紧为只读。
- 实例不能修改 `VolumeTemplateId`，也不能引用 Tool 未声明的新存储。

### 2.6 不同团队按照 tag 鉴权

客户希望不同团队只能使用自己被授权的存储声明。例如团队 A 只能使用 `team=team-a` 的 `VolumeTemplate`，生产环境 Tool 只能使用 `env=prod` 的 `VolumeTemplate`。

#### 2.6.1 创建带 tag 的 VolumeTemplate

```go
vt, err := client.CreateVolumeTemplate(ctx, &ags.CreateVolumeTemplateRequest{
    VolumeTemplateName: "team-a-workspace",
    Description:        "workspace for team-a agents",
    Tags: []ags.Tag{
        {Key: "team", Value: "team-a"},
        {Key: "env", Value: "prod"},
    },
    ProvisionMode:   "Dedicated",
    ReclaimPolicy:   "Retain",
    SubPathTemplate: "${sessionId}",
    Source: ags.VolumeSource{
        Type: "Cos",
        Cos: &ags.CosVolumeSource{
            BucketName: "agent-workspaces",
            BucketPath: "/team-a",
        },
    },
})
```

#### 2.6.2 Tool 引用 VolumeTemplate 时触发鉴权

```go
tool, err := client.CreateSandboxTool(ctx, &ags.CreateSandboxToolRequest{
    ToolName: "team-a-agent",
    VolumeMounts: []ags.VolumeMount{
        {
            Name:              "workspace",
            VolumeTemplateId: vt.VolumeTemplateId,
            MountPath:         "/workspace",
            Inherit:           ptr.Bool(true),
        },
    },
})
```

预期结果：

- 调用方有 `team=team-a` 且 `env=prod` 的 `VolumeTemplate` 使用权限时，Tool 创建成功。
- 调用方没有对应 tag 权限时，引用该 `VolumeTemplate` 会被拒绝。
- 后续实例启动只能使用 Tool 已声明的同名挂载，不能绕过 Tool 临时引用其他团队的 `VolumeTemplate`。
- AgentCBS 的费用和审计也通过所属 `VolumeTemplate` 的 tag 归属到对应团队。

鉴权检查点：

- 创建 `VolumeTemplate` 时，记录该资源的 tag，作为后续授权和审计依据。
- `CreateSandboxTool` 引用 `VolumeTemplate` 时，检查调用方是否有该 `VolumeTemplate` 的使用权限，包括 tag 条件。
- `StartSandboxInstance` 不允许传入新的 `VolumeTemplate`，只能启用或覆盖 Tool 已声明的同名挂载，因此不能绕过 Tool 侧授权。
- `DescribeVolumeTemplates` 可以按 tag 过滤，便于团队查看自己有权限或归属自己的存储声明。
- AgentCBS 不单独打 tag；它的鉴权、审计和费用归属都继承所属 `VolumeTemplate`。

## 3. API 设计

### 3.1 API 列表

首期新增或调整以下 API：

| API | 类型 | 作用 |
|-----|------|------|
| `CreateVolumeTemplate` | 新增 | 创建存储声明资源 |
| `DescribeVolumeTemplates` | 新增 | 查询存储声明资源 |
| `DeleteVolumeTemplate` | 新增 | 删除未被引用且无存活 AgentCBS 的存储声明 |
| `DescribeAgentCBS` | 新增 | 查询 AGS 派生的数据盘，区分绑定中和空闲 |
| `DeleteAgentCBS` | 新增 | 删除空闲 AgentCBS |
| `CreateSandboxTool` | 调整 | 在已有创建 Tool API 上新增 `VolumeMounts[]` 字段，声明 Tool 可使用的存储集合和默认挂载方式 |
| `StartSandboxInstance` | 调整 | 复用已有 `Metadata[]` 做模板渲染；复用已有 `MountOptions[]` 覆盖或启用 Tool 已声明的 Volume 挂载 |
| `DescribeSandboxInstance` | 调整 | 返回最终实际挂载结果，包括 `ResolvedSubPath` 和 `ResolvedAgentCBSId` |

首期不支持以下 API 行为：

- 不支持客户直接 `CreateAgentCBS`。
- 不支持启动实例时追加全新存储。
- 不支持接管客户已有 CBS 数据盘。
- 不支持通用 CBS API。

### 3.2 CreateVolumeTemplate

创建存储声明资源。

```go
type CreateVolumeTemplateRequest struct {
    VolumeTemplateName string
    Description        string
    Tags               []Tag

    ProvisionMode string // Dedicated / Shared
    ReclaimPolicy string // Retain / Delete

    Source          VolumeSource
    SubPathTemplate string

    DefaultCapacity string // AgentCBS 默认容量，例如 20Gi
}
```

```go
type CreateVolumeTemplateResponse struct {
    VolumeTemplate VolumeTemplate
}
```

字段说明：

| 字段 | 是否必填 | 说明 |
|------|----------|------|
| `VolumeTemplateName` | 是 | 用户自定义名称，同一租户内唯一 |
| `Description` | 否 | 描述信息 |
| `Tags` | 否 | 云资源 tag，用于鉴权、审计和成本归属 |
| `ProvisionMode` | 是 | `Dedicated` 或 `Shared` |
| `ReclaimPolicy` | 是 | `Retain` 或 `Delete`；共享介质首期只支持 `Retain` |
| `Source` | 是 | 存储源，多态结构 |
| `SubPathTemplate` | 否 | 共享介质子目录模板，首期只支持一个变量，例如 `${sessionId}` |
| `DefaultCapacity` | AgentCBS 必填 | AgentCBS 默认容量，首期不支持实例级覆盖 |

关键校验：

- `Source.Type=AgentCBS` 时，`DefaultCapacity` 必填。
- `Source.Type=AgentCBS` 时，可选 `NameTemplate`；不传表示每次实例启动创建唯一数据盘。
- `Source.Type=AgentCBS` 时，首期仅支持 AGS 托管的 AgentCBS，不接入外部数据盘。
- 共享介质传 `ReclaimPolicy=Delete` 时拒绝。
- `SubPathTemplate` 只能包含一个变量。

### 3.3 DescribeVolumeTemplates

查询存储声明资源。

```go
type DescribeVolumeTemplatesRequest struct {
    VolumeTemplateIds   []string
    VolumeTemplateName  string
    SourceType          string
    Tags                []TagFilter
    Offset              int
    Limit               int
}
```

```go
type DescribeVolumeTemplatesResponse struct {
    TotalCount      int
    VolumeTemplates []VolumeTemplate
}
```

常用过滤条件：

| 过滤条件 | 说明 |
|----------|------|
| `VolumeTemplateIds` | 按资源 ID 查询 |
| `VolumeTemplateName` | 按名称查询 |
| `SourceType` | 按 `Cos` / `Cfs` / `AgentBucket` / `AgentCBS` 查询 |
| `Tags` | 按 tag 查询，用于项目、环境、成本归属 |

### 3.4 DeleteVolumeTemplate

删除存储声明资源。

```go
type DeleteVolumeTemplateRequest struct {
    VolumeTemplateId string
}
```

删除约束：

- 如果仍被 `SandboxTool.VolumeMounts[]` 引用，拒绝删除。
- 如果仍存在未删除的 AgentCBS，拒绝删除。
- 删除共享介质类型 `VolumeTemplate` 时，不删除底层 COS/CFS/Agent Bucket 资源，也不删除其中的数据。

### 3.5 CreateSandboxTool API 调整

`CreateSandboxTool` 是已有 API。本次 Volume 方案不是新增一个创建 Tool 的 API，而是在已有创建 Tool API 上新增 `VolumeMounts[]` 字段，用于声明 Tool 可使用的 `VolumeTemplate` 以及默认挂载方式。

现有 `StorageMounts[]` 是把存储源和挂载声明都写在 Tool 内；新 `VolumeMounts[]` 改为引用独立的 `VolumeTemplate`。下面只展示本方案新增或相关字段，其他已有字段保持现有 API 语义。

```go
type CreateSandboxToolRequest struct {
    // 已有字段，保持不变。
    ToolName string
    ToolType string
    // ...

    // 新增字段。
    VolumeMounts []VolumeMount
}
```

```go
type VolumeMount struct {
    Name              string
    VolumeTemplateId string

    MountPath string
    ReadOnly  *bool
    SubPath   string

    Inherit *bool
}
```

Tool 侧字段说明：

| 字段 | 是否必填 | 说明 |
|------|----------|------|
| `Name` | 是 | Tool 内唯一，实例级覆盖时按该字段匹配 |
| `VolumeTemplateId` | 是 | 引用的 `VolumeTemplate` 资源 ID |
| `MountPath` | 是 | 容器内挂载路径 |
| `ReadOnly` | 否 | 默认读写；设置为 true 后实例不能放宽为可写 |
| `SubPath` | 否 | 共享介质子路径；AgentCBS 禁止填写 |
| `Inherit` | 否 | 默认 true；false 表示实例默认不挂载 |

关键校验：

- `VolumeTemplateId` 必须存在。
- 调用方必须有使用该 `VolumeTemplate` 的权限。
- `Name` 在 Tool 内唯一。
- `MountPath` 在 Tool 内不能冲突。
- AgentCBS 挂载不允许填写 `SubPath`。

### 3.6 StartSandboxInstance.Metadata 字段语义扩展

`StartSandboxInstance` 是已有 API，`Metadata[]` 也是已有字段。本次 Volume 方案不改变 `Metadata[]` 的基础形态，只扩展它在 `VolumeTemplate` 模板渲染中的用途。

```go
type Metadata struct {
    Name  string
    Value string
}
```

示例：

```go
Metadata: []ags.Metadata{
    {Name: "sessionId", Value: "sess-001"},
}
```

渲染规则：

- `SubPathTemplate="${sessionId}"` 渲染为 `sess-001`。
- `NameTemplate="agent-${sessionId}"` 渲染为 `agent-sess-001`。
- 模板引用的变量缺失时拒绝启动实例。
- 首期只支持一个模板变量。

### 3.7 StartSandboxInstance 挂载覆盖字段调整

`StartSandboxInstance` 是已有 API。现有实例级挂载覆盖字段是 `MountOptions[]`，语义是按 `Name` 引用 Tool 已声明的挂载，并覆盖本次实例的 `MountPath`、`ReadOnly`、`SubPath`。

首期沿用这个实例级覆盖模型，而不是让实例在启动时直接引用新的 `VolumeTemplate`。也就是说，实例启动时仍然只能覆盖或启用 Tool 已声明的同名挂载，不能追加全新存储。

下面只展示与本方案相关的已有字段，不是完整 `StartSandboxInstanceRequest`。`ToolId`、`ToolName`、`TemplateId` 等现有选择规则保持不变。

```go
type StartSandboxInstanceRequest struct {
    // 已有字段，保持不变。
    ToolId   string
    ToolName string
    // ...

    // 已有字段，本方案扩展其语义。
    Metadata []Metadata

    // 已有字段，本方案沿用其覆盖模型。
    MountOptions []MountOption
}

type MountOption struct {
    Name      string
    MountPath string
    ReadOnly  *bool
    SubPath   string
}
```

实例级 `MountOptions[]` 的语义：

- 只能按 `Name` 引用 Tool 已声明的同名挂载。
- 可以启用 Tool 侧 `Inherit=false` 的挂载。
- 可以覆盖本次实例的 `MountPath`。
- 可以将 `ReadOnly` 从 false 收紧为 true。
- 可以在允许范围内指定 `SubPath`。

共享介质 SubPath 解析规则：

- 对 COS / CFS / Agent Bucket，最终访问边界由 `VolumeTemplate.Source` 中的基础路径和子路径共同决定。
- 如果 `VolumeTemplate.SubPathTemplate` 非空，则最终子路径由模板和 `Metadata` 渲染得到，Tool 侧和实例级都不能再传 `SubPath`。
- 如果 `VolumeTemplate.SubPathTemplate` 为空，Tool 侧可以声明默认 `SubPath`，实例级可以在同名挂载上覆盖 `SubPath`。
- 显式 `SubPath` 必须是相对路径，不能是绝对路径，不能包含 `.`、`..` 等相对路径片段，也不能越过 `VolumeTemplate` 声明的基础路径。
- AgentCBS 是整盘挂载，不支持 `SubPath`。

系统合并规则：

1. 读取 Tool 上所有 `VolumeMounts[]`。
2. 选择 Tool 侧 `Inherit=true` 的挂载作为默认挂载。
3. 读取实例级 `MountOptions[]`。
4. 对实例级每个挂载，按 `Name` 查找 Tool 侧声明。
5. 找到后合并本次覆盖值。
6. 渲染 `Metadata`，生成最终 `ResolvedSubPath` 或 `ResolvedAgentCBSId`。
7. 将最终结果写入实例详情，并生成最终实例挂载配置。

拒绝规则：

- 实例级挂载 `Name` 在 Tool 中不存在。
- 实例级传入新的 `VolumeTemplateId` 或其他 `VolumeTemplate` 引用字段。
- 实例级修改容量、盘类型、回收策略等资源定义。
- Tool 侧或 VolumeTemplate 要求只读，实例级试图改为可写。
- `VolumeTemplate.SubPathTemplate` 非空时，实例级同时传 `SubPath`。
- AgentCBS 挂载传 `SubPath`。

### 3.8 DescribeSandboxInstance.VolumeMounts

查询实例时返回最终实际挂载结果。

```go
type SandboxInstance struct {
    InstanceId   string
    VolumeMounts []InstanceVolumeMount
}

type InstanceVolumeMount struct {
    Name              string
    VolumeTemplateId string

    MountPath string
    ReadOnly  bool
    SubPath   string

    ResolvedSubPath    string
    ResolvedAgentCBSId string
}
```

出参语义：

| 字段 | 说明 |
|------|------|
| `Name` | Tool 侧挂载名称 |
| `VolumeTemplateId` | 实际引用的 `VolumeTemplate` 资源 ID |
| `MountPath` | 最终容器内挂载路径 |
| `ReadOnly` | 最终只读状态 |
| `SubPath` | 客户显式传入的子路径，若有 |
| `ResolvedSubPath` | 系统最终解析出的共享介质子路径 |
| `ResolvedAgentCBSId` | AgentCBS 场景下最终绑定的数据盘 ID |

说明：

- 返回的是实例最终挂载快照，不是 Tool 原始声明。
- 该信息用于客户排查、审计、账单归属和问题定位。
- 它不是独立云资源。

### 3.9 DescribeAgentCBS

查询 AGS 派生的数据盘。

```go
type DescribeAgentCBSRequest struct {
    AgentCBSIds         []string
    VolumeTemplateId    string
    VolumeTemplateName  string
    Status              string // Creating / Available / Bound / Deleting / Deleted / Failed
    BoundInstanceId     string
    Offset              int
    Limit               int
}
```

```go
type DescribeAgentCBSResponse struct {
    TotalCount int
    AgentCBS   []AgentCBS
}
```

```go
type AgentCBS struct {
    AgentCBSId         string
    Name               string
    VolumeTemplateId   string
    VolumeTemplateName string

    Status          string
    BoundInstanceId string

    Capacity string
    DiskType string

    CreateTime     string
    UpdateTime     string
    LastUnbindTime string
}
```

状态说明：

| 状态 | 说明 |
|------|------|
| `Creating` | 正在创建 |
| `Available` | 空闲，可被后续相同模板和名称复用 |
| `Bound` | 已绑定到某个沙箱实例 |
| `Deleting` | 正在删除 |
| `Deleted` | 已删除 |
| `Failed` | 创建或绑定失败 |

首期约束：

- AgentCBS 不支持客户直接创建。
- AgentCBS 不支持 tag。
- AgentCBS 的鉴权、计费和审计归属到所属 `VolumeTemplate`。
- 同名 AgentCBS 已经 `Bound` 时，不允许另一个实例同时绑定。

### 3.10 DeleteAgentCBS

删除空闲 AgentCBS。

```go
type DeleteAgentCBSRequest struct {
    AgentCBSId string
}
```

删除约束：

- 只能删除 `Available` 状态的 AgentCBS。
- `Bound` 状态必须先删除或停止对应沙箱实例，使其解绑。
- 删除后不可恢复。

### 3.11 VolumeSource

`VolumeSource` 复用现有共享介质字段，并新增 AgentCBS。

```go
type VolumeSource struct {
    Type        string // Cos / Cfs / AgentBucket / AgentCBS
    Cos         *CosVolumeSource
    Cfs         *CfsVolumeSource
    AgentBucket *AgentBucketVolumeSource
    AgentCBS    *AgentCBSVolumeSource
}
```

共享介质字段示例：

```go
type CosVolumeSource struct {
    Endpoint   string
    BucketName string
    BucketPath string
}

type CfsVolumeSource struct {
    FileSystemId string
    Path         string
}

type AgentBucketVolumeSource struct {
    LibraryId    string
    AccessDomain string
    SpaceId      string
}
```

AgentCBS 字段：

```go
type AgentCBSVolumeSource struct {
    NameTemplate string
    DiskType     string
}
```

约束：

- `Source.Type=AgentCBS` 时只允许填写 `AgentCBS`。
- `Source.Type=Cos` 时只允许填写 `Cos`。
- 其他类型同理，只能填写一个具体 source。

### 3.12 命名约定

本文示例使用 Go SDK 风格字段名。

命名约定：

- 展示名称使用 `COS` / `CFS` / `Agent Bucket`，API 枚举示例使用 `Cos` / `Cfs` / `AgentBucket`。
- `VolumeTemplate.DefaultCapacity` 表示后续派生 AgentCBS 时使用的默认容量。
- `AgentCBS.Capacity` 表示某块已创建 AgentCBS 的实际容量。
- `AgentCBS` 缩写大小写：本文统一写 `AgentCBS` / `ResolvedAgentCBSId`。
