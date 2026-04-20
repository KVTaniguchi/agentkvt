Check the health of the AgentKVT production server at familyagent@taniguchis-macbook-pro.tail82812d.ts.net.

Run these checks over SSH and report results:

1. Rails API: `ssh familyagent@taniguchis-macbook-pro.tail82812d.ts.net 'curl -sS http://127.0.0.1:3000/healthz'`
2. Solid Queue workers: `ssh familyagent@taniguchis-macbook-pro.tail82812d.ts.net 'pgrep -a ruby | grep solid'`
3. Ollama: `ssh familyagent@taniguchis-macbook-pro.tail82812d.ts.net 'curl -sS http://localhost:11434/api/tags | head -c 200'`
4. Mac Brain process: `ssh familyagent@taniguchis-macbook-pro.tail82812d.ts.net 'pgrep -a AgentKVT'`

Summarize: which services are up, which are down, and any immediate action needed.
