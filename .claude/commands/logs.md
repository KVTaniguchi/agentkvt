Run the production log analyzer and summarize the current health of the AgentKVT stack.

1. Run: `./bin/analyze_agent_logs.sh` from the repo root (defaults to `familyagent@taniguchis-macbook-pro.tail82812d.ts.net`).
2. If the user passed `--raw`, add `--raw` to the command.
3. Report stack status (Rails API, Solid Queue, Ollama, /healthz) first.
4. Then list dominant failure classes in severity order with timestamps and affected routes or missions.
5. Call out any stale deploys, process mismatches, or known error patterns from the interpretation guide:
   - `No route matches` → stale Rails routes, needs restart
   - `422 Content can't be blank` for assistant_final/outcome → empty runner payload
   - `WebhookListener error: Address already in use` → duplicate app instances
   - `cached plan must not change result type` → prepared statement / schema mismatch in Postgres
