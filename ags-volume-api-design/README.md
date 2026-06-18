# AGS Volume API Change Notes

This directory contains customer-facing AGS Volume API change notes, covering new APIs, existing API field changes, request/response semantics, and first-phase boundaries.

Chinese document: [cookbook.zh-CN.md](cookbook.zh-CN.md)

## Contents

- API change overview: new APIs and existing API changes.
- New APIs: `CreateVolumeTemplate`, `DescribeVolumeTemplates`, `DeleteVolumeTemplate`, `DescribeAgentCBS`, and `DeleteAgentCBS`.
- Existing API changes: `CreateSandboxTool`, `StartSandboxInstance`, `DescribeSandboxInstance`, and `DescribeSandboxTool`.
- Key fields: `VolumeTemplate`, `VolumeMounts[]`, `MountOptions[]`, `Metadata[]`, and final instance `VolumeMounts[]`.
- First-phase constraints: AgentCBS lifecycle, `${sessionId}` template variables, tag-based authorization, compatibility, and boundaries.
