# AGS Volume API Change Notes

This directory contains customer-facing AGS Volume API change notes, covering new APIs, existing API field changes, request/response semantics, and first-phase scope.

Chinese document: [cookbook.zh-CN.md](cookbook.zh-CN.md)

## Contents

- API change overview: new APIs and existing API changes.
- New APIs: `CreateVolumeTemplate`, `DescribeVolumeTemplates`, `DeleteVolumeTemplate`, `DescribeAgentCBS`, and `DeleteAgentCBS`.
- Existing API changes: `CreateSandboxTool`, `StartSandboxInstance`, `DescribeSandboxTool` / `DescribeSandboxToolList`, and `DescribeSandboxInstance` / `DescribeSandboxInstanceList`.
- Key fields: `VolumeTemplate`, `VolumeMounts[]`, `MountOptions[]`, `Metadata[]`, and final instance `VolumeMounts[]`.
- First-phase scope: AgentCBS, `${sessionId}` template variables, tag ownership, and compatibility.
