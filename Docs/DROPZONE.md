# Dropzone (Secure File Inbound)

The agent receives files from the main machine via a single **read-only** directory. The agent has no broad system access.

## Directory

- **Default:** `~/.agentkvt/inbound/`
- **Override:** Set `AGENTKVT_INBOUND_DIR` to a path (e.g. `~/Desktop/AgentInbound`). Supports `~`.

## Supported types

- **PDF** — text extracted via PDFKit.
- **CSV** — read as UTF-8 text.
- **TXT** — read as UTF-8 text.

Dropped files are parsed and their content is passed to the MissionRunner as **additional context** for each scheduled mission run. Content is capped (default 100KB) to avoid oversized prompts.

## Usage

When the Mac runner runs in scheduler mode (`RUN_SCHEDULER=1`), it starts the Dropzone watcher and injects any parsed content into the mission context. Other users can point `AGENTKVT_INBOUND_DIR` to their own folder and use the same engine.
