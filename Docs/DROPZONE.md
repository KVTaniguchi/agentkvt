# Dropzone (Secure File Inbound)

The agent receives files from the main machine via a single **read-only** directory. The agent has no broad system access.

## Directory

- **Default:** `~/.agentkvt/inbound/`
- **Override:** Set `AGENTKVT_INBOUND_DIR` to a path (e.g. `~/Desktop/AgentInbound`). Supports `~`.

## Supported types

- **PDF** — text extracted via PDFKit.
- **CSV** — read as UTF-8 text.
- **TXT** — read as UTF-8 text.

Dropped files are parsed and their content is available to the agent via the `list_dropzone_files` and `read_dropzone_file` tools. Content is capped (default 100KB) to avoid oversized prompts.

## Usage

When the Mac runner runs in scheduler mode (`RUN_SCHEDULER=1`), the Dropzone directory is watched via FSEvents. New files trigger an `.inboundFile` event in the `AgentExecutionQueue`. The `list_dropzone_files` and `read_dropzone_file` tools let the agent access this content during task execution.
