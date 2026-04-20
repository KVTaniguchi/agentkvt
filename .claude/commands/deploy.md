Deploy the AgentKVT Rails backend to the production server.

1. Run: `./bin/deploy_remote_agentkvt_backend.sh familyagent@taniguchis-macbook-pro.tail82812d.ts.net origin/main`
2. Watch for migration errors or /healthz failures in the output.
3. After the script finishes, confirm the API is up by checking the /healthz response in the output.
4. If the deploy fails, report the exact error and suggest next steps (e.g. SSH in manually, check server/.env, check gem/bundle issues).
