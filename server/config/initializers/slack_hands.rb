# Agent Hands — Slack Events API (ingest)
#
# Required for signature verification on POST /v1/slack/events:
#   SLACK_SIGNING_SECRET — Signing Secret from the Slack app (api.slack.com → App → Basic Information)
#
# Workspace resolution (map Slack team_id → AgentKVT workspace):
#   1) Preferred: create a `slack_workspace_links` row (slack_team_id → workspace_id)
#   2) Fallback when SLACK_TEAM_ID matches the incoming team_id:
#        SLACK_WORKSPACE_SLUG — workspace slug (defaults to DEFAULT_WORKSPACE_SLUG / "default")
#
# Optional (outbound / later): store bot token via WorkspaceProviderCredential or env.
