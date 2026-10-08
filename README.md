# Cloudera Blueprint: Claude Code with AWS Bedrock

> Run [Claude Code](https://code.claude.com/docs/en/quickstart) in Cloudera AI Workbench against any [Amazon Bedrock](https://aws.amazon.com/bedrock/) foundation model you choose.

## Table of Contents

- [Overview](#overview)
- [Use Case](#use-case)
- [Key Features](#key-features)
- [Quickstart](#quickstart)
- [Authentication (12-hour tokens)](#authentication-12-hour-tokens)
- [Recommended models](#recommended-models)
- [Architecture](#architecture)
- [Alternative: native Bedrock (no LiteLLM)](#alternative-native-bedrock-no-litellm)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Hardware Requirements](#hardware-requirements)
- [Troubleshooting](#troubleshooting)
- [Documentation](#documentation)

## Overview

This blueprint connects **Claude Code**—Anthropic's terminal coding agent—to **AWS Bedrock**. A custom **workbench runtime image** preinstalls Claude Code and a local **LiteLLM proxy** that translates Anthropic's API to Bedrock's Invoke API. Configuration comes from **project environment variables** (`BEDROCK_MODEL` + standard AWS credentials). No model is hosted inside the workbench pod—inference runs in your AWS account.

```
claude  →  LiteLLM (localhost:4000)  →  AWS Bedrock
```

## Use Case

**Problem:** Teams want **Claude Code's agentic workflow** (shell, edits, search) on **models served through AWS Bedrock**, with credentials and model choice controlled via environment variables—without routing traffic through Anthropic's cloud API.

**Outcome:** Register this runtime, set four env vars, run **`claude-sync-config`** and **`claude`** in a workbench terminal.

## Key Features

- **Pre-built image** supported — `docker.io/kevintalbert/claudeworkbenchwithawsbedrock:latest` (no Docker build required)
- **Custom runtime** with Claude Code, LiteLLM, and agent-friendly tooling preinstalled
- **Model from env** — set `BEDROCK_MODEL` to any Bedrock model id you have access to
- **12-hour Bedrock bearer tokens** — auto-minted from AWS credentials, or pasted from the Bedrock console
- **LiteLLM proxy** bridges Anthropic API → Bedrock Invoke API
- **Bedrock-safe Claude Code settings** — experimental beta headers disabled for Bedrock compatibility

## Quickstart

### 1. Enable Bedrock model access

In the AWS console:

1. Open **Amazon Bedrock → Model access** (or **Model catalog**) in your target region
2. Request access to the model you want (e.g. **Claude Sonnet 4**)
3. Create an IAM user or role with `bedrock:InvokeModel` (and `bedrock:InvokeModelWithResponseStream` if streaming) on your chosen model
4. Note the **model id** for `BEDROCK_MODEL`:
   - **Console:** [Amazon Bedrock → Model catalog](https://console.aws.amazon.com/bedrock/home#/model-catalog) — browse all models in your region
   - **Full reference list:** [Supported foundation models (model IDs)](https://docs.aws.amazon.com/bedrock/latest/userguide/model-ids.html)
   - Example: `us.anthropic.claude-sonnet-5-5`

### 2. Register the workbench runtime

**Option A (recommended):** Use the **pre-built runtime image** — no Docker build required. In **Admin → Runtime Catalog → Add Runtime**, paste:

```text
docker.io/kevintalbert/claudeworkbenchwithawsbedrock:latest
```

When registered, the runtime shows **Edition: Claude Code with AWS Bedrock** and a green status checkmark.

Create a project with that runtime and start a session. **No GPU required on the workbench pod**—inference runs on Bedrock.

**Option B:** Build and register from this repo:

```bash
docker build --pull --rm -f Dockerfile -t <your-registry>/claudeworkbench-bedrock:1.0.0 .
# push to your registry, then Add Runtime in the catalog
```

### 3. Set environment variables

**Project → Settings → Advanced → Environment Variables** → **Submit**, then **restart the session** (stop/start workbench or start a new session).

After the session is back up, open a terminal and run **`claude-sync-config`** once to mint a bearer token, start LiteLLM, and write Claude settings. Re-run it when your token expires (up to **12 hours**).

**Required for all modes:**

| Name | Value |
|------|--------|
| `BEDROCK_MODEL` | Model id from the [model catalog](https://console.aws.amazon.com/bedrock/home#/model-catalog) or [model IDs reference](https://docs.aws.amazon.com/bedrock/latest/userguide/model-ids.html) (e.g. `us.anthropic.claude-sonnet-4-6`) |
| `AWS_REGION` | Bedrock region (e.g. `us-east-1`) |

**Option A — Auto-refresh (recommended):** set base AWS credentials; `claude-sync-config` mints a fresh 12-hour Bedrock bearer token automatically.

| Name | Value |
|------|--------|
| `AWS_ACCESS_KEY_ID` | IAM or STS access key |
| `AWS_SECRET_ACCESS_KEY` | Secret key |
| `AWS_SESSION_TOKEN` | Required for temporary (STS) credentials |

**Option B — Manual token:** generate a short-term key (see [Generate a new token](#generate-a-new-token-manual) below), then paste it:

| Name | Value |
|------|--------|
| `AWS_BEARER_TOKEN_BEDROCK` | Token from the Bedrock API keys page (valid up to 12 hours) |

Optional:

| Name | Default | Description |
|------|---------|-------------|
| `BEDROCK_LITELLM_PORT` | `4000` | Local LiteLLM proxy port |
| `BEDROCK_MAX_OUTPUT_TOKENS` | `8192` | Cap Claude Code output tokens |
| `BEDROCK_MAX_INPUT_TOKENS` | `192000` | Advertised input limit to LiteLLM |

If `BEDROCK_MODEL` does not start with `bedrock/`, the runtime prefixes it as `bedrock/invoke/<model>` (recommended for Claude Code + Bedrock).

See [Authentication (12-hour tokens)](#authentication-12-hour-tokens) for details and the token generation link.

### 4. Sync and run Claude Code

In a JupyterLab terminal:

```bash
claude-sync-config
claude
```

One-shot prompt:

```bash
claude -p "explain this repo"
```

Helper commands:

| Command | Description |
|---------|-------------|
| `claude-sync-config` | Mint bearer token, start/restart LiteLLM, write Claude settings |
| `claude-refresh-token` | Mint a fresh 12-hour bearer token (requires base AWS creds) |
| `claude` | Sync config then launch Claude Code |
| `claude-status` | Show env + proxy health |
| `claude-stop-proxy` | Stop background LiteLLM |
| `claude-logs` | Tail LiteLLM log |

## Authentication (12-hour tokens)

This runtime uses **short-term Bedrock bearer tokens** (valid up to **12 hours**). AWS recommends these over long-lived keys for production-style use within account restrictions.

### Generate a new token (manual)

In the AWS console (select your target region first):

1. Open **[Amazon Bedrock](https://console.aws.amazon.com/bedrock/)**
2. In the left nav, under **Discover**, choose **API keys**
3. Open the **Short-term API keys** tab
4. Choose **Generate short-term API keys**
5. Copy the token and set it as `AWS_BEARER_TOKEN_BEDROCK` in project env vars
6. Restart the session, then run `claude-sync-config`

Direct link: [Bedrock → API keys](https://console.aws.amazon.com/bedrock/home#/api-keys)

Docs: [Generate an Amazon Bedrock API key](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys-generate.html)

### Auto-refresh (recommended)

If you set `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and (for STS) `AWS_SESSION_TOKEN`, the runtime mints a fresh bearer token on every `claude-sync-config` / `claude` invocation using [`aws-bedrock-token-generator`](https://github.com/aws/aws-bedrock-token-generator-python).

```bash
claude-sync-config   # mints token + starts proxy
claude               # re-mints if needed, then launches
claude-refresh-token # mint only, without restarting proxy
```

**Note:** If your base credentials are STS (prefix `ASIA`), they may expire before 12 hours. Refresh those credentials first, then re-run `claude-sync-config`.

## Recommended models

This runtime is designed for **Anthropic Claude models on Bedrock**, which support tool calling and work well with Claude Code's agent loop.

| Model | Example `BEDROCK_MODEL` value | Notes |
|-------|-------------------------------|-------|
| Claude Sonnet 4 | `us.anthropic.claude-sonnet-4-6` | Strong balance of speed and capability |
| Claude Opus 4 | `us.anthropic.claude-opus-4-6` | Highest capability |
| Claude 3.5 Sonnet | `anthropic.claude-3-5-sonnet-20241022-v2:0` | Region-specific model id |

Use the exact model id shown in the Bedrock console for your region. Cross-region inference profile ids (prefixed with `us.`, `eu.`, etc.) are supported.

**Find model IDs:**

- [Model catalog (console)](https://console.aws.amazon.com/bedrock/home#/model-catalog) — browse all available models in your region
- [Model IDs reference (docs)](https://docs.aws.amazon.com/bedrock/latest/userguide/model-ids.html) — complete list of supported foundation models and inference profile ids

Other Bedrock models (e.g. Amazon Nova, Meta Llama) may work via LiteLLM but are not validated with Claude Code's tool-calling workflow.

## Architecture

| Component | Role |
|-----------|------|
| **AWS Bedrock** | Serves the foundation model you select via `BEDROCK_MODEL` |
| **Custom runtime image** | JupyterLab + Claude Code + LiteLLM; `scripts/bedrock-runtime-startup.sh` |
| **LiteLLM** | Translates Anthropic API → Bedrock Invoke API |
| **Claude Code** | Agent CLI (`claude`) — tools, bash, edits |
| **Bearer token** | Short-term Bedrock API key (auto-minted or from console) authenticates to Bedrock |

## Alternative: native Bedrock (no LiteLLM)

**LiteLLM is not required for Bedrock.** This blueprint uses it as a local proxy (Anthropic API → Bedrock Invoke API), which matches the original CAII pattern and keeps a single `BEDROCK_MODEL` env var routing all Claude tiers to one model.

[Claude Code supports Amazon Bedrock natively](https://code.claude.com/docs/en/amazon-bedrock). With that path, Claude Code calls Bedrock directly — no local proxy, no `claude-sync-config`, and a smaller runtime image.

```
claude  →  AWS Bedrock (direct)
```

To use native Bedrock instead, set project environment variables and skip the LiteLLM workflow:

| Name | Value |
|------|--------|
| `CLAUDE_CODE_USE_BEDROCK` | `1` |
| `AWS_ACCESS_KEY_ID` | IAM access key |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key |
| `AWS_REGION` | Bedrock region |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | Bedrock model id (e.g. `us.anthropic.claude-sonnet-5-5`) |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | Same or a different Bedrock model id |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Same or a different Bedrock model id |

Then run `claude` directly — no `claude-sync-config` needed.

**When to keep LiteLLM (this blueprint):**

- You want one `BEDROCK_MODEL` env var for all Claude aliases
- You may route to non-Claude Bedrock models later (LiteLLM can translate APIs)
- You want a local proxy for logging, routing, or future multi-provider setups

**When to drop LiteLLM:**

- You only use Anthropic Claude models on Bedrock
- You want the smallest image and fewest moving parts
- You are fine with per-tier `ANTHROPIC_DEFAULT_*_MODEL` vars instead of `BEDROCK_MODEL`

The Dockerfile comments mark which layers can be removed for a native-Bedrock build (LiteLLM venv, `requirements-litellm.txt`, and the proxy scripts under `scripts/lib/bedrock-common.sh`).

## Repository Structure

| Path | Description |
| --- | --- |
| `assets/` | Screenshots for README and demos |
| `scripts/bedrock-runtime-startup.sh` | Runtime profile hook: `claude`, `claude-sync-config`, helpers |
| `scripts/lib/bedrock-common.sh` | LiteLLM proxy + Bedrock env helpers |
| `requirements-litellm.txt` | Pinned LiteLLM + FastAPI + boto3 deps (verified at image build) |
| `scripts/verify-litellm-install.sh` | Build-time smoke test for the LiteLLM proxy |
| `Dockerfile` | Workbench runtime image definition |
| `METADATA.yaml` | Blueprint catalog metadata |

## Prerequisites

- Cloudera AI with **Workbench** (runtime catalog access for admins)
- An **AWS account** with Bedrock model access enabled in your target region
- IAM credentials with permission to invoke your chosen Bedrock model
- For custom image build: `docker`, registry push access

## Hardware Requirements

| Deployment | Guidance |
| --- | --- |
| **AWS Bedrock** | Inference runs in AWS; no GPU required in your account beyond Bedrock's managed service |
| **Workbench runtime** | Standard session resources (e.g. 2 vCPU / 4 GB RAM); **no GPU** on the workbench pod |

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Banner: "Set BEDROCK_MODEL …" | Set `BEDROCK_MODEL`, `AWS_REGION`, and credentials? **New session** after Submit? |
| `claude-sync-config` fails | Verify env vars; for manual mode generate a fresh token: Bedrock → **Discover** → **API keys** → **Short-term API keys** ([direct link](https://console.aws.amazon.com/bedrock/home#/api-keys)) |
| Token expired / `403` / auth errors | Re-run `claude-sync-config` (tokens last up to 12 hours) |
| STS creds expired before token | Refresh `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`, then `claude-sync-config` |
| `AccessDeniedException` | IAM policy needs `bedrock:InvokeModel` on your model; confirm model access is enabled in the Bedrock console |
| `ValidationException` / invalid model | Use the exact model id from the [model catalog](https://console.aws.amazon.com/bedrock/home#/model-catalog) or [model IDs reference](https://docs.aws.amazon.com/bedrock/latest/userguide/model-ids.html) |
| `400 invalid beta flag` | Runtime sets `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1` by default; run `claude-stop-proxy` then `claude-sync-config` |
| Model error for subagent/summary calls | All Claude aliases route to your `BEDROCK_MODEL`; check `claude-status` |
| Proxy won't start | `claude-logs` or `tail ~/.claude/bedrock/litellm.log`. Rebuild the runtime image if LiteLLM import fails. |
| `ContextWindowExceededError` | Lower `BEDROCK_MAX_OUTPUT_TOKENS` or raise limits if your model supports a larger window |

## Documentation

- [Model catalog (console)](https://console.aws.amazon.com/bedrock/home#/model-catalog) — browse all Bedrock models in your region
- [Model IDs reference (docs)](https://docs.aws.amazon.com/bedrock/latest/userguide/model-ids.html) — complete list of model and inference profile ids
- [API keys (console)](https://console.aws.amazon.com/bedrock/home#/api-keys) — Bedrock → Discover → API keys → Short-term API keys
- [Generate Bedrock API keys (docs)](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys-generate.html)
- [Amazon Bedrock user guide](https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html)
- [Claude Code quickstart](https://code.claude.com/docs/en/quickstart)
- [LiteLLM Bedrock provider](https://docs.litellm.ai/docs/providers/bedrock)
- [LiteLLM + Claude Code](https://docs.litellm.ai/docs/tutorials/claude_responses_api)

MIT © 2026 Cloudera, Inc.
