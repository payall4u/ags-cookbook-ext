# AGS Log Delivery Cookbook

This directory contains customer-deliverable best-practice cookbooks for sending AGS sandbox logs to a customer-owned OpenTelemetry-compatible logging system over VPC networking.

Language-specific cookbook documents:

- Chinese: [cookbook.zh-CN.md](cookbook.zh-CN.md)
- English: [cookbook.en.md](cookbook.en.md)

Supporting artifacts:

- [iac/ags-tool.template.json](iac/ags-tool.template.json): shape-only AGS custom Tool request template for delivery review.
- [iac/variables.example.env](iac/variables.example.env): example variables required to create the Tool.
- [scripts/inject_sandbox_id.sh](scripts/inject_sandbox_id.sh): writes the current AGS InstanceID into the sandbox through the AGS Go SDK envd command API.
- [scripts/ags-envd-exec](scripts/ags-envd-exec): small Go SDK helper used by the injection script to call the envd command API.
- [reference-implementation/README.zh-CN.md](reference-implementation/README.zh-CN.md): Chinese reference image implementation notes.
- [reference-implementation/README.en.md](reference-implementation/README.en.md): English reference image implementation notes.
- [images/sandbox](images/sandbox): runnable sandbox image reference implementation.

Recommended run order:

1. Read the language-specific cookbook for the full design and operating boundaries.
2. Review the reference implementation under `images/sandbox`.
3. Confirm the target VPC subnet can reach the customer's OTLP/gRPC endpoint.
4. Build and push the sandbox image, then optionally pre-cache it in AGS.
5. Copy and edit `.env.local`, generate the Tool request, and create the AGS Tool.
6. Start an instance, inject its `InstanceID`, and validate logs in the customer logging system.

Quick request generation:

Before running commands, read the cookbook scope: this pattern collects file logs only and starts the collector only after `InstanceID` injection.

```bash
# Build and push the sandbox image first, then put that image URI in AGS_IMAGE.
cp iac/variables.example.env .env.local
# Edit .env.local before sourcing it. At minimum, fill AGS_IMAGE,
# AGS_SUBNET_ID, AGS_SECURITY_GROUP_ID, OTLP_ENDPOINT, SERVICE_NAME,
# BUSINESS_COMMAND, and the business env values in EXTRA_ENV_JSON.
set -a
source .env.local
set +a

DRY_RUN=true scripts/create_ags_tool.sh > ags-tool.generated.json
jq . ags-tool.generated.json
```

After an instance reaches `RUNNING`, inject its runtime identity:

```bash
export TENCENTCLOUD_SECRET_ID=<secret-id>
export TENCENTCLOUD_SECRET_KEY=<secret-key>
export TENCENTCLOUD_REGION=<region>
INSTANCE_ID=<ags-instance-id> scripts/inject_sandbox_id.sh
```

The injection script runs from the control plane or delivery pipeline and uses the AGS Go SDK command API by default. Set `INJECT_METHOD=agr` only if the local `agr instance exec` path is known to work in your environment.

Use `scripts/create_ags_tool.sh` to generate the request that should be submitted to AGS. Do not submit `iac/ags-tool.template.json` directly; it is only a review aid for the expected shape. The script omits empty `RoleArn` and empty tag fields automatically.
